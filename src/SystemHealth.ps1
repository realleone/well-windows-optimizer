$tabHealth = New-Object Windows.Forms.TabPage
$tabHealth.Text = 'Sistem Sağlığı'
[void]$tabs.TabPages.Add($tabHealth)

$gridHealth = New-StdGrid @(@('Kategori', 130), @('Bilgi', 220), @('Değer', 620), @('Durum', 110))
$tabHealth.Controls.Add($gridHealth)
$barHealth = New-Bar
$barHealth.Height = 46
$tabHealth.Controls.Add($barHealth)
$lblHealth = New-StatusLabel
$tabHealth.Controls.Add($lblHealth)

$script:HealthLoaded = $false
$script:HealthList = New-Object 'System.Collections.Generic.List[object]'
$script:HealthRowMap = @{}

function Add-HRow([string]$key, [string]$cat, [string]$name, [string]$value, [string]$status) {
    $script:HealthList.Add([pscustomobject]@{ Key = $key; Cat = $cat; Name = $name; Value = $value; Status = $status })
}

function Get-HwMonSensors {
    # LibreHardwareMonitor / OpenHardwareMonitor çalışıyorsa WMI üzerinden gerçek sensör verisi sunar.
    $out = @()
    foreach ($ns in @('root\LibreHardwareMonitor', 'root\OpenHardwareMonitor')) {
        try {
            $s = @(Get-CimInstance -Namespace $ns -ClassName Sensor -Filter "SensorType='Temperature'" -ErrorAction Stop)
            foreach ($x in $s) {
                if ($null -ne $x.Value -and [double]$x.Value -gt 0 -and [double]$x.Value -lt 130) {
                    $out += [pscustomobject]@{ Name = [string]$x.Name; Id = [string]$x.Identifier; Value = [double]$x.Value; Src = ($ns -replace '^root\\', '') }
                }
            }
            if ($out.Count -gt 0) { break }
        } catch {}
    }
    return $out
}

function Get-CpuTempInfo {
    $hw = @(Get-HwMonSensors | Where-Object { $_.Id -match '/(intelcpu|amdcpu|cpu)' })
    if ($hw.Count -gt 0) {
        $pick = $hw | Where-Object { $_.Name -match 'Package|Tctl|Tdie|Core \(Tctl' } | Select-Object -First 1
        if (-not $pick) { $pick = $hw | Sort-Object Value -Descending | Select-Object -First 1 }
        return [pscustomobject]@{ Value = $pick.Value; Text = ('{0:N0} °C ({1}: {2})' -f $pick.Value, $pick.Src, $pick.Name) }
    }
    try {
        $z = @(Get-CimInstance -Namespace 'root\wmi' -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop)
        $vals = @($z | ForEach-Object { [math]::Round(($_.CurrentTemperature / 10.0) - 273.15, 1) } | Where-Object { $_ -gt 10 -and $_ -lt 120 })
        if ($vals.Count -gt 0) {
            $m = ($vals | Measure-Object -Maximum).Maximum
            return [pscustomobject]@{ Value = $m; Text = ('{0:N0} °C (ACPI termal bölge; doğrudan CPU çekirdek sıcaklığı olmayabilir)' -f $m) }
        }
    } catch {}
    return $null
}

function Get-GpuTempInfo([string]$gpuName) {
    if ($gpuName -match 'NVIDIA') {
        $exe = $null
        $cmd = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
        if ($cmd) { $exe = $cmd.Source }
        if (-not $exe) {
            foreach ($p in @("$env:ProgramFiles\NVIDIA Corporation\NVSMI\nvidia-smi.exe", "$env:windir\System32\nvidia-smi.exe")) { if (Test-Path -LiteralPath $p) { $exe = $p; break } }
        }
        if ($exe) {
            try {
                $o = (& $exe --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>$null | Select-Object -First 1)
                $t = 0.0
                if ([double]::TryParse(([string]$o).Trim(), [ref]$t) -and $t -gt 0 -and $t -lt 130) {
                    return [pscustomobject]@{ Value = $t; Text = ('{0:N0} °C (nvidia-smi)' -f $t) }
                }
            } catch {}
        }
    }
    $hw = @(Get-HwMonSensors | Where-Object { $_.Id -match '/(gpu|nvidiagpu|atigpu|intelgpu)' })
    if ($hw.Count -gt 0) {
        $pick = $hw | Where-Object { $_.Name -match 'GPU Core|Core' } | Select-Object -First 1
        if (-not $pick) { $pick = $hw | Sort-Object Value -Descending | Select-Object -First 1 }
        return [pscustomobject]@{ Value = $pick.Value; Text = ('{0:N0} °C ({1}: {2})' -f $pick.Value, $pick.Src, $pick.Name) }
    }
    return $null
}

function Update-Health {
    $form.Cursor = 'WaitCursor'; $lblHealth.Text = '  Donanım ve sistem bilgisi okunuyor...'; $form.Refresh()
    $script:HealthList = New-Object 'System.Collections.Generic.List[object]'
    try {
        # --- İşlemci ---
        $cpu = @(Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue)
        if ($cpu.Count -gt 0) {
            $c = $cpu[0]
            Add-HRow 'cpu' 'İşlemci' 'İşlemci modeli' ("{0} ({1} çekirdek / {2} mantıksal işlemci)" -f ([string]$c.Name).Trim(), (($cpu | Measure-Object NumberOfCores -Sum).Sum), (($cpu | Measure-Object NumberOfLogicalProcessors -Sum).Sum)) 'Bilgi'
        } else { Add-HRow 'cpu' 'İşlemci' 'İşlemci modeli' 'Veri yok (okunamadı)' 'Veri yok' }

        # --- RAM ---
        $mods = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue)
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
        $totalGB = $null
        if ($cs -and $cs.TotalPhysicalMemory) { $totalGB = [double]$cs.TotalPhysicalMemory / 1GB }
        if ($null -ne $totalGB) {
            $extra = ''
            if ($mods.Count -gt 0) {
                $spd = ($mods | Where-Object { $_.Speed } | Select-Object -First 1).Speed
                $extra = " ({0} modül" -f $mods.Count
                if ($spd) { $extra += ", $spd MHz" }
                $extra += ')'
            }
            Add-HRow 'ramtotal' 'Bellek' 'RAM miktarı' (('{0:N1} GB' -f $totalGB) + $extra) 'Bilgi'
        } else { Add-HRow 'ramtotal' 'Bellek' 'RAM miktarı' 'Veri yok (okunamadı)' 'Veri yok' }
        Add-HRow 'ram' 'Bellek' 'RAM kullanımı' 'Ölçülüyor...' 'Bilgi'

        # --- GPU ---
        $gpus = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.Name })
        $gpuMain = ''
        if ($gpus.Count -gt 0) {
            $i = 0
            foreach ($g in $gpus) {
                $i++
                $drv = ''; if ($g.DriverVersion) { $drv = " (sürücü $($g.DriverVersion))" }
                Add-HRow "gpu$i" 'Ekran kartı' ('GPU modeli' + $(if ($gpus.Count -gt 1) { " $i" } else { '' })) (([string]$g.Name).Trim() + $drv) 'Bilgi'
            }
            $gpuMain = [string]($gpus | Where-Object { $_.Name -match 'NVIDIA|AMD|Radeon|GeForce' } | Select-Object -First 1).Name
            if (-not $gpuMain) { $gpuMain = [string]$gpus[0].Name }
        } else { Add-HRow 'gpu1' 'Ekran kartı' 'GPU modeli' 'Veri yok (okunamadı)' 'Veri yok' }

        # --- Anakart ---
        $bb = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue
        if ($bb -and ($bb.Manufacturer -or $bb.Product)) {
            Add-HRow 'board' 'Anakart' 'Anakart bilgisi' (("{0} {1}" -f $bb.Manufacturer, $bb.Product).Trim()) 'Bilgi'
        } else { Add-HRow 'board' 'Anakart' 'Anakart bilgisi' 'Veri yok (üretici bilgi vermiyor)' 'Veri yok' }

        # --- Diskler ---
        $drives = @(Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue)
        $di = 0
        foreach ($d in $drives) {
            $di++
            $sz = ''; if ($d.Size) { $sz = (' - {0:N0} GB' -f ([double]$d.Size / 1GB)) }
            Add-HRow "diskmodel$di" 'Disk' ('Disk modeli' + $(if ($drives.Count -gt 1) { " $di" } else { '' })) (([string]$d.Model).Trim() + $sz) 'Bilgi'
        }
        if ($drives.Count -eq 0) { Add-HRow 'diskmodel1' 'Disk' 'Disk modeli' 'Veri yok (okunamadı)' 'Veri yok' }

        foreach ($ld in @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction SilentlyContinue)) {
            if (-not $ld.Size) { continue }
            $used = [double]$ld.Size - [double]$ld.FreeSpace
            $pct = $used / [double]$ld.Size * 100
            $st = 'Bilgi'; if ($pct -ge 90) { $st = 'Uyarı' }
            Add-HRow ('disk:' + $ld.DeviceID) 'Disk' ("Doluluk $($ld.DeviceID)") ('{0:N0} GB dolu / {1:N0} GB (%{2:N0}), boş {3:N0} GB' -f ($used / 1GB), ([double]$ld.Size / 1GB), $pct, ([double]$ld.FreeSpace / 1GB)) $st
        }

        $pdisks = @()
        try { $pdisks = @(Get-PhysicalDisk -ErrorAction Stop) } catch {}
        if ($pdisks.Count -gt 0) {
            $pi = 0
            foreach ($pd in $pdisks) {
                $pi++
                $parts = @()
                $st = 'Bilgi'
                if ($pd.HealthStatus) { $parts += "Sağlık: $($pd.HealthStatus)"; if ([string]$pd.HealthStatus -ne 'Healthy') { $st = 'Uyarı' } }
                if ($pd.OperationalStatus) { $parts += "Durum: $((@($pd.OperationalStatus)) -join ', ')" }
                if ($pd.MediaType -and [string]$pd.MediaType -ne 'Unspecified') { $parts += "Tür: $($pd.MediaType)" }
                try {
                    $rc = Get-StorageReliabilityCounter -PhysicalDisk $pd -ErrorAction Stop
                    if ($rc) {
                        if ($null -ne $rc.Temperature -and $rc.Temperature -gt 0) { $parts += ('Sıcaklık: {0} °C' -f $rc.Temperature) }
                        if ($null -ne $rc.Wear) { $parts += ('Aşınma: %{0}' -f $rc.Wear); if ($rc.Wear -ge 90) { $st = 'Uyarı' } }
                        if ($null -ne $rc.PowerOnHours -and $rc.PowerOnHours -gt 0) { $parts += ('Çalışma: {0:N0} saat' -f $rc.PowerOnHours) }
                        if ($null -ne $rc.ReadErrorsUncorrected -and $rc.ReadErrorsUncorrected -gt 0) { $parts += ('Düzeltilemeyen okuma hatası: {0}' -f $rc.ReadErrorsUncorrected); $st = 'Uyarı' }
                    }
                } catch {}
                Add-HRow "diskhealth$pi" 'Disk' ("Disk sağlığı: " + ([string]$pd.FriendlyName).Trim()) ($parts -join '  |  ') $st
            }
        }
        try {
            $fp = @(Get-CimInstance -Namespace 'root\wmi' -ClassName MSStorageDriver_FailurePredictStatus -ErrorAction Stop)
            if ($fp.Count -gt 0) {
                $bad = @($fp | Where-Object { $_.PredictFailure })
                if ($bad.Count -gt 0) { Add-HRow 'smart' 'Disk' 'SMART arıza tahmini' "$($bad.Count) diskte arıza öngörülüyor - verilerinizi yedekleyin" 'Uyarı' }
                else { Add-HRow 'smart' 'Disk' 'SMART arıza tahmini' 'Arıza öngörülmüyor' 'Bilgi' }
            }
        } catch {}
        if (-not ($script:HealthList | Where-Object { $_.Key -like 'diskhealth*' -or $_.Key -eq 'smart' })) {
            Add-HRow 'diskhealth0' 'Disk' 'Disk sağlık verisi' 'Veri yok (disk/sürücü bu verileri sunmuyor)' 'Veri yok'
        }

        # --- Windows ---
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($os) {
            $dv = ''
            try { $dv = [string](Get-ItemPropertyValue -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name DisplayVersion -ErrorAction Stop) } catch {}
            $ver = "{0} (sürüm {1}, derleme {2})" -f ([string]$os.Caption).Trim(), $(if ($dv) { $dv } else { $os.Version }), $os.BuildNumber
            Add-HRow 'win' 'Windows' 'Windows sürümü' $ver 'Bilgi'
            Add-HRow 'arch' 'Windows' 'Sistem mimarisi' ("{0} (işlem: {1})" -f $os.OSArchitecture, $(if ([Environment]::Is64BitProcess) { '64-bit' } else { '32-bit' })) 'Bilgi'
            if ($os.LastBootUpTime) {
                $up = (Get-Date) - $os.LastBootUpTime
                $st = 'Bilgi'; if ($up.TotalDays -ge 14) { $st = 'Uyarı' }
                Add-HRow 'uptime' 'Windows' 'Son başlatma / çalışma süresi' ("{0:yyyy-MM-dd HH:mm}  ({1}g {2}s {3}dk)" -f $os.LastBootUpTime, $up.Days, $up.Hours, $up.Minutes) $st
            }
        } else { Add-HRow 'win' 'Windows' 'Windows sürümü' 'Veri yok (okunamadı)' 'Veri yok' }

        $boot = $null
        try { $boot = (Get-StartupImpact).Boot } catch {}
        if ($boot) {
            $st = 'Bilgi'; if ($boot -ge 90) { $st = 'Uyarı' }
            Add-HRow 'boot' 'Windows' 'Açılış süresi' ("{0} sn (Windows tanılama kaydı, son ölçüm)" -f $boot) $st
        } else { Add-HRow 'boot' 'Windows' 'Açılış süresi' 'Veri yok (Windows tanılama olayı bulunamadı)' 'Veri yok' }

        # --- Sıcaklıklar (yalnızca gerçek sensör verisi) ---
        $ct = Get-CpuTempInfo
        if ($ct) { $st = 'Bilgi'; if ($ct.Value -ge 90) { $st = 'Uyarı' }; Add-HRow 'cputemp' 'Sıcaklık' 'CPU sıcaklığı' $ct.Text $st }
        else { Add-HRow 'cputemp' 'Sıcaklık' 'CPU sıcaklığı' 'Sensör verisi yok (Windows bu bilgiyi sunmuyor; LibreHardwareMonitor çalışıyorsa okunur)' 'Veri yok' }
        $gt = Get-GpuTempInfo $gpuMain
        if ($gt) { $st = 'Bilgi'; if ($gt.Value -ge 90) { $st = 'Uyarı' }; Add-HRow 'gputemp' 'Sıcaklık' 'GPU sıcaklığı' $gt.Text $st }
        else { Add-HRow 'gputemp' 'Sıcaklık' 'GPU sıcaklığı' 'Sensör verisi yok (nvidia-smi veya LibreHardwareMonitor bulunamadı)' 'Veri yok' }

        $script:HealthLoaded = $true
        Show-HealthGrid
    } catch {
        $lblHealth.Text = '  Hata: ' + $_.Exception.Message
        Write-Log ('Sistem sağlığı hatası: ' + $_.Exception.Message)
    } finally { $form.Cursor = 'Default' }
}

function Show-HealthGrid {
    $gridHealth.Rows.Clear(); $script:HealthRowMap = @{}
    foreach ($r in $script:HealthList) {
        $i = $gridHealth.Rows.Add([object[]]@($r.Cat, $r.Name, $r.Value, $r.Status))
        $row = $gridHealth.Rows[$i]; $row.Tag = $r
        $script:HealthRowMap[$r.Key] = $row
        if ($r.Status -eq 'Uyarı') { $row.DefaultCellStyle.BackColor = [Drawing.Color]::LightYellow }
        elseif ($r.Status -eq 'Veri yok') { $row.DefaultCellStyle.ForeColor = [Drawing.Color]::Gray }
    }
    Update-HealthLive
    $warn = @($script:HealthList | Where-Object { $_.Status -eq 'Uyarı' }).Count
    $nod = @($script:HealthList | Where-Object { $_.Status -eq 'Veri yok' }).Count
    $verdict = if ($warn -eq 0) { 'ölçülebilen verilerde dikkat gerektiren bir durum yok' } else { "$warn uyarı var (sarı satırlar)" }
    $lblHealth.Text = "  Genel durum: $verdict.  Okunamayan/sensörsüz veri: $nod (uydurulmaz).  RAM canlı güncellenir; diğer değerler için Yenile."
}

function Update-HealthLive {
    if (-not $script:HealthLoaded) { return }
    try {
        if ($script:Sys -and $script:HealthRowMap.ContainsKey('ram')) {
            $r = $script:HealthRowMap['ram']; $s = $script:Sys
            $r.Cells[2].Value = ('{0:N1} GB kullanılıyor / {1:N1} GB (%{2:N0}), boş {3:N1} GB' -f ($s.UsedMB / 1024), ($s.TotalMB / 1024), $s.Pct, ($s.FreeMB / 1024))
            if ($s.Pct -ge 90) { $r.Cells[3].Value = 'Uyarı'; $r.DefaultCellStyle.BackColor = [Drawing.Color]::LightYellow }
            else { $r.Cells[3].Value = 'Bilgi'; $r.DefaultCellStyle.BackColor = [Drawing.Color]::Empty }
        }
        foreach ($k in @($script:HealthRowMap.Keys | Where-Object { $_ -like 'disk:*' })) {
            $dl = $k.Substring(5)
            $d = New-Object IO.DriveInfo $dl
            if (-not $d.IsReady) { continue }
            $used = [double]($d.TotalSize - $d.AvailableFreeSpace); $pct = $used / [double]$d.TotalSize * 100
            $r = $script:HealthRowMap[$k]
            $r.Cells[2].Value = ('{0:N0} GB dolu / {1:N0} GB (%{2:N0}), boş {3:N0} GB' -f ($used / 1GB), ($d.TotalSize / 1GB), $pct, ($d.AvailableFreeSpace / 1GB))
            if ($pct -ge 90) { $r.Cells[3].Value = 'Uyarı'; $r.DefaultCellStyle.BackColor = [Drawing.Color]::LightYellow }
            else { $r.Cells[3].Value = 'Bilgi'; $r.DefaultCellStyle.BackColor = [Drawing.Color]::Empty }
        }
    } catch {}
}

function Show-Health {
    if (-not $script:HealthLoaded) { Update-Health; return }
    Update-HealthLive
}

function Get-HealthReportText {
    $lines = @("WinOpt Suite - Sistem Sağlığı Raporu  |  Developed by Leone  ($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))", ('-' * 70))
    foreach ($r in $script:HealthList) { $lines += ('[{0}] {1}: {2}  <{3}>' -f $r.Cat, $r.Name, $(if ($r.Key -eq 'ram' -and $script:HealthRowMap.ContainsKey('ram')) { $script:HealthRowMap['ram'].Cells[2].Value } else { $r.Value }), $r.Status) }
    return ($lines -join [Environment]::NewLine)
}

New-Btn $barHealth 'Yenile' 90 { Update-Health }
New-Btn $barHealth 'Raporu Kaydet (TXT)' 160 {
    if (-not $script:HealthLoaded) { return }
    $dlg = New-Object Windows.Forms.SaveFileDialog
    $dlg.Filter = 'Metin (*.txt)|*.txt'; $dlg.FileName = 'sistem-sagligi.txt'
    if ($dlg.ShowDialog() -eq 'OK') {
        [IO.File]::WriteAllText($dlg.FileName, (Get-HealthReportText), (New-Object Text.UTF8Encoding($true)))
        Write-Log "Sistem sağlığı raporu kaydedildi: $($dlg.FileName)"
    }
}
New-Btn $barHealth 'Panoya Kopyala' 120 { if ($script:HealthLoaded) { [Windows.Forms.Clipboard]::SetText((Get-HealthReportText)) } }
