param(
  [string]$VpsHost,
  [string]$VpsUser,
  [string]$SshKeyPath,
  [int]$SinceHours = 24,
  [int]$ArticleId = 0,
  [int]$TimeoutMinutes = 30,
  [switch]$ResetRecent,
  [switch]$ClearTranslationJobs,
  [switch]$ClearLock = $true,
  [switch]$NoWait
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot | Split-Path -Parent

function Import-DotEnv {
  param([string]$Path)

  if (-not (Test-Path $Path)) { return }

  Get-Content $Path | ForEach-Object {
    $line = $_.Trim()
    if (-not $line -or $line.StartsWith('#')) { return }
    $idx = $line.IndexOf('=')
    if ($idx -lt 1) { return }
    $name = $line.Substring(0, $idx).Trim()
    $value = $line.Substring($idx + 1)
    if (-not [string]::IsNullOrWhiteSpace($name)) {
      [Environment]::SetEnvironmentVariable($name, $value, 'Process')
    }
  }
}

Import-DotEnv -Path (Join-Path $root '.env')

if ([string]::IsNullOrWhiteSpace($VpsHost)) { $VpsHost = $env:VPS_HOST }
if ([string]::IsNullOrWhiteSpace($VpsUser)) { $VpsUser = $env:VPS_USER }
if ([string]::IsNullOrWhiteSpace($SshKeyPath)) { $SshKeyPath = $env:SSH_KEY_PATH }

if ([string]::IsNullOrWhiteSpace($VpsHost)) { $VpsHost = '81.163.29.109' }
if ([string]::IsNullOrWhiteSpace($VpsUser)) { $VpsUser = 'root' }
if ([string]::IsNullOrWhiteSpace($SshKeyPath)) { $SshKeyPath = "$env:USERPROFILE\.ssh\farmspot_vps_ed25519" }

if (-not (Test-Path $SshKeyPath)) {
  throw "SSH key not found: $SshKeyPath"
}

$waitFlag = (-not $NoWait).ToString().ToLower()
$clearLockFlag = $ClearLock.ToString().ToLower()
$clearJobsFlag = $ClearTranslationJobs.ToString().ToLower()
$resetRecentFlag = $ResetRecent.ToString().ToLower()

$ruby = @"
require "redis"
require "sidekiq/api"

redis = Redis.new(url: RuntimeConfig.redis_url)

clear_lock = $clearLockFlag
clear_jobs = $clearJobsFlag
reset_recent = $resetRecentFlag
wait_for_result = $waitFlag
article_id = $ArticleId
since_hours = $SinceHours
start_time = Time.current
lock_key = "news:translation:pending_articles_lock"

if clear_lock
  removed = redis.del(lock_key)
  puts "removed_lock=#{removed}"
end

if clear_jobs
  removed_jobs = 0
  [Sidekiq::Queue.all, [Sidekiq::RetrySet.new], [Sidekiq::ScheduledSet.new], [Sidekiq::DeadSet.new]].flatten.each do |collection|
    collection.each do |job|
      next unless job.klass == "NewsTranslatePendingArticlesJob"
      job.delete
      removed_jobs += 1
    end
  end
  puts "removed_translation_jobs=#{removed_jobs}"
end

scope = NewsArticle.where(created_at: since_hours.hours.ago..Time.current)
scope = scope.where(id: article_id) if article_id > 0

if reset_recent
  reset_count = scope.update_all(
    translation_status: "pending",
    translation_error: nil,
    translation_completed_at: nil,
    updated_at: Time.current
  )
  puts "reset_articles=#{reset_count}"
else
  puts "reset_articles=0"
end

jid = NewsTranslatePendingArticlesJob.perform_async
puts "enqueued_jid=#{jid}"
puts "workers=#{Sidekiq::Workers.new.size}"
puts "queue_default=#{Sidekiq::Queue.new("default").size}"
puts "lock_exists=#{redis.exists?(lock_key)}"

if wait_for_result && article_id > 0
  deadline = Time.current + (90.minutes)
  loop do
    article = NewsArticle.find_by(id: article_id)
    break unless article

    puts "poll_status=#{article.translation_status} completed_at=#{article.translation_completed_at.inspect} error=#{article.translation_error.to_s.inspect}"
    break if article.translated? || article.failed?
    break if Time.current >= deadline

    sleep 10
  end

  article = NewsArticle.find_by(id: article_id)
  if article
    puts "final_status=#{article.translation_status}"
    puts "final_error=#{article.translation_error.to_s.inspect}"
    puts "final_completed_at=#{article.translation_completed_at.inspect}"
  end
end

summary_scope = NewsArticle.where(created_at: since_hours.hours.ago..Time.current)
summary_scope = summary_scope.where(id: article_id) if article_id > 0
summary = summary_scope.group(:translation_status).count
summary.keys.sort.each do |status|
  puts "status_#{status}=#{summary[status]}"
end
"@

$sshArgs = @('-i', $SshKeyPath, "$VpsUser@$VpsHost", 'docker exec -i farmspot-web-1 bin/rails runner -')

$ruby | & ssh.exe @sshArgs
