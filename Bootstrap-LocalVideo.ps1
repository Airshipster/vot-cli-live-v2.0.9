param([string]$BinRoot)
$ErrorActionPreference = 'Stop'
$cloudflared = Join-Path $BinRoot 'cloudflared.exe'
$expectedHash = '86aee4017b26625cee8484c113558f48effa4cd47f7aa05fcf425604e5d2b23c'
if (-not (Test-Path -LiteralPath $cloudflared) -or (Get-FileHash -LiteralPath $cloudflared -Algorithm SHA256).Hash -ne $expectedHash) {
    Write-Host 'Подготовка временной ссылки для Яндекса: скачивание Cloudflare Tunnel…' -ForegroundColor Cyan
    $partial = $cloudflared + '.download'
    try {
        Invoke-WebRequest -Uri 'https://github.com/cloudflare/cloudflared/releases/download/2026.10.0/cloudflared-windows-amd64.exe' -OutFile $partial -TimeoutSec 300
        if ((Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash -ne $expectedHash) { throw 'Контрольная сумма Cloudflare Tunnel не совпала.' }
        Move-Item -LiteralPath $partial -Destination $cloudflared -Force
    } finally { if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force } }
}
$env:VOT_CLOUDFLARED_EXE = $cloudflared
