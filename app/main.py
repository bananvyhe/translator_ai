import math
import os
import re
import subprocess
import threading
import time
from functools import lru_cache
from pathlib import Path
from typing import Optional

import torch
from dotenv import load_dotenv
from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel, Field
from transformers import AutoModelForImageTextToText, AutoProcessor

load_dotenv()

_RUNTIME_LOG_LOCK = threading.Lock()
_RUNTIME_LOG_DIR = Path(__file__).resolve().parents[1] / "logs"
_RUNTIME_LOG_DIR.mkdir(parents=True, exist_ok=True)
_RUNTIME_LOG_PATH = _RUNTIME_LOG_DIR / f"runtime-{time.strftime('%Y%m%d-%H%M%S')}.log"


def _append_runtime_log(message: str) -> None:
    line = message.rstrip()
    with _RUNTIME_LOG_LOCK:
        with _RUNTIME_LOG_PATH.open("a", encoding="utf-8") as handle:
            handle.write(line + "\n")


class Settings(BaseModel):
    model_config = {"protected_namespaces": ()}

    model_id: str = os.getenv("MODEL_ID", "google/translategemma-4b-it")
    host: str = os.getenv("HOST", "127.0.0.1")
    port: int = int(os.getenv("PORT", "8008"))
    device: str = os.getenv("DEVICE", "cuda")
    dtype: str = os.getenv("DTYPE", "bfloat16")
    source_lang_code: str = os.getenv("SOURCE_LANG_CODE", "en")
    target_lang_code: str = os.getenv("TARGET_LANG_CODE", "ru-RU")
    max_input_chars: int = int(os.getenv("MAX_INPUT_CHARS", "24000"))
    max_chunk_chars: int = int(os.getenv("MAX_CHUNK_CHARS", "3500"))
    max_new_tokens_title: int = int(os.getenv("MAX_NEW_TOKENS_TITLE", "256"))
    max_new_tokens_preview: int = int(os.getenv("MAX_NEW_TOKENS_PREVIEW", "768"))
    max_new_tokens_body: int = int(os.getenv("MAX_NEW_TOKENS_BODY", "4096"))
    generation_num_beams: int = int(os.getenv("GENERATION_NUM_BEAMS", "6"))
    generation_length_penalty: float = float(os.getenv("GENERATION_LENGTH_PENALTY", "1.0"))
    generation_repetition_penalty: float = float(os.getenv("GENERATION_REPETITION_PENALTY", "1.0"))
    translation_token: Optional[str] = os.getenv("TRANSLATION_TOKEN")
    hf_token: Optional[str] = os.getenv("HF_TOKEN") or os.getenv("HUGGINGFACE_HUB_TOKEN")
    hf_offline_mode: bool = os.getenv("HF_OFFLINE_MODE", "true").lower() in ("1", "true", "yes")

    manage_miner: bool = os.getenv("MANAGE_MINER", "false").lower() in ("1", "true", "yes")
    miner_process_name: str = os.getenv("MINER_PROCESS_NAME", "onezerominer.exe")
    miner_launch_path: str = os.getenv(
        "MINER_LAUNCH_PATH",
        os.getenv("MINER_BAT_PATH", r"C:\bbb\onezerominer-win64-1.7.4\qubitcoin.bat"),
    )
    miner_restart_delay_sec: int = int(os.getenv("MINER_RESTART_DELAY_SEC", "2"))

    lazy_model_load: bool = os.getenv("LAZY_MODEL_LOAD", "false").lower() in ("1", "true", "yes")
    unload_model_after_request: bool = os.getenv("UNLOAD_MODEL_AFTER_REQUEST", "false").lower() in ("1", "true", "yes")


class TranslationRequest(BaseModel):
    request_id: Optional[str] = ""
    title: str = Field(default="", max_length=4000)
    preview_text: str = Field(default="", max_length=12000)
    body_text: str = Field(default="", max_length=200000)


class TranslationResponse(BaseModel):
    request_id: str = ""
    status: str = "ok"
    title_ru: str
    preview_text_ru: str
    body_text_ru: str
    translated_title: str
    translated_preview_text: str
    translated_body_text: str
    model: str
    latency_ms: int
    error: Optional[str] = None


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()


class Translator:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.request_lock = threading.Lock()
        self.lock = threading.Lock()
        self.miner_lock = threading.Lock()
        self.active_jobs = 0
        self.processor = None
        self.model = None
        self.model_lock = threading.Lock()
        self.model_dtype = self._resolve_torch_dtype(settings.dtype)

        if settings.device == "cuda" and not torch.cuda.is_available():
            raise RuntimeError("CUDA is not available. Check NVIDIA driver, CUDA runtime and PyTorch build.")

        if settings.hf_token:
            os.environ["HF_TOKEN"] = settings.hf_token

        if not settings.lazy_model_load:
            self._load_model()

    @staticmethod
    def _resolve_torch_dtype(raw_dtype: str) -> torch.dtype:
        dtype_name = (raw_dtype or "float16").strip().lower()
        dtype_map = {
            "float16": torch.float16,
            "fp16": torch.float16,
            "half": torch.float16,
            "bfloat16": torch.bfloat16,
            "bf16": torch.bfloat16,
            "float32": torch.float32,
            "fp32": torch.float32,
        }
        if dtype_name not in dtype_map:
            raise ValueError(f"Unsupported DTYPE '{raw_dtype}'. Use float16, bfloat16 or float32.")
        return dtype_map[dtype_name]

    def _log(self, message: str) -> None:
        print(message, flush=True)
        _append_runtime_log(message)

    def _load_model(self) -> None:
        with self.model_lock:
            if self.model is not None and self.processor is not None:
                return

            self._log(f"[model] loading {self.settings.model_id} dtype={self.settings.dtype}")
            load_started_at = time.monotonic()
            self.processor = AutoProcessor.from_pretrained(
                self.settings.model_id,
                token=self.settings.hf_token,
                local_files_only=self.settings.hf_offline_mode,
                use_fast=True,
            )
            self.model = AutoModelForImageTextToText.from_pretrained(
                self.settings.model_id,
                device_map="auto",
                torch_dtype=self.model_dtype,
                token=self.settings.hf_token,
                local_files_only=self.settings.hf_offline_mode,
            )
            self.model.eval()
            device_map = getattr(self.model, "hf_device_map", None)
            self._log(f"[model] loaded {self.settings.model_id} in {time.monotonic() - load_started_at:.1f}s")
            if device_map:
                self._log(f"[model] hf_device_map={device_map}")

    def _unload_model(self) -> None:
        with self.model_lock:
            if self.model is None:
                return

            self._log("[model] unloading")
            self.model.to("cpu")
            self.model = None
            self.processor = None
            if torch.cuda.is_available():
                torch.cuda.empty_cache()
                torch.cuda.ipc_collect()
            self._log("[model] unloaded")

    def _stop_miner(self) -> None:
        if not self.settings.manage_miner:
            return

        self._log(f"[miner] stopping {self.settings.miner_process_name}")
        subprocess.run(
            ["taskkill", "/IM", self.settings.miner_process_name, "/F"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )

    def _resolve_miner_launch_path(self) -> Optional[Path]:
        raw_path = Path(self.settings.miner_launch_path)
        candidates = [raw_path]
        if not raw_path.suffix:
            candidates.extend([
                raw_path.with_suffix(".lnk"),
                raw_path.with_suffix(".bat"),
                raw_path.with_suffix(".cmd"),
                raw_path.with_suffix(".exe"),
            ])
            candidates.extend(sorted(raw_path.parent.glob(f"{raw_path.name}*.lnk")))
            candidates.extend(sorted(raw_path.parent.glob(f"{raw_path.name}*.bat")))
            candidates.extend(sorted(raw_path.parent.glob(f"{raw_path.name}*.cmd")))
            candidates.extend(sorted(raw_path.parent.glob(f"{raw_path.name}*.exe")))

        for candidate in candidates:
            if candidate.exists():
                return candidate

        return None

    def _start_miner(self) -> None:
        if not self.settings.manage_miner:
            return

        launch_path = self._resolve_miner_launch_path()
        if launch_path is None:
            self._log(f"[miner] launch path not found: {self.settings.miner_launch_path}")
            return

        launch_parent = str(launch_path.parent)
        launch_target = str(launch_path)
        self._log(f"[miner] starting from {launch_target}")

        subprocess.Popen(
            ["cmd", "/c", "start", "", launch_target],
            cwd=launch_parent,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            creationflags=subprocess.CREATE_NEW_CONSOLE,
        )

    def _enter_translation_job(self) -> None:
        if not self.settings.manage_miner:
            return

        with self.miner_lock:
            self.active_jobs += 1
            self._log(f"[miner] translation job entered; active_jobs={self.active_jobs}")
            if self.active_jobs == 1:
                self._stop_miner()

    def _exit_translation_job(self) -> None:
        if not self.settings.manage_miner:
            return

        with self.miner_lock:
            self.active_jobs = max(0, self.active_jobs - 1)
            self._log(f"[miner] translation job exited; active_jobs={self.active_jobs}")
            if self.active_jobs == 0:
                time.sleep(self.settings.miner_restart_delay_sec)
                self._start_miner()

    def _looks_like_html(self, text: str) -> bool:
        return bool(re.search(r"<[^>]+>", text))

    def _estimate_max_new_tokens(self, text: str, configured_max: int, field_name: str) -> int:
        text_len = len(text.strip())
        if text_len <= 0:
            return configured_max

        base_by_field = {
            "title": 48,
            "preview": 96,
            "body": 192,
        }
        floor = base_by_field.get(field_name, 64)
        estimated = math.ceil(text_len / 3.0) + floor
        effective = max(floor, min(configured_max, estimated))
        self._log(f"[translate] {field_name} max_new_tokens configured={configured_max} effective={effective} chars={text_len}")
        return effective

    def _find_soft_boundary(self, text: str, start: int, limit: int) -> int:
        end = min(len(text), start + limit)
        if end >= len(text):
            return len(text)

        window = text[start:end]
        patterns = []
        if self._looks_like_html(window):
            patterns.extend([
                r"(?is)(?:</(?:p|div|section|article|header|footer|aside|main|blockquote|ul|ol|li|table|tr|td|th|h[1-6])\s*>|<br\s*/?>)\s*",
                r"(?is)>\s*<",
            ])
        patterns.extend([
            r"\n\s*\n+",
            r"(?<=[\.!?])\s+",
            r"(?<=[;:])\s+",
            r"\n",
            r"\s+",
        ])

        for pattern in patterns:
            matches = list(re.finditer(pattern, window))
            if matches:
                return start + matches[-1].end()

        return end

    def _split_long_segment(self, text: str, chunk_limit: int) -> list[str]:
        parts = []
        cursor = 0
        while cursor < len(text):
            boundary = self._find_soft_boundary(text, cursor, chunk_limit)
            if boundary <= cursor:
                boundary = min(len(text), cursor + chunk_limit)
            piece = text[cursor:boundary].strip()
            if piece:
                parts.append(piece)
            cursor = boundary
        return parts

    def _split_for_translation(self, text: str) -> list[str]:
        stripped = text.strip()
        if not stripped:
            return []

        chunk_limit = max(400, min(self.settings.max_chunk_chars, self.settings.max_input_chars))
        if len(stripped) <= chunk_limit:
            return [stripped]

        paragraphs = [p.strip() for p in re.split(r"\n\s*\n+", stripped) if p.strip()]
        if len(paragraphs) <= 1:
            return self._split_long_segment(stripped, chunk_limit)

        chunks = []
        current = []
        current_len = 0

        def flush_current() -> None:
            nonlocal current, current_len
            if current:
                chunks.append("\n\n".join(current))
                current = []
                current_len = 0

        for paragraph in paragraphs:
            if len(paragraph) > chunk_limit:
                flush_current()
                chunks.extend(self._split_long_segment(paragraph, chunk_limit))
                continue

            added_len = len(paragraph) if not current else current_len + 2 + len(paragraph)
            if current and added_len > chunk_limit:
                flush_current()

            current.append(paragraph)
            current_len = len(paragraph) if len(current) == 1 else current_len + 2 + len(paragraph)

        flush_current()
        return chunks

    def _translate_text(self, text: str, max_new_tokens: int, field_name: str) -> str:
        if not text.strip():
            return ""

        if len(text) > self.settings.max_input_chars:
            text = text[: self.settings.max_input_chars]

        self._load_model()
        assert self.processor is not None
        assert self.model is not None

        effective_max_new_tokens = self._estimate_max_new_tokens(text, max_new_tokens, field_name)

        messages = [
            {
                "role": "user",
                "content": [
                    {
                        "type": "text",
                        "source_lang_code": self.settings.source_lang_code,
                        "target_lang_code": self.settings.target_lang_code,
                        "text": text,
                    }
                ],
            }
        ]

        prep_started_at = time.monotonic()
        inputs = self.processor.apply_chat_template(
            messages,
            tokenize=True,
            add_generation_prompt=True,
            return_dict=True,
            return_tensors="pt",
        ).to(self.model.device)
        self._log(f"[translate] prep done in {time.monotonic() - prep_started_at:.1f}s")

        input_len = len(inputs["input_ids"][0])

        generate_started_at = time.monotonic()
        with torch.inference_mode():
            with self.lock:
                generation = self.model.generate(
                    **inputs,
                    do_sample=False,
                    max_new_tokens=effective_max_new_tokens,
                    pad_token_id=self.processor.tokenizer.eos_token_id,
                )
        self._log(f"[translate] generate done in {time.monotonic() - generate_started_at:.1f}s")

        decode_started_at = time.monotonic()
        output_tokens = generation[0][input_len:]
        translated = self.processor.decode(output_tokens, skip_special_tokens=True).strip()
        if field_name in {"title", "preview"}:
            raw_decoded = self.processor.decode(output_tokens, skip_special_tokens=False)
            preview_raw = raw_decoded.replace("\n", "\\n")
            if len(preview_raw) > 200:
                preview_raw = preview_raw[:200] + "..."
            token_preview = output_tokens[:24].detach().cpu().tolist()
            self._log(f"[translate] {field_name} raw_decode={preview_raw}")
            self._log(f"[translate] {field_name} output_tokens_head={token_preview}")
        self._log(f"[translate] decode done in {time.monotonic() - decode_started_at:.1f}s")
        return translated

    def _translate_in_chunks(self, text: str, max_new_tokens: int, label: str) -> str:
        chunks = self._split_for_translation(text)
        if not chunks:
            return ""

        if len(chunks) == 1:
            return self._translate_text(chunks[0], max_new_tokens, label)

        self._log(
            f"[translate] {label} split into {len(chunks)} chunks; "
            f"sizes={[len(chunk) for chunk in chunks]} html={self._looks_like_html(text)}"
        )

        translated_chunks = []
        for index, chunk in enumerate(chunks, start=1):
            chunk_started_at = time.monotonic()
            translated_chunks.append(self._translate_text(chunk, max_new_tokens, label))
            self._log(
                f"[translate] {label} chunk {index}/{len(chunks)} finished "
                f"in {time.monotonic() - chunk_started_at:.1f}s"
            )
        return "\n\n".join(translated_chunks)

    def _fallback_text(self, translated: str, source: str, field_name: str) -> str:
        cleaned = translated.strip()
        if cleaned:
            return cleaned
        fallback = source.strip()
        self._log(f"[translate] {field_name} fallback to source text because translation was blank")
        return fallback

    def translate_article(self, payload: TranslationRequest) -> TranslationResponse:
        queued_at = time.monotonic()
        self._log(
            "[translate] request queued "
            f"request_id={payload.request_id or ''} title_chars={len(payload.title)} "
            f"preview_chars={len(payload.preview_text)} body_chars={len(payload.body_text)}"
        )
        with self.request_lock:
            started_at = time.monotonic()
            self._log(f"[translate] request started after {started_at - queued_at:.1f}s in queue")
            self._enter_translation_job()
            try:
                title_started_at = time.monotonic()
                title_raw = self._translate_text(payload.title, self.settings.max_new_tokens_title, "title")
                title_ru = self._fallback_text(title_raw, payload.title, "title")
                self._log(f"[translate] title finished in {time.monotonic() - title_started_at:.1f}s")

                preview_started_at = time.monotonic()
                preview_raw = self._translate_text(payload.preview_text, self.settings.max_new_tokens_preview, "preview")
                preview_text_ru = self._fallback_text(preview_raw, payload.preview_text, "preview")
                self._log(f"[translate] preview finished in {time.monotonic() - preview_started_at:.1f}s")

                body_started_at = time.monotonic()
                body_raw = self._translate_in_chunks(payload.body_text, self.settings.max_new_tokens_body, "body")
                body_text_ru = self._fallback_text(body_raw, payload.body_text, "body")
                self._log(f"[translate] body finished in {time.monotonic() - body_started_at:.1f}s")

                latency_ms = int((time.monotonic() - started_at) * 1000)
                response = TranslationResponse(
                    request_id=payload.request_id or "",
                    status="ok",
                    title_ru=title_ru,
                    preview_text_ru=preview_text_ru,
                    body_text_ru=body_text_ru,
                    translated_title=title_ru,
                    translated_preview_text=preview_text_ru,
                    translated_body_text=body_text_ru,
                    model=self.settings.model_id,
                    latency_ms=latency_ms,
                    error=None,
                )
                self._log(f"[translate] request finished in {time.monotonic() - started_at:.1f}s")
                return response
            except Exception as exc:
                self._log(f"[translate] request failed after {time.monotonic() - started_at:.1f}s: {exc}")
                raise
            finally:
                if self.settings.unload_model_after_request:
                    self._unload_model()
                self._exit_translation_job()


app = FastAPI(title="farmspot-local-translation", version="1.0.0")
settings = get_settings()
translator = Translator(settings)


@app.get("/health")
def health() -> dict:
    return {
        "status": "ok",
        "model": settings.model_id,
        "device": settings.device,
        "dtype": settings.dtype,
        "cuda": torch.cuda.is_available(),
        "model_loaded": translator.model is not None,
    }


@app.post("/translate/news", response_model=TranslationResponse)
def translate_news(payload: TranslationRequest, x_translation_token: Optional[str] = Header(default=None)) -> TranslationResponse:
    if settings.translation_token:
        if not x_translation_token or x_translation_token != settings.translation_token:
            raise HTTPException(status_code=401, detail="Unauthorized")

    return translator.translate_article(payload)
