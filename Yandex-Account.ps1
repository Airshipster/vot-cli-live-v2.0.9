param(
    [switch]$Login,
    [switch]$Status,
    [switch]$Forget,
    [switch]$ImportClipboard,
    [string]$CallbackState,
    [string]$AuthNodeExe,
    [string]$AccountRoot
)

function Get-VotAccountPath {
    param([string]$Root)
    if (-not $Root) { $Root = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.vot-cli-live' }
    return Join-Path $Root 'yandex-account.dpapi.json'
}

function Get-VotLegacyAccountPath {
    return Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'VOT-CLI-Live\yandex-account.dpapi.json'
}

function Get-VotYandexToken {
    param([string]$Root)
    $path = Get-VotAccountPath $Root
    $sourcePath = $path
    if (-not (Test-Path -LiteralPath $path)) {
        if ($Root -or (Test-Path -LiteralPath (Join-Path (Split-Path $path -Parent) 'yandex-account.logout'))) { return $null }
        $sourcePath = Get-VotLegacyAccountPath
        if (-not (Test-Path -LiteralPath $sourcePath)) { return $null }
    }
    try {
        $account = Get-Content -LiteralPath $sourcePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ([double]$account.expiresAt -le [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() + 60000) { return $null }
        $secure = ConvertTo-SecureString ([string]$account.protectedToken) -ErrorAction Stop
    } catch { throw 'Сохранённый вход найден, но прочитать его не удалось. Запустите VOT под тем пользователем Windows, который выполнил вход. Сохранённые данные не изменены.' }
    try {
        if ($sourcePath -ne $path) {
            try {
                New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null
                [IO.File]::Move($sourcePath, $path)
            } catch { throw 'Не удалось перенести зашифрованный вход в общее хранилище. Повторная авторизация не требуется; исходный файл не перезаписывался.' }
        }
        $buffer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($buffer) }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($buffer) }
    } finally { $secure.Dispose() }
}

function Save-VotYandexToken {
    param([string]$Token, [double]$ExpiresAt, [string]$Root)
    if ($Token.Length -lt 20 -or $ExpiresAt -le [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) { throw 'Яндекс не выдал действующий доступ.' }
    $path = Get-VotAccountPath $Root
    $secure = ConvertTo-SecureString $Token -AsPlainText -Force
    try { $protected = ConvertFrom-SecureString $secure }
    finally { $secure.Dispose() }
    New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null
    $temporary = $path + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [pscustomobject]@{version=1; expiresAt=$ExpiresAt; protectedToken=$protected} |
            ConvertTo-Json -Compress | Set-Content -LiteralPath $temporary -Encoding UTF8
        Move-Item -LiteralPath $temporary -Destination $path -Force
        if (-not $Root) {
            $logoutMarker = Join-Path (Split-Path $path -Parent) 'yandex-account.logout'
            if (Test-Path -LiteralPath $logoutMarker) { Remove-Item -LiteralPath $logoutMarker -Force }
        }
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}

function Connect-VotYandex {
    param([string]$NodePath, [string]$Root)
    $existingToken = Get-VotYandexToken $Root
    if ($existingToken) {
        Write-Host 'Вход в Яндекс уже сохранён. Повторная авторизация не нужна.' -ForegroundColor Green
        return $existingToken
    }
    if (-not $NodePath) { $NodePath = $env:VOT_NODE_EXE }
    if (-not $NodePath) { $NodePath = (Get-Command node.exe -ErrorAction Stop).Source }
    $helper = Join-Path $PSScriptRoot 'app\src\yandexLogin.js'
    if (-not (Test-Path -LiteralPath $helper)) { $helper = Join-Path $PSScriptRoot 'src\yandexLogin.js' }
    Write-Host 'Откроется обычная вкладка вашего Chrome с текущей сессией Яндекса.' -ForegroundColor Cyan
    Write-Host 'В Яндексе приложение называется «Text To Morse» — этот вход использует исходное расширение VOT. Запрашиваются имя и аватар.'
    Write-Host 'У сервиса есть собственный интерфейс азбуки Морзе. Он не участвует в переводе видео.'
    Write-Host 'Дополнительные расширения не нужны. Результат входа передаётся программе через локальную страницу.' -ForegroundColor Yellow
    Write-Host 'Если вы уже вошли в Яндекс, повторный пароль обычно не потребуется. Нажмите «Продолжить вход Яндекса».'
    Write-Host 'После входа доступ будет сохранён в зашифрованном виде для текущего пользователя Windows.'
    $previousParent = $env:VOT_AUTH_PARENT_PID
    try {
        $env:VOT_AUTH_PARENT_PID = [string]$PID
        $response = & $NodePath $helper
    } finally { [Environment]::SetEnvironmentVariable('VOT_AUTH_PARENT_PID', $previousParent, 'Process') }
    if ($LASTEXITCODE -ne 0 -or -not $response) {
        $importedToken = Get-VotYandexToken $Root
        if ($importedToken) {
            Write-Host 'Вход в Яндекс уже сохранён локально.' -ForegroundColor Green
            return $importedToken
        }
        throw 'Вход в Яндекс не завершён. Выбранная озвучка не заменена другой.'
    }
    try {
        $account = ($response -join [Environment]::NewLine) | ConvertFrom-Json
        Save-VotYandexToken ([string]$account.token) ([double]$account.expiresAt) $Root
        Write-Host 'Вход в Яндекс сохранён. Повторно входить перед каждым видео не нужно.' -ForegroundColor Green
        return [string]$account.token
    } catch { throw 'Не удалось сохранить вход Яндекса. Откройте «Локальное видео → Аккаунт Яндекса».' }
    finally { $response = $null; $account = $null }
}

function Disconnect-VotYandex {
    param([string]$Root)
    $path = Get-VotAccountPath $Root
    if (-not $Root) {
        New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null
        Set-Content -LiteralPath (Join-Path (Split-Path $path -Parent) 'yandex-account.logout') -Value '1' -Encoding ASCII
        $legacyPath = Get-VotLegacyAccountPath
        if (Test-Path -LiteralPath $legacyPath) { Remove-Item -LiteralPath $legacyPath -Force }
    }
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    Write-Host 'Сохранённый вход удалён с этого компьютера.'
}

function Import-VotYandexClipboard {
    param([string]$ExpectedState, [string]$Root)
    $clearOwnClipboard = $false
    $clipboardValue = $null
    try {
        if ($ExpectedState -notmatch '^vot-cli\.\d{1,5}\.[a-f0-9]{64}$') { throw 'Invalid request state' }
        $clipboardValue = Get-Clipboard -Raw
        if (-not $clipboardValue -or $clipboardValue.Length -gt 16384) { throw 'Invalid clipboard response' }
        $uri = [Uri]::new($clipboardValue.Trim())
        if ($uri.Scheme -ne 'https' -or $uri.Host -ne 'rust-server-531j.onrender.com' -or -not $uri.IsDefaultPort -or $uri.UserInfo -or $uri.AbsolutePath -ne '/auth/callback') { throw 'Invalid callback' }
        $parameters = [Web.HttpUtility]::ParseQueryString($uri.Fragment.TrimStart('#'))
        $state = $parameters['state']
        if (-not $state) { $state = ([Web.HttpUtility]::ParseQueryString($uri.Query.TrimStart('?')))['state'] }
        if ($state -ne $ExpectedState -or $parameters['error']) { throw 'Invalid response state' }
        $token = [string]$parameters['access_token']
        $expires = 0.0
        if ($token -notmatch '^[A-Za-z0-9._~-]{20,8192}$' -or -not [double]::TryParse($parameters['expires_in'], [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$expires) -or $expires -le 0 -or $expires -gt 316224000) { throw 'Invalid credentials' }
        $clearOwnClipboard = $true
        Save-VotYandexToken $token ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() + $expires * 1000) $Root
        Write-Host 'Вход Яндекса из основного Chrome сохранён локально.' -ForegroundColor Green
    } catch { throw 'Не удалось принять результат текущего входа из буфера. Значение не выводилось и не записывалось в журнал.' }
    finally {
        if ($clearOwnClipboard -and (Get-Clipboard -Raw) -ceq $clipboardValue) { Set-Clipboard -Value '' }
        $token = $null; $parameters = $null; $uri = $null; $clipboardValue = $null
    }
}

if ($ImportClipboard) { Import-VotYandexClipboard $CallbackState $AccountRoot }
elseif ($Login) { Connect-VotYandex $AuthNodeExe $AccountRoot | Out-Null }
elseif ($Forget) { Disconnect-VotYandex $AccountRoot }
elseif ($Status) {
    $available = -not [string]::IsNullOrWhiteSpace((Get-VotYandexToken $AccountRoot))
    if ($available) { Write-Host 'Вход в Яндекс сохранён.' } else { Write-Host 'Сохранённого действующего входа нет.' }
}
