function Write-VotDiagnostic {
    param([string]$Event, [hashtable]$Data = @{})
    if (-not $env:VOT_DIAGNOSTIC_FILE -or -not $env:VOT_DIAGNOSTIC_HELPER -or -not $env:VOT_NODE_EXE) { return }
    $previous = $env:VOT_DIAGNOSTIC_DATA
    try {
        $env:VOT_DIAGNOSTIC_DATA = $Data | ConvertTo-Json -Depth 8 -Compress
        & $env:VOT_NODE_EXE $env:VOT_DIAGNOSTIC_HELPER $Event 2>&1 | ForEach-Object { Write-Host ([string]$_) -ForegroundColor Yellow }
    } catch {
        Write-Host 'Не удалось записать диагностический журнал.' -ForegroundColor Yellow
    } finally {
        if ($null -eq $previous) { Remove-Item Env:VOT_DIAGNOSTIC_DATA -ErrorAction SilentlyContinue }
        else { $env:VOT_DIAGNOSTIC_DATA = $previous }
    }
}

function Get-VotQueueRoot {
    $root = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'VOT-CLI-Live\queues'
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    return $root
}

function Save-VotQueue {
    param($Queue, [string]$Manifest)
    $Queue.updatedAt = [DateTimeOffset]::Now.ToString('o')
    $temporary = $Manifest + '.tmp'
    $Queue | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $temporary -Encoding UTF8
    Move-Item -LiteralPath $temporary -Destination $Manifest -Force
}

function Get-VotExclusions {
    param([string]$Text, [int]$Count)
    $numbers = [Collections.Generic.HashSet[int]]::new()
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    foreach ($part in ($Text -replace '[–—]', '-') -split '[,;\s]+') {
        if (-not $part) { continue }
        if ($part -notmatch '^(\d+)(?:-(\d+))?$') { throw 'Введите номера или диапазоны: например, 2, 5, 8-12.' }
        $first = 0; $last = 0
        if (-not [int]::TryParse($Matches[1], [ref]$first)) { throw 'Слишком большой номер.' }
        if ($Matches[2]) {
            if (-not [int]::TryParse($Matches[2], [ref]$last)) { throw 'Слишком большой номер.' }
        } else { $last = $first }
        if ($first -lt 1 -or $last -gt $Count -or $last -lt $first) { throw ('Номера должны быть от 1 до ' + $Count + '.') }
        for ($number = $first; $number -le $last; $number++) { [void]$numbers.Add($number) }
    }
    return @($numbers | Sort-Object)
}

function Read-VotQueueRequestMode {
    Write-Host ''
    Write-Host 'Режим запросов:' -ForegroundColor Cyan
    Write-Host '1 — Постепенный (меньше одновременных запросов)'
    Write-Host '    Качество перед каждым роликом, фрагменты последовательно, пауза 10 с между роликами.'
    Write-Host '2 — С предварительной проверкой'
    Write-Host '    Сначала качество всего списка; затем ролики по очереди, фрагменты в 4 потока.'
    Write-Host 'В обоих режимах одновременно обрабатывается один ролик. Отказы сервисов всё ещё возможны.'
    if ((Read-NumberedChoice 'Выберите режим запросов' 2 1 -NoCancel) -eq 1) { return 'gradual' }
    return 'preflight'
}

function Get-VotQueueRequestMode {
    param($Settings)
    if ($Settings.requestMode -eq 'gradual') { return 'gradual' }
    return 'preflight'
}

function Read-VotDeferredQualitySettings {
    $limits = @(4320,2160,1440,1080,720,480,360,240,144)
    $allVariants = $false
    while ($true) {
        Write-Host ''; Write-Host 'Качество — без предварительных запросов ко всему списку:' -ForegroundColor Cyan
        Write-Host ('1 — Лучшее доступное качество каждого ролика (без ограничения; ' + $(if ($allVariants) { 'без фильтров' } else { 'приоритет MP4 / H.264' }) + ')')
        for ($i = 0; $i -lt $limits.Count; $i++) { Write-Host ([string]($i + 2) + ' — до ' + $limits[$i] + 'p, любая частота кадров') }
        $count = $limits.Count + 1
        if (-not $allVariants) { $count++; Write-Host ([string]$count + ' — Отобразить все варианты') }
        else { Write-Host 'Фильтры H.264 и MP4 отключены; доступны все кодеки и контейнеры в выбранном пределе.' }
        if (-not $allVariants) { Write-Host 'Приоритет в каждом разрешении: H.264, затем MP4; если их нет — другие кодеки/контейнеры.' }
        Write-Host 'Это пределы качества, а не заранее проверенная доступность. Список форматов запрашивается перед каждым роликом.'
        Write-Host 'Если выбранного разрешения нет — ближайшее меньшее; ошибка запроса не считается отсутствием качества.'
        $choice = Read-QualityChoice $count 1 $true
        if (-not $allVariants -and $choice.Number -eq $count) { $allVariants = $true; continue }
        $height = if ($choice.Number -eq 1) { 0 } else { $limits[$choice.Number - 2] }
        return [pscustomobject]@{maxHeight=$height; maxFps=0; thumbnail=[bool]$choice.Thumbnail; allVariants=$allVariants}
    }
}

function Read-VotQueueSettings {
    param([array]$Items)
    $languages = Read-VotLanguageSettings
    $source = $languages.Source
    $target = $languages.Target
    $voices = @()
    if ($source -in @('en','auto') -and $target -eq 'ru') { $voices += [pscustomobject]@{Id='live'; Name='Яндекс — Живые голоса (английский → русский)'} }
    $voices += [pscustomobject]@{Id='tts'; Name='Яндекс — Стандартные голоса'}
    $voices += [pscustomobject]@{Id='edge'; Name='Microsoft Edge — нейронные голоса'}
    for ($i = 0; $i -lt $voices.Count; $i++) { Write-Host (([string]($i + 1)) + ' — ' + $voices[$i].Name) }
    $voice = $voices[(Read-NumberedChoice 'Выберите озвучку всей очереди' $voices.Count 1) - 1].Id
    $speaker = if ($voice -eq 'edge') { Read-MicrosoftVoice $target '' } else { '' }
    if ($voice -eq 'live') { Write-Host 'Живые голоса подходят для английских роликов. Другие языки не будут молча переведены стандартным голосом.' -ForegroundColor Yellow }
    $requestMode = Read-VotQueueRequestMode
    if ($requestMode -eq 'gradual') {
        $quality = Read-VotDeferredQualitySettings
        return [pscustomobject]@{source=$source; target=$target; voice=$voice; speaker=$speaker; maxHeight=$quality.maxHeight; maxFps=$quality.maxFps; thumbnail=$quality.thumbnail; allVariants=$quality.allVariants; requestMode='gradual'}
    }
    $catalog = [Collections.Generic.List[object]]::new()
    $index = 0
    foreach ($item in $Items) {
        $index++
        Write-Host ('Проверка качества [' + $index + '/' + $Items.Count + '] ' + $item.title) -ForegroundColor Cyan
        try {
            $metadata = Get-VideoMetadata $item.url
            $catalog.Add([pscustomobject]@{Item=$item; Preferred=@(Get-QualityOptions $metadata); All=@(Get-QualityOptions $metadata -AllVariants)})
        } catch {
            Write-Host ('Не удалось проверить качество: ' + $item.url + '. Ошибка не считается отсутствием высокого разрешения. При обработке будет новая попытка.') -ForegroundColor Yellow
        }
    }
    if (-not $catalog.Count) { throw 'Не удалось получить качество ни одного выбранного видео. Очередь сохранена; повторите позже.' }
    $allVariants = $false
    while ($true) {
        $levels = @(Get-VotQueueQualityLevels $catalog $allVariants)
        Write-Host ''; Write-Host ('Качество всех роликов: проверено ' + $catalog.Count + ' из ' + $Items.Count) -ForegroundColor Cyan
        Write-Host ('1 — Лучшее доступное качество каждого ролика (без ограничения; ' + $(if ($allVariants) { 'без фильтров' } else { 'приоритет MP4 / H.264' }) + ')')
        if (-not $allVariants) { Write-Host 'Приоритет в каждом разрешении: H.264, затем MP4; если их нет — другие кодеки/контейнеры.' }
        $showFps = @($levels.Fps | Sort-Object -Unique).Count -gt 1
        for ($i = 0; $i -lt $levels.Count; $i++) {
            $level = $levels[$i]
            Write-Host ([string]($i + 2) + ' — до ' + $level.Height + 'p' + $(if ($showFps) { ', до ' + $level.Fps + ' FPS' }) + ' | есть у ' + $level.Count + ' из ' + $catalog.Count + ' проверенных роликов')
        }
        $count = $levels.Count + 1
        if (-not $allVariants) { $count++; Write-Host ([string]$count + ' — Отобразить все варианты') }
        else { Write-Host 'Фильтры H.264 и MP4 отключены. Для очереди одинаковые разрешения/FPS объединены.' }
        Write-Host 'Это верхняя граница для каждого ролика: например, при выборе 1080p ролик с максимумом 720p будет сохранён в 720p.'
        Write-Host 'Ошибка связи не понижает качество: список запрашивается повторно, а при неудаче ролик отмечается ошибкой.'
        $choice = Read-QualityChoice $count 1 $true
        if (-not $allVariants -and $choice.Number -eq $count) { $allVariants = $true; continue }
        $heightLimit = 0; $fpsLimit = 0
        if ($choice.Number -ne 1) {
            $heightLimit = $levels[$choice.Number - 2].Height
            $fpsLimit = $levels[$choice.Number - 2].Fps
        }
        foreach ($record in $catalog) {
            $options = if ($allVariants) { $record.All } else { $record.Preferred }
            $qualityLevels = @($options | ForEach-Object { [pscustomobject]@{Height=$_.Height; Width=$_.Width; Fps=$_.Fps} })
            $record.Item | Add-Member -NotePropertyName qualityLevels -NotePropertyValue $qualityLevels -Force
        }
        return [pscustomobject]@{source=$source; target=$target; voice=$voice; speaker=$speaker; maxHeight=$heightLimit; maxFps=$fpsLimit; thumbnail=[bool]$choice.Thumbnail; allVariants=$allVariants; requestMode='preflight'}
    }
}

function Get-VotQueueQualityLevels {
    param([array]$Catalog, [bool]$AllVariants = $false)
    $levels = @{}
    foreach ($record in $Catalog) {
        $seen = @{}
        $options = if ($AllVariants) { $record.All } else { $record.Preferred }
        foreach ($option in $options) {
            $fps = [Math]::Round($option.Fps)
            $key = [string]$option.Height + '/' + $fps
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true
            if (-not $levels.ContainsKey($key)) { $levels[$key] = [pscustomobject]@{Height=$option.Height; Fps=$fps; Count=0} }
            $levels[$key].Count++
        }
    }
    return @($levels.Values | Sort-Object -Property @{Expression='Height';Descending=$true}, @{Expression='Fps';Descending=$true})
}

function New-VotQueue {
    param([ValidateSet('channel','batch')][string]$Mode)
    if ($Mode -eq 'channel') {
        $text = Read-Host 'Вставьте ссылку на канал YouTube (0 — отмена)'
        if ($text -eq '0' -or -not $text) { throw [OperationCanceledException]::new('Выбор канала отменён.') }
    } else {
        $raw = & (Join-Path $PSHOME 'pwsh.exe') -NoLogo -NoProfile -STA -File (Join-Path $PSScriptRoot 'Select-VideoSources.ps1')
        if ($LASTEXITCODE -ne 0) { throw 'Не удалось открыть окно списка ссылок.' }
        if (-not $raw) { throw [OperationCanceledException]::new('Ввод списка отменён.') }
        $text = ($raw -join [Environment]::NewLine) | ConvertFrom-Json
        if ([string]::IsNullOrWhiteSpace($text)) { throw 'Список ссылок пуст.' }
    }
    $directory = Join-Path (Get-VotQueueRoot) ((Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $inputPath = Join-Path $directory 'input.txt'
    $text | Set-Content -LiteralPath $inputPath -Encoding UTF8
    $collector = Join-Path $appRoot 'src\queueSources.js'
    if ($Mode -eq 'channel') {
        $parsedLines = & $nodeExe $collector $inputPath --parse-only
        $parsed = ($parsedLines -join [Environment]::NewLine) | ConvertFrom-Json
        if (@($parsed.sources).Count -ne 1 -or $parsed.sources[0].kind -ne 'channel' -or @($parsed.issues).Count) { throw 'Вставьте одну ссылку на канал YouTube, например https://www.youtube.com/@channel.' }
    }
    Write-Host 'Составляю очередь. Для большого канала получение списка может занять несколько минут…' -ForegroundColor Cyan
    $lines = & $nodeExe $collector $inputPath
    if ($LASTEXITCODE -ne 0) { throw 'Не удалось составить очередь.' }
    $collected = ($lines -join [Environment]::NewLine) | ConvertFrom-Json
    $queue = [pscustomobject]@{version=1; createdAt=[DateTimeOffset]::Now.ToString('o'); updatedAt=''; state='draft'; settings=$null; items=@($collected.items); issues=@($collected.issues)}
    $manifest = Join-Path $directory 'queue.json'
    Save-VotQueue $queue $manifest
    foreach ($issue in $queue.issues) { Write-Host ($issue.input + ' — ' + $issue.reason) -ForegroundColor Yellow }
    if (-not $queue.items.Count) { Write-VotQueueReport $queue $directory; throw ('Нет доступных ссылок. Отчёт: ' + $directory) }
    Write-Host ''; Write-Host ('Найдено уникальных роликов: ' + $queue.items.Count) -ForegroundColor Cyan
    for ($i = 0; $i -lt $queue.items.Count; $i++) {
        Write-Host ([string]($i + 1) + ' — ' + $queue.items[$i].title + ' | ' + $queue.items[$i].url)
    }
    while ($true) {
        try {
            $excludedText = Read-Host 'Какие номера исключить? Например, 2, 5, 8-12. Enter — оставить все; 0 — отмена'
            if ($excludedText -eq '0') { throw [OperationCanceledException]::new('Запуск очереди отменён.') }
            $excluded = @(Get-VotExclusions $excludedText $queue.items.Count)
            break
        } catch [OperationCanceledException] { throw }
        catch { Write-Host $_.Exception.Message -ForegroundColor Yellow }
    }
    foreach ($number in $excluded) { $queue.items[$number - 1].status = 'excluded' }
    Save-VotQueue $queue $manifest
    $selected = @($queue.items | Where-Object status -ne 'excluded')
    if (-not $selected.Count) { throw [OperationCanceledException]::new('Все ролики исключены.') }
    Write-Host ('К обработке: ' + $selected.Count + '; исключено: ' + $excluded.Count)
    $queue.settings = Read-VotQueueSettings $selected
    Save-VotQueue $queue $manifest
    $confirm = Read-Host ('Запустить ' + $selected.Count + ' роликов? Enter — начать; 0 — вернуться в меню')
    if ($confirm -eq '0') { throw [OperationCanceledException]::new('Очередь сохранена. Продолжение доступно в разделе YouTube → Продолжить очередь.') }
    Invoke-VotQueue $queue $manifest
}

function Write-VotQueueReport {
    param($Queue, [string]$Directory)
    $report = [Collections.Generic.List[string]]::new()
    $report.Add('VOT — отчёт очереди, ' + [DateTimeOffset]::Now.ToString('o'))
    $report.Add('Состояние: ' + $Queue.state)
    if ($Queue.settings) {
        $report.Add('Режим запросов: ' + $(if ((Get-VotQueueRequestMode $Queue.settings) -eq 'gradual') { 'постепенный; качество перед роликом, 1 поток фрагментов, пауза 10 с' } else { 'предварительная проверка; 4 потока фрагментов' }))
    }
    foreach ($item in $Queue.items) {
        $report.Add('[' + $item.status + '] ' + $item.title + ' | ' + $item.url)
        if ($item.output) { $report.Add('  Файл: ' + $item.output) }
        if ($item.error) { $report.Add('  Ошибка: ' + $item.error) }
        if ($item.diagnosticFile) { $report.Add('  Диагностика: ' + $item.diagnosticFile) }
    }
    foreach ($issue in $Queue.issues) { $report.Add('[Не разобрано / недоступно] ' + $issue.input + ' — ' + $issue.reason) }
    $report | Set-Content -LiteralPath (Join-Path $Directory 'report.txt') -Encoding UTF8
}

function Invoke-VotQueue {
    param($Queue, [string]$Manifest, [scriptblock]$Worker)
    $directory = Split-Path $Manifest -Parent
    try { $queueLock = [IO.File]::Open((Join-Path $directory 'queue.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) }
    catch { throw 'Эта очередь уже обрабатывается в другом окне либо её папка недоступна.' }
    try {
    $items = @($Queue.items | Where-Object status -ne 'excluded')
    $done = @($items | Where-Object status -eq 'completed').Count
    $Queue.state = 'running'; Save-VotQueue $Queue $Manifest
    Write-Host ('Очередь сохранена: ' + $directory)
    Write-Host 'Основано на FOSWLY/vot-cli (Toil / @ToilOfficial) → fantomcheg/vot-cli-live.' -ForegroundColor DarkGray
    Write-Host 'Прервать: Ctrl+C. Продолжить позже: YouTube → Продолжить очередь. Готовые видео сохраняются на рабочий стол.'
    $requestMode = Get-VotQueueRequestMode $Queue.settings
    Write-Host $(if ($requestMode -eq 'gradual') { 'Постепенный режим: качество перед каждым роликом; пауза 10 с между роликами; фрагменты последовательно.' } else { 'Предварительная проверка: ролики по очереди; фрагменты в 4 потока.' })
    $processedInRun = 0
    try {
        for ($i = 0; $i -lt $items.Count; $i++) {
            $item = $items[$i]
            if ($item.status -eq 'completed') { continue }
            if ($requestMode -eq 'gradual' -and $processedInRun -gt 0) { Wait-VotQueueInterval 10 }
            $item.status = 'running'; $item.error = ''; Save-VotQueue $Queue $Manifest
            $percentage = if ($items.Count) { [Math]::Floor(100 * $done / $items.Count) } else { 0 }
            Write-Host ''; Write-Host ('[' + ($i + 1) + '/' + $items.Count + '] ' + $item.title + ' — очередь ' + $percentage + '%') -ForegroundColor Cyan
            $resultPath = Join-Path $directory ('item-' + $i + '.json')
            $logPath = Join-Path $directory ('item-' + $i + '.log')
            $attemptId = [Guid]::NewGuid().ToString('N')
            $outcome = $null
            try {
                if ($Worker) { $outcome = & $Worker $item $Queue.settings }
                else {
                    $settings = $Queue.settings
                    $item | Add-Member -NotePropertyName diagnosticFile -NotePropertyValue (Join-Path $directory ('diagnostic-' + $attemptId + '.jsonl')) -Force
                    $arguments = @('-NoLogo','-NoProfile','-STA','-File',(Join-Path $PSScriptRoot 'Run-VOT.ps1'),'-Once','-VideoUrl',$item.url,'-SourceLanguage',$settings.source,'-TargetLanguage',$settings.target,'-VoiceStyle',$settings.voice,'-AutoQuality','-MaxHeight',[string]$settings.maxHeight,'-MaxFps',[string]$settings.maxFps,'-ResultFile',$resultPath,'-AttemptId',$attemptId)
                    if ($settings.speaker) { $arguments += @('-TtsVoice',$settings.speaker) }
                    if ($settings.thumbnail) { $arguments += '-ThumbnailFirstFrame' }
                    if ($settings.allVariants) { $arguments += '-ShowAllFormats' }
                    if ($requestMode -eq 'preflight' -and $item.qualityLevels) {
                        $expected = $item.qualityLevels | Where-Object {
                            ($settings.maxHeight -eq 0 -or $_.Height -le $settings.maxHeight) -and ($settings.maxFps -eq 0 -or $_.Fps -le $settings.maxFps + 0.1)
                        } | Sort-Object -Property @{Expression='Height';Descending=$true}, @{Expression='Width';Descending=$true}, @{Expression='Fps';Descending=$true} | Select-Object -First 1
                        if ($expected) { $arguments += @('-ExpectedHeight',[string]$expected.Height,'-ExpectedFps',[string]$expected.Fps) }
                    }
                    Invoke-VotQueueChild $arguments $logPath $settings.voice -RequestMode $requestMode
                    if (Test-Path -LiteralPath $resultPath) {
                        $candidate = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
                        if ($candidate.attemptId -eq $attemptId) { $outcome = $candidate }
                    }
                }
                if (-not $outcome) { throw 'Процесс завершился без результата. Подробности в журнале задания.' }
                if ($outcome.diagnosticFile) { $item | Add-Member -NotePropertyName diagnosticFile -NotePropertyValue $outcome.diagnosticFile -Force }
                if ($outcome.success -and (Test-Path -LiteralPath $outcome.output) -and (Get-Item -LiteralPath $outcome.output).Length -gt 0) {
                    $item.status = 'completed'; $item.output = $outcome.output
                    if ($outcome.title) { $item.title = $outcome.title }
                } else { throw $(if ($outcome.error) { [string]$outcome.error } else { 'Готовый файл не найден.' }) }
            } catch {
                $item.status = 'failed'; $item.error = $_.Exception.Message
                $details = if (Test-Path -LiteralPath $logPath) { (Get-Content -LiteralPath $logPath -Tail 35) -join ' ' } else { $item.error }
                if (Test-Path -LiteralPath $logPath) {
                    $errorLines = @(Get-Content -LiteralPath $logPath -Tail 35)
                    $providerMessage = $errorLines | Where-Object { $_ -match '(?i)HTTP(?: Error)?\s*\d{3}' } | Select-Object -Last 1
                    if (-not $providerMessage) { $providerMessage = $errorLines | Where-Object {
                        $_ -match '(?i)ERROR:|Yandex auth required|Yandex couldn.t|Video unavailable|Private video|not available|HTTP Error|too many requests'
                    } | Select-Object -Last 1 }
                    if ($providerMessage) {
                        $providerMessage = [regex]::Replace([string]$providerMessage, '\x1b\[[0-9;]*m', '')
                        $item.error = $providerMessage.Substring(0, [Math]::Min(500, $providerMessage.Length))
                    }
                }
                $youtube401 = $details -match '(?i)yt-dlp(?:\.exe)?:' -and $details -match '(?i)HTTP(?: Error)?\s*401\b'
                if ($youtube401 -or $details -match '(?i)HTTP(?: Error)?\s*403\b') {
                    $downloadStatus = if ($youtube401) { 401 } else { 403 }
                    $Queue.state = 'paused'
                    $item.error += (' Очередь приостановлена: сервер запретил скачивание (HTTP ' + $downloadStatus + '). Качество не понижено. Повторите позже через YouTube → Продолжить очередь.')
                } elseif ($details -match '(?i)Yandex auth required|HTTP(?: Error)?\s*401|status.?7\b|too many requests|HTTP(?: Error)?\s*429|status.?429\b') {
                    $Queue.state = 'paused'
                    $item.error += ' Очередь приостановлена: сервис отклонил авторизацию либо ограничил запросы. Это не означает, что сохранённый вход потерян. Повторите позже через YouTube → Продолжить очередь.'
                }
                Write-Host ($item.url + ' — ' + $item.error) -ForegroundColor Yellow
            }
            $done++
            $processedInRun++
            Save-VotQueue $Queue $Manifest; Write-VotQueueReport $Queue $directory
            $succeeded = @($items | Where-Object status -eq 'completed').Count
            $failed = @($items | Where-Object status -eq 'failed').Count
            Write-Host ('Очередь: ' + [Math]::Floor(100 * $done / $items.Count) + '%; готово: ' + $succeeded + '/' + $items.Count + '; ошибок: ' + $failed + '; осталось: ' + ($items.Count - $done))
            if ($Queue.state -eq 'paused') { break }
        }
        if ($Queue.state -eq 'running') { $Queue.state = 'finished' }
    } finally {
        if ($Queue.state -eq 'running') { $Queue.state = 'interrupted' }
        Save-VotQueue $Queue $Manifest; Write-VotQueueReport $Queue $directory
        $completed = @($items | Where-Object status -eq 'completed').Count
        $errors = @($items | Where-Object status -eq 'failed').Count
        $remaining = @($items | Where-Object { $_.status -in @('pending','running') }).Count
        $label = if ($Queue.state -eq 'finished') { 'Обработка очереди завершена' } elseif ($Queue.state -eq 'paused') { 'Очередь приостановлена' } else { 'Очередь прервана' }
        Write-Host ($label + ': готово ' + $completed + '/' + $items.Count + '; ошибок: ' + $errors + '; осталось: ' + $remaining + '.') -ForegroundColor Cyan
        Write-Host ('Отчёт: ' + (Join-Path $directory 'report.txt')) -ForegroundColor Cyan
    }
    } finally { $queueLock.Dispose() }
}

function Wait-VotQueueInterval {
    param([int]$Seconds = 10)
    $state = New-VotProgressState
    try {
        if (-not $state.Interactive) {
            Write-Host ('Пауза между роликами: ' + $Seconds + ' с — следующий запрос ещё не начат.')
            Start-Sleep -Seconds $Seconds
            return
        }
        for ($remaining = $Seconds; $remaining -gt 0; $remaining--) {
            $line = @{event='update';text=('Пауза между роликами: осталось ' + $remaining + ' с')} | ConvertTo-Json -Compress
            Write-VotProcessLine ('VOT_PROGRESS_JSON:' + $line) $state
            Start-Sleep -Seconds 1
        }
    } finally { Complete-VotProgressLine $state }
}

function New-VotProgressState {
    $width = 119
    try { $width = [Math]::Max(20, $Host.UI.RawUI.WindowSize.Width - 1) } catch { }
    return @{Active=$false; Width=0; MaxWidth=$width; Interactive=(-not [Console]::IsOutputRedirected); Output={param($Text) [Console]::Write($Text)}; Message={param($Text) Write-Host $Text}}
}

function Complete-VotProgressLine {
    param($State)
    if ($State.Active) { & $State.Output ([Environment]::NewLine); $State.Active=$false; $State.Width=0 }
}

function Write-VotProcessLine {
    param([string]$Line, $State)
    $prefix = 'VOT_PROGRESS_JSON:'
    if ($Line.StartsWith($prefix, [StringComparison]::Ordinal)) {
        try {
            $record = $Line.Substring($prefix.Length) | ConvertFrom-Json -ErrorAction Stop
            if ($record.event -notin @('update','finish','fail') -or $record.text -isnot [string]) { throw 'Invalid progress record' }
        } catch {
            Complete-VotProgressLine $State
            & $State.Message $Line
            return
        }
        $text = [regex]::Replace($record.text, '[\x00-\x1f\x7f]', '')
        if (-not $State.Interactive) { & $State.Message $text; return }
        if ($text.Length -gt $State.MaxWidth) {
            $head = [int][Math]::Floor(($State.MaxWidth - 1) / 2)
            $tail = $State.MaxWidth - $head - 1
            $text = $text.Substring(0,$head) + '…' + $text.Substring($text.Length-$tail)
        }
        & $State.Output ("`r" + $text.PadRight([Math]::Max($text.Length,$State.Width)))
        $State.Width=$text.Length; $State.Active=$true
        if ($record.event -ne 'update') { Complete-VotProgressLine $State }
        return
    }
    Complete-VotProgressLine $State
    & $State.Message $Line
}

function Invoke-VotQueueChild {
    param([array]$Arguments, [string]$LogPath, [string]$Voice, [scriptblock]$Process, [ValidateSet('gradual','preflight')][string]$RequestMode = 'preflight')
    $previousToken = $env:YANDEX_OAUTH_TOKEN
    $previousProgress = $env:VOT_PROGRESS_TRANSPORT
    $previousRequestMode = $env:VOT_REQUEST_MODE
    $previousQueueWorker = $env:VOT_QUEUE_WORKER
    $progressState = New-VotProgressState
    try {
        $env:VOT_PROGRESS_TRANSPORT = 'json'
        $env:VOT_REQUEST_MODE = $RequestMode
        $env:VOT_QUEUE_WORKER = '1'
        if ($Voice -eq 'live') {
            $token = Get-VotYandexToken
            if ($token) {
                $env:YANDEX_OAUTH_TOKEN = $token
                Write-Host 'Сохранённый вход Яндекса передан заданию очереди.'
            }
            $token = $null
        }
        if ($Process) { & $Process }
        else { & (Join-Path $PSHOME 'pwsh.exe') @Arguments 2>&1 | Tee-Object -FilePath $LogPath | ForEach-Object { Write-VotProcessLine ([string]$_) $progressState } }
    } finally {
        Complete-VotProgressLine $progressState
        if ($null -eq $previousToken) { Remove-Item -LiteralPath Env:YANDEX_OAUTH_TOKEN -ErrorAction SilentlyContinue }
        else { [Environment]::SetEnvironmentVariable('YANDEX_OAUTH_TOKEN', $previousToken, 'Process') }
        if ($null -eq $previousProgress) { Remove-Item -LiteralPath Env:VOT_PROGRESS_TRANSPORT -ErrorAction SilentlyContinue }
        else { [Environment]::SetEnvironmentVariable('VOT_PROGRESS_TRANSPORT', $previousProgress, 'Process') }
        if ($null -eq $previousRequestMode) { Remove-Item -LiteralPath Env:VOT_REQUEST_MODE -ErrorAction SilentlyContinue }
        else { [Environment]::SetEnvironmentVariable('VOT_REQUEST_MODE', $previousRequestMode, 'Process') }
        if ($null -eq $previousQueueWorker) { Remove-Item -LiteralPath Env:VOT_QUEUE_WORKER -ErrorAction SilentlyContinue }
        else { [Environment]::SetEnvironmentVariable('VOT_QUEUE_WORKER', $previousQueueWorker, 'Process') }
        $previousToken = $null; $token = $null
    }
}

function Resume-VotQueue {
    $files = @(Get-ChildItem -LiteralPath (Get-VotQueueRoot) -Filter queue.json -Recurse -File | Sort-Object LastWriteTime -Descending)
    if (-not $files.Count) { throw 'Сохранённых очередей пока нет.' }
    for ($i = 0; $i -lt $files.Count; $i++) {
        $info = Get-Content -LiteralPath $files[$i].FullName -Raw | ConvertFrom-Json
        Write-Host ([string]($i + 1) + ' — ' + (Split-Path $files[$i].DirectoryName -Leaf) + ' | ' + $info.state + ' | роликов: ' + @($info.items).Count)
    }
    $choice = Read-NumberedChoice 'Какую очередь продолжить' $files.Count 1
    $manifest = $files[$choice - 1].FullName
    $queue = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
    if ($queue.version -ne 1) { throw 'Не поддерживается версия очереди.' }
    foreach ($item in $queue.items) {
        $item.url = Get-CanonicalVideoUrl $item.url
        if ($item.status -eq 'excluded') { continue }
        if ($item.status -eq 'completed' -and $item.output -and (Test-Path -LiteralPath $item.output) -and (Get-Item -LiteralPath $item.output).Length -gt 0) { continue }
        $item.status = 'pending'; $item.output = ''; $item.error = ''
    }
    $pending = @($queue.items | Where-Object status -eq 'pending')
    if (-not $pending.Count) { Write-Host 'Все выбранные видео уже готовы.' -ForegroundColor Green; return }
    if (-not $queue.settings) { $queue.settings = Read-VotQueueSettings $pending }
    $answer = Read-Host ('Продолжить ' + $pending.Count + ' незавершённых / неудачных заданий? Enter — да; 0 — отмена')
    if ($answer -eq '0') { return }
    Invoke-VotQueue $queue $manifest
}
