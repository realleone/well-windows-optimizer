$script:Items = @()
$script:BootSec = $null

$form = New-Object Windows.Forms.Form
$form.Text = 'WinOpt Suite - Başlangıç Uygulamaları Yöneticisi | Developed by Leone'
$form.Size = New-Object Drawing.Size(1250, 650)
$form.StartPosition = 'CenterScreen'

$tabs = New-Object Windows.Forms.TabControl
$tabs.Dock = 'Fill'
$form.Controls.Add($tabs)
$tabStartup = New-Object Windows.Forms.TabPage
$tabStartup.Text = 'Başlangıç'
[void]$tabs.TabPages.Add($tabStartup)

$grid = New-Object Windows.Forms.DataGridView
$grid.Dock = 'Fill'; $grid.ReadOnly = $true; $grid.AllowUserToAddRows = $false
$grid.SelectionMode = 'FullRowSelect'; $grid.MultiSelect = $true; $grid.RowHeadersVisible = $false
$grid.AutoSizeColumnsMode = 'None'; $grid.BackgroundColor = [Drawing.Color]::White
foreach ($c in @(@('Durum',80), @('Ad',200), @('Kaynak',190), @('Yayıncı',160), @('Dosya yolu',300), @('Başlatma etkisi',110), @('Not',120), @('Komut',400))) {
    $col = New-Object Windows.Forms.DataGridViewTextBoxColumn
    $col.HeaderText = $c[0]; $col.Width = $c[1]; $col.SortMode = 'Automatic'
    [void]$grid.Columns.Add($col)
}
$tabStartup.Controls.Add($grid)

$bar = New-Object Windows.Forms.FlowLayoutPanel
$bar.Dock = 'Top'; $bar.Height = 46; $bar.Padding = New-Object Windows.Forms.Padding(6)
$tabStartup.Controls.Add($bar)

$statusStrip = New-Object Windows.Forms.StatusStrip
$status = New-Object Windows.Forms.ToolStripStatusLabel
[void]$statusStrip.Items.Add($status)
$tabStartup.Controls.Add($statusStrip)

function Add-Button([string]$text, [int]$w, [scriptblock]$handler) {
    $b = New-Object Windows.Forms.Button
    $b.Text = $text; $b.Width = $w; $b.Height = 30
    $b.Add_Click($handler)
    $bar.Controls.Add($b)
}

function Get-Selected { @($grid.SelectedRows | ForEach-Object { $_.Tag } | Where-Object { $_ }) }

function Save-Snapshot { ($script:Items | ForEach-Object { $_.Key }) | ConvertTo-Json | Set-Content -LiteralPath $SnapFile -Encoding UTF8 }

function Update-List {
    $form.Cursor = 'WaitCursor'; $status.Text = 'Taranıyor...'; $form.Refresh()
    try {
        $items = @(Get-RegistryEntries) + @(Get-FolderEntries) + @(Get-TaskEntries)

        $imp = Get-StartupImpact
        $script:BootSec = $imp.Boot
        foreach ($it in $items) {
            if ($it.Path) {
                $k = ([IO.Path]::GetFileName($it.Path)).ToLower()
                if ($imp.Map.ContainsKey($k)) { $it.Impact = "{0} sn gecikme" -f $imp.Map[$k] }
            }
        }

        $script:Items = $items
        if (Test-Path -LiteralPath $SnapFile) {
            $knownRaw = Get-Content -LiteralPath $SnapFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $known = @($knownRaw | ForEach-Object { $_ })
            foreach ($it in $items) { if ($known -notcontains $it.Key) { $it.IsNew = $true } }
        } else {
            Save-Snapshot
        }

        $grid.Rows.Clear()
        foreach ($it in ($items | Sort-Object @{e={$_.Enabled};Descending=$true}, Name)) {
            $notes = @()
            if ($it.IsNew) { $notes += 'YENİ' }
            if ($it.Protected) { $notes += 'Korumalı' }
            if ($it.Type -eq 'Registry' -and -not $it.Extra.Manageable) { $notes += 'Yalnızca izleme' }
            $durum = if ($it.Enabled) { 'Etkin' } else { 'Devre dışı' }
            $i = $grid.Rows.Add($durum, $it.Name, $it.Source, $it.Publisher, $it.Path, $it.Impact, ($notes -join ', '), $it.Command)
            $row = $grid.Rows[$i]; $row.Tag = $it
            if (-not $it.Enabled) { $row.DefaultCellStyle.ForeColor = [Drawing.Color]::Gray }
            if ($it.Protected)    { $row.DefaultCellStyle.BackColor = [Drawing.Color]::Gainsboro }
            if ($it.IsNew)        { $row.DefaultCellStyle.BackColor = [Drawing.Color]::LightYellow }
        }
        $en = @($items | Where-Object { $_.Enabled }).Count
        $new = @($items | Where-Object { $_.IsNew }).Count
        $bootText = if ($script:BootSec) { "Son açılış süresi: $($script:BootSec) sn" } else { 'Açılış süresi: ölçüm yok' }
        $status.Text = "Toplam: $($items.Count)  |  Etkin: $en  |  Devre dışı: $($items.Count - $en)  |  Yeni: $new  |  $bootText"
    } catch {
        $status.Text = 'Hata: ' + $_.Exception.Message
        Write-Log ("Tarama hatası: " + $_.Exception.Message)
    } finally { $form.Cursor = 'Default' }
}

function Set-StartupState([bool]$enable) {
    $sel = Get-Selected
    if ($sel.Count -eq 0) { [L10nMsg]::Show('Önce listeden bir veya daha fazla öğe seçin.', 'WinOpt Suite - Developed by Leone') | Out-Null; return }
    $ok = 0; $skipped = @(); $failed = @()
    foreach ($it in $sel) {
        if ($it.Protected -and -not $enable) { $skipped += "$($it.Name) (korumalı Windows/güvenlik bileşeni)"; continue }
        if ($it.Type -eq 'Registry' -and -not $it.Extra.Manageable) { $skipped += "$($it.Name) (RunOnce: yalnızca izlenir)"; continue }
        if ($it.Enabled -eq $enable) { continue }
        try {
            if ($it.Type -eq 'Görev') {
                if ($enable) { Enable-ScheduledTask -TaskName $it.Extra.TaskName -TaskPath $it.Extra.TaskPath -ErrorAction Stop | Out-Null }
                else { Disable-ScheduledTask -TaskName $it.Extra.TaskName -TaskPath $it.Extra.TaskPath -ErrorAction Stop | Out-Null }
            } else {
                Set-ApprovedState $it.Extra.Hive $it.Extra.Approved $it.Extra.ValueName $enable
            }
            Write-Log ("{0}: {1} [{2}]" -f ($(if ($enable) { 'ETKİNLEŞTİRİLDİ' } else { 'DEVRE DIŞI' })), $it.Name, $it.Source)
            $ok++
        } catch {
            $failed += "$($it.Name): $($_.Exception.Message)"
            Write-Log ("HATA {0}: {1}" -f $it.Name, $_.Exception.Message)
        }
    }
    Update-List
    $msg = "$ok öğe güncellendi."
    if ($skipped.Count) { $msg += "`n`nAtlananlar:`n" + ($skipped -join "`n") }
    if ($failed.Count)  { $msg += "`n`nBaşarısız:`n" + ($failed -join "`n") }
    [L10nMsg]::Show($msg, 'WinOpt Suite - Developed by Leone') | Out-Null
}

Add-Button 'Yenile' 80 { Update-List }
Add-Button 'Devre Dışı Bırak' 130 { Set-StartupState $false }
Add-Button 'Yeniden Etkinleştir' 140 { Set-StartupState $true }
Add-Button 'Dosya Konumunu Aç' 140 {
    foreach ($it in (Get-Selected | Select-Object -First 1)) {
        if ($it.Path -and (Test-Path -LiteralPath $it.Path)) { Start-Process explorer.exe -ArgumentList "/select,`"$($it.Path)`"" }
        else { [L10nMsg]::Show('Dosya bulunamadı.', 'WinOpt Suite - Developed by Leone') | Out-Null }
    }
}
Add-Button 'Yeni Girdileri Onayla' 150 { Save-Snapshot; Write-Log 'Yeni girdiler bilinen olarak işaretlendi'; Update-List }
Add-Button 'CSV Raporu' 90 {
    $dlg = New-Object Windows.Forms.SaveFileDialog
    $dlg.Filter = 'CSV (*.csv)|*.csv'; $dlg.FileName = 'baslangic-raporu.csv'
    if ($dlg.ShowDialog() -eq 'OK') {
        $script:Items | Select-Object Name, Source, Publisher, Path, Command, Enabled, Protected, IsNew, Impact |
            Export-Csv -LiteralPath $dlg.FileName -NoTypeInformation -Encoding UTF8
        Write-Log "Rapor dışa aktarıldı: $($dlg.FileName)"
    }
}
Add-Button 'Günlüğü Aç' 100 { if (Test-Path -LiteralPath $LogFile) { Start-Process notepad.exe $LogFile } else { [L10nMsg]::Show('Henüz işlem günlüğü yok.', 'WinOpt Suite - Developed by Leone') | Out-Null } }

$form.Add_Shown({ Update-List })
