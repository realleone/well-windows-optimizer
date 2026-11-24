$CleanHistFile = Join-Path $AppDir 'temizlik-gecmisi.csv'
$script:ClResults  = @()
$script:ClBusy     = $false
$script:ClLoading  = $false
$script:ClScanTime = $null

$tabClean = New-Object Windows.Forms.TabPage
$tabClean.Text = 'Derin Temizlik'
[void]$tabs.TabPages.Add($tabClean)

$gridCl = New-StdGrid @(@('Seç', 45), @('Kategori', 240), @('Dosya', 80), @('Boyut', 100), @('Yaş filtresi', 90), @('Açıklama / uyarı', 520), @('Taranan konum', 520))
$gridCl.Columns.RemoveAt(0)
$ccCl = New-Object Windows.Forms.DataGridViewCheckBoxColumn
$ccCl.HeaderText = 'Seç'; $ccCl.Width = 45
$gridCl.Columns.Insert(0, $ccCl)
$gridCl.ReadOnly = $false
$gridCl.MultiSelect = $false
for ($ci = 1; $ci -lt $gridCl.Columns.Count; $ci++) { $gridCl.Columns[$ci].ReadOnly = $true }
$gridCl.Columns[2].DefaultCellStyle.Format = 'N0'
$gridCl.Columns[2].SortMode = 'NotSortable'
$gridCl.Columns[3].SortMode = 'NotSortable'
$tabClean.Controls.Add($gridCl)

$lblClDetail = New-Object Windows.Forms.Label
$lblClDetail.Dock = 'Bottom'; $lblClDetail.Height = 22; $lblClDetail.TextAlign = 'MiddleLeft'
$lblClDetail.Text = '  Bir kategori seçin: en büyük dosyaları burada listelenir.'
$tabClean.Controls.Add($lblClDetail)

$gridClDetail = New-StdGrid @(@('Dosya', 260), @('Boyut', 90), @('Son değişiklik', 130), @('Klasör', 700))
$gridClDetail.Dock = 'Bottom'; $gridClDetail.Height = 190
$tabClean.Controls.Add($gridClDetail)

$pbClean = New-Object Windows.Forms.ProgressBar
$pbClean.Dock = 'Bottom'; $pbClean.Height = 10
$tabClean.Controls.Add($pbClean)

$lblClStatus = New-StatusLabel
$lblClStatus.Text = '  Taramak için "Tara" düğmesine basın. Hiçbir şey seçmeden/onaylamadan silinmez.'
$tabClean.Controls.Add($lblClStatus)

$barCl = New-Bar
$tabClean.Controls.Add($barCl)

function Get-CleanDefs {
    $la = $env:LOCALAPPDATA; $ra = $env:APPDATA; $pd = $env:ProgramData; $wd = $env:windir
    $defs = @()

    $defs += @{ Id = 'usertemp'; Name = 'Kullanıcı TEMP klasörü'; AgeMode = 'User'; Checked = $true; RemoveDirs = $true; LeafRx = '^(temp|tmp)$'
        Roots = @((New-CleanRoot $env:TEMP), (New-CleanRoot (Join-Path $la 'Temp')))
        Note = 'Uygulamaların bıraktığı geçici dosyalar. Kullanımdaki dosyalar atlanır.' }

    $defs += @{ Id = 'wintemp'; Name = 'Windows TEMP klasörü'; AgeMode = 'User'; Checked = $true; RemoveDirs = $true; LeafRx = '^(temp|tmp)$'
        Roots = @((New-CleanRoot (Join-Path $wd 'Temp')))
        Note = 'Sistem geçici dosyaları. Kullanımdaki dosyalar atlanır.' }

    $defs += @{ Id = 'wer'; Name = 'Eski hata raporları'; MinDays = 7; Checked = $true; RemoveDirs = $true
        Roots = @(
            (New-CleanRoot (Join-Path $pd 'Microsoft\Windows\WER\ReportArchive')),
            (New-CleanRoot (Join-Path $pd 'Microsoft\Windows\WER\ReportQueue')),
            (New-CleanRoot (Join-Path $la 'Microsoft\Windows\WER\ReportArchive')),
            (New-CleanRoot (Join-Path $la 'Microsoft\Windows\WER\ReportQueue')),
            (New-CleanRoot (Join-Path $la 'CrashDumps')),
            (New-CleanRoot (Join-Path $wd 'Minidump')),
            (New-CleanRoot (Join-Path $wd 'LiveKernelReports')),
            (New-CleanRoot $wd $false @('MEMORY.DMP')))
        Note = 'Windows hata raporları ve çökme dökümleri (7 günden eski).' }

    $defs += @{ Id = 'logs'; Name = 'Kullanılmayan günlük dosyaları'; MinDays = 30; Checked = $true; RemoveDirs = $false
        Roots = @(
            (New-CleanRoot (Join-Path $wd 'Logs\CBS') $false @('*.log', '*.cab') @('CBS.log')),
            (New-CleanRoot (Join-Path $wd 'Logs\DISM') $false @('*.log') @('dism.log')))
        Note = '30 günden eski CBS/DISM günlükleri. Güncel günlük dosyaları ve Windows Update günlükleri korunur.' }

    $defs += @{ Id = 'thumbs'; Name = 'Thumbnail (küçük resim) önbelleği'; MinDays = 0; Checked = $true; RemoveDirs = $false
        Roots = @((New-CleanRoot (Join-Path $la 'Microsoft\Windows\Explorer') $false @('thumbcache_*.db', 'iconcache_*.db')))
        Warn = 'Küçük resim önbelleği Explorer tarafından yeniden oluşturulur (klasörler ilk açılışta biraz yavaş olabilir).'
        Note = 'Explorer kullandığı dosyaları kilitler; kilitli dosyalar atlanır, Explorer kapatılmaz.' }

    $defs += @{ Id = 'shader'; Name = 'DirectX Shader Cache'; MinDays = 0; Checked = $true; RemoveDirs = $true
        Roots = @((New-CleanRoot (Join-Path $la 'D3DSCache')), (New-CleanRoot (Join-Path $la 'Microsoft\DirectX Shader Cache')))
        Warn = 'DirectX shader önbelleği silinince oyunlar/uygulamalar ilk açılışta shader''ları yeniden derler (kısa süreli takılma).'
        Note = 'Windows tarafından otomatik yeniden oluşturulur.' }

    $defs += @{ Id = 'gfx'; Name = 'Eski grafik önbellekleri (NVIDIA/AMD/Intel)'; MinDays = 7; Checked = $true; RemoveDirs = $true
        Roots = @(
            (New-CleanRoot (Join-Path $la 'NVIDIA\DXCache')), (New-CleanRoot (Join-Path $la 'NVIDIA\GLCache')),
            (New-CleanRoot (Join-Path $pd 'NVIDIA Corporation\NV_Cache')),
            (New-CleanRoot (Join-Path $la 'AMD\DxCache')), (New-CleanRoot (Join-Path $la 'AMD\GLCache')),
            (New-CleanRoot (Join-Path $la 'AMD\VkCache')), (New-CleanRoot (Join-Path $la 'AMD\DxcCache')),
            (New-CleanRoot (Join-Path $la 'Intel\ShaderCache')))
        Warn = 'Grafik sürücüsü önbellekleri (7 günden eski) silinince oyunlar ilk açılışta shader''ları yeniden oluşturabilir.'
        Note = 'Grafik sürücüsü shader önbellekleri; sürücü kendiliğinden yeniden üretir.' }

    $rb = @()
    try {
        $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        foreach ($dr in [IO.DriveInfo]::GetDrives()) {
            if ($dr.DriveType -eq 'Fixed' -and $dr.IsReady) { $rb += (New-CleanRoot (Join-Path $dr.Name ('$Recycle.Bin\' + $sid))) }
        }
    } catch {}
    $defs += @{ Id = 'recycle'; Name = 'Geri dönüşüm kutusu'; Kind = 'Recycle'; MinDays = 0; Checked = $false; RemoveDirs = $false
        Roots = $rb
        Warn = 'GERİ DÖNÜŞÜM KUTUSU KALICI OLARAK BOŞALTILIR; içindeki dosyalar geri getirilemez.'
        Note = 'Kalıcı silme olduğu için varsayılan olarak seçili değildir.' }

    $defs += @{ Id = 'do'; Name = 'Eski teslim iyileştirme dosyaları'; MinDays = 7; Checked = $true; RemoveDirs = $true
        Roots = @(
            (New-CleanRoot (Join-Path $pd 'Microsoft\Windows\DeliveryOptimization\Cache')),
            (New-CleanRoot (Join-Path $wd 'ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache')))
        Note = 'Delivery Optimization önbelleği (7 günden eski). Windows Update bileşenlerine dokunulmaz.' }

    $defs += @{ Id = 'appcache'; Name = 'Gereksiz uygulama önbellekleri'; AgeMode = 'User'; Checked = $false; RemoveDirs = $true
        Procs = @('Discord', 'slack', 'Code', 'Teams', 'steam', 'steamwebhelper')
        Roots = @(
            (New-CleanRoot (Join-Path $ra 'discord\Cache')), (New-CleanRoot (Join-Path $ra 'discord\Code Cache')), (New-CleanRoot (Join-Path $ra 'discord\GPUCache')),
            (New-CleanRoot (Join-Path $ra 'Slack\Cache')), (New-CleanRoot (Join-Path $ra 'Slack\Code Cache')), (New-CleanRoot (Join-Path $ra 'Slack\GPUCache')),
            (New-CleanRoot (Join-Path $ra 'Code\Cache')), (New-CleanRoot (Join-Path $ra 'Code\CachedData')), (New-CleanRoot (Join-Path $ra 'Code\Code Cache')), (New-CleanRoot (Join-Path $ra 'Code\GPUCache')),
            (New-CleanRoot (Join-Path $ra 'Microsoft\Teams\Cache')), (New-CleanRoot (Join-Path $ra 'Microsoft\Teams\Code Cache')), (New-CleanRoot (Join-Path $ra 'Microsoft\Teams\GPUCache')), (New-CleanRoot (Join-Path $ra 'Microsoft\Teams\tmp')),
            (New-CleanRoot (Join-Path $la 'Steam\htmlcache')),
            (New-CleanRoot (Join-Path $la 'Microsoft\Windows\INetCache')))
        Warn = 'Uygulama önbellekleri (Discord, Slack, VS Code, Teams, Steam web, INetCache) silinir; uygulamalar ilk açılışta biraz yavaş olabilir. Oturum/ayar verilerine dokunulmaz.'
        Note = 'Yalnızca önbellek klasörleri; oturum, ayar ve yerel depolama verileri hedeflenmez. Varsayılan: seçili değil.' }

    return $defs
}

function Get-CleanMinDays($d) {
    if ($d.AgeMode -eq 'User') {
        switch ($cmbClAge.SelectedIndex) { 1 { return 1 } 2 { return 7 } default { return 0 } }
    }
    if ($d.MinDays) { return [int]$d.MinDays }
    return 0
}

function Search-CleanCategory($d) {
    $files = New-Object 'System.Collections.Generic.List[object]'
    $dirs  = New-Object 'System.Collections.Generic.List[string]'
    $ctr   = @{ Bytes = [long]0; Denied = 0; Young = 0 }
    $minDays = Get-CleanMinDays $d
    $cutoff = $null
    if ($minDays -gt 0) { $cutoff = (Get-Date).AddDays(-$minDays) }
    $used = @(); $recRoots = @()

    foreach ($r in $d.Roots) {
        if ($script:ClCancel) { break }
        $rp = Resolve-CleanRoot $r $d.LeafRx
        if (-not $rp) { continue }
        $dup = $false
        foreach ($s in $recRoots) { if ($rp.Equals($s, 'OrdinalIgnoreCase') -or $rp.StartsWith($s + '\', 'OrdinalIgnoreCase')) { $dup = $true } }
        if ($dup) { continue }
        if ($r.Recursive) { $recRoots += $rp }
        $used += $rp
        Add-CleanFolderScan $rp $r $cutoff $files $dirs $ctr
    }

    $top = New-Object 'System.Collections.Generic.List[object]'
    if ($files.Count -gt 0) {
        $keys = New-Object 'long[]' $files.Count
        for ($k = 0; $k -lt $files.Count; $k++) { $keys[$k] = [long]$files[$k][1] }
        $arr = $files.ToArray()
        [Array]::Sort($keys, $arr)
        [Array]::Reverse($arr)
        $m = [math]::Min(300, $arr.Length)
        for ($k = 0; $k -lt $m; $k++) { $top.Add($arr[$k]) }
    }

    return [pscustomobject]@{
        Def = $d; Id = $d.Id; Name = $d.Name; Kind = $d.Kind; Files = $files; Dirs = $dirs
        Bytes = [long]$ctr.Bytes; Count = $files.Count; Denied = $ctr.Denied; Young = $ctr.Young
        Top = $top; Roots = $used; MinDays = $minDays; Checked = [bool]$d.Checked
    }
}

function Show-CleanGrid {
    $script:ClLoading = $true
    try {
        $gridCl.Rows.Clear()
        foreach ($r in $script:ClResults) {
            $age = if ($r.MinDays -gt 0) { "$($r.MinDays) gün+" } else { 'Tümü' }
            $loc = if ($r.Roots.Count -gt 0) { ($r.Roots -join ' ; ') } else { 'Bulunamadı / bu sistemde yok' }
            $note = [string]$r.Def.Note
            if ($r.Young -gt 0) { $note += " ($($r.Young) yeni dosya yaş filtresi nedeniyle dışarıda bırakıldı.)" }
            if ($r.Denied -gt 0) { $note += " ($($r.Denied) klasöre erişim yok, atlandı.)" }
            $i = $gridCl.Rows.Add([object[]]@($(if ($r.Count -gt 0) { $r.Checked } else { $false }), $r.Name, $r.Count, (Format-Bytes $r.Bytes), $age, $note, $loc))
            $row = $gridCl.Rows[$i]; $row.Tag = $r
            if ($r.Count -eq 0) { $row.DefaultCellStyle.ForeColor = [Drawing.Color]::Gray; $row.Cells[0].ReadOnly = $true }
            if ($r.Kind -eq 'Recycle' -and $r.Count -gt 0) { $row.DefaultCellStyle.BackColor = [Drawing.Color]::LightYellow }
        }
    } finally { $script:ClLoading = $false }
    Update-CleanTotals
    Show-CleanDetail
}

function Update-CleanTotals {
    if ($script:ClLoading) { return }
    $totB = [long]0; $totN = 0; $selB = [long]0; $selN = 0
    foreach ($row in $gridCl.Rows) {
        $r = $row.Tag
        if (-not $r) { continue }
        $totB += $r.Bytes; $totN += $r.Count
        $on = ($row.Cells[0].Value -eq $true)
        $r.Checked = $on
        if ($on) { $selB += $r.Bytes; $selN += $r.Count }
    }
    $lblClStatus.Text = ('  Temizlenebilir toplam: {0} ({1:N0} dosya)   |   Seçili: {2} ({3:N0} dosya)   |   {4} boş alan: {5}' -f (Format-Bytes $totB), $totN, (Format-Bytes $selB), $selN, $env:SystemDrive, (Format-Bytes (Get-SystemFree)))
}

function Show-CleanDetail {
    $gridClDetail.Rows.Clear()
    if ($gridCl.SelectedRows.Count -eq 0) { return }
    $r = $gridCl.SelectedRows[0].Tag
    if (-not $r) { return }
    $lblClDetail.Text = ('  {0}: en büyük {1} dosya (kategori toplamı {2}, {3:N0} dosya)' -f $r.Name, $r.Top.Count, (Format-Bytes $r.Bytes), $r.Count)
    foreach ($t in $r.Top) {
        [void]$gridClDetail.Rows.Add([object[]]@([IO.Path]::GetFileName([string]$t[0]), (Format-Bytes $t[1]), ([datetime]$t[2]).ToString('yyyy-MM-dd HH:mm'), [IO.Path]::GetDirectoryName([string]$t[0])))
    }
}

function Invoke-CleanScan {
    if ($script:ClBusy) { return }
    $script:ClBusy = $true; $script:ClCancel = $false
    $form.Cursor = 'WaitCursor'; $script:Timer.Stop()
    try {
        $defs = @(Get-CleanDefs)
        $res = @(); $k = 0
        foreach ($d in $defs) {
            if ($script:ClCancel) { break }
            $lblClStatus.Text = "  Taranıyor: $($d.Name) ..."
            $pbClean.Value = [int][math]::Min(100, [math]::Floor($k * 100 / $defs.Count)); $k++
            [Windows.Forms.Application]::DoEvents()
            $res += Search-CleanCategory $d
        }
        $script:ClResults = $res
        $script:ClScanTime = Get-Date
        $pbClean.Value = 0
        Show-CleanGrid
        if ($script:ClCancel) { $lblClStatus.Text = '  Tarama iptal edildi (kısmi sonuç). ' + $lblClStatus.Text }
    } catch {
        $lblClStatus.Text = '  Tarama hatası: ' + $_.Exception.Message
        Write-Log ('Derin temizlik tarama hatası: ' + $_.Exception.Message)
    } finally { $form.Cursor = 'Default'; $script:Timer.Start(); $script:ClBusy = $false }
}

function Get-CleanPreCheck($sel) {
    $w = @()
    if ($script:ClScanTime -and ((Get-Date) - $script:ClScanTime).TotalMinutes -gt 15) {
        $w += ('Tarama {0:N0} dk önce yapıldı; her dosya silinmeden önce yeniden doğrulanır, değişenler atlanır.' -f ((Get-Date) - $script:ClScanTime).TotalMinutes)
    }
    foreach ($r in $sel) {
        if ($r.Def.Warn) { $w += $r.Def.Warn }
        if ($r.Def.Procs) {
            $run = @(Get-Process -Name $r.Def.Procs -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ProcessName -Unique)
            if ($run.Count -gt 0) { $w += ("Çalışan uygulama: {0}. Kilitli dosyalar atlanır; tam temizlik için önce uygulamayı kendiniz kapatın." -f ($run -join ', ')) }
        }
        if ($r.Roots.Count -eq 0) { $w += "$($r.Name): güvenli kök klasör bulunamadı." }
    }
    return @($w | Select-Object -Unique)
}

function Invoke-CleanSelected {
    if ($script:ClBusy) { return }
    $sel = @($gridCl.Rows | Where-Object { $_.Cells[0].Value -eq $true } | ForEach-Object { $_.Tag } | Where-Object { $_ -and $_.Count -gt 0 })
    if ($sel.Count -eq 0) { [L10nMsg]::Show('Önce taratıp temizlenecek kategorileri seçin (dosya içeren kategoriler).', 'WinOpt Suite - Developed by Leone') | Out-Null; return }

    $totB = [long]0; $totN = 0
    foreach ($r in $sel) { $totB += $r.Bytes; $totN += $r.Count }
    $lines = ($sel | ForEach-Object { '  • {0}: {1:N0} dosya, {2}' -f $_.Name, $_.Count, (Format-Bytes $_.Bytes) }) -join "`n"
    $pre = @(Get-CleanPreCheck $sel)
    $msg = ("{0} kategori, {1:N0} dosya, toplam {2} temizlenecek:`n`n{3}" -f $sel.Count, $totN, (Format-Bytes $totB), $lines)
    if ($pre.Count -gt 0) { $msg += "`n`nÖN KONTROL UYARILARI:`n" + (($pre | ForEach-Object { '  - ' + $_ }) -join "`n") }
    $msg += "`n`nKullanımda olan veya erişim engelli dosyalar zorla silinmez, atlanır. Windows Update bileşenlerine ve kritik sistem dosyalarına dokunulmaz.`n`nDevam edilsin mi?"
    if ([L10nMsg]::Show($msg, 'Temizliği onayla', 'YesNo', 'Warning') -ne 'Yes') { return }

    $script:ClBusy = $true; $script:ClCancel = $false
    $form.Cursor = 'WaitCursor'; $script:Timer.Stop()
    $free0 = Get-SystemFree
    $summary = @(); $grandFreed = [long]0
    try {
        $total = 0; foreach ($r in $sel) { $total += $r.Count }
        $done = 0
        foreach ($r in $sel) {
            if ($script:ClCancel) { break }
            $stat = @{ ok = 0; gone = 0; changed = 0; locked = 0; denied = 0; unsafe = 0 }
            $freed = [long]0; $extra = ''

            if ($r.Kind -eq 'Recycle') {
                $lblClStatus.Text = "  Temizleniyor: $($r.Name) ..."; [Windows.Forms.Application]::DoEvents()
                try {
                    Clear-RecycleBin -Force -ErrorAction Stop
                } catch { $extra = ' (' + $_.Exception.Message + ')' }
                $after = Search-CleanCategory $r.Def
                $freed = [math]::Max([long]0, [long]($r.Bytes - $after.Bytes))
                $stat.ok = [math]::Max(0, $r.Count - $after.Count)
                $stat.locked = $after.Count
                $done += $r.Count
            } else {
                $i = 0
                foreach ($rec in $r.Files) {
                    $i++; $done++
                    if (($i % 50) -eq 0) {
                        $lblClStatus.Text = ('  Temizleniyor: {0} ({1:N0}/{2:N0})' -f $r.Name, $i, $r.Count)
                        $pbClean.Value = [int][math]::Min(100, [math]::Floor($done * 100 / [math]::Max(1, $total)))
                        [Windows.Forms.Application]::DoEvents()
                        if ($script:ClCancel) { break }
                    }
                    $res = Remove-CleanFile $rec $r.Roots
                    $stat[$res]++
                    if ($res -eq 'ok') { $freed += [long]$rec[1] }
                }
                if ($r.Def.RemoveDirs -and -not $script:ClCancel) {
                    $cut = $null; if ($r.MinDays -gt 0) { $cut = (Get-Date).AddDays(-$r.MinDays) }
                    [void](Remove-CleanEmptyDirs $r.Dirs $r.Roots $cut)
                }
            }

            $skipped = $stat.locked + $stat.denied + $stat.changed + $stat.unsafe
            $grandFreed += $freed
            Add-CleanHistory $CleanHistFile ([pscustomobject][ordered]@{
                'Zaman' = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); 'Kategori' = $r.Name
                'Silinen' = $stat.ok; 'Atlanan' = $skipped
                'Kazanılan bayt' = $freed; 'Kazanılan alan' = (Format-Bytes $freed) })
            Write-Log ('Derin temizlik: {0} - silinen {1}, atlanan {2} (kullanımda {3}, erişim engeli {4}, değişen {5}), kazanılan {6}' -f $r.Name, $stat.ok, $skipped, $stat.locked, $stat.denied, $stat.changed, (Format-Bytes $freed))
            $summary += ('  • {0}: {1:N0} silindi, {2:N0} atlandı, {3} kazanıldı{4}' -f $r.Name, $stat.ok, $skipped, (Format-Bytes $freed), $extra)
        }
    } catch {
        Write-Log ('Derin temizlik hatası: ' + $_.Exception.Message)
        $summary += '  ! Hata: ' + $_.Exception.Message
    } finally { $form.Cursor = 'Default'; $script:Timer.Start(); $script:ClBusy = $false; $pbClean.Value = 0 }

    Invoke-CleanScan
    $free1 = Get-SystemFree
    $m = "Temizlik tamamlandı.`n`n" + ($summary -join "`n") + ("`n`nToplam kazanılan alan: {0}`n{1} sürücüsü boş alan: {2} -> {3}" -f (Format-Bytes $grandFreed), $env:SystemDrive, (Format-Bytes $free0), (Format-Bytes $free1))
    $m += "`nTüm zamanlarda kazanılan: " + (Format-Bytes (Get-CleanTotalFreed $CleanHistFile))
    $m += "`n`n'Atlanan' dosyalar kullanımda, erişim engelli veya taramadan sonra değişmiş olanlardır; zorla silinmez."
    [L10nMsg]::Show($m, 'WinOpt Suite - Developed by Leone') | Out-Null
}

New-Btn $barCl 'Tara' 80 { Invoke-CleanScan }
New-Btn $barCl 'Seçilileri Temizle' 130 { Invoke-CleanSelected }
New-Btn $barCl 'İptal' 70 { $script:ClCancel = $true }
New-Btn $barCl 'Tümünü Seç' 90 {
    $script:ClLoading = $true
    foreach ($row in $gridCl.Rows) { if ($row.Tag -and $row.Tag.Count -gt 0) { $row.Cells[0].Value = $true } }
    $script:ClLoading = $false; Update-CleanTotals
}
New-Btn $barCl 'Seçimi Kaldır' 100 {
    $script:ClLoading = $true
    foreach ($row in $gridCl.Rows) { $row.Cells[0].Value = $false }
    $script:ClLoading = $false; Update-CleanTotals
}
$lblClAge = New-Object Windows.Forms.Label
$lblClAge.Text = 'Dosya yaşı (TEMP/uygulama):'; $lblClAge.AutoSize = $true; $lblClAge.Margin = New-Object Windows.Forms.Padding(12, 9, 2, 0)
$barCl.Controls.Add($lblClAge)
$cmbClAge = New-Object Windows.Forms.ComboBox
$cmbClAge.DropDownStyle = 'DropDownList'; $cmbClAge.Width = 200; $cmbClAge.Margin = New-Object Windows.Forms.Padding(2, 5, 8, 0)
[void]$cmbClAge.Items.Add('Tümü (kullanımda olmayanlar)'); [void]$cmbClAge.Items.Add('1 gün ve daha eski'); [void]$cmbClAge.Items.Add('7 gün ve daha eski')
$cmbClAge.SelectedIndex = 1
$cmbClAge.Add_SelectionChangeCommitted({ if ($script:ClResults.Count -gt 0) { Invoke-CleanScan } })
$barCl.Controls.Add($cmbClAge)
New-Btn $barCl 'Temizleme Geçmişi' 130 { Show-CsvDialog $CleanHistFile 'Temizleme geçmişi' }
New-Btn $barCl 'CSV Raporu' 90 {
    if ($script:ClResults.Count -eq 0) { [L10nMsg]::Show('Önce tarama yapın.', 'WinOpt Suite - Developed by Leone') | Out-Null; return }
    $dlg = New-Object Windows.Forms.SaveFileDialog; $dlg.Filter = 'CSV (*.csv)|*.csv'; $dlg.FileName = 'derin-temizlik-raporu.csv'
    if ($dlg.ShowDialog() -eq 'OK') {
        $script:ClResults | ForEach-Object {
            [pscustomobject][ordered]@{ Kategori = $_.Name; Dosya = $_.Count; Bayt = $_.Bytes; Boyut = (Format-Bytes $_.Bytes); YasFiltresi = $_.MinDays; Konum = ($_.Roots -join ' ; ') }
        } | Export-Csv -LiteralPath $dlg.FileName -NoTypeInformation -Encoding UTF8
    }
}

$gridCl.Add_CurrentCellDirtyStateChanged({ if ($gridCl.IsCurrentCellDirty) { $gridCl.CommitEdit('CurrentCellChange') } })
$gridCl.Add_CellValueChanged({ param($s, $e) if ($e.ColumnIndex -eq 0 -and -not $script:ClLoading) { Update-CleanTotals } })
$gridCl.Add_SelectionChanged({ try { if (-not $script:ClLoading) { Show-CleanDetail } } catch {} })
