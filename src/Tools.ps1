$tabTools = New-Object Windows.Forms.TabPage
$tabTools.Text = 'Araçlar'
[void]$tabs.TabPages.Add($tabTools)

$tabQuick = New-Object Windows.Forms.TabPage
$tabQuick.Text = 'Hızlı Mod'
[void]$tabs.TabPages.Add($tabQuick)

$script:ToolsApps = @()
$script:ToolsLoaded = $false

$gridTools = New-StdGrid @(@('Program', 300), @('Yayıncı', 200), @('Sürüm', 110), @('Boyut (MB)', 90), @('Kurulum tarihi', 110), @('Kapsam', 170))
$gridTools.Columns[3].DefaultCellStyle.Format = 'N0'
$tabTools.Controls.Add($gridTools)

$txtToolsDrives = New-Object Windows.Forms.TextBox
$txtToolsDrives.Multiline = $true; $txtToolsDrives.ReadOnly = $true; $txtToolsDrives.ScrollBars = 'Vertical'
$txtToolsDrives.Dock = 'Bottom'; $txtToolsDrives.Height = 80; $txtToolsDrives.BackColor = [Drawing.Color]::White
$tabTools.Controls.Add($txtToolsDrives)

$lblTools = New-StatusLabel
$tabTools.Controls.Add($lblTools)

$barTools = New-Bar
$barTools.Height = 112
$tabTools.Controls.Add($barTools)

function Confirm-Tool([string]$msg) {
    return ([L10nMsg]::Show($msg, 'WinOpt Suite - Developed by Leone', 'YesNo', 'Question') -eq 'Yes')
}

function Get-DriveSummaryText {
    $l = @()
    foreach ($d in [IO.DriveInfo]::GetDrives()) {
        try {
            if ($d.DriveType -ne 'Fixed' -or -not $d.IsReady) { continue }
            $used = $d.TotalSize - $d.AvailableFreeSpace
            $l += ('{0}  toplam {1}  |  kullanılan {2} (%{3:N0})  |  boş {4}' -f $d.Name, (Format-Bytes $d.TotalSize), (Format-Bytes $used), ($used / $d.TotalSize * 100), (Format-Bytes $d.AvailableFreeSpace))
        } catch {}
    }
    if ($l.Count -eq 0) { return 'Sürücü bilgisi okunamadı.' }
    return ($l -join [Environment]::NewLine)
}

function Get-InstalledPrograms {
    $roots = @(
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'; Scope = 'Tüm kullanıcılar' },
        @{ Path = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'; Scope = 'Tüm kullanıcılar (32 bit)' },
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'; Scope = 'Geçerli kullanıcı' }
    )
    $seen = @{}; $out = New-Object System.Collections.ArrayList
    foreach ($r in $roots) {
        if (-not (Test-Path -LiteralPath $r.Path)) { continue }
        foreach ($k in @(Get-ChildItem -LiteralPath $r.Path -ErrorAction SilentlyContinue)) {
            try {
                $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction Stop
                $name = [string]$p.DisplayName
                if ([string]::IsNullOrWhiteSpace($name)) { continue }
                if ($p.SystemComponent -eq 1) { continue }
                if ($p.ParentKeyName -or $p.ParentDisplayName) { continue }
                if ($name -match '^(KB\d{6,}|Security Update|Update for )') { continue }
                $ver = [string]$p.DisplayVersion
                $dk = ($name + '|' + $ver).ToLower()
                if ($seen.ContainsKey($dk)) { continue }
                $seen[$dk] = $true
                $sizeMB = $null
                if ($p.EstimatedSize) { try { $sizeMB = [math]::Round(([double]$p.EstimatedSize) / 1024, 1) } catch {} }
                $date = ''
                $rawDate = [string]$p.InstallDate
                if ($rawDate -match '^(\d{4})(\d{2})(\d{2})$') { $date = "$($Matches[3]).$($Matches[2]).$($Matches[1])" }
                [void]$out.Add([pscustomobject]@{
                    Name = $name; Publisher = ([string]$p.Publisher).Trim(); Version = $ver; SizeMB = $sizeMB
                    Date = $date; Scope = $r.Scope; Uninstall = [string]$p.UninstallString
                })
            } catch {}
        }
    }
    return @($out | Sort-Object Name)
}

function Show-ToolsGrid {
    $q = $txtToolsFilter.Text.Trim()
    $gridTools.Rows.Clear()
    $n = 0
    foreach ($it in $script:ToolsApps) {
        if ($q -and ($it.Name.IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -lt 0) -and ($it.Publisher.IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -lt 0)) { continue }
        $i = $gridTools.Rows.Add([object[]]@($it.Name, $it.Publisher, $it.Version, $it.SizeMB, $it.Date, $it.Scope))
        $gridTools.Rows[$i].Tag = $it
        $n++
    }
    $lblTools.Text = "  Kurulu program: $($script:ToolsApps.Count)  |  Gösterilen: $n  |  'Kaldır' programın kendi kaldırıcısını açar; WinOpt dosya silmez. Boyut, programın bildirdiği tahmini değerdir."
}

function Update-Tools {
    $form.Cursor = 'WaitCursor'
    try {
        $script:ToolsApps = @(Get-InstalledPrograms)
        $txtToolsDrives.Text = Get-DriveSummaryText
        $script:ToolsLoaded = $true
        Show-ToolsGrid
    } catch {
        $lblTools.Text = '  Hata: ' + $_.Exception.Message
        Write-Log ('Araçlar listeleme hatası: ' + $_.Exception.Message)
    } finally { $form.Cursor = 'Default' }
}

function New-WinOptRestorePoint {
    if (-not (Confirm-Tool "Bir sistem geri yükleme noktası oluşturulacak. Birkaç saniye sürebilir.`n`nNot: Windows varsayılan olarak 24 saatte en fazla bir nokta oluşturur ve Sistem Korumasının açık olması gerekir.`n`nDevam edilsin mi?")) { return }
    $form.Cursor = 'WaitCursor'
    try {
        $w = $null
        Checkpoint-Computer -Description ('WinOpt Suite ' + (Get-Date -Format 'yyyy-MM-dd HH:mm')) -RestorePointType 'MODIFY_SETTINGS' -WarningVariable w -WarningAction SilentlyContinue -ErrorAction Stop
        if ($w -and @($w).Count -gt 0) {
            $msg = (@($w) | ForEach-Object { $_.ToString() }) -join "`n"
            Write-Log ('Geri yükleme noktası uyarısı: ' + $msg)
            [L10nMsg]::Show("Windows bir uyarı verdi, nokta oluşmamış olabilir:`n`n$msg", 'WinOpt Suite - Developed by Leone') | Out-Null
        } else {
            Write-Log 'Geri yükleme noktası oluşturuldu'
            [L10nMsg]::Show("Komut hatasız tamamlandı. Noktayı 'Geri Yükleme Noktaları' düğmesiyle listede görebilirsiniz.", 'WinOpt Suite - Developed by Leone') | Out-Null
        }
    } catch {
        Write-Log ('Geri yükleme noktası hatası: ' + $_.Exception.Message)
        [L10nMsg]::Show("Geri yükleme noktası oluşturulamadı:`n`n$($_.Exception.Message)`n`nSistem Koruması kapalı olabilir (Sistem Özellikleri > Sistem Koruması).", 'WinOpt Suite - Developed by Leone') | Out-Null
    } finally { $form.Cursor = 'Default' }
}

function Show-RestorePoints {
    $form.Cursor = 'WaitCursor'
    try {
        $pts = @(Get-ComputerRestorePoint -ErrorAction Stop | Sort-Object SequenceNumber -Descending | Select-Object -First 20)
        if ($pts.Count -eq 0) { [L10nMsg]::Show('Kayıtlı geri yükleme noktası bulunamadı (Sistem Koruması kapalı olabilir).', 'WinOpt Suite - Developed by Leone') | Out-Null; return }
        $lines = foreach ($p in $pts) {
            $t = ''
            try { $t = [Management.ManagementDateTimeConverter]::ToDateTime($p.CreationTime).ToString('yyyy-MM-dd HH:mm') } catch {}
            ('{0}   #{1}   {2}' -f $t, $p.SequenceNumber, $p.Description)
        }
        Show-TextDialog 'Geri Yükleme Noktaları (son 20)' ($lines -join [Environment]::NewLine)
    } catch {
        [L10nMsg]::Show("Liste okunamadı: $($_.Exception.Message)", 'WinOpt Suite - Developed by Leone') | Out-Null
    } finally { $form.Cursor = 'Default' }
}

function Start-ConsoleTool([string]$title, [string]$cmdLine, [string]$info) {
    if (-not (Confirm-Tool $info)) { return }
    try {
        Start-Process -FilePath 'cmd.exe' -ArgumentList ('/k title ' + $title + ' & ' + $cmdLine)
        Write-Log ('Araç başlatıldı: ' + $cmdLine)
    } catch {
        Write-Log ('Araç başlatılamadı: ' + $cmdLine + ' - ' + $_.Exception.Message)
        [L10nMsg]::Show("Başlatılamadı: $($_.Exception.Message)", 'WinOpt Suite - Developed by Leone') | Out-Null
    }
}

function Invoke-UninstallSelected {
    $row = $gridTools.SelectedRows | Select-Object -First 1
    if (-not $row -or -not $row.Tag) { [L10nMsg]::Show('Önce listeden bir program seçin.', 'WinOpt Suite - Developed by Leone') | Out-Null; return }
    $it = $row.Tag
    if ([string]::IsNullOrWhiteSpace($it.Uninstall)) { [L10nMsg]::Show('Bu program kaldırma komutu bildirmemiş. Windows Ayarları > Uygulamalar bölümünü kullanın.', 'WinOpt Suite - Developed by Leone') | Out-Null; return }
    if (-not (Confirm-Tool "'$($it.Name)' için programın kendi kaldırıcısı açılacak. Kaldırma işlemi o programın penceresinden onaylanır.`n`nDevam edilsin mi?")) { return }
    try {
        Start-Process -FilePath 'cmd.exe' -ArgumentList ('/c "' + $it.Uninstall + '"') -WindowStyle Hidden
        Write-Log ('Kaldırıcı açıldı: ' + $it.Name)
    } catch {
        Write-Log ('Kaldırıcı açılamadı: ' + $it.Name + ' - ' + $_.Exception.Message)
        [L10nMsg]::Show("Açılamadı: $($_.Exception.Message)", 'WinOpt Suite - Developed by Leone') | Out-Null
    }
}

New-Btn $barTools 'Geri Yükleme Noktası Oluştur' 200 { New-WinOptRestorePoint }
New-Btn $barTools 'Geri Yükleme Noktaları' 160 { Show-RestorePoints }
New-Btn $barTools 'DNS Önbelleğini Temizle' 170 {
    try {
        $o = (& ipconfig.exe /flushdns 2>&1 | Out-String).Trim()
        Write-Log 'DNS önbelleği temizlendi'
        [L10nMsg]::Show($o, 'WinOpt Suite - Developed by Leone') | Out-Null
    } catch { [L10nMsg]::Show("Başarısız: $($_.Exception.Message)", 'WinOpt Suite - Developed by Leone') | Out-Null }
}
New-Btn $barTools 'Geri Dönüşüm Kutusunu Boşalt' 200 {
    if (-not (Confirm-Tool 'Tüm sürücülerdeki Geri Dönüşüm Kutusu kalıcı olarak boşaltılacak. Bu işlem geri alınamaz.' )) { return }
    try {
        Clear-RecycleBin -Force -ErrorAction Stop
        Write-Log 'Geri Dönüşüm Kutusu boşaltıldı'
        $txtToolsDrives.Text = Get-DriveSummaryText
        [L10nMsg]::Show('Geri Dönüşüm Kutusu boşaltıldı.', 'WinOpt Suite - Developed by Leone') | Out-Null
    } catch { [L10nMsg]::Show("Başarısız (kutu zaten boş olabilir): $($_.Exception.Message)", 'WinOpt Suite - Developed by Leone') | Out-Null }
}
New-Btn $barTools 'SFC Taraması' 110 { Start-ConsoleTool 'SFC' 'sfc /scannow' "Windows sistem dosyaları denetlenecek (sfc /scannow). Yaklaşık 5-20 dakika sürebilir; sonuç açılan konsol penceresinde görünür.`n`nBaşlatılsın mı?" }
New-Btn $barTools 'DISM Onarım' 110 { Start-ConsoleTool 'DISM' 'DISM /Online /Cleanup-Image /RestoreHealth' "Windows bileşen deposu onarılacak (DISM RestoreHealth). Internet bağlantısı gerekebilir, 10-30 dakika sürebilir.`n`nBaşlatılsın mı?" }
New-Btn $barTools 'Disk Denetimi (salt okunur)' 190 { Start-ConsoleTool 'CHKDSK' 'chkdsk %SystemDrive%' "Sistem sürücüsü yalnızca okuma modunda denetlenecek (hiçbir şey onarılmaz). Sonuç konsol penceresinde görünür.`n`nBaşlatılsın mı?" }
New-Btn $barTools 'Programları Yenile' 140 { Update-Tools }
New-Btn $barTools 'Seçili Programı Kaldır' 170 { Invoke-UninstallSelected }
New-Btn $barTools 'CSV Raporu' 100 {
    if (-not $script:ToolsLoaded) { Update-Tools }
    $dlg = New-Object Windows.Forms.SaveFileDialog
    $dlg.Filter = 'CSV (*.csv)|*.csv'; $dlg.FileName = 'kurulu-programlar.csv'
    if ($dlg.ShowDialog() -eq 'OK') {
        $script:ToolsApps | Select-Object Name, Publisher, Version, SizeMB, Date, Scope |
            Export-Csv -LiteralPath $dlg.FileName -NoTypeInformation -Encoding UTF8
        Write-Log "Program listesi dışa aktarıldı: $($dlg.FileName)"
    }
}

$lblFilter = New-Object Windows.Forms.Label
$lblFilter.Text = 'Ara:'; $lblFilter.AutoSize = $true; $lblFilter.Margin = New-Object Windows.Forms.Padding(14, 9, 2, 0)
$barTools.Controls.Add($lblFilter)
$txtToolsFilter = New-Object Windows.Forms.TextBox
$txtToolsFilter.Width = 200; $txtToolsFilter.Margin = New-Object Windows.Forms.Padding(2, 6, 2, 0)
$txtToolsFilter.Add_TextChanged({ if ($script:ToolsLoaded) { Show-ToolsGrid } })
$barTools.Controls.Add($txtToolsFilter)

$tabs.Add_SelectedIndexChanged({
    if ([object]::ReferenceEquals($tabs.SelectedTab, $tabTools) -and -not $script:ToolsLoaded) { try { Update-Tools } catch {} }
})
