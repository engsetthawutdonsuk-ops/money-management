$port = 8888

# Create HTTP listener - try multiple bindings
$listener = New-Object System.Net.HttpListener

# Try binding to all interfaces first, fall back to localhost
$started = $false
foreach ($prefix in @("http://*:$port/", "http://+:$port/", "http://localhost:$port/")) {
    try {
        $listener = New-Object System.Net.HttpListener
        $listener.Prefixes.Add($prefix)
        $listener.Start()
        $started = $true
        Write-Host "Bound to: $prefix" -ForegroundColor DarkGray
        break
    } catch {
        $listener.Close()
    }
}

if (-not $started) {
    Write-Host "ERROR: Could not start on port $port." -ForegroundColor Red
    exit 1
}

$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.*' } | Select-Object -First 1).IPAddress

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Money Management Server Running!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Local:   http://localhost:$port" -ForegroundColor Yellow
Write-Host "  Mobile:  http://${ip}:$port" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Open the Mobile link on your phone" -ForegroundColor White
Write-Host "  (both devices must be on same WiFi)" -ForegroundColor Gray
Write-Host ""
Write-Host "  Press Ctrl+C to stop the server" -ForegroundColor Gray
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$root = $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }

$mimeTypes = @{
    '.html' = 'text/html; charset=utf-8'
    '.css'  = 'text/css; charset=utf-8'
    '.js'   = 'application/javascript; charset=utf-8'
    '.json' = 'application/json; charset=utf-8'
    '.png'  = 'image/png'
    '.jpg'  = 'image/jpeg'
    '.gif'  = 'image/gif'
    '.svg'  = 'image/svg+xml'
    '.ico'  = 'image/x-icon'
    '.woff' = 'font/woff'
    '.woff2'= 'font/woff2'
}

$dataFile = Join-Path $root 'appdata.json'

function Add-CorsHeaders($resp) {
    $resp.AddHeader('Access-Control-Allow-Origin', '*')
    $resp.AddHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
    $resp.AddHeader('Access-Control-Allow-Headers', 'Content-Type')
}

while ($listener.IsListening) {
    try {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response

        $path = $request.Url.LocalPath

        # ===== CORS preflight =====
        if ($request.HttpMethod -eq 'OPTIONS') {
            Add-CorsHeaders $response
            $response.StatusCode = 204
            $response.ContentLength64 = 0
            $response.OutputStream.Close()
            continue
        }

        # ===== API: GET /api/data =====
        if ($path -eq '/api/data' -and $request.HttpMethod -eq 'GET') {
            Add-CorsHeaders $response
            if (Test-Path $dataFile) {
                $bytes = [System.IO.File]::ReadAllBytes($dataFile)
            } else {
                $bytes = [System.Text.Encoding]::UTF8.GetBytes('{}')
            }
            $response.ContentType = 'application/json; charset=utf-8'
            $response.ContentLength64 = $bytes.Length
            $response.StatusCode = 200
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
            Write-Host "$(Get-Date -Format 'HH:mm:ss') 200 GET /api/data" -ForegroundColor Cyan
            $response.OutputStream.Close()
            continue
        }

        # ===== API: POST /api/data =====
        if ($path -eq '/api/data' -and $request.HttpMethod -eq 'POST') {
            Add-CorsHeaders $response
            $reader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
            $body = $reader.ReadToEnd()
            $reader.Close()
            [System.IO.File]::WriteAllBytes($dataFile, [System.Text.Encoding]::UTF8.GetBytes($body))
            $msg = [System.Text.Encoding]::UTF8.GetBytes('{"ok":true}')
            $response.ContentType = 'application/json; charset=utf-8'
            $response.ContentLength64 = $msg.Length
            $response.StatusCode = 200
            $response.OutputStream.Write($msg, 0, $msg.Length)
            $sizeKB = [math]::Round($body.Length / 1024, 1)
            Write-Host "$(Get-Date -Format 'HH:mm:ss') 200 POST /api/data (${sizeKB}KB saved)" -ForegroundColor Cyan
            $response.OutputStream.Close()
            continue
        }

        # ===== Static files =====
        if ($path -eq '/') { $path = '/index.html' }

        $filePath = Join-Path $root ($path -replace '/', '\')

        if (Test-Path $filePath -PathType Leaf) {
            $ext = [System.IO.Path]::GetExtension($filePath).ToLower()
            $contentType = if ($mimeTypes.ContainsKey($ext)) { $mimeTypes[$ext] } else { 'application/octet-stream' }

            $bytes = [System.IO.File]::ReadAllBytes($filePath)
            $response.ContentType = $contentType
            $response.ContentLength64 = $bytes.Length
            $response.StatusCode = 200
            $response.OutputStream.Write($bytes, 0, $bytes.Length)

            Write-Host "$(Get-Date -Format 'HH:mm:ss') 200 $path" -ForegroundColor Green
        } else {
            $response.StatusCode = 404
            $msg = [System.Text.Encoding]::UTF8.GetBytes("<h1>404 Not Found</h1>")
            $response.ContentType = 'text/html'
            $response.ContentLength64 = $msg.Length
            $response.OutputStream.Write($msg, 0, $msg.Length)

            Write-Host "$(Get-Date -Format 'HH:mm:ss') 404 $path" -ForegroundColor Red
        }

        $response.OutputStream.Close()
    } catch {
        # Listener was stopped
        break
    }
}
