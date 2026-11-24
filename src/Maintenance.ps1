if (-not ('WinOptIdle' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class WinOptIdle {
    [StructLayout(LayoutKind.Sequential)] struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
    [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO p);
    public static double IdleSeconds() {
        LASTINPUTINFO i = new LASTINPUTINFO();
        i.cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO));
        if (!GetLastInputInfo(ref i)) return -1;
        return ((uint)Environment.TickCount - i.dwTime) / 1000.0;
    }
}
'@
}

$MaintCfgFile  = Join-Path $AppDir 'bakim-ayarlari.json'
$MaintHistFile = Join-Path $AppDir 'bakim-gecmisi.csv'
$script:MaintTask = 'WinOptSuite Otomatik Bakim'
$script:MaintBusy = $false
$script:MaintDefs = @()
$script:WeekDays = @(@('Pazartesi', 'MON'), @('Salı', 'TUE'), @('Çarşamba', 'WED'), @('Perşembe', 'THU'), @('Cuma', 'FRI'), @('Cumartesi', 'SAT'), @('Pazar', 'SUN'))

function Read-MaintCfg {
    $cfg = [pscustomobject]@{ Enabled = $false; Plan = 'Haftalık'; Day = 'SUN'; Time = '03:00'; IdleOnly = $true; IdleMinutes = 10; Categories = $null }
    if (Test-Path -LiteralPath $MaintCfgFile) {
        try {
            $x = Get-Content -LiteralPath $MaintCfgFile -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in 'Enabled', 'Plan', 'Day', 'Time', 'IdleOnly', 'IdleMinutes', 'Categories') { if ($null -ne $x.$p) { $cfg.$p = $x.$p } }
        } catch {}
    }
    return $cfg
}
function Save-MaintCfg($cfg) { ConvertTo-Json -InputObject $cfg -Depth 4 | Set-Content -LiteralPath $MaintCfgFile -Encoding UTF8 }

function Add-MaintHistory($row) {
    try { $row | Export-Csv -LiteralPath $MaintHistFile -Append -NoTypeInformation -Encoding UTF8 }
    catch { Write-Log ('Bakım geçmişi yazılamadı: ' + $_.Exception.Message) }
}

function Test-IdleNow([int]$minutes) {
    $idle = [WinOptIdle]::IdleSeconds()
    if ($idle -lt 0 -or $idle -lt ($minutes * 60)) { return $false }
    $s = Get-PerfSample 3
    if ($s.CpuOk -and $s.Cpu -ge 25) { return $false }
    return $true
}

function Invoke-MaintCategory($d) {
    $script:ClCancel = $false
    $res = Search-CleanCategory $d
    $del = 0; $skip = 0; $freed = [long]0
    if ($d.Kind -eq 'Recycle') {
        Clear-RecycleBin -Force -ErrorAction Stop
        $after = Search-CleanCategory $d
        $del = [math]::Max(0, $res.Count - $after.Count); $skip = $after.Count
        $freed = [math]::Max([long]0, [long]($res.Bytes - $after.Bytes))
    } else {
        foreach ($rec in $res.Files) {
            $x = Remove-CleanFile $rec $res.Roots
            if ($x -eq 'ok') { $freed += [long]$rec[1]; $del++ } else { $skip++ }
        }
        if ($d.RemoveDirs) {
            $cut = $null; if ($res.MinDays -gt 0) { $cut = (Get-Date).AddDays(-$res.MinDays) }
            [void](Remove-CleanEmptyDirs $res.Dirs $res.Roots $cut)
        }
    }
    Add-CleanHistory $CleanHistFile ([pscustomobject][ordered]@{ 'Zaman' = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); 'Kategori' = ($d.Name + ' (Otomatik Bakım)')
        'Silinen' = $del; 'Atlanan' = $skip; 'Kazanılan bayt' = $freed; 'Kazanılan alan' = (Format-Bytes $freed) })
    return @{ Del = $del; Skip = $skip; Freed = $freed }
}

# Bakım yalnızca kullanıcının seçtiği temizlik kategorilerini çalıştırır; ayar, servis veya başlangıç değişikliği yapmaz.
function Invoke-MaintenanceRun([string]$trigger) {
    $mutex = New-Object Threading.Mutex($false, 'Global\WinOptSuiteMaintenance')
    $got = $false
    try { $got = $mutex.WaitOne(0) } catch { $got = $true }
    if (-not $got) { Add-MaintHistory ([pscustomobject][ordered]@{ Zaman = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); Tetikleyici = $trigger; Durum = 'Atlandı'; Kategori = 0; Silinen = 0; Atlanan = 0; 'Kazanılan bayt' = 0; 'Süre sn' = 0; Not = 'Başka bir bakım zaten çalışıyor' }); return $null }
    $start = Get-Date
    try {
        $cfg = Read-MaintCfg
        $defs = @(Get-CleanDefs | Where-Object { @($cfg.Categories) -contains $_.Id })
        $row = [ordered]@{ Zaman = $start.ToString('yyyy-MM-dd HH:mm:ss'); Tetikleyici = $trigger; Durum = ''; Kategori = $defs.Count; Silinen = 0; Atlanan = 0; 'Kazanılan bayt' = [long]0; 'Süre sn' = 0; Not = '' }
        if ($defs.Count -eq 0) {
            $row.Durum = 'Atlandı'; $row.Not = 'Seçili temizlik kategorisi yok'
            Add-MaintHistory ([pscustomobject]$row); return $null
        }
        if ($trigger -eq 'Zamanlanmış' -and $cfg.IdleOnly) {
            $idleOk = $false
            for ($k = 0; $k -lt 30; $k++) {
                if (Test-IdleNow ([int]$cfg.IdleMinutes)) { $idleOk = $true; break }
                Start-Sleep -Seconds 60
            }
            if (-not $idleOk) {
                $row.Durum = 'Atlandı'; $row.Not = 'Bilgisayar 30 dk içinde boşta olmadı (kullanıcı çalışıyor veya CPU yüksek)'; $row['Süre sn'] = [int]((Get-Date) - $start).TotalSeconds
                Add-MaintHistory ([pscustomobject]$row); Write-Log 'Otomatik bakım atlandı: bilgisayar boşta değil'; return $null
            }
        }
        $before = Get-PerfSample
        $okCats = @(); $failCats = @(); $del = 0; $skip = 0; $freed = [long]0
        foreach ($d in $defs) {
            try {
                $r = Invoke-MaintCategory $d
                $del += $r.Del; $skip += $r.Skip; $freed += $r.Freed
                $okCats += ('{0}: {1:N0} silindi, {2:N0} atlandı (kullanımda/erişim engelli), {3} kazanıldı' -f $d.Name, $r.Del, $r.Skip, (Format-Bytes $r.Freed))
            } catch { $failCats += ('{0}: {1}' -f $d.Name, $_.Exception.Message) }
        }
        $after = Get-PerfSample
        $row.Silinen = $del; $row.Atlanan = $skip; $row['Kazanılan bayt'] = $freed; $row['Süre sn'] = [int]((Get-Date) - $start).TotalSeconds
        if ($failCats.Count -eq 0) { $row.Durum = 'Başarılı' } elseif ($okCats.Count -gt 0) { $row.Durum = 'Kısmen başarılı' } else { $row.Durum = 'Başarısız' }
        Add-MaintHistory ([pscustomobject]$row)
        Write-Log ("Otomatik bakım ({0}): {1}, kazanılan {2}" -f $trigger, $row.Durum, (Format-Bytes $freed))
        $rv = New-PerfReport @{ Source = "Otomatik Bakım ($trigger)"; Slug = 'bakim'; Start = $start; End = (Get-Date); Before = $before; After = $after; FreedBytes = $freed
            Startups = @(); Services = @(); Tweaks = @(); Reversible = @(); Irreversible = @($okCats); Failures = $failCats
            Notes = @('Bakım yalnızca sizin seçtiğiniz temizlik kategorilerini çalıştırır; başlangıç, servis veya Windows ayarı değiştirmez.', 'Silinen geçici dosyalar geri alınamaz.') }
        return $rv
    } finally { try { $mutex.ReleaseMutex() } catch {}; $mutex.Dispose() }
}

function Register-MaintTask($cfg) {
    $main = $script:MainScript
    if (-not $main -or -not (Test-Path -LiteralPath $main)) { throw 'Ana betik yolu bulunamadı; planlama yapılamadı (EXE sürümünde desteklenmez).' }
    $tr = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File \"' + $main + '\" -Maintenance'
    $sa = @('/Create', '/TN', $script:MaintTask, '/TR', $tr, '/ST', [string]$cfg.Time, '/RL', 'HIGHEST', '/F')
    switch ($cfg.Plan) {
        'Günlük'   { $sa += @('/SC', 'DAILY') }
        'Haftalık' { $sa += @('/SC', 'WEEKLY', '/D', [string]$cfg.Day) }
        'Aylık'    { $sa += @('/SC', 'MONTHLY', '/D', [string]$cfg.Day) }
    }
    $o = & schtasks.exe @args 2>&1
    if ($LASTEXITCODE -ne 0) { throw (($o | Out-String).Trim()) }
}
function Remove-MaintTask {
    $o = & schtasks.exe /Delete /TN $script:MaintTask /F 2>&1
    return ($LASTEXITCODE -eq 0)
}
function Test-MaintTask { $null = & schtasks.exe /Query /TN $script:MaintTask 2>&1; return ($LASTEXITCODE -eq 0) }

# ---------------- Otomatik Bakım sekmesi ----------------
$tabMaint = New-Object Windows.Forms.TabPage
$tabMaint.Text = 'Otomatik Bakım'
[void]$tabs.TabPages.Add($tabMaint)

$gridMaint = New-StdGrid @(@('Zaman', 140), @('Tetikleyici', 100), @('Durum', 120), @('Kategori', 70), @('Silinen', 80), @('Atlanan', 80), @('Kazanılan', 100), @('Süre (sn)', 70), @('Not', 450))
$tabMaint.Controls.Add($gridMaint)
$lblMaint = New-StatusLabel
$tabMaint.Controls.Add($lblMaint)
$panMaint = New-Object Windows.Forms.Panel
$panMaint.Dock = 'Top'; $panMaint.Height = 330
$tabMaint.Controls.Add($panMaint)

function New-MLabel([string]$text, [int]$x, [int]$y) {
    $l = New-Object Windows.Forms.Label; $l.Text = $text; $l.AutoSize = $true; $l.Location = New-Object Drawing.Point($x, $y)
    $panMaint.Controls.Add($l); return $l
}
$chkMaint = New-Object Windows.Forms.CheckBox
$chkMaint.Text = 'Otomatik bakımı etkinleştir (Windows Görev Zamanlayıcı ile planlanır)'; $chkMaint.AutoSize = $true; $chkMaint.Location = New-Object Drawing.Point(10, 8)
$panMaint.Controls.Add($chkMaint)
[void](New-MLabel 'Plan:' 10 42)
$cmbPlan = New-Object Windows.Forms.ComboBox
$cmbPlan.DropDownStyle = 'DropDownList'; $cmbPlan.Location = New-Object Drawing.Point(55, 38); $cmbPlan.Width = 110
[void]$cmbPlan.Items.AddRange(@('Günlük', 'Haftalık', 'Aylık'))
$panMaint.Controls.Add($cmbPlan)
[void](New-MLabel 'Gün:' 185 42)
$cmbDay = New-Object Windows.Forms.ComboBox
$cmbDay.DropDownStyle = 'DropDownList'; $cmbDay.Location = New-Object Drawing.Point(225, 38); $cmbDay.Width = 120
$panMaint.Controls.Add($cmbDay)
[void](New-MLabel 'Saat:' 365 42)
$dtpMaint = New-Object Windows.Forms.DateTimePicker
$dtpMaint.Format = 'Custom'; $dtpMaint.CustomFormat = 'HH:mm'; $dtpMaint.ShowUpDown = $true; $dtpMaint.Width = 70; $dtpMaint.Location = New-Object Drawing.Point(410, 38)
$panMaint.Controls.Add($dtpMaint)
$chkIdle = New-Object Windows.Forms.CheckBox
$chkIdle.Text = 'Yalnızca bilgisayar boşta iken çalıştır (kullanıcı girişi yok ve CPU %25 altı); en fazla 30 dk beklenir, boşta olmazsa atlanır'; $chkIdle.AutoSize = $true; $chkIdle.Location = New-Object Drawing.Point(10, 72)
$panMaint.Controls.Add($chkIdle)
[void](New-MLabel 'Boşta kalma süresi (dk):' 10 100)
$numIdle = New-Object Windows.Forms.NumericUpDown
$numIdle.Minimum = 1; $numIdle.Maximum = 120; $numIdle.Value = 10; $numIdle.Width = 60; $numIdle.Location = New-Object Drawing.Point(170, 96)
$panMaint.Controls.Add($numIdle)
[void](New-MLabel 'Bakımda temizlenecek kategoriler (siz seçersiniz):' 10 128)
$clbMaint = New-Object Windows.Forms.CheckedListBox
$clbMaint.CheckOnClick = $true; $clbMaint.Location = New-Object Drawing.Point(10, 150); $clbMaint.Size = New-Object Drawing.Size(760, 112)
$panMaint.Controls.Add($clbMaint)

function Update-MaintDayList {
    $cmbDay.Items.Clear()
    if ($cmbPlan.SelectedItem -eq 'Haftalık') { foreach ($w in $script:WeekDays) { [void]$cmbDay.Items.Add($w[0]) }; $cmbDay.Enabled = $true; $cmbDay.SelectedIndex = 6 }
    elseif ($cmbPlan.SelectedItem -eq 'Aylık') { foreach ($i in 1..28) { [void]$cmbDay.Items.Add([string]$i) }; $cmbDay.Enabled = $true; $cmbDay.SelectedIndex = 0 }
    else { $cmbDay.Enabled = $false }
}
$cmbPlan.Add_SelectedIndexChanged({ try { Update-MaintDayList } catch {} })

function Show-MaintHistory {
    $gridMaint.Rows.Clear()
    if (-not (Test-Path -LiteralPath $MaintHistFile)) { return }
    try {
        foreach ($h in @(Import-Csv -LiteralPath $MaintHistFile -Encoding UTF8 | Select-Object -Last 200 | Sort-Object Zaman -Descending)) {
            $i = $gridMaint.Rows.Add([object[]]@($h.Zaman, $h.Tetikleyici, $h.Durum, $h.Kategori, $h.Silinen, $h.Atlanan, (Format-Bytes ([double]$h.'Kazanılan bayt')), $h.'Süre sn', $h.Not))
            if ($h.Durum -eq 'Başarısız') { $gridMaint.Rows[$i].DefaultCellStyle.BackColor = [Drawing.Color]::MistyRose }
            elseif ($h.Durum -ne 'Başarılı') { $gridMaint.Rows[$i].DefaultCellStyle.BackColor = [Drawing.Color]::LightYellow }
        }
    } catch {}
}

function Load-MaintUi {
    $cfg = Read-MaintCfg
    $script:MaintDefs = @(Get-CleanDefs)
    $chosen = $cfg.Categories
    $clbMaint.Items.Clear()
    foreach ($d in $script:MaintDefs) {
        $txt = $d.Name
        if ($d.Kind -eq 'Recycle') { $txt += '  (geri alınamaz)' } elseif (-not $d.Checked) { $txt += '  (varsayılan kapalı; kişisel/uygulama verisi içerebilir)' }
        $on = if ($null -ne $chosen) { (@($chosen) -contains $d.Id) } else { ([bool]$d.Checked -and $d.Kind -ne 'Recycle') }
        [void]$clbMaint.Items.Add((T $txt), $on)
    }
    $chkMaint.Checked = [bool]$cfg.Enabled
    $cmbPlan.SelectedItem = $cfg.Plan; if (-not $cmbPlan.SelectedItem) { $cmbPlan.SelectedItem = 'Haftalık' }
    Update-MaintDayList
    if ($cfg.Plan -eq 'Haftalık') { for ($i = 0; $i -lt $script:WeekDays.Count; $i++) { if ($script:WeekDays[$i][1] -eq $cfg.Day) { $cmbDay.SelectedIndex = $i } } }
    elseif ($cfg.Plan -eq 'Aylık') { $idx = $cmbDay.Items.IndexOf([string]$cfg.Day); if ($idx -ge 0) { $cmbDay.SelectedIndex = $idx } }
    try { $dtpMaint.Value = [datetime]::ParseExact([string]$cfg.Time, 'HH:mm', $null) } catch {}
    $chkIdle.Checked = [bool]$cfg.IdleOnly
    $numIdle.Value = [math]::Min(120, [math]::Max(1, [int]$cfg.IdleMinutes))
    $lblMaint.Text = '  Zamanlanmış görev: ' + $(if (Test-MaintTask) { 'kayıtlı' } else { 'kayıtlı değil' }) + '.  Bakım yalnızca seçtiğiniz temizlik kategorilerini çalıştırır; ayar/servis/başlangıç değişikliği yapmaz.'
    Show-MaintHistory
}

function Get-MaintCfgFromUi {
    $ids = @(); for ($i = 0; $i -lt $script:MaintDefs.Count; $i++) { if ($clbMaint.GetItemChecked($i)) { $ids += $script:MaintDefs[$i].Id } }
    $plan = [string]$cmbPlan.SelectedItem; $day = ''
    if ($plan -eq 'Haftalık') { $day = $script:WeekDays[[math]::Max(0, $cmbDay.SelectedIndex)][1] } elseif ($plan -eq 'Aylık') { $day = [string]$cmbDay.SelectedItem }
    [pscustomobject]@{ Enabled = $chkMaint.Checked; Plan = $plan; Day = $day; Time = $dtpMaint.Value.ToString('HH:mm'); IdleOnly = $chkIdle.Checked; IdleMinutes = [int]$numIdle.Value; Categories = @($ids) }
}

function Save-MaintFromUi {
    $cfg = Get-MaintCfgFromUi
    $risky = @($script:MaintDefs | Where-Object { @($cfg.Categories) -contains $_.Id -and ($_.Kind -eq 'Recycle' -or -not $_.Checked) })
    if ($risky.Count -gt 0) {
        $m = "Şu kategoriler varsayılan olarak kapalıdır ve kişisel/uygulama verisi içerebilir veya geri alınamaz:`n`n" + (($risky | ForEach-Object { '  • ' + $_.Name }) -join "`n") + "`n`nBunların zamanlanmış bakımda sizin adınıza otomatik temizlenmesini onaylıyor musunuz?"
        if ([L10nMsg]::Show($m, 'Ek onay', 'YesNo', 'Warning') -ne 'Yes') { return }
    }
    if ($cfg.Enabled -and @($cfg.Categories).Count -eq 0) { [L10nMsg]::Show('Planlamadan önce en az bir temizlik kategorisi seçin.', 'WinOpt Suite - Developed by Leone') | Out-Null; return }
    try {
        Save-MaintCfg $cfg
        if ($cfg.Enabled) { Register-MaintTask $cfg; Write-Log "Otomatik bakım planlandı: $($cfg.Plan) $($cfg.Day) $($cfg.Time)"; $msg = 'Ayarlar kaydedildi ve bakım planlandı.' }
        else { [void](Remove-MaintTask); Write-Log 'Otomatik bakım planı kapatıldı'; $msg = 'Ayarlar kaydedildi; otomatik bakım kapalı (zamanlanmış görev kaldırıldı).' }
        [L10nMsg]::Show($msg, 'WinOpt Suite - Developed by Leone') | Out-Null
    } catch { [L10nMsg]::Show('Planlama başarısız: ' + $_.Exception.Message, 'WinOpt Suite - Developed by Leone') | Out-Null; Write-Log ('Bakım planlama hatası: ' + $_.Exception.Message) }
    $lblMaint.Text = '  Zamanlanmış görev: ' + $(if (Test-MaintTask) { 'kayıtlı' } else { 'kayıtlı değil' })
}

function Start-MaintNow {
    if ($script:MaintBusy) { return }
    $cfg = Get-MaintCfgFromUi
    if (@($cfg.Categories).Count -eq 0) { [L10nMsg]::Show('Önce en az bir temizlik kategorisi seçin.', 'WinOpt Suite - Developed by Leone') | Out-Null; return }
    $names = ($script:MaintDefs | Where-Object { @($cfg.Categories) -contains $_.Id } | ForEach-Object { '  • ' + $_.Name }) -join "`n"
    if ([L10nMsg]::Show("Şimdi şu kategoriler temizlenecek (silinenler geri alınamaz):`n`n$names`n`nDevam edilsin mi?", 'Bakımı onayla', 'YesNo', 'Question') -ne 'Yes') { return }
    Save-MaintCfg $cfg
    $script:MaintBusy = $true; $form.Cursor = 'WaitCursor'; $script:Timer.Stop(); $lblMaint.Text = '  Bakım çalışıyor...'; [Windows.Forms.Application]::DoEvents()
    $rv = $null
    try { $rv = Invoke-MaintenanceRun 'Elle' } catch { Write-Log ('Bakım hatası: ' + $_.Exception.Message); [L10nMsg]::Show('Bakım hatası: ' + $_.Exception.Message, 'WinOpt Suite - Developed by Leone') | Out-Null }
    finally { $form.Cursor = 'Default'; $script:Timer.Start(); $script:MaintBusy = $false }
    Show-MaintHistory; $lblMaint.Text = '  Bakım bitti.'
    if ($rv) { Show-TextDialog 'Bakım raporu' $rv.Text }
}

$btnY = 272
function Add-MBtn([string]$text, [int]$x, [int]$w, [scriptblock]$h) {
    $b = New-Object Windows.Forms.Button; $b.Text = $text; $b.Width = $w; $b.Height = 30; $b.Location = New-Object Drawing.Point($x, $btnY); $b.Add_Click($h); $panMaint.Controls.Add($b)
}
Add-MBtn 'Kaydet ve Planla' 10 140 { Save-MaintFromUi }
Add-MBtn 'Planı Kaldır' 160 110 { [void](Remove-MaintTask); $chkMaint.Checked = $false; $c = Get-MaintCfgFromUi; Save-MaintCfg $c; $lblMaint.Text = '  Zamanlanmış görev kaldırıldı.' }
Add-MBtn 'Şimdi Çalıştır' 280 120 { Start-MaintNow }
Add-MBtn 'Geçmişi Yenile' 410 120 { Show-MaintHistory }
Add-MBtn 'Son Bakım Raporu' 540 140 {
    $f = Get-ChildItem -LiteralPath $ReportDir -Filter '*-bakim.txt' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($f) { Show-TextDialog 'Bakım raporu' ([IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)) } else { [L10nMsg]::Show('Henüz bakım raporu yok.', 'WinOpt Suite - Developed by Leone') | Out-Null }
}
$form.Add_Shown({ try { Load-MaintUi } catch { Write-Log ('Bakım ayarları yüklenemedi: ' + $_.Exception.Message) } })
