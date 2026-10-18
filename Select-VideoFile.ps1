param([switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
Add-Type -AssemblyName System.Windows.Forms
[Windows.Forms.Application]::EnableVisualStyles()
$dialog = [Windows.Forms.OpenFileDialog]::new()
try {
    $dialog.Title = 'Выберите видео для перевода'
    $dialog.Filter = 'Видеофайлы|*.mp4;*.mkv;*.mov;*.webm;*.avi;*.m4v;*.wmv;*.ts;*.mts|Все файлы|*.*'
    $dialog.CheckFileExists = $true
    $dialog.Multiselect = $false
    $dialog.RestoreDirectory = $true
    $dialog.InitialDirectory = [Environment]::GetFolderPath('MyVideos')
    if ($CheckOnly) { Write-Output 'File picker ready'; exit 0 }
    if ($dialog.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) { Write-Output $dialog.FileName }
} finally { $dialog.Dispose() }
