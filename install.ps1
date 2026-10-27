# opencode-crosstalk-v2 setup helper
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 [-SessionId ses_X] [-Model name] [-NonInteractive]
param(
    [string]$SessionId = '',
    [string]$Model = '',
    [switch]$NonInteractive
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $MyInvocation.MyCommand.Path -Parent
$cli = Join-Path $root 'cross\cross.ps1'
$localPath = Join-Path $root 'cross\cross.config.local.json'

Write-Host "== opencode-crosstalk-v2 setup =="

if (-not (Test-Path $cli)) { Write-Host "ERROR: cross\cross.ps1 not found"; exit 1 }

# password
$password = $env:OPENCODE_SERVER_PASSWORD
if (-not $password) {
    $envFile = Join-Path $env:USERPROFILE '.config\opencode\.env'
    if (Test-Path $envFile) {
        $m = [regex]::Match((Get-Content $envFile -Raw), '(?m)^\s*OPENCODE_SERVER_PASSWORD\s*=\s*(.+?)\s*$')
        if ($m.Success) { $password = $m.Groups[1].Value.Trim() }
    }
}
if (-not $password) { Write-Host "ERROR: OPENCODE_SERVER_PASSWORD not found. Set env var or add to ~/.config/opencode/.env"; exit 1 }

# detect port: try 4096 first, then scan 30000-40000
$port = 0
foreach ($p in @(4096) + (30000..40000)) {
    try {
        $code = & curl.exe -s -o NUL -w "%{http_code}" --max-time 2 -u "opencode:$password" "http://127.0.0.1:$p/api/session" 2>$null
        if ($code -eq '200') { $port = $p; break }
    } catch {}
}
if (-not $port) { Write-Host "ERROR: no OpenCode server found. Start with: opencode serve --port 4096"; exit 1 }
Write-Host "Server detected on port $port"

$baseUrl = "http://127.0.0.1:$port"
$sessions = & curl.exe -s -u "opencode:$password" "$baseUrl/api/session" | ConvertFrom-Json
$sessions = if ($sessions.data) { $sessions.data } else { $sessions }
if (-not $sessions -or @($sessions).Count -eq 0) { Write-Host "ERROR: no sessions found"; exit 2 }

# identity
$chosen = $null
if ($SessionId) {
    $chosen = $sessions | Where-Object { $_.id -eq $SessionId } | Select-Object -First 1
    if (-not $chosen) { Write-Host "ERROR: session $SessionId not found"; exit 2 }
} else {
    $candidates = @($sessions | Where-Object { $_.title -match '(?i)leader|lider' })
    if ($candidates.Count -eq 1) { $chosen = $candidates[0] }
    elseif ($candidates.Count -gt 1) {
        Write-Host "Multiple candidates found. Specify -SessionId:"
        $candidates | ForEach-Object { Write-Host "  $($_.id)  $($_.title)" }
        exit 2
    } else {
        # pick most recently updated
        $chosen = $sessions | Sort-Object { $_.time.updated } -Descending | Select-Object -First 1
        Write-Host "No unambiguous leader found. Using most recent session:"
        Write-Host "  id: $($chosen.id)"
        Write-Host "  title: $($chosen.title)"
        if (-not $NonInteractive) {
            $a = Read-Host "Use this? [Y/n]"
            if ($a -and $a.ToLower() -ne 'y') { exit 2 }
        }
    }
}

if (-not $Model) { $Model = $chosen.model.id }

$local = @{
    my_session_id = $chosen.id
    my_model = $Model
    my_role = 'leader'
}
$local | ConvertTo-Json -Depth 3 | Set-Content -Path $localPath -Encoding UTF8
Write-Host "Config written to $localPath"
Write-Host "  session: $($chosen.id)"
Write-Host "  model: $Model"
Write-Host ""
Write-Host "Done. Run: cd cross; .\cross.ps1 health"
