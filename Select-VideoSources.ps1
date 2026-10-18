param([switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
Add-Type -AssemblyName System.Windows.Forms
[Windows.Forms.Application]::EnableVisualStyles()
$form = [Windows.Forms.Form]::new()
try {
    $form.Text = 'VOT — список ссылок на видео'
    $form.Size = [Drawing.Size]::new(760,520)
    $form.MinimumSize = [Drawing.Size]::new(520,360)
    $form.StartPosition = 'CenterScreen'
    $label = [Windows.Forms.Label]::new()
    $label.Text = 'Вставьте ссылки из текста, таблицы или списка. Повторы будут убраны. Каналы и плейлисты будут раскрыты.'
    $label.Dock = 'Top'; $label.Height = 48; $label.Padding = [Windows.Forms.Padding]::new(10)
    $inputBox = [Windows.Forms.TextBox]::new()
    $inputBox.Multiline = $true; $inputBox.AcceptsReturn = $true
    $inputBox.ScrollBars = 'Both'; $inputBox.WordWrap = $false; $inputBox.Dock = 'Fill'
    $buttons = [Windows.Forms.FlowLayoutPanel]::new()
    $buttons.Dock = 'Bottom'; $buttons.Height = 46; $buttons.FlowDirection = 'RightToLeft'
    $cancel = [Windows.Forms.Button]::new()
    $cancel.Text = 'Отмена'; $cancel.DialogResult = 'Cancel'; $cancel.Width = 110
    $ok = [Windows.Forms.Button]::new()
    $ok.Text = 'Продолжить'; $ok.DialogResult = 'OK'; $ok.Width = 130
    $load = [Windows.Forms.Button]::new()
    $load.Text = 'Из файла…'; $load.Width = 130
    $load.Add_Click({
        $dialog = [Windows.Forms.OpenFileDialog]::new()
        try {
            $dialog.Filter = 'Списки ссылок|*.txt;*.csv;*.json;*.md|Все файлы|*.*'
            if ($dialog.ShowDialog() -eq 'OK') { $inputBox.Text = [IO.File]::ReadAllText($dialog.FileName) }
        } catch { [Windows.Forms.MessageBox]::Show('Не удалось прочитать файл.', 'VOT') | Out-Null }
        finally { $dialog.Dispose() }
    })
    $buttons.Controls.AddRange(@($cancel,$ok,$load))
    $form.Controls.Add($inputBox); $form.Controls.Add($label); $form.Controls.Add($buttons)
    $form.CancelButton = $cancel
    if ($CheckOnly) { Write-Output 'Link list picker ready'; exit 0 }
    if ($form.ShowDialog() -eq 'OK') { ConvertTo-Json -InputObject $inputBox.Text -Compress }
} finally { $form.Dispose() }
