param()
$ErrorActionPreference = 'Stop'
$launcher = Join-Path $PSScriptRoot 'Start-VOT.cmd'
if (-not (Test-Path -LiteralPath $launcher)) { throw 'Рядом со скриптом не найден Start-VOT.cmd.' }
$desktop = [Environment]::GetFolderPath('Desktop')
$shell = New-Object -ComObject WScript.Shell
$title = 'VOT — Нейроперевод'
$number = 1
do {
    $name = if ($number -eq 1) { $title + '.lnk' } else { $title + ' (' + $number + ').lnk' }
    $path = Join-Path $desktop $name
    if (-not (Test-Path -LiteralPath $path)) { break }
    $existing = $shell.CreateShortcut($path)
    if ($existing.TargetPath -eq $launcher) { break }
    $number++
} while ($true)
$shortcut = $shell.CreateShortcut($path)
$shortcut.TargetPath = $launcher
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.Description = 'Скачать видео с нейропереводом'
$shortcut.WindowStyle = 1
$pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue | Select-Object -First 1
$icon = if ($pwsh) { $pwsh.Source } else { Join-Path ([Environment]::GetFolderPath('System')) 'WindowsPowerShell\v1.0\powershell.exe' }
$shortcut.IconLocation = $icon + ',0'
$shortcut.Save()
$verified = $shell.CreateShortcut($path)
if ($verified.TargetPath -ne $launcher -or $verified.WorkingDirectory -ne $PSScriptRoot) { throw 'Ярлык не прошёл проверку.' }
Write-Host ('Ярлык создан: ' + $path)
