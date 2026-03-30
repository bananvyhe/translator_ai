# farmspot Windows Translation Service

Local translation API for farmspot using `google/translategemma-4b-it` on Windows + RTX 3080.

## 1) Prerequisites

- Python 3.11
- NVIDIA driver + CUDA-capable GPU
- OpenSSH client (`ssh`)
- Access approved for gated model: <https://huggingface.co/google/translategemma-4b-it>

## 2) Install dependencies

```powershell
py -3.11 -m venv .venv
.\.venv\Scripts\python -m pip install --upgrade pip
.\.venv\Scripts\python -m pip install torch==2.6.0+cu124 torchvision==0.21.0+cu124 torchaudio==2.6.0+cu124 --index-url https://download.pytorch.org/whl/cu124
.\.venv\Scripts\python -m pip install -r requirements.txt hf_xet
```

## 3) Configure `.env`

```powershell
Copy-Item .env.example .env
```

Required:

- `TRANSLATION_TOKEN=...`
- `HUGGINGFACE_HUB_TOKEN=hf_...`
- `SSH_PASSWD=...` if you want password-based SSH
- `VPS_HOSTKEY_SHA256=SHA256:...` to pin the VPS host key fingerprint

Miner automation is disabled by default:

- `MANAGE_MINER=false`
- `MINER_PROCESS_NAME=onezerominer.exe`
- `MINER_STOP_PATH=C:\cofex\translation\stop_onezerominer.cmd`
- `MINER_LAUNCH_PATH=C:\Users\fuler\Desktop\qubitcoin`
- `MINER_RESTART_DELAY_SEC=15`
- `GENERATION_NUM_BEAMS=4` for a balanced quality/speed default
- `MAX_NEW_TOKENS_TITLE=192`
- `MAX_NEW_TOKENS_PREVIEW=512`
- `MAX_NEW_TOKENS_BODY=2048`
- `GENERATION_LENGTH_PENALTY=1.0`
- `GENERATION_REPETITION_PENALTY=1.0`
- `MAX_CHUNK_CHARS=800` to `1200` is a safer speed-oriented range for `TranslateGemma`
- `HF_OFFLINE_MODE=true`
- `VPS_HOST=81.163.29.109`
- `VPS_USER=root`
- `REMOTE_PORT=19191`
- `REMOTE_BIND_ADDRESS=0.0.0.0`
- `LOCAL_PORT=8008`
- `SSH_KEY_PATH=C:\Users\fuler\.ssh\farmspot_vps_ed25519`

## 4) Start everything manually

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run_windows_translation.ps1 -VpsHost <VPS_HOST> -VpsUser <VPS_USER>
```

For a visible desktop launch with separate service, tunnel, and monitor windows, run:

```cmd
start_visible_translation.cmd
```

If you prefer PowerShell directly:

```powershell
powershell -ExecutionPolicy Bypass -File .\start_visible_translation.ps1
```

To stop them again:

```cmd
stop_visible_translation.cmd
```

Or in PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\stop_visible_translation.ps1
```

That starts:

- local translator on `127.0.0.1:8008`
- reverse tunnel to VPS `127.0.0.1:19191`

If you want the VPS host itself to see the tunnel, the default `127.0.0.1:19191` binding is enough. If the client runs in Docker on the VPS and needs to reach it via `host.docker.internal`, bind the tunnel to all interfaces instead and make sure `sshd` allows remote ports on non-loopback addresses. On the VPS, that usually means `GatewayPorts clientspecified` or `GatewayPorts yes` in `sshd_config`.

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\start_tunnel.ps1 -VpsHost <VPS_HOST> -VpsUser <VPS_USER> -RemoteBindAddress 0.0.0.0
```

The root launcher at `start_visible_translation.cmd` opens three visible windows:

- service
- tunnel
- monitor

It is the easiest way to see the stop/start and translation flow live.

Rule of thumb:

- use `C:\cofex\translation\start_visible_translation.cmd` to start
- use `C:\cofex\translation\start_idle_translation.cmd` if you want idle-mining mode with automatic miner stop/start around translations
- use `C:\cofex\translation\stop_visible_translation.cmd` to stop
- keep settings in `.env`; the launcher reads them on start, so changes show up automatically
- if you want miner control back later, set `MANAGE_MINER=true`
- the service handles one translation request at a time, so a busy VPS should wait for each response before sending the next

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\start_service.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\start_tunnel.ps1 -VpsHost <VPS_HOST> -VpsUser <VPS_USER>
```

## 5) Install autostart

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install_autostart.ps1 -VpsHost <VPS_HOST> -VpsUser <VPS_USER>
```

This registers a scheduled task that starts the launcher on logon and restarts it if it exits.

Remove it with:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\uninstall_autostart.ps1
```

## 5.1) Stop everything

To stop the current translation service and reverse tunnel without touching other PowerShell sessions:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\stop_windows_translation.ps1
```

If you also want to remove the autostart task:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\stop_windows_translation.ps1 -DisableAutostart
```

## 6) API

Endpoints:

- `GET /health`
- `POST /translate/news`

Request:

```json
{
  "title": "Original title",
  "preview_text": "Original preview",
  "body_text": "Original body"
}
```

Response:

```json
{
  "request_id": "debug-1",
  "status": "ok",
  "title_ru": "...",
  "preview_text_ru": "...",
  "body_text_ru": "...",
  "translated_title": "...",
  "translated_preview_text": "...",
  "translated_body_text": "...",
  "model": "google/translategemma-4b-it",
  "latency_ms": 1234,
  "error": null
}
```

## 7) farmspot on VPS

Set translation client to:

- base URL: `http://127.0.0.1:19191` if the service runs on the VPS host, or `http://host.docker.internal:19191` only after binding the tunnel to `0.0.0.0` and opening that port to the container
- endpoint: `/translate/news`
- header: `X-Translation-Token: <same TRANSLATION_TOKEN>`

## 8) Pitfalls

- `TranslateGemma 4B IT` is slow on long requests. Treat `title`, `preview_text`, and `body_text` as separate translations. Do not merge them into one large prompt.
- Do not send raw HTML to the model. The current service translates plain text and rebuilds the final structure outside the model.
- The service now splits long `body_text` by paragraphs first, then splits oversized paragraphs by softer boundaries. If translation becomes too slow, reduce `MAX_CHUNK_CHARS` before changing anything else.
- Very large `max_new_tokens` values slow down short fields badly. Short `title` and `preview_text` should stay on tight token budgets.
- The local API must return both legacy fields (`title_ru`, `preview_text_ru`, `body_text_ru`) and farmspot-compatible fields (`translated_title`, `translated_preview_text`, `translated_body_text`). If farmspot shows `Translator response missing translated_title`, first verify the local `/translate/news` response schema.
- Blank model output is possible. The local service now falls back to source text for blank `title`, `preview_text`, or `body_text` so the VPS client does not fail the whole article.
- If VPS articles stay in `pending` and `NewsTranslatePendingArticlesJob` starts and finishes in a few milliseconds, check Redis for a stale lock:

```ruby
LOCK_KEY = "news:translation:pending_articles_lock"
```

- A stale `news:translation:pending_articles_lock` prevents new translation jobs from processing `pending` articles. On this project it was observed with a TTL of about 12 hours, so jobs looked "successful" while doing nothing.
- If that happens, remove only the stale translation lock and enqueue one fresh `NewsTranslatePendingArticlesJob`.
- `stop_visible_translation.cmd` should stop the visible launcher windows and free port `8008`. If `8008` is still busy after stop, check for an older Python process still listening on the port.
- The visible launcher relies on PID files in `logs\`. Current names are:
  `farmspot_service.pid`
  `farmspot_tunnel.pid`
  `farmspot_monitor.pid`
- If stop logic ever regresses, confirm it still targets these PID file names and not older names such as `service.pid` or `tunnel.pid`.
- Runtime translation logs are written to `logs\runtime-YYYYMMDD-HHMMSS.log` in addition to the live console window. Use that file to inspect `request queued`, `generate done`, `raw_decode`, and `output_tokens_head` after a run.

## 9) Idle Mode

If you want the GPU to stay free while the VPS is idle, use these settings together:

- `MANAGE_MINER=true`
- `LAZY_MODEL_LOAD=true`
- `UNLOAD_MODEL_AFTER_REQUEST=true`

That mode makes the translator load only when the first request arrives, stop the miner while translation is running, and keep the model loaded until the idle window expires after the last request. It is slower for repeated back-to-back translations only if the gap exceeds the idle window, but it is the right setup when you want the miner to come back automatically after a batch.

Keep `MINER_PROCESS_NAME` pointed at the real miner process name and `MINER_LAUNCH_PATH` pointed at `C:\bbb\onezerominer-win64-1.7.4\qubitcoin.bat` if you want the automatic stop/start hooks to work reliably.

For convenience, `start_idle_translation.cmd` enables that mode and starts the miner if it is not already running before opening the translation launcher.

If you ever see `dict object has no attribute 'en-US'`, set `SOURCE_LANG_CODE=en` in `.env` or keep the default. The current template accepts `en`, `ru`, and regional variants that actually exist in the model's language map.

Because the service translates in paragraph-sized chunks, these token limits are tuned per chunk rather than for one giant body prompt. The effective token budget is still computed per chunk in code, so these values only act as upper caps. If you want more literal output for a specific article, raise `MAX_NEW_TOKENS_BODY` first.

When `MANAGE_MINER=true`, `MINER_RESTART_DELAY_SEC` is treated as an idle window after the last translation. During that window the model stays loaded and the miner stays off; after the window expires, the model unloads and the miner restarts.
