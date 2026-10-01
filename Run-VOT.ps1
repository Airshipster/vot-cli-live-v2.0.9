param(
    [string]$VideoUrl,
    [switch]$Once,
    [ValidateRange(0,8640)][int]$MaxHeight = 0,
    [ValidateSet('','live','tts','edge')][string]$VoiceStyle = '',
    [string]$TtsVoice = '',
    [string]$VideoFormatId = '',
    [string]$SourceLanguage = 'auto',
    [string]$TargetLanguage = 'ru',
    [switch]$CheckOnly,
    [switch]$HelpOnly
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding
$installedLayout = Test-Path -LiteralPath (Join-Path $PSScriptRoot 'app\src\index.js')
$appRoot = if ($installedLayout) { Join-Path $PSScriptRoot 'app' } else { $PSScriptRoot }
$entryPoint = Join-Path $appRoot 'src\index.js'
$languageConfig = Get-Content -LiteralPath (Join-Path $appRoot 'src\config\languages.json') -Raw | ConvertFrom-Json
if ($SourceLanguage -notin $languageConfig.source.code) { throw 'Не поддерживается выбранный исходный язык.' }
if ($TargetLanguage -notin $languageConfig.target.code) { throw 'Не поддерживается выбранный язык озвучки.' }
$toolsRoot = if ($installedLayout) { $PSScriptRoot } else { Join-Path $PSScriptRoot '.tools' }
$dependencies = & (Join-Path $PSScriptRoot 'Bootstrap-VOT.ps1') -AppRoot $appRoot -ToolsRoot $toolsRoot
$nodeExe = $dependencies.NodeExe
$binRoot = $dependencies.BinRoot
$shimRoot = Join-Path $PSScriptRoot 'launcher-bin'
$videoRoot = [Environment]::GetFolderPath('Desktop')
$containerRoot = Split-Path $PSScriptRoot -Parent
$usesOutputLayout = $installedLayout -and (Split-Path $containerRoot -Leaf) -eq 'outputs'
$workRoot = if ($usesOutputLayout) { Join-Path (Split-Path $containerRoot -Parent) 'work' } else { Join-Path $PSScriptRoot '.work' }
New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
$statePath = Join-Path $workRoot 'vot-console-state.json'
$env:PATH = $shimRoot + ';' + $binRoot + ';' + (Split-Path $nodeExe -Parent) + ';' + $env:PATH
$env:VOT_NODE_EXE = $nodeExe
$env:VOT_YTDLP_EXE = Join-Path $binRoot 'yt-dlp.exe'
$env:VOT_FFMPEG_EXE = Join-Path $binRoot 'ffmpeg.exe'
$env:VOT_FFPROBE_EXE = Join-Path $binRoot 'ffprobe.exe'
[Environment]::SetEnvironmentVariable('VOT_CLI_QUIET', $null, 'Process')
$jobsRoot = Join-Path $workRoot 'video-jobs'
New-Item -ItemType Directory -Path $jobsRoot -Force | Out-Null

function Set-VotState {
    param([string]$Stage, [string]$Message = '')
    [pscustomobject]@{stage=$Stage; message=$Message; processId=$PID; updatedAt=[DateTimeOffset]::Now.ToString('o')} |
        ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8
}

function Get-CanonicalVideoUrl {
    param([string]$InputUrl)
    $parsedUrl = $null
    if (-not [Uri]::TryCreate($InputUrl.Trim(), [UriKind]::Absolute, [ref]$parsedUrl) -or $parsedUrl.Scheme -ne 'https') {
        throw 'Введите полную HTTPS-ссылку на YouTube.'
    }
    $videoId = $null
    if ($parsedUrl.Host -eq 'youtu.be') {
        $videoId = $parsedUrl.AbsolutePath.Trim('/')
    } elseif ($parsedUrl.Host -in @('youtube.com','www.youtube.com','m.youtube.com','music.youtube.com')) {
        if ($parsedUrl.AbsolutePath -match '^/(shorts|embed|live)/([A-Za-z0-9_-]{11})/?$') {
            $videoId = $Matches[2]
        } elseif ($parsedUrl.AbsolutePath -eq '/watch') {
            foreach ($queryPart in $parsedUrl.Query.TrimStart('?').Split('&')) {
                $queryPair = $queryPart.Split('=', 2)
                if ($queryPair[0] -eq 'v' -and $queryPair.Length -eq 2) { $videoId = $queryPair[1]; break }
            }
        }
    }
    if ($videoId -notmatch '^[A-Za-z0-9_-]{11}$') { throw 'Не удалось определить видео. Нужна ссылка на один ролик YouTube.' }
    return 'https://www.youtube.com/watch?v=' + $videoId
}

function Read-NumberedChoice {
    param([string]$Prompt, [int]$Count, [int]$Default = 1)
    while ($true) {
        $answer = Read-Host ($Prompt + ' (Enter — ' + $Default + '; 0 — отмена)')
        if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
        $number = 0
        if ([int]::TryParse($answer, [ref]$number) -and $number -ge 0 -and $number -le $Count) {
            if ($number -eq 0) { throw [OperationCanceledException]::new('Загрузка отменена.') }
            return $number
        }
        Write-Host ('Введите число от 1 до ' + $Count + '.') -ForegroundColor Yellow
    }
}

function Get-VideoMetadata {
    param([string]$Url)
    Write-Host 'Получение названия и полного списка качества с YouTube…' -ForegroundColor Cyan
    $metadataLines = & $env:VOT_YTDLP_EXE --ignore-config --no-playlist --no-progress --js-runtimes ('node:' + $nodeExe) --socket-timeout 30 --retries 2 --dump-single-json --skip-download $Url
    if ($LASTEXITCODE -ne 0) { throw 'Не удалось получить список качества. Сообщение yt-dlp находится выше.' }
    $metadata = ($metadataLines -join [Environment]::NewLine) | ConvertFrom-Json
    if (-not $metadata.title -or -not $metadata.formats) { throw 'YouTube не вернул название или форматы видео.' }
    return $metadata
}

function Read-LanguageChoice {
    param([string]$Prompt, [array]$Languages, [string]$DefaultCode)
    Write-Host ''
    $defaultNumber = 1
    for ($i = 0; $i -lt $Languages.Count; $i++) {
        Write-Host ([string]($i + 1) + ' — ' + $Languages[$i].name)
        if ($Languages[$i].code -eq $DefaultCode) { $defaultNumber = $i + 1 }
    }
    $number = Read-NumberedChoice $Prompt $Languages.Count $defaultNumber
    return [string]$Languages[$number - 1].code
}

function Get-DetectedSourceLanguage {
    param($Metadata)
    $language = [string]$Metadata.language
    if (-not $language) {
        $original = $Metadata.formats | Where-Object {
            $_.language -and $_.acodec -ne 'none' -and $_.format_note -match '(?i)original'
        } | Select-Object -First 1
        if ($original) { $language = [string]$original.language }
    }
    if (-not $language -and $Metadata.automatic_captions) {
        $originalCaption = $Metadata.automatic_captions.PSObject.Properties.Name |
            Where-Object { $_ -match '-orig$' } | Select-Object -First 1
        if ($originalCaption) { $language = $originalCaption -replace '-orig$', '' }
    }
    if (-not $language) { return 'auto' }
    $code = $language.Split('-')[0].ToLowerInvariant()
    if ($code -notin $languageConfig.source.code) { return 'auto' }
    return $code
}

function Read-MicrosoftVoice {
    param([string]$Language, [string]$RequestedVoice)
    $edgeRuntime = & (Join-Path $PSScriptRoot 'Bootstrap-Edge.ps1') -ToolsRoot $toolsRoot
    $env:VOT_PYTHON_EXE = $edgeRuntime.PythonExe
    $env:VOT_EDGE_PACKAGES = $edgeRuntime.ModuleRoot
    Write-Host 'Получение списка дикторов Microsoft…' -ForegroundColor Cyan
    $voiceLines = & $edgeRuntime.PythonExe -X utf8 (Join-Path $appRoot 'src\edge_worker.py') --list-voices --lang $Language
    if ($LASTEXITCODE -ne 0) { throw 'Не удалось получить голоса Microsoft. Сообщение сервиса находится выше.' }
    $voices = @(($voiceLines -join [Environment]::NewLine) | ConvertFrom-Json)
    if (-not $voices.Count) { throw 'Microsoft не предоставляет голоса для выбранного языка.' }
    if ($RequestedVoice) {
        if ($RequestedVoice -notin $voices.id) { throw 'Этот диктор Microsoft не поддерживает выбранный язык.' }
        return $RequestedVoice
    }
    Write-Host ''
    $default = 1
    for ($i = 0; $i -lt $voices.Count; $i++) {
        $voice = $voices[$i]
        $name = switch ($voice.id) {
            'ru-RU-DmitryNeural' { 'Дмитрий' }
            'ru-RU-SvetlanaNeural' { 'Светлана' }
            default { ($voice.id -replace '^[a-z]{2,3}-[A-Z]{2}-', '') -replace 'Neural$', '' }
        }
        $gender = if ($voice.gender -eq 'Female') { 'женский' } else { 'мужской' }
        Write-Host ([string]($i + 1) + ' — ' + $name + ' (' + $gender + ', ' + $voice.locale + ')')
        if ($voice.id -eq 'ru-RU-SvetlanaNeural') { $default = $i + 1 }
    }
    Set-VotState 'awaiting_microsoft_voice'
    $number = Read-NumberedChoice 'Выберите диктора Microsoft' $voices.Count $default
    return [string]$voices[$number - 1].id
}

function Get-QualityOptions {
    param($Metadata)
    $hasAudio = @($Metadata.formats | Where-Object { $_.acodec -and $_.acodec -ne 'none' }).Count -gt 0
    if (-not $hasAudio) { throw 'У ролика нет доступной оригинальной аудиодорожки для смешивания.' }
    $qualityNames = @{}
    foreach ($format in $Metadata.formats) {
        if ($format.format_note -match '(\d{3,4})p') {
            $qualityNames[([string]$format.width + 'x' + $format.height)] = $Matches[1] + 'p'
        }
    }
    $options = foreach ($format in $Metadata.formats) {
        if (-not $format.vcodec -or $format.vcodec -eq 'none' -or $format.height -le 0 -or
            $format.has_drm -or $format.protocol -eq 'mhtml') { continue }
        if ($format.ext -ne 'mp4' -or $format.vcodec -notmatch '^(avc[13]|h264)(\.|$)') { continue }
        $id = [string]$format.format_id
        $selector = if ($format.acodec -and $format.acodec -ne 'none') { $id } else { $id + '+ba[ext=m4a]/' + $id + '+ba' }
        $bitrate = if ($format.vbr -gt 0) { [double]$format.vbr } elseif ($format.tbr -gt 0) { [double]$format.tbr } else { 0 }
        $codec = switch -Regex ($format.vcodec) {
            '^avc|^h264' { 'H.264'; break }
            '^av01' { 'AV1'; break }
            '^vp0?9' { 'VP9'; break }
            '^hev|^hvc' { 'HEVC'; break }
            default { [string]$format.vcodec }
        }
        $pictureKey = [string]$format.width + 'x' + $format.height
        $quality = if ($qualityNames.ContainsKey($pictureKey)) { $qualityNames[$pictureKey] } else { [string]$format.height + 'p' }
        [pscustomobject]@{
            Id = $id; Selector = $selector; Quality = $quality
            Width = [int]$format.width; Height = [int]$format.height
            Fps = [double]$format.fps; Bitrate = $bitrate; Codec = $codec
            Container = [string]$format.ext
            Range = if ($format.dynamic_range -and $format.dynamic_range -ne 'SDR') { [string]$format.dynamic_range } else { '' }
        }
    }
    $options = @($options | Sort-Object -Property @{Expression='Height';Descending=$true}, @{Expression='Width';Descending=$true}, @{Expression='Fps';Descending=$true}, @{Expression='Bitrate';Descending=$true}, Id)
    if ($options.Count -eq 0) { throw 'У ролика нет доступных MP4 с кодеком H.264.' }
    return $options
}

function Show-QualityOptions {
    param([array]$Options)
    $showFps = @($Options | Where-Object { $_.Fps -gt 0 } | ForEach-Object { [Math]::Round($_.Fps) } | Sort-Object -Unique).Count -gt 1
    $showBitrate = @($Options | Where-Object { $_.Bitrate -gt 0 } | ForEach-Object { [Math]::Round($_.Bitrate) } | Sort-Object -Unique).Count -gt 1
    $showCodec = @($Options.Codec | Sort-Object -Unique).Count -gt 1
    $showContainer = @($Options.Container | Sort-Object -Unique).Count -gt 1
    $rows = for ($i = 0; $i -lt $Options.Count; $i++) {
        $option = $Options[$i]
        [pscustomobject]@{
            Number = [string]($i + 1)
            Quality = $option.Quality
            Picture = [string]$option.Width + '×' + $option.Height
            Fps = if ($option.Fps -gt 0) { ('{0:0.##}' -f $option.Fps) + ' FPS' } else { '—' }
            Bitrate = if ($option.Bitrate -gt 0) { ('{0:N0}' -f $option.Bitrate) + ' кбит/с' } else { '—' }
            Codec = $option.Codec
            Container = $option.Container.ToUpperInvariant()
            Range = $option.Range
            Id = '[' + $option.Id + ']'
        }
    }
    $fields = @('Number','Quality','Picture')
    if ($showFps) { $fields += 'Fps' }
    if ($showBitrate) { $fields += 'Bitrate' }
    if ($showCodec) { $fields += 'Codec' }
    if ($showContainer) { $fields += 'Container' }
    if (@($Options | Where-Object { $_.Range }).Count -gt 0) { $fields += 'Range' }
    $fields += 'Id'
    $widths = @{}
    foreach ($field in $fields) {
        $widths[$field] = ($rows | ForEach-Object { ([string]$_.$field).Length } | Measure-Object -Maximum).Maximum
    }
    Write-Host ''
    Write-Host 'Доступное качество MP4 / H.264 (от большего к меньшему):' -ForegroundColor Cyan
    foreach ($row in $rows) {
        $cells = foreach ($field in $fields) { ([string]$row.$field).PadRight($widths[$field]) }
        Write-Host ($cells -join '  ')
    }
    Write-Host 'В каждом варианте: оригинальный звук 15%, перевод 100%.'
}

function Get-DesktopResultPath {
    param([string]$Title)
    $cleanTitle = [regex]::Replace($Title, '[<>:"/\\|?*\x00-\x1F]', '_').Trim().TrimEnd('.',' ')
    if (-not $cleanTitle) { $cleanTitle = 'Видео' }
    if ($cleanTitle -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)') { $cleanTitle = '_' + $cleanTitle }
    $limit = [Math]::Min(180, 235 - $videoRoot.Length - ' (Нейроперевод).mp4'.Length)
    if ($limit -lt 20) { throw 'Слишком длинный путь к рабочему столу.' }
    if ($cleanTitle.Length -gt $limit) { $cleanTitle = $cleanTitle.Substring(0, $limit).TrimEnd('.',' ') }
    $destination = Join-Path $videoRoot ($cleanTitle + ' (Нейроперевод).mp4')
    $copyNumber = 2
    while (Test-Path -LiteralPath $destination) {
        $destination = Join-Path $videoRoot ($cleanTitle + ' (' + $copyNumber + ') (Нейроперевод).mp4')
        $copyNumber++
    }
    return $destination
}

function Remove-VotJob {
    param([string]$JobPath)
    if (-not $JobPath -or -not (Test-Path -LiteralPath $JobPath)) { return }
    $absoluteRoot = (Resolve-Path -LiteralPath $jobsRoot).Path.TrimEnd('\') + '\'
    $absoluteJob = (Resolve-Path -LiteralPath $JobPath).Path
    if (-not $absoluteJob.StartsWith($absoluteRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Очистка отменена: временная папка находится вне video-jobs.'
    }
    $items = @((Get-Item -LiteralPath $absoluteJob -Force)) + @(Get-ChildItem -LiteralPath $absoluteJob -Recurse -Force)
    $reparsePoints = $items |
        Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }
    if ($reparsePoints) { throw 'Очистка отменена: временная папка содержит ссылку на другой каталог.' }
    Remove-Item -LiteralPath $absoluteJob -Recurse -Force
}

foreach ($requiredPath in @($nodeExe,$entryPoint,(Join-Path $binRoot 'yt-dlp.exe'),(Join-Path $binRoot 'ffmpeg.exe'),(Join-Path $binRoot 'ffprobe.exe'))) {
    if (-not (Test-Path -LiteralPath $requiredPath)) { throw ('Не найден компонент: ' + $requiredPath) }
}

Write-Host ''
Write-Host 'VOT-CLI Live — озвучка видео (локальная версия 2.0.5)' -ForegroundColor Cyan
Write-Host 'Выберите языки, озвучку и качество видео.'
Write-Host 'Видеоформат: MP4 / H.264.'
Write-Host ('Папка для видео: ' + $videoRoot)
Write-Host ''

if ($CheckOnly) {
    & $nodeExe $entryPoint --version
    & (Join-Path $binRoot 'yt-dlp.exe') --version
    & (Join-Path $binRoot 'ffmpeg.exe') -version | Select-Object -First 1
    if ($LASTEXITCODE -ne 0) { throw 'Проверка компонентов не пройдена.' }
    Write-Host 'Компоненты готовы.' -ForegroundColor Green
    exit 0
}
if ($HelpOnly) { & $nodeExe $entryPoint --help; exit $LASTEXITCODE }

do {
    $configureLanguages = $false
    $requestedSource = $SourceLanguage
    $selectedTarget = $TargetLanguage
    if (-not $VideoUrl) {
        Write-Host '1 — Скачать видео: английский → русский'
        Write-Host '2 — Скачать видео — выбрать другие языки'
        Write-Host '3 — Показать справку оригинальной утилиты'
        Write-Host '0 — Выход'
        Set-VotState 'awaiting_menu'
        $menuChoice = Read-Host 'Выберите пункт'
        if ($menuChoice -eq '0') { Set-VotState 'closed'; break }
        if ($menuChoice -eq '3') { & $nodeExe $entryPoint --help; Write-Host ''; continue }
        if ($menuChoice -notin @('1','2')) { continue }
        if ($menuChoice -eq '1') { $requestedSource = 'en'; $selectedTarget = 'ru' }
        else { $configureLanguages = $true }
        Set-VotState 'awaiting_url'
        $VideoUrl = Read-Host 'Вставьте ссылку на YouTube-видео'
    }
    $jobRoot = $null
    $workVideo = $null
    $votExitCode = $null
    $resultSaved = $false
    $downloadFailed = $false
    try {
        $canonicalUrl = Get-CanonicalVideoUrl $VideoUrl
        if ($configureLanguages) {
            Set-VotState 'awaiting_source_language'
            $requestedSource = Read-LanguageChoice 'С какого языка переводить' $languageConfig.source 'auto'
            Set-VotState 'awaiting_target_language'
            $selectedTarget = Read-LanguageChoice 'На какой язык озвучить' $languageConfig.target 'ru'
        }
        Set-VotState 'fetching_formats'
        $metadata = Get-VideoMetadata $canonicalUrl
        $sourceLanguage = if ($requestedSource -eq 'auto') { Get-DetectedSourceLanguage $metadata } else { $requestedSource }
        $sourceName = ($languageConfig.source | Where-Object { $_.code -eq $sourceLanguage }).name
        $targetName = ($languageConfig.target | Where-Object { $_.code -eq $selectedTarget }).name
        if ($requestedSource -eq 'auto') {
            Write-Host ('Исходный язык: ' + $sourceName + $(if ($sourceLanguage -eq 'auto') { ' — определит сервис перевода.' } else { ' (определён по данным YouTube).' }))
        }
        Write-Host ('Перевод: ' + $sourceName + ' → ' + $targetName)
        if ($sourceLanguage -eq $selectedTarget) { throw 'Исходный язык совпадает с языком озвучки. Выберите другой язык результата.' }
        $canUseLive = $sourceLanguage -in @('en','auto') -and $selectedTarget -eq 'ru'
        $selectedVoice = $VoiceStyle
        if (-not $selectedVoice) {
            Write-Host ''
            $voiceOptions = @()
            if ($canUseLive) { $voiceOptions += [pscustomobject]@{Id='live'; Name='Яндекс — Живые голоса (английский → русский)'} }
            $voiceOptions += [pscustomobject]@{Id='tts'; Name=('Яндекс — Стандартные голоса (' + $targetName + ')')}
            $voiceOptions += [pscustomobject]@{Id='edge'; Name=('Microsoft Edge — нейронные голоса (' + $targetName + ', выбрать диктора)')}
            for ($i = 0; $i -lt $voiceOptions.Count; $i++) { Write-Host ([string]($i + 1) + ' — ' + $voiceOptions[$i].Name) }
            Set-VotState 'awaiting_voice'
            $voiceChoice = Read-NumberedChoice 'Выберите озвучку' $voiceOptions.Count 1
            $selectedVoice = $voiceOptions[$voiceChoice - 1].Id
        }
        if ($selectedVoice -eq 'live' -and -not $canUseLive) {
            throw '«Живые голоса» поддерживают английский → русский. Для этой языковой пары выберите другую озвучку.'
        }
        $selectedTtsVoice = ''
        if ($selectedVoice -eq 'edge') { $selectedTtsVoice = Read-MicrosoftVoice $selectedTarget $TtsVoice }
        Write-Host ('Видео: ' + $metadata.title)
        $qualityOptions = @(Get-QualityOptions $metadata)
        Show-QualityOptions $qualityOptions
        if ($VideoFormatId) {
            $selectedQuality = $qualityOptions | Where-Object { $_.Id -eq $VideoFormatId } | Select-Object -First 1
            if (-not $selectedQuality) { throw ('У ролика нет формата ' + $VideoFormatId + '.') }
        } elseif ($Once -and $MaxHeight -gt 0) {
            $selectedQuality = $qualityOptions | Where-Object { $_.Height -le $MaxHeight } | Select-Object -First 1
            if (-not $selectedQuality) { throw 'Нет формата в пределах указанной высоты.' }
        } else {
            Set-VotState 'awaiting_quality'
            $qualityChoice = Read-NumberedChoice 'Выберите качество' $qualityOptions.Count 1
            $selectedQuality = $qualityOptions[$qualityChoice - 1]
        }
        $jobName = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,6)
        $jobRoot = Join-Path $jobsRoot $jobName
        New-Item -ItemType Directory -Path $jobRoot -Force | Out-Null
        Set-VotState 'running' $jobRoot
        Write-Host ('Выбрано: ' + $selectedQuality.Quality + ', ' + $selectedQuality.Width + '×' + $selectedQuality.Height + ', ' + $selectedQuality.Codec)
        Write-Host 'Получение перевода и скачивание видео…' -ForegroundColor Cyan
        $votArguments = @($entryPoint, ('--voice-style=' + $selectedVoice), ('--lang=' + $sourceLanguage), ('--reslang=' + $selectedTarget), '--merge-video', ('--video-format=' + $selectedQuality.Selector), ('--video-title=' + $metadata.title), ('--video-duration=' + $metadata.duration), '--keep-original-audio=true', '--normalize-audio=false', '--original-volume=0.15', '--translation-volume=1', '--translation-timeout=900', ('--output=' + $jobRoot), '--output-file=video-ru')
        if ($selectedVoice -eq 'edge') {
            $metadataPath = Join-Path $jobRoot 'metadata.json'
            $metadata | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $metadataPath -Encoding UTF8
            $votArguments += @(('--tts-voice=' + $selectedTtsVoice), ('--video-metadata=' + $metadataPath))
        }
        $votArguments += $canonicalUrl
        & $nodeExe @votArguments
        $votExitCode = $LASTEXITCODE
        $workVideo = Join-Path $jobRoot 'video-ru.mp4'
        if ($votExitCode -ne 0 -or -not (Test-Path -LiteralPath $workVideo) -or (Get-Item -LiteralPath $workVideo).Length -eq 0) {
            throw ('Видео не создано. Код завершения: ' + $votExitCode + '. Сообщение сервиса находится выше.')
        }
        $resultVideo = Get-DesktopResultPath ([string]$metadata.title)
        Move-Item -LiteralPath $workVideo -Destination $resultVideo
        $resultSaved = $true
        Set-VotState 'completed' $resultVideo
        Write-Host ('Готово: ' + $resultVideo) -ForegroundColor Green
    } catch {
        $downloadFailed = $true
        Set-VotState 'failed' $_.Exception.Message
        Write-Host $_.Exception.Message -ForegroundColor Red
    } finally {
        if (-not $resultSaved -and $votExitCode -eq 0 -and $workVideo -and (Test-Path -LiteralPath $workVideo)) {
            Write-Host ('Сохранение на рабочий стол не удалось. Готовый файл оставлен здесь: ' + $workVideo) -ForegroundColor Yellow
        } else {
            try { Remove-VotJob $jobRoot }
            catch { Write-Host $_.Exception.Message -ForegroundColor Yellow }
        }
    }
    if ($Once) { if ($downloadFailed) { exit 1 }; exit 0 }
    $VideoUrl = ''
    Write-Host ''
} while ($true)
