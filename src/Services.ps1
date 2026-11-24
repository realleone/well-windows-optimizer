$tabSvc = New-Object Windows.Forms.TabPage
$tabSvc.Text = 'Servisler'
[void]$tabs.TabPages.Add($tabSvc)

$gridSvc = New-StdGrid @(
    @('Servis adı', 150), @('Görünen ad', 220), @('Durum', 80), @('Başlangıç türü', 130), @('CPU %', 60), @('RAM MB', 80),
    @('Çalıştığı işlem', 190), @('Koruma / kategori', 210), @('Değerlendirme', 260), @('Açıklama', 500))
$gridSvc.Columns[4].DefaultCellStyle.Format = 'N1'
$gridSvc.Columns[5].DefaultCellStyle.Format = 'N0'
$tabSvc.Controls.Add($gridSvc)
$barSvc = New-Bar
$tabSvc.Controls.Add($barSvc)
$lblSvc = New-StatusLabel
$tabSvc.Controls.Add($lblSvc)

$script:Svcs = @()
$script:SvcLoaded = $false
$script:HasPrinter = $false

$script:SvcOptional = @{
    'xblauthmanager' = 'Xbox'; 'xblgamesave' = 'Xbox'; 'xboxgipsvc' = 'Xbox'; 'xboxnetapisvc' = 'Xbox'
    'spooler' = 'Yazdırma'; 'printnotify' = 'Yazdırma'; 'printworkflowusersvc' = 'Yazdırma'
    'fax' = 'Faks'; 'mapsbroker' = 'Haritalar'; 'retaildemo' = 'Perakende demo'
    'wmpnetworksvc' = 'Medya paylaşımı'; 'diagtrack' = 'Telemetri'
}

$script:SvcProtect = @('wuauserv','usosvc','waasmedicsvc','bits','trustedinstaller','windefend','sense','wdnissvc','wdfilter',
    'securityhealthservice','wscsvc','mpssvc','bfe','dhcp','dnscache','nsi','nlasvc','netprofm','lanmanworkstation','lanmanserver',
    'netman','wcmsvc','wlansvc','audiosrv','audioendpointbuilder','rpcss','rpceptmapper','dcomlaunch','plugplay','power','eventlog',
    'profsvc','usermanager','gpsvc','cryptsvc','keyiso','samss','winmgmt','schedule','themes','lsm','staterepository',
    'timebrokersvc','systemeventsbroker','coremessagingregistrar','appinfo','sens','sessionenv','tokenbroker','vaultsvc','wlidsvc')
$script:SvcCriticalRegex = 'audio|sound|realtek|waves|nahimic|network|ethernet|wi-?fi|wlan|bluetooth|vpn|nvidia|nvcontainer|intel|amd |radeon|driver|display|touchpad|chipset|firewall|defender'

$script:StartText = @{ Automatic = 'Otomatik'; AutomaticDelayed = 'Otomatik (Gecikmeli)'; Manual = 'Elle'; Disabled = 'Devre dışı'; Other = 'Sistem/Önyükleme' }
$script:StartKeys = @('Automatic', 'AutomaticDelayed', 'Manual', 'Disabled')

function Get-StartKey([string]$mode, [bool]$delayed) {
    switch ($mode) {
        'Auto'     { if ($delayed) { return 'AutomaticDelayed' } else { return 'Automatic' } }
        'Manual'   { return 'Manual' }
        'Disabled' { return 'Disabled' }
        default    { return 'Other' }
    }
}

function Test-DelayedStart([string]$name) {
    try { return ((Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$name" -Name DelayedAutostart -ErrorAction Stop).DelayedAutostart -eq 1) } catch { return $false }
}

function Get-LiveSvc([string]$name) {
    $c = Get-CimInstance Win32_Service -Filter ("Name='{0}'" -f $name.Replace("'", "''")) -ErrorAction Stop
    $d = $false; if ($c.StartMode -eq 'Auto') { $d = Test-DelayedStart $name }
    return [pscustomobject]@{ StartKey = (Get-StartKey $c.StartMode $d); State = $c.State }
}

function Get-SvcPolicy($s, [string]$exe, [string]$pub, [string]$startKey) {
    $base = ($s.Name -replace '_[0-9a-fA-F]{4,8}$', '').ToLower()
    $inWin = ($exe -and $exe.StartsWith($env:windir, [StringComparison]::OrdinalIgnoreCase))
    $third = ($exe -and -not $inWin -and $pub -notmatch 'Microsoft')
    $text = "$($s.Name) $($s.DisplayName) $exe $pub"
    $r = @{ Protected = $true; Reason = ''; Category = ''; Advice = '' }
    if ($script:SvcOptional.ContainsKey($base)) {
        $r.Protected = $false; $r.Category = 'İsteğe bağlı: ' + $script:SvcOptional[$base]
        if ($base -like '*print*' -or $base -eq 'spooler') {
            if ($script:HasPrinter) { $r.Advice = 'Yazıcı bulundu, durdurmanız önerilmez' } else { $r.Advice = 'Yazıcı yok: durdurulabilir' }
        } else { $r.Advice = 'Kullanmıyorsanız durdurulabilir' }
        return $r
    }
    if ($text -match $script:SecRegex) { $r.Reason = 'Güvenlik bileşeni'; return $r }
    if ($script:SvcProtect -contains $base) { $r.Reason = 'Kritik Windows servisi'; return $r }
    if (-not $third) { $r.Reason = 'Windows servisi'; return $r }
    if ($text -match $script:SvcCriticalRegex) { $r.Reason = 'Ağ/ses/sürücü servisi'; return $r }
    $r.Protected = $false
    if ($text -match 'update|updater|helper|telemetry|crash|agent|assistant') { $r.Category = 'Üçüncü taraf: yardımcı/güncelleyici' } else { $r.Category = 'Üçüncü taraf' }
    if ($startKey -in 'Automatic', 'AutomaticDelayed') { $r.Advice = 'Otomatik başlıyor: kullanıyor musunuz?' } else { $r.Advice = 'İsteğe bağlı başlıyor' }
    return $r
}

function Update-ServiceList {
    $form.Cursor = 'WaitCursor'; $lblSvc.Text = '  Servisler okunuyor...'; $form.Refresh()
    try {
        $script:HasPrinter = (@(Get-CimInstance Win32_Printer -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch 'PDF|XPS|OneNote|Fax|Document Writer|Microsoft Print|Send To' }).Count -gt 0)
        $pidCount = @{}
        $list = foreach ($s in Get-CimInstance Win32_Service) {
            $delayed = $false; if ($s.StartMode -eq 'Auto') { $delayed = Test-DelayedStart $s.Name }
            $key = Get-StartKey $s.StartMode $delayed
            $exe = Resolve-ExePath $s.PathName
            $pub = if ($exe) { Get-Publisher $exe } else { '' }
            $pol = Get-SvcPolicy $s $exe $pub $key
            if ($s.ProcessId -gt 0) { $pidCount[[int]$s.ProcessId] = 1 + [int]$pidCount[[int]$s.ProcessId] }
            [pscustomobject]@{
                Name = $s.Name; Display = $s.DisplayName; Desc = $s.Description; State = $s.State; StartKey = $key
                Pid = [int]$s.ProcessId; Exe = $exe; Publisher = $pub
                Protected = $pol.Protected; Reason = $pol.Reason; Category = $pol.Category; Advice = $pol.Advice
            }
        }
        $script:Svcs = @($list); $script:PidCount = $pidCount; $script:SvcLoaded = $true
        Show-ServiceGrid
    } catch {
        $lblSvc.Text = '  Hata: ' + $_.Exception.Message
        Write-Log ('Servis listesi hatası: ' + $_.Exception.Message)
    } finally { $form.Cursor = 'Default' }
}

function Show-ServiceGrid {
    $gridSvc.Rows.Clear()
    $items = @($script:Svcs | Where-Object { (-not $chkSvcRun.Checked -or $_.State -eq 'Running') -and (-not $chkSvcMan.Checked -or -not $_.Protected) })
    foreach ($it in $items) {
        $stateTr = switch ($it.State) { 'Running' { 'Çalışıyor' } 'Stopped' { 'Durdu' } default { $it.State } }
        $procText = ''; $cpu = $null; $ram = $null
        if ($it.Pid -gt 0) {
            $shared = ''; if ($script:PidCount[$it.Pid] -gt 1) { $shared = ', paylaşımlı' }
            $procText = '{0} (PID {1}{2})' -f [IO.Path]::GetFileName($it.Exe), $it.Pid, $shared
            if ($script:SnapByPid.ContainsKey($it.Pid)) { $cpu = $script:SnapByPid[$it.Pid].Cpu; $ram = $script:SnapByPid[$it.Pid].WsMB }
        }
        $prot = if ($it.Protected) { "Korumalı: $($it.Reason)" } else { $it.Category }
        $i = $gridSvc.Rows.Add([object[]]@($it.Name, $it.Display, $stateTr, $script:StartText[$it.StartKey], $cpu, $ram, $procText, $prot, $it.Advice, $it.Desc))
        $row = $gridSvc.Rows[$i]; $row.Tag = $it
        if ($it.Protected) { $row.DefaultCellStyle.BackColor = [Drawing.Color]::Gainsboro }
        elseif ($it.Advice -like '*durdurulabilir*' -and $it.Advice -notlike 'Yazıcı bulundu*') { $row.DefaultCellStyle.BackColor = [Drawing.Color]::LightYellow }
    }
    $run = @($script:Svcs | Where-Object { $_.State -eq 'Running' }).Count
    $man = @($script:Svcs | Where-Object { -not $_.Protected }).Count
    $lblSvc.Text = "  Toplam: $($script:Svcs.Count)  |  Çalışan: $run  |  Yönetilebilir: $man  |  Gösterilen: $($items.Count)  |  CPU/RAM değerleri servisin çalıştığı işleme aittir; svchost paylaşımlı olabilir."
}

function Show-ServiceUsage {
    if (-not $script:SvcLoaded) { Update-ServiceList; return }
    foreach ($row in $gridSvc.Rows) {
        $it = $row.Tag
        if ($it -and $it.Pid -gt 0 -and $script:SnapByPid.ContainsKey($it.Pid)) {
            $sn = $script:SnapByPid[$it.Pid]
            $row.Cells[4].Value = $sn.Cpu; $row.Cells[5].Value = $sn.WsMB
        }
    }
}

function Read-SvcBackup {
    if (Test-Path -LiteralPath $SvcBackupFile) {
        try {
            $x = Get-Content -LiteralPath $SvcBackupFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -eq $x) { return @() }
            return @($x | ForEach-Object { $_ })
        } catch {}
    }
    return @()
}
function Save-SvcBackup($recs) { ConvertTo-Json -InputObject @($recs) -Depth 4 | Set-Content -LiteralPath $SvcBackupFile -Encoding UTF8 }

function Add-SvcBackup($name, $display, $op, $live, $newKey) {
    $rec = [pscustomobject]@{
        Id = [guid]::NewGuid().ToString(); Zaman = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); Ad = $name; Gorunen = $display
        Islem = $op; OncekiBaslangic = $live.StartKey; OncekiDurum = $live.State; YeniBaslangic = $newKey; GeriYuklendi = $false
    }
    Save-SvcBackup (@(Read-SvcBackup) + $rec)
}

function Set-SvcStartType([string]$name, [string]$key) {
    $val = switch ($key) { 'Automatic' { 'auto' } 'AutomaticDelayed' { 'delayed-auto' } 'Manual' { 'demand' } 'Disabled' { 'disabled' } default { $null } }
    if (-not $val) { throw "Desteklenmeyen başlangıç türü: $key" }
    $out = & sc.exe config $name start= $val 2>&1
    if ($LASTEXITCODE -ne 0) { throw (($out | Out-String).Trim()) }
}

function Get-SelectedSvcs { @($gridSvc.SelectedRows | ForEach-Object { $_.Tag } | Where-Object { $_ }) }

function Split-SvcSelection($sel) {
    $blocked = @($sel | Where-Object { $_.Protected })
    if ($blocked.Count -gt 0) {
        [L10nMsg]::Show("Şu servisler korumalıdır, değiştirilemez:`n`n" + (($blocked | ForEach-Object { "$($_.Name): $($_.Reason)" }) -join "`n"), 'Korumalı servisler') | Out-Null
    }
    return @($sel | Where-Object { -not $_.Protected })
}

function Stop-SelectedSvcs {
    $sel = Get-SelectedSvcs
    if ($sel.Count -eq 0) { [L10nMsg]::Show('Önce listeden servis seçin.', 'WinOpt Suite - Developed by Leone') | Out-Null; return }
    $ok = Split-SvcSelection $sel
    if ($ok.Count -eq 0) { return }
    if ($ok.Count -gt 5) { [L10nMsg]::Show('Güvenlik için tek seferde en fazla 5 servis durdurulabilir.', 'WinOpt Suite - Developed by Leone') | Out-Null; return }
    $msg = "Şu servisler durdurulacak (başlangıç türleri değişmez, yeniden başlatmada tekrar açılabilir):`n`n" + (($ok | ForEach-Object { "$($_.Name) - $($_.Display)" }) -join "`n") + "`n`nDevam edilsin mi?"
    if ([L10nMsg]::Show($msg, 'Servisleri durdur', 'YesNo', 'Warning') -ne 'Yes') { return }
    $done = 0; $fail = @()
    foreach ($it in $ok) {
        try {
            $live = Get-LiveSvc $it.Name
            if ($live.State -ne 'Running') { continue }
            Stop-Service -Name $it.Name -ErrorAction Stop
            (Get-Service -Name $it.Name).WaitForStatus('Stopped', [TimeSpan]::FromSeconds(20))
            Add-SvcBackup $it.Name $it.Display 'Durduruldu' $live $live.StartKey
            Write-Log "Servis durduruldu: $($it.Name)"; $done++
        } catch { $fail += "$($it.Name): $($_.Exception.Message)"; Write-Log "Servis durdurma hatası $($it.Name): $($_.Exception.Message)" }
    }
    Update-ServiceList
    $m = "$done servis durduruldu."
    if ($fail.Count) { $m += "`n`nBaşarısız (bağımlı servisler veya yetki):`n" + ($fail -join "`n") }
    [L10nMsg]::Show($m, 'WinOpt Suite - Developed by Leone') | Out-Null
}

function Set-SelectedSvcStartType {
    if ($cmbSvcStart.SelectedIndex -lt 0) { [L10nMsg]::Show('Önce yeni başlangıç türünü seçin.', 'WinOpt Suite - Developed by Leone') | Out-Null; return }
    $newKey = $script:StartKeys[$cmbSvcStart.SelectedIndex]
    $sel = Get-SelectedSvcs
    if ($sel.Count -eq 0) { [L10nMsg]::Show('Önce listeden servis seçin.', 'WinOpt Suite - Developed by Leone') | Out-Null; return }
    $ok = Split-SvcSelection $sel
    if ($ok.Count -eq 0) { return }
    if ($ok.Count -gt 5) { [L10nMsg]::Show('Güvenlik için tek seferde en fazla 5 servis değiştirilebilir.', 'WinOpt Suite - Developed by Leone') | Out-Null; return }
    $msg = "Şu servislerin başlangıç türü '$($script:StartText[$newKey])' yapılacak:`n`n" + (($ok | ForEach-Object { "$($_.Name) (şu an: $($script:StartText[$_.StartKey]))" }) -join "`n") + "`n`nÖnceki ayar kaydedilir ve geri yüklenebilir. Devam edilsin mi?"
    if ([L10nMsg]::Show($msg, 'Başlangıç türünü değiştir', 'YesNo', 'Warning') -ne 'Yes') { return }
    $done = 0; $fail = @()
    foreach ($it in $ok) {
        try {
            $live = Get-LiveSvc $it.Name
            if ($live.StartKey -eq $newKey) { continue }
            Set-SvcStartType $it.Name $newKey
            Add-SvcBackup $it.Name $it.Display 'Başlangıç türü değiştirildi' $live $newKey
            Write-Log "Servis başlangıç türü: $($it.Name) $($live.StartKey) -> $newKey"; $done++
        } catch { $fail += "$($it.Name): $($_.Exception.Message)"; Write-Log "Başlangıç türü hatası $($it.Name): $($_.Exception.Message)" }
    }
    Update-ServiceList
    $m = "$done servis güncellendi."
    if ($fail.Count) { $m += "`n`nBaşarısız:`n" + ($fail -join "`n") }
    [L10nMsg]::Show($m, 'WinOpt Suite - Developed by Leone') | Out-Null
}

function Restore-Svcs([string[]]$names) {
    $recs = @(Read-SvcBackup)
    $pending = @(for ($i = $recs.Count - 1; $i -ge 0; $i--) { if ($recs[$i].GeriYuklendi -ne $true) { $recs[$i] } })
    if ($names) { $pending = @($pending | Where-Object { $names -contains $_.Ad }) }
    if ($pending.Count -eq 0) { [L10nMsg]::Show('Geri yüklenecek kayıt yok.', 'WinOpt Suite - Developed by Leone') | Out-Null; return }
    $doneNames = @{}; $toRestore = @()
    foreach ($r in $pending) { if ($names) { if ($doneNames.ContainsKey($r.Ad)) { continue }; $doneNames[$r.Ad] = $true }; $toRestore += $r }
    $msg = "$($toRestore.Count) değişiklik geri yüklenecek (en yeniden eskiye):`n`n" + (($toRestore | ForEach-Object { "$($_.Ad): $($_.Islem) -> önceki: $($script:StartText[$_.OncekiBaslangic]), $($_.OncekiDurum)" }) -join "`n") + "`n`nDevam edilsin mi?"
    if ([L10nMsg]::Show($msg, 'Geri yükle', 'YesNo', 'Question') -ne 'Yes') { return }
    $done = 0; $fail = @()
    foreach ($r in $toRestore) {
        try {
            if ($r.OncekiBaslangic -ne 'Other') { Set-SvcStartType $r.Ad $r.OncekiBaslangic }
            if ($r.OncekiDurum -eq 'Running') { if ((Get-Service -Name $r.Ad).Status -ne 'Running') { Start-Service -Name $r.Ad -ErrorAction Stop } }
            $r.GeriYuklendi = $true; $done++
            Write-Log "Servis geri yüklendi: $($r.Ad)"
        } catch { $fail += "$($r.Ad): $($_.Exception.Message)" }
    }
    Save-SvcBackup $recs
    Update-ServiceList
    $m = "$done değişiklik geri yüklendi."
    if ($fail.Count) { $m += "`n`nBaşarısız:`n" + ($fail -join "`n") }
    [L10nMsg]::Show($m, 'WinOpt Suite - Developed by Leone') | Out-Null
}

New-Btn $barSvc 'Yenile' 70 { Update-ServiceList }
New-Btn $barSvc 'Seçili Servisi Durdur' 150 { Stop-SelectedSvcs }
$cmbSvcStart = New-Object Windows.Forms.ComboBox
$cmbSvcStart.DropDownStyle = 'DropDownList'; $cmbSvcStart.Width = 150; $cmbSvcStart.Margin = New-Object Windows.Forms.Padding(8, 5, 0, 0)
[void]$cmbSvcStart.Items.AddRange(@('Otomatik', 'Otomatik (Gecikmeli)', 'Elle', 'Devre dışı'))
$barSvc.Controls.Add($cmbSvcStart)
New-Btn $barSvc 'Başlangıç Türünü Uygula' 170 { Set-SelectedSvcStartType }
New-Btn $barSvc 'Seçiliyi Geri Yükle' 130 { Restore-Svcs @((Get-SelectedSvcs | ForEach-Object { $_.Name })) }
New-Btn $barSvc 'Tümünü Geri Yükle' 130 { Restore-Svcs $null }
New-Btn $barSvc 'Değişiklik Geçmişi' 130 {
    $recs = @(Read-SvcBackup)
    $tmp = Join-Path $AppDir 'servis-degisiklikleri.csv'
    if ($recs.Count -gt 0) { $recs | Select-Object Zaman, Ad, Islem, OncekiBaslangic, OncekiDurum, YeniBaslangic, GeriYuklendi | Export-Csv -LiteralPath $tmp -NoTypeInformation -Encoding UTF8 }
    Show-CsvDialog $tmp 'Servis değişiklik geçmişi'
}
$chkSvcRun = New-Chk $barSvc 'Yalnızca çalışanlar' $true { if ($script:SvcLoaded) { Show-ServiceGrid } }
$chkSvcMan = New-Chk $barSvc 'Yalnızca yönetilebilir olanlar' $false { if ($script:SvcLoaded) { Show-ServiceGrid } }
