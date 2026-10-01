param([string]$AppRoot, [string]$ToolsRoot)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Path $ToolsRoot -Force | Out-Null

function Get-VerifiedDownload {
    param([string]$Url, [string]$Target, [string]$Sha256)
    if (-not (Test-Path -LiteralPath $Target) -or (Get-FileHash -LiteralPath $Target -Algorithm SHA256).Hash -ne $Sha256) {
        Write-Host ('Downloading ' + [IO.Path]::GetFileName($Target))
        Invoke-WebRequest -Uri $Url -OutFile $Target -TimeoutSec 300
    }
    if ((Get-FileHash -LiteralPath $Target -Algorithm SHA256).Hash -ne $Sha256) { throw 'Download checksum mismatch.' }
}

$nodeCommand = Get-Command node.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$nodeExe = if ($nodeCommand) { $nodeCommand.Source } else { $null }
if ($nodeExe) {
    $nodeVersion = (& $nodeExe --version).Trim().TrimStart('v')
    if ([version]$nodeVersion -lt [version]'22.19.0') { $nodeExe = $null }
}
if (-not $nodeExe) {
    $nodeVersion = '24.16.0'
    $nodeArchiveName = 'node-v' + $nodeVersion + '-win-x64.zip'
    $nodeExe = Join-Path $ToolsRoot ('node-v' + $nodeVersion + '-win-x64\node.exe')
    if (-not (Test-Path -LiteralPath $nodeExe)) {
        $nodeBaseUrl = 'https://nodejs.org/dist/v' + $nodeVersion + '/'
        $checksums = (Invoke-WebRequest -Uri ($nodeBaseUrl + 'SHASUMS256.txt') -TimeoutSec 60).Content
        $nodeChecksum = [regex]::Match($checksums, '(?m)^([a-f0-9]{64})\s+' + [regex]::Escape($nodeArchiveName) + '\s*$').Groups[1].Value
        if (-not $nodeChecksum) { throw 'Node.js checksum not found.' }
        $nodeArchive = Join-Path $ToolsRoot $nodeArchiveName
        Get-VerifiedDownload ($nodeBaseUrl + $nodeArchiveName) $nodeArchive $nodeChecksum
        Expand-Archive -LiteralPath $nodeArchive -DestinationPath $ToolsRoot -Force
    }
}

$binRoot = Join-Path $ToolsRoot 'bin'
New-Item -ItemType Directory -Path $binRoot -Force | Out-Null
$ytdlpExe = Join-Path $binRoot 'yt-dlp.exe'
$expectedYtdlp = '2026.08.19'
$haveYtdlp = if (Test-Path -LiteralPath $ytdlpExe) { (& $ytdlpExe --version).Trim() } else { '' }
if ($haveYtdlp -lt $expectedYtdlp) {
    Get-VerifiedDownload ('https://github.com/yt-dlp/yt-dlp/releases/download/' + $expectedYtdlp + '/yt-dlp.exe') $ytdlpExe '66674953fe251b89f4d08c5f0e35e0728679bd67ab3d7d05c0562af101dd3e7a'
}
$ffmpegExe = Join-Path $binRoot 'ffmpeg.exe'
$ffprobeExe = Join-Path $binRoot 'ffprobe.exe'
$ffmpegReady = (Test-Path -LiteralPath $ffmpegExe) -and (Test-Path -LiteralPath $ffprobeExe)
if ($ffmpegReady) {
    $ffmpegHeader = & $ffmpegExe -version | Select-Object -First 1
    $ffmpegReady = ($ffmpegHeader -match 'ffmpeg version (\d+\.\d+(?:\.\d+)?)') -and ([version]$Matches[1] -ge [version]'9.0.2')
}
if (-not $ffmpegReady) {
    $ffmpegArchive = Join-Path $ToolsRoot 'ffmpeg-9.0.2-essentials_build.7z'
    Get-VerifiedDownload 'https://github.com/GyanD/codexffmpeg/releases/download/9.0.2/ffmpeg-9.0.2-essentials_build.7z' $ffmpegArchive '4705843ccaaf54257c16ad90f3e952ece33c17df964ecf7bfdbb0f49c7171077'
    $ffmpegExtract = Join-Path $ToolsRoot 'ffmpeg-extracted'
    New-Item -ItemType Directory -Path $ffmpegExtract -Force | Out-Null
    $extractPrefix = [IO.Path]::GetFullPath($ffmpegExtract) + [IO.Path]::DirectorySeparatorChar
    $archiveEntries = & tar.exe -tf $ffmpegArchive
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read the FFmpeg archive.' }
    foreach ($archiveEntry in $archiveEntries) {
        $archiveTarget = [IO.Path]::GetFullPath((Join-Path $ffmpegExtract $archiveEntry))
        if (-not ($archiveTarget + [IO.Path]::DirectorySeparatorChar).StartsWith($extractPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unexpected archive path.' }
    }
    & tar.exe -xf $ffmpegArchive -C $ffmpegExtract
    if ($LASTEXITCODE -ne 0) { throw 'Cannot extract FFmpeg.' }
    $extractedBin = Join-Path $ffmpegExtract 'ffmpeg-9.0.2-essentials_build\bin'
    Copy-Item -LiteralPath (Join-Path $extractedBin 'ffmpeg.exe') -Destination $ffmpegExe
    Copy-Item -LiteralPath (Join-Path $extractedBin 'ffprobe.exe') -Destination $ffprobeExe
}

$nodePackage = Join-Path $AppRoot 'node_modules\@vot.js\node\package.json'
$installedSdk = if (Test-Path -LiteralPath $nodePackage) { (Get-Content -LiteralPath $nodePackage -Raw | ConvertFrom-Json).version } else { '' }
$package = Get-Content -LiteralPath (Join-Path $AppRoot 'package.json') -Raw | ConvertFrom-Json
$expectedSdk = $package.dependencies.'@vot.js/node'
$translatorPackage = Join-Path $AppRoot 'node_modules\@toil\translate\package.json'
$installedTranslator = if (Test-Path -LiteralPath $translatorPackage) { (Get-Content -LiteralPath $translatorPackage -Raw | ConvertFrom-Json).version } else { '' }
if ($installedSdk -ne $expectedSdk -or $installedTranslator -ne $package.dependencies.'@toil/translate') {
    $npmExe = Join-Path (Split-Path $nodeExe -Parent) 'npm.cmd'
    & $npmExe ci --prefix $AppRoot --omit=dev --ignore-scripts --no-audit --no-fund --cache (Join-Path $ToolsRoot 'npm-cache') | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Cannot install VOT dependencies.' }
}
[pscustomobject]@{NodeExe=$nodeExe; BinRoot=$binRoot}
