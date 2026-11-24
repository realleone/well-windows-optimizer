$RegBackupRoot = Join-Path $AppDir 'registry-yedekleri'

$tabReg = New-Object Windows.Forms.TabPage
$tabReg.Text = 'Kayıt Defteri'
[void]$tabs.TabPages.Add($tabReg)

$gridReg = New-StdGrid @(
    @('Kategori', 210), @('Ad', 180), @('Risk', 70), @('Kayıt yolu', 430), @('Değer', 120), @('Eksik hedef', 300), @('Açıklama', 560))
$tabReg.Controls.Add($gridReg)
$barReg = New-Bar
$barReg.Height = 46
$tabReg.Controls.Add($barReg)
$lblReg = New-StatusLabel
$lblReg.Height = 48
$lblReg.Text = '  Taramak için "Tara" düğmesine basın.' + [Environment]::NewLine + '  Not: Registry temizliği CPU/RAM performansını doğrudan artırmaz. Gerçek iyileştirme için Başlangıç, İşlemler ve Servisler sekmelerini kullanın.'
$tabReg.Controls.Add($lblReg)

$script:RegItems = @()

function Open-RegKey([string]$hive, [string]$path, [bool]$write = $false) {
    $root = if ($hive -eq 'HKCU') { [Microsoft.Win32.Registry]::CurrentUser } else { [Microsoft.Win32.Registry]::LocalMachine }
    try { return $root.OpenSubKey($path, $write) } catch { return $null }
}

function Test-PathMissing([string]$p) {
    if (-not $p) { return $false }
    $p = [Environment]::ExpandEnvironmentVariables($p.Trim().Trim('"'))
    if ($p -notmatch '^[A-Za-z]:\\') { return $false }
    if (-not (Test-Path -LiteralPath ([IO.Path]::GetPathRoot($p)))) { return $false }
    return (-not (Test-Path -LiteralPath $p))
}

function Test-TargetMissing([string]$cmd) {
    if ([string]::IsNullOrWhiteSpace($cmd)) { return $null }
    $exe = Resolve-ExePath $cmd
    if ($exe -and (Test-PathMissing $exe)) { return $exe.Trim('"') }
    return $null
}

function Get-RegRisk([string]$cat, [string]$target, [string]$text) {
    if ($target -and $target.StartsWith($env:windir, [StringComparison]::OrdinalIgnoreCase)) { return 'Yüksek' }
    if ("$target $text" -match ($script:SecRegex + '|Windows Defender|Windows Security|\\WindowsApps\\|\\Microsoft\\Edge')) { return 'Yüksek' }
    if ($cat -like '*Paylaşılan DLL*') { return 'Orta' }
    return 'Düşük'
}

function New-RegItem($cat, $name, $hive, $key, $value, [bool]$isKey, $target, $desc) {
    $risk = Get-RegRisk $cat $target "$name $key"
    [pscustomobject]@{
        Category = $cat; Name = $name; Hive = $hive; Key = $key; Value = $value; IsKey = $isKey
        Target = $target; Desc = $desc; Risk = $risk; Removable = ($risk -ne 'Yüksek')
    }
}

function Set-RegProgress([string]$t) { $lblReg.Text = "  $t"; [Windows.Forms.Application]::DoEvents() }

function Find-OrphanUninstall {
    Set-RegProgress 'Kaldırılmış uygulama kalıntıları taranıyor...'
    $roots = @(@('HKLM', 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'),
               @('HKLM', 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'),
               @('HKCU', 'Software\Microsoft\Windows\CurrentVersion\Uninstall'))
    foreach ($r in $roots) {
        $k = Open-RegKey $r[0] $r[1]; if (-not $k) { continue }
        foreach ($sub in $k.GetSubKeyNames()) {
            try {
                $s = $k.OpenSubKey($sub)
                $name = [string]$s.GetValue('DisplayName'); $us = [string]$s.GetValue('UninstallString')
                $loc = [string]$s.GetValue('InstallLocation'); $sys = $s.GetValue('SystemComponent')
                $s.Close()
                if (-not $name -or $sys -eq 1 -or $us -match '(?i)msiexec') { continue }
                $miss = Test-TargetMissing $us
                if (-not $miss) { continue }
                if ($loc -and -not (Test-PathMissing $loc)) { continue }
                New-RegItem 'Kaldırılmış uygulama kalıntısı' $name $r[0] "$($r[1])\$sub" $null $true $miss `
                    "'$name' için programlar listesinde kayıt duruyor, ancak kaldırıcı dosyası bulunamadı. Uygulama büyük olasılıkla elle silinmiş."
            } catch {}
        }
        $k.Close()
    }
}

function Find-InvalidStartup {
    Set-RegProgress 'Geçersiz başlangıç girdileri taranıyor...'
    $roots = @(@('HKCU', 'Software\Microsoft\Windows\CurrentVersion\Run'), @('HKLM', 'SOFTWARE\Microsoft\Windows\CurrentVersion\Run'),
               @('HKLM', 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'),
               @('HKCU', 'Software\Microsoft\Windows\CurrentVersion\RunOnce'), @('HKLM', 'SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'))
    foreach ($r in $roots) {
        $k = Open-RegKey $r[0] $r[1]; if (-not $k) { continue }
        foreach ($n in $k.GetValueNames()) {
            if ($n -eq '') { continue }
            $cmd = [string]$k.GetValue($n, '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            $miss = Test-TargetMissing $cmd
            if ($miss) {
                New-RegItem 'Geçersiz başlangıç girdisi' $n $r[0] $r[1] $n $false $miss `
                    "Windows açılışında çalıştırılmak istenen dosya bulunamadı; girdi her açılışta boşuna denenir. Çalışan başlangıç girdilerini Başlangıç sekmesinden yönetin."
            }
        }
        $k.Close()
    }
}

function Find-BrokenAppPaths {
    Set-RegProgress 'Bozuk uygulama yolları taranıyor...'
    $roots = @(@('HKLM', 'SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths'),
               @('HKLM', 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths'),
               @('HKCU', 'Software\Microsoft\Windows\CurrentVersion\App Paths'))
    foreach ($r in $roots) {
        $k = Open-RegKey $r[0] $r[1]; if (-not $k) { continue }
        foreach ($sub in $k.GetSubKeyNames()) {
            try {
                $s = $k.OpenSubKey($sub); $def = [string]$s.GetValue(''); $s.Close()
                $miss = Test-TargetMissing $def
                if ($miss) {
                    New-RegItem 'Bozuk uygulama yolu' $sub $r[0] "$($r[1])\$sub" $null $true $miss `
                        "'$sub' için kayıtlı uygulama yolu geçersiz; Çalıştır penceresi veya kısayollar bu kaydı kullanmaya çalışırsa hata verir."
                }
            } catch {}
        }
        $k.Close()
    }
}

function Find-UnusedConfig {
    Set-RegProgress 'Kullanılmayan uygulama yapılandırmaları taranıyor...'
    foreach ($r in @(@('HKCU', 'Software\Classes\Applications'), @('HKLM', 'SOFTWARE\Classes\Applications'))) {
        $k = Open-RegKey $r[0] $r[1]; if (-not $k) { continue }
        foreach ($sub in $k.GetSubKeyNames()) {
            try {
                $c = $k.OpenSubKey("$sub\shell\open\command")
                if (-not $c) { continue }
                $cmd = [string]$c.GetValue(''); $c.Close()
                $miss = Test-TargetMissing $cmd
                if ($miss) {
                    New-RegItem 'Kullanılmayan uygulama yapılandırması' $sub $r[0] "$($r[1])\$sub" $null $true $miss `
                        "'Birlikte aç' listesinde kalmış uygulama kaydı; çalıştırılacak dosya artık yok."
                }
            } catch {}
        }
        $k.Close()
    }
    Set-RegProgress 'Paylaşılan DLL kayıtları taranıyor...'
    $k = Open-RegKey 'HKLM' 'SOFTWARE\Microsoft\Windows\CurrentVersion\SharedDLLs'
    if ($k) {
        $i = 0
        foreach ($n in $k.GetValueNames()) {
            $i++; if ($i % 200 -eq 0) { [Windows.Forms.Application]::DoEvents() }
            if (Test-PathMissing $n) {
                New-RegItem 'Paylaşılan DLL kaydı (kullanılmayan yapılandırma)' ([IO.Path]::GetFileName($n)) 'HKLM' 'SOFTWARE\Microsoft\Windows\CurrentVersion\SharedDLLs' $n $false $n `
                    'Paylaşılan DLL sayaç kaydı, ancak dosya diskte yok. Orta risk: kaldırıcıların sayaç mantığıyla ilgilidir, yalnızca emin olduğunuzda kaldırın.'
            }
        }
        $k.Close()
    }
}

function Start-RegScan {
    $form.Cursor = 'WaitCursor'; $script:Timer.Stop()
    try {
        $items = @()
        $items += @(Find-OrphanUninstall)
        $items += @(Find-InvalidStartup)
        $items += @(Find-BrokenAppPaths)
        $items += @(Find-UnusedConfig)
        $script:RegItems = $items
        Show-RegGrid
    } catch {
        $lblReg.Text = '  Tarama hatası: ' + $_.Exception.Message
        Write-Log ('Registry tarama hatası: ' + $_.Exception.Message)
    } finally { $form.Cursor = 'Default'; $script:Timer.Start() }
}

function Show-RegGrid {
    $gridReg.Rows.Clear()
    $items = @($script:RegItems | Where-Object { -not $chkRegHideHigh.Checked -or $_.Removable })
    foreach ($it in $items) {
        $i = $gridReg.Rows.Add([object[]]@($it.Category, $it.Name, $it.Risk, "$($it.Hive)\$($it.Key)", $it.Value, $it.Target, $it.Desc))
        $row = $gridReg.Rows[$i]; $row.Tag = $it
        switch ($it.Risk) {
            'Düşük'  { $row.DefaultCellStyle.BackColor = [Drawing.Color]::Honeydew }
            'Orta'   { $row.DefaultCellStyle.BackColor = [Drawing.Color]::LightYellow }
            'Yüksek' { $row.DefaultCellStyle.BackColor = [Drawing.Color]::Gainsboro }
        }
    }
    $lo = @($script:RegItems | Where-Object { $_.Risk -eq 'Düşük' }).Count
    $mid = @($script:RegItems | Where-Object { $_.Risk -eq 'Orta' }).Count
    $hi = @($script:RegItems | Where-Object { $_.Risk -eq 'Yüksek' }).Count
    $lblReg.Text = "  Bulgu: $($script:RegItems.Count) (gösterilen $($items.Count))  |  Düşük: $lo  |  Orta: $mid  |  Yüksek (yalnızca inceleme): $hi" + [Environment]::NewLine +
        '  Not: Registry temizliği CPU/RAM performansını doğrudan artırmaz. Gerçek iyileştirme için Başlangıç, İşlemler ve Servisler sekmelerini kullanın.'
}

function Remove-RegItem($it) {
    if ($it.IsKey) {
        $idx = $it.Key.LastIndexOf('\')
        $k = Open-RegKey $it.Hive $it.Key.Substring(0, $idx) $true
        if (-not $k) { throw 'Üst anahtar açılamadı (zaten silinmiş olabilir).' }
        try { $k.DeleteSubKeyTree($it.Key.Substring($idx + 1), $true) } finally { $k.Close() }
    } else {
        $k = Open-RegKey $it.Hive $it.Key $true
        if (-not $k) { throw 'Anahtar açılamadı (zaten silinmiş olabilir).' }
        try { $k.DeleteValue($it.Value, $true) } finally { $k.Close() }
    }
}

function Remove-SelectedRegItems {
    $sel = @($gridReg.SelectedRows | ForEach-Object { $_.Tag } | Where-Object { $_ })
    if ($sel.Count -eq 0) { [L10nMsg]::Show('Önce listeden kayıt seçin.', 'WinOpt Suite - Developed by Leone') | Out-Null; return }
    $blocked = @($sel | Where-Object { -not $_.Removable })
    $ok = @($sel | Where-Object { $_.Removable })
    if ($blocked.Count -gt 0) {
        [L10nMsg]::Show("Yüksek riskli (Windows/güvenlik ile ilgili) kayıtlar yalnızca incelenir, kaldırılamaz:`n`n" + (($blocked | Select-Object -First 15 | ForEach-Object { $_.Name }) -join "`n"), 'Korumalı kayıtlar') | Out-Null
    }
    if ($ok.Count -eq 0) { return }
    $mid = @($ok | Where-Object { $_.Risk -eq 'Orta' }).Count
    $msg = "$($ok.Count) kayıt kaldırılacak.`n`n" + (($ok | Group-Object Category | ForEach-Object { "$($_.Name): $($_.Count)" }) -join "`n") +
        "`n`nSilmeden önce ilgili anahtarların .reg yedeği alınır; yedek alınamayan kayıt silinmez. Yedeği 'Yedeği Geri Yükle' ile geri getirebilirsiniz."
    if ($mid -gt 0) { $msg += "`n`nDİKKAT: $mid kayıt ORTA risklidir (paylaşılan DLL kaydı)." }
    $msg += "`n`nDevam edilsin mi?"
    if ([L10nMsg]::Show($msg, 'Kayıt defteri temizliğini onayla', 'YesNo', 'Warning') -ne 'Yes') { return }

    $dir = Join-Path $RegBackupRoot (Get-Date -Format 'yyyyMMdd-HHmmss')
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $exported = @{}; $manifest = @(); $done = 0; $fail = @()
    foreach ($it in $ok) {
        try {
            $fullKey = "$($it.Hive)\$($it.Key)"
            if (-not $exported.ContainsKey($fullKey)) {
                $file = Join-Path $dir ('{0:D3}.reg' -f ($exported.Count + 1))
                $null = & reg.exe export $fullKey $file /y 2>&1
                if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $file)) { throw 'Yedek alınamadı, kayıt silinmedi.' }
                $exported[$fullKey] = $file
            }
            Remove-RegItem $it
            $manifest += [pscustomobject]@{
                Zaman = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); Kategori = $it.Category; Ad = $it.Name
                Anahtar = $fullKey; Deger = $it.Value; Yedek = (Split-Path $exported[$fullKey] -Leaf)
            }
            $done++
            Write-Log "Registry kaydı kaldırıldı: $fullKey $($it.Value)"
        } catch {
            $fail += "$($it.Name): $($_.Exception.Message)"
            Write-Log "Registry kaldırma hatası $($it.Name): $($_.Exception.Message)"
        }
    }
    if ($manifest.Count -gt 0) { ConvertTo-Json -InputObject @($manifest) -Depth 3 | Set-Content -LiteralPath (Join-Path $dir 'manifest.json') -Encoding UTF8 }
    else { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
    Start-RegScan
    $m = "$done kayıt kaldırıldı."
    if ($done -gt 0) { $m += "`nYedek: $dir" }
    if ($fail.Count) { $m += "`n`nBaşarısız:`n" + ($fail -join "`n") }
    [L10nMsg]::Show($m, 'WinOpt Suite - Developed by Leone') | Out-Null
}

function Select-RegBackup {
    if (-not (Test-Path -LiteralPath $RegBackupRoot)) { return $null }
    $dirs = @(Get-ChildItem -LiteralPath $RegBackupRoot -Directory | Sort-Object Name -Descending)
    if ($dirs.Count -eq 0) { return $null }
    $f = New-Object Windows.Forms.Form
    $f.Text = 'Geri yüklenecek yedeği seçin'; $f.Size = New-Object Drawing.Size(460, 360); $f.StartPosition = 'CenterParent'
    $lb = New-Object Windows.Forms.ListBox; $lb.Dock = 'Fill'
    foreach ($d in $dirs) {
        $n = 0; $m = Join-Path $d.FullName 'manifest.json'
        if (Test-Path -LiteralPath $m) { try { $x = Get-Content -LiteralPath $m -Raw -Encoding UTF8 | ConvertFrom-Json; $n = @($x | ForEach-Object { $_ }).Count } catch {} }
        [void]$lb.Items.Add(('{0}   -   {1} kayıt' -f $d.Name, $n))
    }
    $pan = New-Object Windows.Forms.FlowLayoutPanel; $pan.Dock = 'Bottom'; $pan.Height = 44; $pan.FlowDirection = 'RightToLeft'
    $bc = New-Object Windows.Forms.Button; $bc.Text = 'İptal'; $bc.DialogResult = 'Cancel'
    $bo = New-Object Windows.Forms.Button; $bo.Text = 'Geri Yükle'; $bo.DialogResult = 'OK'
    $pan.Controls.Add($bc); $pan.Controls.Add($bo)
    $f.Controls.Add($lb); $f.Controls.Add($pan); $f.AcceptButton = $bo; $f.CancelButton = $bc
    $res = $f.ShowDialog($form)
    if ($res -eq 'OK' -and $lb.SelectedIndex -ge 0) { return $dirs[$lb.SelectedIndex].FullName }
    return $null
}

function Restore-RegBackup {
    $dir = Select-RegBackup
    if (-not $dir) { [L10nMsg]::Show('Yedek seçilmedi veya henüz yedek yok.', 'WinOpt Suite - Developed by Leone') | Out-Null; return }
    $files = @(Get-ChildItem -LiteralPath $dir -Filter *.reg)
    if ([L10nMsg]::Show("$($files.Count) yedek dosyası içe aktarılacak. Silinen kayıtlar yeniden oluşturulur.`n`n$dir`n`nDevam edilsin mi?", 'Yedeği geri yükle', 'YesNo', 'Question') -ne 'Yes') { return }
    $ok = 0; $fail = @()
    foreach ($f in $files) {
        $null = & reg.exe import $f.FullName 2>&1
        if ($LASTEXITCODE -eq 0) { $ok++ } else { $fail += $f.Name }
    }
    Write-Log "Registry yedeği geri yüklendi: $dir ($ok/$($files.Count))"
    Start-RegScan
    $m = "$ok/$($files.Count) yedek dosyası geri yüklendi."
    if ($fail.Count) { $m += "`n`nBaşarısız: " + ($fail -join ', ') }
    [L10nMsg]::Show($m, 'WinOpt Suite - Developed by Leone') | Out-Null
}

New-Btn $barReg 'Tara' 80 { Start-RegScan }
New-Btn $barReg 'Seçili Kayıtları Yedekle ve Kaldır' 230 { Remove-SelectedRegItems }
New-Btn $barReg 'Yedeği Geri Yükle' 140 { Restore-RegBackup }
New-Btn $barReg 'Yedek Klasörünü Aç' 140 {
    New-Item -ItemType Directory -Path $RegBackupRoot -Force | Out-Null
    Start-Process explorer.exe -ArgumentList "`"$RegBackupRoot`""
}
New-Btn $barReg 'CSV Raporu' 90 {
    $dlg = New-Object Windows.Forms.SaveFileDialog; $dlg.Filter = 'CSV (*.csv)|*.csv'; $dlg.FileName = 'registry-raporu.csv'
    if ($dlg.ShowDialog() -eq 'OK') {
        $script:RegItems | Select-Object Category, Name, Risk, Hive, Key, Value, Target, Desc |
            Export-Csv -LiteralPath $dlg.FileName -NoTypeInformation -Encoding UTF8
    }
}
$chkRegHideHigh = New-Chk $barReg 'Yüksek riskli (yalnızca inceleme) kayıtları gizle' $false { if ($script:RegItems.Count -gt 0) { Show-RegGrid } }
