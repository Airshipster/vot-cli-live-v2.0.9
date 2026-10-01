param([Parameter(Mandatory)][string]$ToolsRoot)
$ErrorActionPreference = 'Stop'
$runtimeRoot = Join-Path $ToolsRoot 'python-runtime'
$moduleRoot = Join-Path $ToolsRoot 'edge-packages'
$edgeVersion = '7.2.8'
$candidates = @((Join-Path $runtimeRoot 'python.exe'))
$pythonCommand = Get-Command python.exe -ErrorAction SilentlyContinue
if ($pythonCommand -and $pythonCommand.Source -notmatch 'WindowsApps') { $candidates += $pythonCommand.Source }
$candidates += Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$pythonExe = $null
foreach ($candidate in $candidates) {
    if (-not (Test-Path -LiteralPath $candidate)) { continue }
    $version = & $candidate -c 'import sys, importlib.util; print(".".join(map(str, sys.version_info[:3])) if importlib.util.find_spec("pip") else "")' 2>$null
    if ($LASTEXITCODE -eq 0 -and $version -and [version]$version -ge [version]'3.12.0') { $pythonExe = $candidate; break }
}
if (-not $pythonExe) {
    Write-Host 'Установка локального Python для Microsoft TTS…' -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null
    $archive = Join-Path $ToolsRoot 'python-3.14.8-amd64.zip'
    $expectedHash = '4873947a8afc037846b180312b83c744a4146a851cfd316a75c3125a4d8299da'
    if (-not (Test-Path -LiteralPath $archive) -or (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $expectedHash) {
        Invoke-WebRequest -Uri 'https://www.python.org/ftp/python/3.14.8/python-3.14.8-amd64.zip' -OutFile $archive -TimeoutSec 180
    }
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $expectedHash) { throw 'Не совпала контрольная сумма Python.' }
    Expand-Archive -LiteralPath $archive -DestinationPath $runtimeRoot -Force
    $pythonExe = Join-Path $runtimeRoot 'python.exe'
    & $pythonExe -m ensurepip --default-pip | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Не удалось подготовить pip для Microsoft TTS.' }
}
$pythonAbi = (& $pythonExe -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")').Trim()
New-Item -ItemType Directory -Path $moduleRoot -Force | Out-Null
$markerPath = Join-Path $moduleRoot 'runtime.json'
$installedVersion = & $pythonExe -X utf8 -c 'import sys, importlib.metadata; sys.path.insert(0, sys.argv[1]); import edge_tts, aiohttp; print(importlib.metadata.version("edge-tts"))' $moduleRoot 2>$null
if ($LASTEXITCODE -ne 0 -or $installedVersion -ne $edgeVersion) {
    Write-Host 'Подготовка Microsoft TTS (локальные зависимости)…' -ForegroundColor Cyan
    & $pythonExe -m pip install ('edge-tts==' + $edgeVersion) --target $moduleRoot --upgrade --only-binary=:all: --disable-pip-version-check --no-warn-script-location --cache-dir (Join-Path $ToolsRoot 'edge-cache') | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Не удалось установить Microsoft TTS.' }
}
[pscustomobject]@{edgeVersion=$edgeVersion; pythonAbi=$pythonAbi} | ConvertTo-Json | Set-Content -LiteralPath $markerPath -Encoding UTF8
[pscustomobject]@{PythonExe=$pythonExe; ModuleRoot=$moduleRoot}
