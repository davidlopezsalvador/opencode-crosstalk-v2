# opencode-crosstalk-v2 - Cross-session messaging for OpenCode V2 (PowerShell)
# Usage: .\cross.ps1 <command> [options]
param(
    [Parameter(Position=0)][string]$Command = 'help',
    [Parameter(ValueFromRemainingArguments=$true)][string[]]$ArgsList = @()
)

$ErrorActionPreference = 'Stop'
$script:Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:Parent = Split-Path -Parent $script:Root
$script:ConfigPath = Join-Path $script:Root 'cross.config.json'
$script:LocalPath = Join-Path $script:Root 'cross.config.local.json'

function Get-CrossConfig {
    if (-not (Test-Path $script:ConfigPath)) { throw "CONFIG_NOT_FOUND: $script:ConfigPath" }
    $cfg = Get-Content $script:ConfigPath -Raw | ConvertFrom-Json
    if (Test-Path $script:LocalPath) {
        $local = Get-Content $script:LocalPath -Raw | ConvertFrom-Json
        foreach ($p in $local.PSObject.Properties) {
            if ($null -ne $p.Value -and "$($p.Value)" -ne '') { $cfg.$($p.Name) = $p.Value }
        }
    }
    # env overrides
    foreach ($k in @('my_session_id','my_model')) {
        $envKey = 'CROSS_MY_' + $k.ToUpper()
        if ([Environment]::GetEnvironmentVariable($envKey)) { $cfg.$k = [Environment]::GetEnvironmentVariable($envKey) }
    }
    if ([Environment]::GetEnvironmentVariable('OPENCODE_SERVER_PASSWORD')) { $cfg.password_override = [Environment]::GetEnvironmentVariable('OPENCODE_SERVER_PASSWORD') }
    return $cfg
}

function Get-CrossPassword {
    if ($env:OPENCODE_SERVER_PASSWORD) { return $env:OPENCODE_SERVER_PASSWORD }
    $envFile = Join-Path $env:USERPROFILE '.config\opencode\.env'
    if (Test-Path $envFile) {
        $m = [regex]::Match((Get-Content $envFile -Raw), '(?m)^\s*OPENCODE_SERVER_PASSWORD\s*=\s*(.+?)\s*$')
        if ($m.Success) { return $m.Groups[1].Value.Trim() }
    }
    return $null
}

function Invoke-CrossApi {
    param([string]$Method, [string]$Path, [string]$BodyJson = '', [int]$Port = 4096, [string]$Password = '', [int]$TimeoutSec = 30)
    $url = "http://127.0.0.1:$Port/api$Path"
    $tmpOut = Join-Path $env:TEMP ("cross_api_" + [System.Guid]::NewGuid().ToString('N') + ".txt")
    $args = @('-s', '--max-time', "$TimeoutSec", '-u', "opencode:$Password", '-X', $Method, '-o', $tmpOut, '-w', '%{http_code}')
    if ($BodyJson) {
        $tmpBody = Join-Path $env:TEMP ("cross_body_" + [System.Guid]::NewGuid().ToString('N') + ".json")
        [System.IO.File]::WriteAllText($tmpBody, $BodyJson, (New-Object System.Text.UTF8Encoding($false)))
        $args += @('-H', 'Content-Type: application/json', '--data-binary', "@$tmpBody")
    }
    $args += $url
    $code = & curl.exe @args 2>$null
    $body = if (Test-Path $tmpOut) { [string](Get-Content $tmpOut -Raw) } else { '' }
    Remove-Item $tmpOut -ErrorAction SilentlyContinue
    if ($tmpBody) { Remove-Item $tmpBody -ErrorAction SilentlyContinue }
    $statusCode = 0
    if ($code -match '^\d+$') { $statusCode = [int]$code } 
    return @{ status = $statusCode; body = $body }
}

function Write-Json($obj) { $obj | ConvertTo-Json -Depth 6 -Compress }

# Parse args
$flags = @{}
$i = 0
while ($i -lt $ArgsList.Count) {
    $a = $ArgsList[$i]
    if ($a -match '^--(.+)$') {
        $key = $Matches[1]
        if ($i + 1 -lt $ArgsList.Count -and -not $ArgsList[$i+1].StartsWith('--')) {
            $flags[$key] = $ArgsList[$i+1]; $i += 2
        } else {
            $flags[$key] = $true; $i++
        }
    } else { $i++ }
}
$PortArg = if ($flags['port']) { [int]$flags['port'] } else { 0 }
$PasswordArg = if ($flags['password']) { [string]$flags['password'] } else { '' }
# default port from config if not specified
if ($PortArg -eq 0) {
    try { $cfg = Get-CrossConfig; if ($cfg.port) { $PortArg = [int]$cfg.port } } catch {}
    if ($PortArg -eq 0) { $PortArg = 4096 }
}

switch ($Command.ToLower()) {
    'help' {
        Write-Host "opencode-crosstalk-v2 - Cross-session messaging for OpenCode V2"
        Write-Host ""
        Write-Host "Commands:"
        Write-Host "  health              Verify server connection"
        Write-Host "  whoami              Show current session info"
        Write-Host "  sessions            List all sessions"
        Write-Host "  read --session ID   Read messages from a session"
        Write-Host "  send --dest ID --text '...'   Send a message (admits+schedules)"
        Write-Host "  wait --session ID   Block until agent loop is idle"
        Write-Host "  config --list       Show configuration"
        Write-Host ""
        Write-Host "Global flags: --port N, --password P"
    }
    'health' {
        $pw = if ($PasswordArg) { $PasswordArg } else { Get-CrossPassword }
        $code = & curl.exe -s -o NUL -w "%{http_code}" --max-time 5 -u "opencode:$pw" "http://127.0.0.1:$PortArg/api/session" 2>$null
        $ok = ($code -eq '200')
        $obj = @{ ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); cmd = 'health'; ok = $ok; code = 0; port = $PortArg; healthy = $ok }
        Write-Json $obj
    }
    'whoami' {
        $cfg = Get-CrossConfig
        $pw = if ($PasswordArg) { $PasswordArg } else { Get-CrossPassword }
        $api = Invoke-CrossApi -Method 'GET' -Path "/session/$($cfg.my_session_id)" -Port $PortArg -Password $pw
        if ($api.status -ge 400 -or $api.status -eq 0) {
            $obj = @{ ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); cmd = 'whoami'; ok = $false; code = 3; error = "HTTP $($api.status)"; detail = $api.body }
            Write-Json $obj; return
        }
        $s = $api.body | ConvertFrom-Json
        $data = if ($s.data) { $s.data } else { $s }
        $obj = @{ ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); cmd = 'whoami'; ok = ($api.status -eq 200); code = 0; session_id = $cfg.my_session_id; title = $data.title; model = $data.model.id; directory = $data.location.directory }
        Write-Json $obj
    }
    'sessions' {
        $pw = if ($PasswordArg) { $PasswordArg } else { Get-CrossPassword }
        $api = Invoke-CrossApi -Method 'GET' -Path '/session' -Port $PortArg -Password $pw
        if ($api.status -ge 400 -or $api.status -eq 0) {
            $obj = @{ ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); cmd = 'sessions'; ok = $false; code = 3; error = "HTTP $($api.status)"; detail = $api.body }
            Write-Json $obj; return
        }
        $parsed = $api.body | ConvertFrom-Json
        $all = if ($parsed.data) { $parsed.data } elseif ($parsed -is [array]) { $parsed } else { @($parsed) }
        $dirFilter = if ($flags['directory']) { [string]$flags['directory'] } else { '' }
        $list = @()
        foreach ($s in $all) {
            $dir = if ($s.location -and $s.location.directory) { $s.location.directory } else { $s.directory }
            if ($dirFilter -and $dir -and -not ($dir.ToLower() -eq $dirFilter.ToLower())) { continue }
            $list += @{ id = $s.id; title = $s.title; model = if ($s.model.id) { $s.model.id } else { '' }; directory = $dir }
        }
        $obj = @{ ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); cmd = 'sessions'; ok = ($api.status -eq 200); code = 0; count = $list.Count; sessions = $list }
        Write-Json $obj
    }
    'read' {
        $sid = [string]$flags['session']
        if (-not $sid) { Write-Host "ERROR: --session required"; exit 1 }
        $pw = if ($PasswordArg) { $PasswordArg } else { Get-CrossPassword }
        $limit = if ($flags['limit']) { [int]$flags['limit'] } else { 20 }
        $api = Invoke-CrossApi -Method 'GET' -Path "/session/$sid/message?limit=$limit" -Port $PortArg -Password $pw
        if ($api.status -ge 400 -or $api.status -eq 0) {
            $obj = @{ ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); cmd = 'read'; ok = $false; code = 3; error = "HTTP $($api.status)"; detail = $api.body }
            Write-Json $obj; return
        }
        $parsed = $api.body | ConvertFrom-Json
        $msgs = if ($parsed.data) { $parsed.data } elseif ($parsed -is [array]) { $parsed } else { @($parsed) }
        $out = @()
        foreach ($m in $msgs) {
            $role = $m.type
            $text = ''
            if ($role -eq 'user') { $text = $m.text }
            elseif ($role -eq 'assistant') { $text = ($m.content | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text }) -join "`n" }
            elseif ($m.text) { $text = $m.text }
            elseif ($m.content) { $text = ($m.content | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text }) -join "`n" }
            $out += @{ id = $m.id; role = $role; text = $text; created = $m.time.created }
        }
        $obj = @{ ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); cmd = 'read'; ok = ($api.status -eq 200); code = 0; count = $out.Count; messages = $out }
        Write-Json $obj
    }
    'send' {
        $dest = [string]$flags['dest']
        $text = [string]$flags['text']
        if (-not $dest -or -not $text) { Write-Host "ERROR: --dest and --text required"; exit 1 }
        $pw = if ($PasswordArg) { $PasswordArg } else { Get-CrossPassword }
        $cfg = Get-CrossConfig
        $bodyObj = @{ text = $text }
        if ($flags['delivery']) { $bodyObj.delivery = [string]$flags['delivery'] }
        if ($flags['no-resume']) { $bodyObj.resume = $false }
        $body = $bodyObj | ConvertTo-Json -Compress
        $api = Invoke-CrossApi -Method 'POST' -Path "/session/$dest/prompt" -BodyJson $body -Port $PortArg -Password $pw -TimeoutSec 120
        $ok = ($api.status -ge 200 -and $api.status -lt 300)
        $obj = @{ ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); cmd = 'send'; ok = $ok; code = 0; dest = $dest; http_status = $api.status; response = $api.body }
        Write-Json $obj
        if ($ok -and $flags['wait']) {
            $waitApi = Invoke-CrossApi -Method 'POST' -Path "/experimental/session/$dest/wait" -Port $PortArg -Password $pw -TimeoutSec 300
            Write-Host ("wait: HTTP " + $waitApi.status)
        }
    }
    'wait' {
        $sid = [string]$flags['session']
        if (-not $sid) { Write-Host "ERROR: --session required"; exit 1 }
        $pw = if ($PasswordArg) { $PasswordArg } else { Get-CrossPassword }
        $api = Invoke-CrossApi -Method 'POST' -Path "/experimental/session/$sid/wait" -Port $PortArg -Password $pw -TimeoutSec 300
        $obj = @{ ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); cmd = 'wait'; ok = ($api.status -ge 200 -and $api.status -lt 300); code = 0; session = $sid; http_status = $api.status }
        Write-Json $obj
    }
    'config' {
        $cfg = Get-CrossConfig
        if ($flags['list']) {
            Write-Json @{ ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); cmd = 'config'; ok = $true; code = 0; config = $cfg }
        } else {
            Write-Host "Usage: config --list"
        }
    }
    default {
        Write-Host "Unknown command: $Command. Use 'help'."
    }
}
