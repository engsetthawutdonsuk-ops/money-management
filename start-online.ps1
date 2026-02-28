# ============================================================
#  Money Management - Internet-Accessible Server
#  Starts the local server + Cloudflare Quick Tunnel
#  so you can access from ANYWHERE (iPhone, work, etc.)
# ============================================================

$port = 8888
$cfDir = Join-Path $PSScriptRoot '.cloudflared'
$cfExe = Join-Path $cfDir 'cloudflared.exe'

# ===== 1) Download cloudflared if not present =====
if (-not (Test-Path $cfExe)) {
    Write-Host ""
    Write-Host "  [SETUP] Downloading Cloudflare Tunnel (first time only)..." -ForegroundColor Yellow
    Write-Host ""

    if (-not (Test-Path $cfDir)) {
        New-Item -ItemType Directory -Path $cfDir -Force | Out-Null
    }

    $dlUrl = 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe'
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $dlUrl -OutFile $cfExe -UseBasicParsing
        Write-Host "  [OK] Downloaded cloudflared.exe" -ForegroundColor Green
    }
    catch {
        Write-Host "  [FAIL] Could not download cloudflared." -ForegroundColor Red
        Write-Host "  Download manually from:" -ForegroundColor Gray
        Write-Host "  $dlUrl" -ForegroundColor Cyan
        Write-Host "  Save as: $cfExe" -ForegroundColor Gray
        Read-Host "  Press Enter to exit"
        exit 1
    }
}

# ===== 2) Start the local server in background =====
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Starting Money Management Server..." -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$serverScript = Join-Path $PSScriptRoot 'server.ps1'
$serverJob = Start-Job -ScriptBlock {
    param($s)
    & powershell -ExecutionPolicy Bypass -File $s
} -ArgumentList $serverScript

Start-Sleep -Seconds 2

# ===== 3) Start Cloudflare Quick Tunnel =====
Write-Host "  Starting Cloudflare Tunnel..." -ForegroundColor Yellow
Write-Host ""

$tunnelLog = Join-Path $cfDir 'tunnel.log'

$tunnelProcess = Start-Process -FilePath $cfExe `
    -ArgumentList "tunnel","--url","http://localhost:$port","--no-autoupdate" `
    -RedirectStandardError $tunnelLog `
    -PassThru -WindowStyle Hidden

# Wait for tunnel URL
$publicUrl = $null
$maxWait = 30
$waited = 0

while ($waited -lt $maxWait -and -not $publicUrl) {
    Start-Sleep -Seconds 1
    $waited++
    if (Test-Path $tunnelLog) {
        $logText = Get-Content $tunnelLog -Raw -ErrorAction SilentlyContinue
        if ($logText -match 'https://[a-z0-9\-]+\.trycloudflare\.com') {
            $publicUrl = $matches[0]
        }
    }
    if ($waited % 5 -eq 0) {
        Write-Host "  Waiting for tunnel... ($waited sec)" -ForegroundColor Gray
    }
}

$ip = (Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.*' } |
    Select-Object -First 1).IPAddress

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Money Management - ONLINE MODE" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  [PC]  Local:   http://localhost:$port" -ForegroundColor Yellow
Write-Host "  [LAN] WiFi:    http://${ip}:$port" -ForegroundColor Yellow
Write-Host ""

if ($publicUrl) {
    Write-Host "  [INTERNET] FROM ANYWHERE:" -ForegroundColor White
    Write-Host "  >>> $publicUrl <<<" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Share this link with your girlfriend!" -ForegroundColor Magenta
    Write-Host "  Works on iPhone, any computer, any network!" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "  iPhone: Open in Safari > Share > Add to Home Screen" -ForegroundColor Gray

    try {
        Set-Clipboard -Value $publicUrl
        Write-Host ""
        Write-Host "  [COPIED] Link copied to clipboard!" -ForegroundColor Green
    }
    catch {
        Write-Host ""
        Write-Host "  (Copy the link above manually)" -ForegroundColor Gray
    }
}
else {
    Write-Host "  [!] Tunnel not ready yet. Check log: $tunnelLog" -ForegroundColor Red
    Write-Host "  The local server still works fine." -ForegroundColor Gray
}

Write-Host ""
Write-Host "  Data auto-syncs between all devices!" -ForegroundColor White
Write-Host "  App works offline after first load!" -ForegroundColor White
Write-Host ""
Write-Host "  Press Ctrl+C to stop everything" -ForegroundColor DarkGray
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# ===== 4) Keep alive =====
try {
    while ($true) {
        if ($tunnelProcess.HasExited) {
            Write-Host "$(Get-Date -Format 'HH:mm:ss') [!] Tunnel stopped. Restarting..." -ForegroundColor Yellow
            $tunnelProcess = Start-Process -FilePath $cfExe `
                -ArgumentList "tunnel","--url","http://localhost:$port","--no-autoupdate" `
                -RedirectStandardError $tunnelLog `
                -PassThru -WindowStyle Hidden
        }

        if ($serverJob.State -eq 'Failed') {
            Write-Host "$(Get-Date -Format 'HH:mm:ss') [!] Server stopped unexpectedly" -ForegroundColor Red
            break
        }

        Start-Sleep -Seconds 5
    }
}
finally {
    Write-Host ""
    Write-Host "  Shutting down..." -ForegroundColor Yellow

    if ($tunnelProcess -and -not $tunnelProcess.HasExited) {
        Stop-Process -Id $tunnelProcess.Id -Force -ErrorAction SilentlyContinue
    }

    if ($serverJob) {
        Stop-Job -Job $serverJob -ErrorAction SilentlyContinue
        Remove-Job -Job $serverJob -Force -ErrorAction SilentlyContinue
    }

    Write-Host "  All stopped." -ForegroundColor Green
}
