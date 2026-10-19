param(
    [string]$VideoUrl,
    [string]$LocalVideo,
    [switch]$Once,
    [ValidateRange(0,8640)][int]$MaxHeight = 0,
    [ValidateRange(0,1000)][double]$MaxFps = 0,
    [switch]$AutoQuality,
    [switch]$ShowAllFormats,
    [int]$ExpectedHeight = 0,
    [double]$ExpectedFps = 0,
    [string]$ResultFile,
    [string]$AttemptId,
    [ValidateSet('','live','tts','edge')][string]$VoiceStyle = '',
    [string]$TtsVoice = '',
    [string]$VideoFormatId = '',
    [switch]$ThumbnailFirstFrame,
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
. (Join-Path $PSScriptRoot 'Yandex-Account.ps1')
. (Join-Path $PSScriptRoot 'Vot-Queue.ps1')
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
    param([string]$Prompt, [int]$Count, [int]$Default = 1, [switch]$NoCancel)
    while ($true) {
        $choices = if ($Count -eq 2) { '1 или 2' } else { '1–' + $Count }
        $hint = if ($NoCancel) { $choices + '; Enter — ' + $Default } else { $choices + '; Enter — ' + $Default + '; 0 — отмена' }
        $answer = Read-Host ($Prompt + ' (' + $hint + ')')
        if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
        $number = 0
        if ([int]::TryParse($answer, [ref]$number) -and $number -ge 0 -and $number -le $Count) {
            if ($number -eq 0) {
                if ($NoCancel) { Write-Host ('Введите ' + $choices + '.') -ForegroundColor Yellow; continue }
                throw [OperationCanceledException]::new('Загрузка отменена.')
            }
            return $number
        }
        Write-Host ('Введите число от 1 до ' + $Count + '.') -ForegroundColor Yellow
    }
}

function Read-QualityChoice {
    param([int]$Count, [int]$Default = 1, [bool]$AllowThumbnail = $true)
    while ($true) {
        $hint = if ($AllowThumbnail) { '; например, 4 000 — с обложкой первым кадром' } else { '; исходное разрешение и FPS' }
        $answer = Read-Host ('Выберите качество (Enter — ' + $Default + '; 0 — отмена' + $hint + ')')
        if ([string]::IsNullOrWhiteSpace($answer)) {
            return [pscustomobject]@{Number=$Default; Thumbnail=$false}
        }
        $number = 0
        if ($answer -match '^\s*(\d+)(?:\s+(000))?\s*$') {
            $withThumbnail = $Matches[2] -eq '000'
            if ($withThumbnail -and -not $AllowThumbnail) { Write-Host 'У локального файла нет обложки YouTube. Введите только номер.' -ForegroundColor Yellow; continue }
            if ([int]::TryParse($Matches[1], [ref]$number) -and $number -ge 0 -and $number -le $Count) {
                if ($number -eq 0) { throw [OperationCanceledException]::new('Загрузка отменена.') }
                return [pscustomobject]@{Number=$number; Thumbnail=$withThumbnail}
            }
        }
        Write-Host ('Введите число от 1 до ' + $Count + ', при необходимости добавьте пробел и 000: например, 4 000.') -ForegroundColor Yellow
    }
}

function Select-LocalVideoFile {
    Set-VotState 'awaiting_local_file'
    $pickerHost = Join-Path $PSHOME 'pwsh.exe'
    $selected = & $pickerHost -NoLogo -NoProfile -STA -File (Join-Path $PSScriptRoot 'Select-VideoFile.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Не удалось открыть окно выбора файла.' }
    if (-not $selected) { throw [OperationCanceledException]::new('Выбор файла отменён.') }
    return [string]($selected | Select-Object -Last 1)
}

function Read-LocalLiveToken {
    Set-VotState 'awaiting_yandex_login'
    Write-Host 'Для «Живых голосов» локального файла нужно один раз войти в Яндекс.' -ForegroundColor Yellow
    return Connect-VotYandex $nodeExe
}

function Get-LocalVideoMetadata {
    param([string]$FilePath)
    $file = Get-Item -LiteralPath $FilePath -ErrorAction Stop
    if ($file.PSIsContainer -or $file.Length -eq 0) { throw 'Выберите непустой видеофайл.' }
    $lines = & $env:VOT_FFPROBE_EXE -v error -show_entries 'format=duration:stream=codec_type,codec_name,width,height,avg_frame_rate,bit_rate:stream_tags=language' -of json $file.FullName
    if ($LASTEXITCODE -ne 0) { throw 'Не удалось прочитать видеофайл. Сообщение FFprobe находится выше.' }
    $probe = ($lines -join [Environment]::NewLine) | ConvertFrom-Json
    $video = $probe.streams | Where-Object { $_.codec_type -eq 'video' } | Select-Object -First 1
    $audio = $probe.streams | Where-Object { $_.codec_type -eq 'audio' } | Select-Object -First 1
    if (-not $video -or -not $audio -or [double]$probe.format.duration -le 0) { throw 'Файл должен содержать видео и оригинальную звуковую дорожку.' }
    $fpsParts = ([string]$video.avg_frame_rate).Split('/')
    $fps = if ($fpsParts.Count -eq 2 -and [double]$fpsParts[1] -gt 0) { [double]$fpsParts[0] / [double]$fpsParts[1] } else { 0 }
    return [pscustomobject]@{
        title=$file.BaseName; duration=[double]$probe.format.duration; language=''; LocalPath=$file.FullName
        formats=@([pscustomobject]@{
            format_id='local'; width=[int]$video.width; height=[int]$video.height; fps=$fps
            vcodec=[string]$video.codec_name; acodec=[string]$audio.codec_name
            vbr=[double]$video.bit_rate / 1000; tbr=0; filesize=$file.Length
            ext=$file.Extension.TrimStart('.'); protocol='file'; format_note=''; has_drm=$false; dynamic_range='SDR'
        })
    }
}

function Get-ThumbnailUrl {
    param($Metadata)
    $thumbnail = $Metadata.thumbnails | Where-Object { $_.url -match '^https://' } |
        Sort-Object -Property @{Expression={ [double]$_.width * [double]$_.height };Descending=$true}, @{Expression='preference';Descending=$true} |
        Select-Object -First 1
    if ($thumbnail) { return [string]$thumbnail.url }
    if ($Metadata.thumbnail -match '^https://') { return [string]$Metadata.thumbnail }
    throw 'YouTube не вернул обложку. Выберите качество без 000 или другой ролик.'
}

function Get-VideoMetadata {
    param([string]$Url)
    Write-Host 'Получение названия и полного списка качества с YouTube…' -ForegroundColor Cyan
    Write-VotDiagnostic 'metadata.start' @{provider='youtube'}
    $metadataOutput = @(& $env:VOT_YTDLP_EXE --ignore-config --no-playlist --no-progress --js-runtimes ('node:' + $nodeExe) --socket-timeout 30 --retries 3 --extractor-retries 3 --dump-single-json --skip-download $Url 2>&1)
    $metadataExit = $LASTEXITCODE
    $metadataLines = foreach ($line in $metadataOutput) {
        if (([string]$line).TrimStart().StartsWith('{')) { [string]$line }
        else { Write-VotDiagnostic 'metadata.message' @{provider='youtube';message=[string]$line}; Write-Host ([string]$line) -ForegroundColor Yellow }
    }
    if ($metadataExit -ne 0) { Write-VotDiagnostic 'metadata.error' @{provider='youtube';exitCode=$metadataExit}; throw 'Не удалось получить список качества. Сообщение yt-dlp находится выше.' }
    $metadata = ($metadataLines -join [Environment]::NewLine) | ConvertFrom-Json
    if (-not $metadata.title -or -not $metadata.formats) { throw 'YouTube не вернул название или форматы видео.' }
    Write-VotDiagnostic 'metadata.finish' @{provider='youtube';videoId=$metadata.id;durationSeconds=$metadata.duration;formats=$metadata.formats.Count}
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

function Read-VotLanguageSettings {
    Write-Host ''
    Write-Host '1 — На русский — определить язык видео автоматически'
    Write-Host '2 — Выбрать другие языки'
    $choice = Read-NumberedChoice 'Язык озвучки' 2 1
    if ($choice -eq 1) { return [pscustomobject]@{Source='auto'; Target='ru'} }
    $source = Read-LanguageChoice 'С какого языка переводить' $languageConfig.source 'auto'
    $target = Read-LanguageChoice 'На какой язык озвучить' $languageConfig.target 'ru'
    return [pscustomobject]@{Source=$source; Target=$target}
}

function Show-VotAccountMenu {
    while ($true) {
        Write-Host ''; Write-Host 'Аккаунт Яндекса' -ForegroundColor Cyan
        try { $hasAccount = -not [string]::IsNullOrWhiteSpace((Get-VotYandexToken)) }
        catch {
            Write-Host $_.Exception.Message -ForegroundColor Yellow
            Write-Host '0 — Назад'
            if ((Read-Host 'Выберите пункт') -eq '0') { return }
            continue
        }
        if ($hasAccount) {
            Write-Host 'Вход сохранён.'
            Write-Host '1 — Удалить сохранённый вход'
        } else { Write-Host '1 — Войти в Яндекс' }
        Write-Host '0 — Назад'
        $choice = Read-Host 'Выберите пункт'
        if ($choice -eq '0') { return }
        if ($choice -ne '1') { continue }
        try {
            if ($hasAccount) { Disconnect-VotYandex }
            else { Connect-VotYandex $nodeExe | Out-Null }
        } catch { Write-Host $_.Exception.Message -ForegroundColor Yellow }
    }
}

function Read-VotMainAction {
    :MainMenu while ($true) {
        Write-Host '1 — Озвучить видео с YouTube'
        Write-Host '2 — Озвучить локальное видео'
        Write-Host '3 — Справка оригинальной утилиты'
        Write-Host '0 — Выход'
        $choice = Read-Host 'Выберите пункт'
        switch ($choice) {
            '0' { return 'exit' }
            '2' {
                :LocalMenu while ($true) {
                    Write-Host ''; Write-Host 'Локальное видео' -ForegroundColor Cyan
                    Write-Host '1 — Выбрать видеофайл'
                    Write-Host '2 — Аккаунт Яндекса'
                    Write-Host '0 — Назад'
                    switch (Read-Host 'Выберите пункт') {
                        '1' { return 'local' }
                        '2' { Show-VotAccountMenu; continue LocalMenu }
                        '0' { break LocalMenu }
                        default { continue LocalMenu }
                    }
                }
                Write-Host ''
            }
            '3' { & $nodeExe $entryPoint --help | Out-Host; Write-Host ''; continue MainMenu }
            '1' {
                :YouTubeMenu while ($true) {
                    Write-Host ''; Write-Host 'YouTube' -ForegroundColor Cyan
                    Write-Host '1 — Одно видео'
                    Write-Host '2 — Канал целиком'
                    Write-Host '3 — Список ссылок'
                    Write-Host '4 — Продолжить очередь'
                    Write-Host '0 — Назад'
                    switch (Read-Host 'Выберите пункт') {
                        '1' { return 'youtube' }
                        '2' { return 'channel' }
                        '3' { return 'batch' }
                        '4' { return 'resume' }
                        '0' { break YouTubeMenu }
                        default { continue YouTubeMenu }
                    }
                }
                Write-Host ''
            }
        }
    }
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
    param($Metadata, [switch]$AllVariants)
    $hasAudio = @($Metadata.formats | Where-Object { $_.acodec -and $_.acodec -ne 'none' }).Count -gt 0
    if (-not $hasAudio) { throw 'У ролика нет доступной оригинальной аудиодорожки для смешивания.' }
    $qualityNames = @{}
    foreach ($format in $Metadata.formats) {
        if ($format.format_note -match '(\d{3,4})p') {
            $qualityNames[([string]$format.width + 'x' + $format.height)] = $Matches[1] + 'p'
        }
    }
    $videoFormats = @($Metadata.formats | Where-Object {
        $_.vcodec -and $_.vcodec -ne 'none' -and $_.width -gt 0 -and $_.height -gt 0 -and
        -not $_.has_drm -and $_.protocol -ne 'mhtml'
    })
    $h264Pictures = @{}
    foreach ($format in $videoFormats) {
        if ($format.vcodec -match '^(avc[13]|h264)(\.|$)') {
            $h264Pictures[([string]$format.width + 'x' + $format.height)] = $true
        }
    }
    $codecFormats = @(foreach ($format in $videoFormats) {
        $pictureKey = [string]$format.width + 'x' + $format.height
        if (-not $AllVariants -and $h264Pictures.ContainsKey($pictureKey) -and $format.vcodec -notmatch '^(avc[13]|h264)(\.|$)') { continue }
        $format
    })
    $mp4Pictures = @{}
    foreach ($format in $codecFormats) {
        if ($format.ext -eq 'mp4') { $mp4Pictures[([string]$format.width + 'x' + $format.height)] = $true }
    }
    $options = foreach ($format in $codecFormats) {
        $pictureKey = [string]$format.width + 'x' + $format.height
        if (-not $AllVariants -and $mp4Pictures.ContainsKey($pictureKey) -and $format.ext -ne 'mp4') { continue }
        $id = [string]$format.format_id
        $selector = if ($format.acodec -and $format.acodec -ne 'none') { $id } else { $id + '+ba[ext=m4a]/' + $id + '+ba' }
        $bitrate = if ($format.vbr -gt 0) { [double]$format.vbr } elseif ($format.tbr -gt 0) { [double]$format.tbr } else { 0 }
        $isHls = $format.protocol -match '^m3u8'
        $codec = switch -Regex ($format.vcodec) {
            '^avc|^h264' { 'H.264'; break }
            '^av01' { 'AV1'; break }
            '^vp0?9' { 'VP9'; break }
            '^hev|^hvc' { 'HEVC'; break }
            default { [string]$format.vcodec }
        }
        $quality = if ($qualityNames.ContainsKey($pictureKey)) { $qualityNames[$pictureKey] } else { [string]$format.height + 'p' }
        [pscustomobject]@{
            Id = $id; Selector = $selector; Quality = $quality
            Width = [int]$format.width; Height = [int]$format.height
            Fps = [double]$format.fps; Bitrate = $bitrate; Codec = $codec
            IsHls = $isHls; FileSize = [double]$format.filesize
            Container = [string]$format.ext
            Range = if ($format.dynamic_range -and $format.dynamic_range -ne 'SDR') { [string]$format.dynamic_range } else { '' }
        }
    }
    $options = @($options | Sort-Object -Property @{Expression='Height';Descending=$true}, @{Expression='Width';Descending=$true}, @{Expression='Fps';Descending=$true}, @{Expression='Bitrate';Descending=$true}, Id)
    if ($options.Count -eq 0) { throw 'У ролика нет доступных видеоформатов.' }
    return $options
}

function Select-VotBestQuality {
    param([array]$Options, [int]$HeightLimit = 0, [double]$FpsLimit = 0)
    $selected = $Options | Where-Object {
        ($HeightLimit -eq 0 -or $_.Height -le $HeightLimit) -and ($FpsLimit -eq 0 -or $_.Fps -le $FpsLimit + 0.1)
    } | Select-Object -First 1
    if (-not $selected) { throw 'Нет формата в пределах выбранного разрешения и FPS. Качество не заменено другим.' }
    return $selected
}

function Get-VotAutoQuality {
    param($Metadata, [string]$Url, [bool]$AllVariants, [int]$HeightLimit, [double]$FpsLimit, [int]$CheckedHeight = 0, [double]$CheckedFps = 0)
    $options = @(Get-QualityOptions $Metadata -AllVariants:$AllVariants)
    $selected = Select-VotBestQuality $options $HeightLimit $FpsLimit
    if ($CheckedHeight -gt 0 -and ($selected.Height -lt $CheckedHeight -or ($selected.Height -eq $CheckedHeight -and $selected.Fps + 0.1 -lt $CheckedFps))) {
        Write-Host 'YouTube вернул качество ниже предварительно проверенного. Повторно запрашиваю список; качество не понижается.' -ForegroundColor Yellow
        $freshMetadata = Get-VideoMetadata $Url
        $options = @(Get-QualityOptions $freshMetadata -AllVariants:$AllVariants)
        $selected = Select-VotBestQuality $options $HeightLimit $FpsLimit
        if ($selected.Height -lt $CheckedHeight -or ($selected.Height -eq $CheckedHeight -and $selected.Fps + 0.1 -lt $CheckedFps)) { throw 'Список качества изменился относительно предварительной проверки. Ролик пропущен без понижения качества; повторите его позже.' }
    }
    return $selected
}

function Read-VotVideoQuality {
    param($Metadata, [bool]$LocalFile = $false, [bool]$AllVariants = $false)
    $options = @(Get-QualityOptions $Metadata -AllVariants:$AllVariants)
    while ($true) {
        Show-QualityOptions $options $LocalFile $allVariants
        $count = $options.Count
        if (-not $LocalFile -and -not $allVariants) { $count++; Write-Host ([string]$count + ' — Отобразить все варианты') }
        $choice = Read-QualityChoice $count 1 (-not $LocalFile)
        if ($choice.Number -gt $options.Count) {
            $allVariants = $true
            $options = @(Get-QualityOptions $Metadata -AllVariants)
            continue
        }
        return [pscustomobject]@{Quality=$options[$choice.Number - 1]; Thumbnail=$choice.Thumbnail}
    }
}

function Show-QualityOptions {
    param([array]$Options, [bool]$LocalFile = $false, [bool]$AllVariants = $false)
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
            Bitrate = if ($option.Bitrate -gt 0) { ('{0:N0}' -f $option.Bitrate) + ' кбит/с' + $(if ($option.IsHls) { ' (HLS*)' }) } else { '—' }
            Size = if ($option.FileSize -gt 0) { ('{0:N1}' -f ($option.FileSize / 1MB)) + ' МиБ' } else { 'размер неизвестен' }
            Codec = $option.Codec
            Container = $option.Container.ToUpperInvariant()
            Range = $option.Range
            Id = '[' + $option.Id + ']'
        }
    }
    $fields = @('Number','Quality','Picture')
    if ($showFps) { $fields += 'Fps' }
    if ($showBitrate) { $fields += 'Bitrate' }
    if (@($Options | Where-Object { $_.FileSize -gt 0 }).Count -gt 0) { $fields += 'Size' }
    if ($showCodec) { $fields += 'Codec' }
    if ($showContainer) { $fields += 'Container' }
    if (@($Options | Where-Object { $_.Range }).Count -gt 0) { $fields += 'Range' }
    $fields += 'Id'
    $widths = @{}
    foreach ($field in $fields) {
        $widths[$field] = ($rows | ForEach-Object { ([string]$_.$field).Length } | Measure-Object -Maximum).Maximum
    }
    Write-Host ''
    Write-Host $(if ($LocalFile) { 'Качество локального исходника:' } else { 'Доступное качество (от большего к меньшему):' }) -ForegroundColor Cyan
    foreach ($row in $rows) {
        $cells = foreach ($field in $fields) { ([string]$row.$field).PadRight($widths[$field]) }
        Write-Host ($cells -join '  ')
    }
    if (@($Options | Where-Object { $_.IsHls }).Count -gt 0) {
        Write-Host '* HLS: заявленная скорость потока, не измеренный средний битрейт. Большая цифра не гарантирует лучшее изображение или больший файл.'
    }
    if ($LocalFile) {
        Write-Host 'Сохраняются исходное разрешение и FPS. Для совместимых кодеков видео копируется без повторного сжатия.'
        Write-Host 'Оригинальный звук 15%, перевод 100%. У файла нет обложки YouTube.'
        return
    }
    Write-Host 'Размер — только исходный видеопоток, без итоговой озвучки.'
    if ($AllVariants) { Write-Host 'Показаны все доступные видеоварианты, без приоритетов H.264 и MP4.' }
    else {
        Write-Host 'Для каждого разрешения: только H.264, если он доступен; иначе все доступные кодеки.'
        Write-Host 'После выбора кодеков: только MP4, если он доступен для этого разрешения; иначе остальные контейнеры.'
    }
    Write-Host 'Контейнер в списке — исходный; готовое видео сохраняется в MP4.'
    Write-Host 'В каждом варианте: оригинальный звук 15%, перевод 100%.'
    Write-Host 'Для обложки первым кадром добавьте пробел и 000: например, 4 000. У H.264 перекодируется только начальный фрагмент; остальное видео копируется.'
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

$appVersion = (Get-Content -LiteralPath (Join-Path $appRoot 'package.json') -Raw | ConvertFrom-Json).version
if ($env:VOT_QUEUE_WORKER -ne '1') {
    Write-Host ''
    Write-Host ('VOT-CLI Live — озвучка видео (версия ' + $appVersion + ')') -ForegroundColor Cyan
    Write-Host ('Папка для видео: ' + $videoRoot)
    Write-Host ''
}

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
    if (-not $VideoUrl -and -not $LocalVideo) {
        Set-VotState 'awaiting_menu'
        $action = Read-VotMainAction
        if ($action -eq 'exit') { Set-VotState 'closed'; break }
        if ($action -in @('channel','batch','resume')) {
            try {
                if ($action -eq 'resume') { Resume-VotQueue }
                else { New-VotQueue $action }
            } catch { Write-Host $_.Exception.Message -ForegroundColor Yellow }
            Write-Host ''; continue
        }
        $configureLanguages = $true
        Set-VotState 'awaiting_url'
        $VideoUrl = if ($action -eq 'local') { '2' } else { Read-Host 'Вставьте ссылку на YouTube' }
    }
    $jobRoot = $null
    $workVideo = $null
    $votExitCode = $null
    $resultSaved = $false
    $downloadFailed = $false
    $currentAttempt = if ($Once -and $AttemptId) { $AttemptId } else { [Guid]::NewGuid().ToString('N') }
    $diagnosticDirectory = if ($ResultFile) { Split-Path $ResultFile -Parent } else { Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'VOT-CLI-Live\diagnostics' }
    $diagnosticFile = Join-Path $diagnosticDirectory ('diagnostic-' + $currentAttempt + '.jsonl')
    $outcome = [pscustomobject]@{attemptId=$currentAttempt; success=$false; output=''; title=''; error=''; authSource='none'; diagnosticFile=$diagnosticFile}
    $diagnosticEnvironment = @{}
    foreach ($variable in @('VOT_DIAGNOSTIC_FILE','VOT_ATTEMPT_ID','VOT_DIAGNOSTIC_HELPER')) { $diagnosticEnvironment[$variable] = [Environment]::GetEnvironmentVariable($variable,'Process') }
    $savedOauthToken = $env:YANDEX_OAUTH_TOKEN
    try {
        $env:VOT_DIAGNOSTIC_FILE = $diagnosticFile
        $env:VOT_ATTEMPT_ID = $currentAttempt
        $env:VOT_DIAGNOSTIC_HELPER = Join-Path $appRoot 'src\diagnostics.js'
        Write-VotDiagnostic 'attempt.start' @{version=$appVersion;powerShell=$PSVersionTable.PSVersion.ToString();ytdlp=((& $env:VOT_YTDLP_EXE --version) -join '').Trim();ffmpeg=((& $env:VOT_FFMPEG_EXE -version | Select-Object -First 1) -split '\s+')[2]}
        $selectedLocalVideo = $LocalVideo
        if (([string]$VideoUrl).Trim() -eq '2' -and -not $selectedLocalVideo) { $selectedLocalVideo = Select-LocalVideoFile }
        $isLocalVideo = -not [string]::IsNullOrWhiteSpace($selectedLocalVideo)
        $canonicalUrl = if ($isLocalVideo) { '' } else { Get-CanonicalVideoUrl $VideoUrl }
        if ($configureLanguages) {
            Set-VotState 'awaiting_language'
            $languages = Read-VotLanguageSettings
            $requestedSource = $languages.Source
            $selectedTarget = $languages.Target
        }
        Set-VotState 'fetching_formats'
        $metadata = if ($isLocalVideo) { Get-LocalVideoMetadata $selectedLocalVideo } else { Get-VideoMetadata $canonicalUrl }
        $outcome.title = [string]$metadata.title
        if ($isLocalVideo) {
            Write-Host ('Выбран файл: ' + $metadata.LocalPath) -ForegroundColor Cyan
            Write-Host 'Перевод выполняется онлайн: программа временно предоставит Яндексу доступ только к этому ролику.'
        }
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
        if ($selectedVoice -eq 'live') {
            $storedToken = Get-VotYandexToken
            if ($storedToken) {
                $env:YANDEX_OAUTH_TOKEN = $storedToken
                $outcome.authSource = 'saved'
                Write-Host 'Используется сохранённый вход Яндекса.'
            }
            elseif ($env:YANDEX_OAUTH_TOKEN -or $env:YANDEX_API_TOKEN) { $outcome.authSource = 'environment'; Write-Host 'Используется вход Яндекса, переданный процессу.' }
            elseif ($isLocalVideo) { $env:YANDEX_OAUTH_TOKEN = Read-LocalLiveToken; $outcome.authSource = 'saved' }
            $storedToken = $null
        }
        $selectedTtsVoice = ''
        if ($selectedVoice -eq 'edge') { $selectedTtsVoice = Read-MicrosoftVoice $selectedTarget $TtsVoice }
        Write-VotDiagnostic 'attempt.settings' @{source=$(if($isLocalVideo){'local'}else{'youtube'});videoId=$(if($isLocalVideo){$null}else{$metadata.id});sourceLanguage=$sourceLanguage;targetLanguage=$selectedTarget;voice=$selectedVoice;authSource=$outcome.authSource}
        Write-Host ('Видео: ' + $metadata.title)
        $allVariants = [bool]$ShowAllFormats -or [bool]$VideoFormatId
        $qualityOptions = @(Get-QualityOptions $metadata -AllVariants:$allVariants)
        $addThumbnail = [bool]$ThumbnailFirstFrame
        if ($VideoFormatId) {
            $selectedQuality = $qualityOptions | Where-Object { $_.Id -eq $VideoFormatId } | Select-Object -First 1
            if (-not $selectedQuality) { throw ('У ролика нет формата ' + $VideoFormatId + '.') }
        } elseif ($AutoQuality -or ($Once -and $MaxHeight -gt 0)) {
            $selectedQuality = Get-VotAutoQuality $metadata $canonicalUrl $allVariants $MaxHeight $MaxFps $ExpectedHeight $ExpectedFps
        } else {
            Set-VotState 'awaiting_quality'
            $qualityChoice = Read-VotVideoQuality $metadata $isLocalVideo $allVariants
            $selectedQuality = $qualityChoice.Quality
            $addThumbnail = $addThumbnail -or $qualityChoice.Thumbnail
        }
        if ($isLocalVideo -and $addThumbnail) { throw 'Для локального файла обложка YouTube недоступна.' }
        $thumbnailUrl = if ($addThumbnail) { Get-ThumbnailUrl $metadata } else { '' }
        $jobName = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,6)
        Write-VotDiagnostic 'quality.selected' @{selector=$selectedQuality.Selector;width=$selectedQuality.Width;height=$selectedQuality.Height;codec=$selectedQuality.Codec;thumbnail=$addThumbnail;originalVolume=0.15;translationVolume=1}
        $jobRoot = Join-Path $jobsRoot $jobName
        New-Item -ItemType Directory -Path $jobRoot -Force | Out-Null
        Set-VotState 'running' $jobRoot
        Write-Host ('Выбрано: ' + $selectedQuality.Quality + ', ' + $selectedQuality.Width + '×' + $selectedQuality.Height + ', ' + $selectedQuality.Codec)
        Write-Host $(if ($isLocalVideo) { 'Получение перевода и сборка видео…' } else { 'Получение перевода и скачивание видео…' }) -ForegroundColor Cyan
        $votArguments = @($entryPoint, ('--voice-style=' + $selectedVoice), ('--lang=' + $sourceLanguage), ('--reslang=' + $selectedTarget), '--merge-video', ('--video-format=' + $selectedQuality.Selector), ('--video-title=' + $metadata.title), ('--video-duration=' + $metadata.duration), '--keep-original-audio=true', '--normalize-audio=false', '--original-volume=0.15', '--translation-volume=1', '--translation-timeout=900', ('--output=' + $jobRoot), '--output-file=video-ru')
        if ($addThumbnail) {
            Write-Host 'Первый кадр: обложка YouTube. Подготовка без ограничения средним битрейтом всего ролика.' -ForegroundColor Cyan
            $votArguments += '--thumbnail-url=' + $thumbnailUrl
        }
        if ($selectedVoice -eq 'edge') {
            $metadataPath = Join-Path $jobRoot 'metadata.json'
            $metadata | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $metadataPath -Encoding UTF8
            $votArguments += @(('--tts-voice=' + $selectedTtsVoice), ('--video-metadata=' + $metadataPath))
        }
        if ($isLocalVideo) {
            & (Join-Path $PSScriptRoot 'Bootstrap-LocalVideo.ps1') -BinRoot $binRoot
            $env:VOT_PARENT_PID = [string]$PID
            $votArguments[0] = Join-Path $appRoot 'src\localVideo.js'
            $votArguments += '--source=' + $metadata.LocalPath
        } else { $votArguments += $canonicalUrl }
        & $nodeExe @votArguments
        $votExitCode = $LASTEXITCODE
        Write-VotDiagnostic 'worker.exit' @{exitCode=$votExitCode}
        $workVideo = Join-Path $jobRoot 'video-ru.mp4'
        if ($votExitCode -ne 0 -or -not (Test-Path -LiteralPath $workVideo) -or (Get-Item -LiteralPath $workVideo).Length -eq 0) {
            throw ('Видео не создано. Код завершения: ' + $votExitCode + '. Сообщение сервиса находится выше.')
        }
        $resultVideo = Get-DesktopResultPath ([string]$metadata.title)
        Move-Item -LiteralPath $workVideo -Destination $resultVideo
        $resultSaved = $true
        $outcome.success = $true; $outcome.output = $resultVideo
        Set-VotState 'completed' $resultVideo
        Write-Host ('Готово: ' + $resultVideo) -ForegroundColor Green
    } catch {
        Write-VotDiagnostic 'attempt.error' @{message=$_.Exception.Message}
        $downloadFailed = $true
        $outcome.error = $_.Exception.Message
        Set-VotState 'failed' $_.Exception.Message
        Write-Host $_.Exception.Message -ForegroundColor $(if ($_.Exception -is [OperationCanceledException]) { 'Yellow' } else { 'Red' })
    } finally {
        [Environment]::SetEnvironmentVariable('YANDEX_OAUTH_TOKEN', $savedOauthToken, 'Process')
        if (-not $resultSaved -and $votExitCode -eq 0 -and $workVideo -and (Test-Path -LiteralPath $workVideo)) {
            Write-Host ('Сохранение на рабочий стол не удалось. Готовый файл оставлен здесь: ' + $workVideo) -ForegroundColor Yellow
        } else {
            try { Remove-VotJob $jobRoot }
            catch { Write-VotDiagnostic 'cleanup.error' @{message=$_.Exception.Message}; Write-Host $_.Exception.Message -ForegroundColor Yellow }
        }
        Write-VotDiagnostic 'attempt.finish' @{success=$outcome.success;workerExitCode=$votExitCode;outputSaved=$resultSaved}
        Write-Host ('Диагностика: ' + $diagnosticFile) -ForegroundColor Cyan
        foreach ($variable in $diagnosticEnvironment.Keys) {
            if ($null -eq $diagnosticEnvironment[$variable]) { Remove-Item -LiteralPath ('Env:' + $variable) -ErrorAction SilentlyContinue }
            else { [Environment]::SetEnvironmentVariable($variable,$diagnosticEnvironment[$variable],'Process') }
        }
    }
    if ($ResultFile) {
        $outcome | ConvertTo-Json -Compress | Set-Content -LiteralPath $ResultFile -Encoding UTF8
    }
    if ($Once) { if ($downloadFailed) { exit 1 }; exit 0 }
    $VideoUrl = ''
    $LocalVideo = ''
    Write-Host ''
} while ($true)
