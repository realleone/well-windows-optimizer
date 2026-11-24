$GameProfFile   = Join-Path $AppDir 'oyun-profilleri.json'
$GameSessFile   = Join-Path $AppDir 'oyun-oturumu.json'
$GameReportFile = Join-Path $AppDir 'oyun-raporlari.csv'
$GameSampleDir  = Join-Path $AppDir 'oyun-oturumlari'

$script:GameProfiles = @()
$script:GameSession = $null
$script:GameMiss = 0
$script:GameRecoveryChecked = $false
$script:GameLoaded = $false
$script:GameGridDirty = $true
$script:GameSuppress = ''
$script:GameLastErr = ''
$script:LastReport = ''
$script:GpuPrev = @{}
$script:GpuOk = $true
$script:GpuFail = 0
$script:GameHist = New-Object 'System.Collections.Generic.List[object]'
$script:PriLabels = @{ Normal = 'Değiştirme'; AboveNormal = 'Normalin üstü'; High = 'Yüksek' }
$script:Dlg = @{}
$script:Pick = @{}

function Read-GameProfiles {
    if (Test-Path -LiteralPath $GameProfFile) {
        try {
            $x = Get-Content -LiteralPath $GameProfFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -ne $x) { return @($x | ForEach-Object { $_ }) }
        } catch {}
    }
    return @()
}

function Save-GameProfiles { ConvertTo-Json -InputObject @($script:GameProfiles) -Depth 6 | Set-Content -LiteralPath $GameProfFile -Encoding UTF8 }

function New-GameProfile([string]$name, [string]$proc) {
    [pscustomobject]@{
        Ad = $name; Islem = $proc; Aktif = $true; PowerGuid = ''; GameMode = $true; KayitKapat = $false
        Oncelik = 'Normal'; Apps = @(); Yeniden = $true; Zorla = $false
    }
}

function Get-PlanName([string]$guid) {
    if (-not $guid) { return '(değiştirme)' }
    $p = @(Get-PowerPlans | Where-Object { $_.Guid -eq $guid.ToLower() } | Select-Object -First 1)
    if ($p.Count -gt 0) { return $p[0].Name }
    return 'Bulunamadı'
}

function Get-Stat($vals) {
    $v = @($vals | Where-Object { $null -ne $_ })
    if ($v.Count -eq 0) { return $null }
    $m = $v | Measure-Object -Average -Maximum
    return [pscustomobject]@{ Avg = $m.Average; Max = $m.Maximum }
}

function Format-Stat($st, [string]$unit) {
    if (-not $st) { return 'ölçülemedi' }
    return ('ort. {0:N1}{2} | maks. {1:N1}{2}' -f $st.Avg, $st.Max, $unit)
}

function Show-TextDialog([string]$title, [string]$text) {
    $d = New-Object Windows.Forms.Form
    $d.Text = $title; $d.Size = New-Object Drawing.Size(780, 580); $d.StartPosition = 'CenterParent'
    $t = New-Object Windows.Forms.TextBox
    $t.Multiline = $true; $t.ReadOnly = $true; $t.ScrollBars = 'Vertical'; $t.Dock = 'Fill'
    $t.Font = New-Object Drawing.Font('Consolas', 10); $t.BackColor = [Drawing.Color]::White; $t.Text = $text
    $d.Controls.Add($t)
    $p = New-Object Windows.Forms.FlowLayoutPanel
    $p.Dock = 'Bottom'; $p.Height = 44; $p.Padding = New-Object Windows.Forms.Padding(6)
    $d.Controls.Add($p)
    $script:Dlg.Txt = $text
    New-Btn $p 'Panoya Kopyala' 130 { [Windows.Forms.Clipboard]::SetText($script:Dlg.Txt) }
    New-Btn $p 'Kapat' 90 { $this.FindForm().Close() }
    $t.Select(0, 0)
    [void]$d.ShowDialog($form)
}

function Get-GpuUsage($pids) {
    $r = [pscustomobject]@{ Game = $null; Total = $null; VramMB = $null }
    if (-not $script:GpuOk) { return $r }
    try {
        $cat = New-Object Diagnostics.PerformanceCounterCategory('GPU Engine')
        $col = $cat.ReadCategory()['Utilization Percentage']
        $engAll = @{}; $engGame = @{}; $cur = @{}
        foreach ($key in @($col.Keys)) {
            $s = $col[$key].Sample
            $cur[$key] = $s
            if (-not $script:GpuPrev.ContainsKey($key)) { continue }
            $val = [Diagnostics.CounterSample]::Calculate($script:GpuPrev[$key], $s)
            if ($key -match '^pid_(\d+)_.*engtype_(.+)$') {
                $id = [int]$Matches[1]; $eng = $Matches[2]
                $engAll[$eng] = [double]$engAll[$eng] + $val
                if ($pids -contains $id) { $engGame[$eng] = [double]$engGame[$eng] + $val }
            }
        }
        $hadPrev = ($script:GpuPrev.Count -gt 0)
        $script:GpuPrev = $cur
        if ($hadPrev -and $engAll.Count -gt 0) {
            $r.Total = [math]::Min(100, [math]::Round(($engAll.Values | Measure-Object -Maximum).Maximum, 1))
            $g = 0
            if ($engGame.Count -gt 0) { $g = ($engGame.Values | Measure-Object -Maximum).Maximum }
            $r.Game = [math]::Min(100, [math]::Round($g, 1))
        }
        $script:GpuFail = 0
    } catch {
        $script:GpuFail++
        if ($script:GpuFail -ge 3) { $script:GpuOk = $false }
    }
    try {
        $vc = (New-Object Diagnostics.PerformanceCounterCategory('GPU Process Memory')).ReadCategory()['Dedicated Usage']
        $sum = 0.0; $found = $false
        foreach ($key in @($vc.Keys)) {
            if ($key -match '^pid_(\d+)_' -and ($pids -contains [int]$Matches[1])) { $sum += [double]$vc[$key].RawValue; $found = $true }
        }
        if ($found) { $r.VramMB = [math]::Round($sum / 1MB, 0) }
    } catch {}
    return $r
}

function Get-TweakRegItems([string]$id) {
    $tw = Get-TweakById $id
    if ($tw) { return @($tw.Items) }
    return @()
}

function Restore-GamePrev($prev) {
    $msgs = @()
    if (-not $prev) { return $msgs }
    $regs = @($prev.Regs | Where-Object { $_ })
    for ($i = $regs.Count - 1; $i -ge 0; $i--) {
        try { Restore-TwRegState $regs[$i] } catch { $msgs += "Ayar geri yüklenemedi ($($regs[$i].Name)): $($_.Exception.Message)" }
    }
    if ($regs.Count -gt 0) { $msgs += 'Oyun Modu / kayıt ayarları geri yüklendi' }
    if ($prev.Power) {
        try { Set-PowerPlanByGuid $prev.Power; $msgs += 'Güç planı geri yüklendi: ' + (Get-PlanName $prev.Power) }
        catch { $msgs += 'Güç planı geri yüklenemedi: ' + $_.Exception.Message }
    }
    if ($prev.Relaunch) {
        $seen = @{}
        foreach ($path in @($prev.Reopen | Where-Object { $_ })) {
            if ($seen.ContainsKey($path)) { continue }
            $seen[$path] = $true
            try {
                if (Test-Path -LiteralPath $path) {
                    Start-Process -FilePath explorer.exe -ArgumentList ('"{0}"' -f $path)
                    $msgs += 'Yeniden başlatıldı: ' + [IO.Path]::GetFileName($path)
                }
            } catch { $msgs += 'Yeniden başlatılamadı: ' + [IO.Path]::GetFileName($path) }
        }
    }
    return $msgs
}

function Save-GameSessionFile($s) {
    [pscustomobject]@{ Ad = $s.Profile.Ad; Islem = $s.Proc; Start = $s.Start.ToString('o'); Prev = $s.Prev } |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $GameSessFile -Encoding UTF8
}

function Start-GameSession($p, $procItems, [bool]$monitorOnly) {
    $procName = [string]$procItems[0].Name
    $prev = [pscustomobject]@{ Power = ''; Regs = @(); Reopen = @(); Relaunch = [bool]$p.Yeniden }
    $applied = @(); $closed = @(); $notClosed = @(); $notes = @()
    if (-not $monitorOnly) {
        if ($p.PowerGuid) {
            try {
                $cur = Get-ActivePowerGuid
                if ($cur -and $cur -ne ([string]$p.PowerGuid).ToLower()) {
                    Set-PowerPlanByGuid $p.PowerGuid
                    $prev.Power = $cur
                    $applied += 'Güç planı: ' + (Get-PlanName $p.PowerGuid)
                }
            } catch { $notes += 'Güç planı değiştirilemedi: ' + $_.Exception.Message }
        }
        foreach ($pair in @(@($p.GameMode, 'gamemode', 'Windows Oyun Modu açıldı'), @($p.KayitKapat, 'gamedvr', 'Arka plan oyun kaydı kapatıldı'))) {
            if (-not [bool]$pair[0]) { continue }
            try {
                foreach ($it in (Get-TweakRegItems $pair[1])) {
                    $prev.Regs = @($prev.Regs) + (Get-TwRegState $it.Path $it.Name $it.Type)
                    Set-TwRegValue $it.Path $it.Name $it.Type $it.Rec
                }
                $applied += $pair[2]
            } catch { $notes += $pair[2] + ' uygulanamadı: ' + $_.Exception.Message }
        }
        if ($p.Oncelik -in 'AboveNormal', 'High') {
            foreach ($it in $procItems) {
                try {
                    $pr = Get-Process -Id $it.Id -ErrorAction Stop
                    $pr.PriorityClass = [Diagnostics.ProcessPriorityClass]$p.Oncelik
                } catch { $notes += "Öncelik ayarlanamadı (PID $($it.Id)): " + $_.Exception.Message }
            }
            $applied += 'İşlem önceliği: ' + $script:PriLabels[[string]$p.Oncelik]
        }
        foreach ($a in @($p.Apps | Where-Object { $_ })) {
            $name = [string]$a.Ad
            if ($name -ieq $procName) { continue }
            $targets = @($script:Snap | Where-Object { $_.Name -ieq $name -and -not $_.Protection })
            if ($targets.Count -eq 0) { continue }
            $closedAny = $false; $still = $false
            foreach ($t in $targets) {
                try {
                    $pr = Get-Process -Id $t.Id -ErrorAction Stop
                    if ($pr.ProcessName -ne $t.Name) { continue }
                    $gone = $false
                    if ($t.HasWin) { [void]$pr.CloseMainWindow(); if ($pr.WaitForExit(2000)) { $gone = $true } }
                    if (-not $gone -and [bool]$p.Zorla) { Stop-Process -Id $t.Id -Force -ErrorAction Stop; $gone = $true }
                    if ($gone) { $closedAny = $true } else { $still = $true }
                } catch { $still = $true }
            }
            if ($closedAny) {
                $closed += $name
                $path = if ($targets[0].Path) { $targets[0].Path } else { [string]$a.Yol }
                if ($path) { $prev.Reopen = @($prev.Reopen) + $path }
            }
            if ($still) { $notClosed += $name }
        }
    }
    $s = [pscustomobject]@{
        Profile = $p; Proc = $procName; Start = (Get-Date); Prev = $prev; Monitor = $monitorOnly
        Samples = (New-Object 'System.Collections.Generic.List[object]')
        Applied = $applied; Closed = $closed; NotClosed = $notClosed; Notes = $notes
    }
    $script:GameSession = $s
    $script:GameMiss = 0
    $script:GameHist.Clear()
    $script:GpuPrev = @{}
    [void](Get-GpuUsage @($procItems | ForEach-Object { $_.Id }))
    try { Save-GameSessionFile $s } catch { Write-Log ('Oturum dosyası yazılamadı: ' + $_.Exception.Message) }
    $script:GameGridDirty = $true
    Write-Log ("Oyun oturumu başladı: {0} (profil: {1}){2}" -f $procName, $p.Ad, $(if ($monitorOnly) { ' [yalnızca izleme]' } else { '' }))
}

function Get-GameReportText($s, [datetime]$end, $restoreMsgs, [string]$reason) {
    $smp = @($s.Samples)
    $dur = $end - $s.Start
    $cpu = Get-Stat ($smp | ForEach-Object { $_.OyunCpu })
    $ram = Get-Stat ($smp | ForEach-Object { $_.OyunRamMB })
    $gpu = Get-Stat ($smp | ForEach-Object { $_.OyunGpu })
    $vram = Get-Stat ($smp | ForEach-Object { $_.OyunVramMB })
    $sysCpu = Get-Stat ($smp | ForEach-Object { $_.SistemCpu })
    $sysRam = Get-Stat ($smp | ForEach-Object { $_.SistemRamYuzde })
    $L = @()
    $L += 'OYUN PERFORMANS RAPORU  |  Developed by Leone'
    $L += '======================'
    $L += "Oyun işlemi : $($s.Proc)"
    $L += "Profil      : $($s.Profile.Ad)$(if ($s.Monitor) { ' (yalnızca izleme)' })"
    $L += "Başlangıç   : $($s.Start.ToString('yyyy-MM-dd HH:mm:ss'))"
    $L += "Bitiş       : $($end.ToString('yyyy-MM-dd HH:mm:ss'))   ($reason)"
    $L += ('Süre        : {0:N1} dk   |   Ölçüm sayısı: {1}' -f $dur.TotalMinutes, $smp.Count)
    $L += ''
    $L += 'KAYNAK KULLANIMI'
    $L += 'Oyun CPU %        : ' + (Format-Stat $cpu '')
    $L += 'Oyun RAM (MB)     : ' + (Format-Stat $ram '')
    $L += 'Oyun GPU %        : ' + (Format-Stat $gpu '')
    $L += 'Oyun VRAM (MB)    : ' + (Format-Stat $vram '')
    $L += 'Sistem CPU %      : ' + (Format-Stat $sysCpu '')
    $L += 'Sistem RAM %      : ' + (Format-Stat $sysRam '')
    $L += ''
    $L += 'UYGULANAN PROFİL AYARLARI'
    if (@($s.Applied).Count -eq 0) { $L += '  (ayar uygulanmadı)' } else { foreach ($a in $s.Applied) { $L += "  - $a" } }
    if (@($s.Closed).Count -gt 0) { $L += '  Kapatılan uygulamalar: ' + (@($s.Closed) -join ', ') }
    if (@($s.NotClosed).Count -gt 0) { $L += '  Kapanmayan (arka planda çalışıyor olabilir): ' + (@($s.NotClosed) -join ', ') }
    foreach ($n in @($s.Notes)) { $L += "  ! $n" }
    $L += ''
    $L += 'GERİ YÜKLEME'
    if (@($restoreMsgs).Count -eq 0) { $L += '  (geri yüklenecek ayar yoktu)' } else { foreach ($m in $restoreMsgs) { $L += "  - $m" } }
    $hints = @()
    if ($gpu -and $gpu.Avg -ge 90) { $hints += 'GPU kullanımı sürekli yüksek göründü; grafik ayarlarını düşürmek daha etkili olabilir.' }
    if ($sysRam -and $sysRam.Max -ge 90) { $hints += 'Sistem RAM kullanımı %90 üzerine çıktı; bellek yetersizliği takılmalara yol açabilir.' }
    if ($hints.Count -gt 0) {
        $L += ''
        $L += 'OLASI GÖZLEMLER (bilgi amaçlı, kesin değildir)'
        foreach ($h in $hints) { $L += "  - $h" }
    }
    $L += ''
    $L += 'ÖNEMLİ NOTLAR'
    $L += '  - Bu rapor FPS ölçmez; yalnızca kaynak kullanımını gösterir. FPS için oyun içi sayaç veya PresentMon/CapFrameX gibi araçlar kullanın.'
    $L += '  - Profil ayarlarının FPS artıracağı garanti edilmez; etki oyuna ve donanıma göre değişir. Karşılaştırma için aynı sahnede profilli ve profilsiz ölçüm yapın.'
    $L += '  - Oyun CPU yüzdesi tüm çekirdeklere göre hesaplanır; tek çekirdek darboğazı bu değerde görünmeyebilir.'
    return ($L -join "`r`n")
}

function End-GameSession([string]$reason) {
    $s = $script:GameSession
    if (-not $s) { return }
    $script:GameSession = $null
    $script:GameMiss = 0
    $end = Get-Date
    $msgs = @(Restore-GamePrev $s.Prev)
    $text = Get-GameReportText $s $end $msgs $reason
    $script:LastReport = $text
    try {
        $smp = @($s.Samples)
        $cpu = Get-Stat ($smp | ForEach-Object { $_.OyunCpu })
        $ram = Get-Stat ($smp | ForEach-Object { $_.OyunRamMB })
        $gpu = Get-Stat ($smp | ForEach-Object { $_.OyunGpu })
        $sc = Get-Stat ($smp | ForEach-Object { $_.SistemCpu })
        $sr = Get-Stat ($smp | ForEach-Object { $_.SistemRamYuzde })
        [pscustomobject][ordered]@{
            Zaman = $s.Start.ToString('yyyy-MM-dd HH:mm:ss'); Oyun = $s.Proc; Profil = $s.Profile.Ad
            SureDk = [math]::Round(($end - $s.Start).TotalMinutes, 1)
            OrtOyunCpu = $(if ($cpu) { [math]::Round($cpu.Avg, 1) }); MaksOyunCpu = $(if ($cpu) { [math]::Round($cpu.Max, 1) })
            OrtOyunRamMB = $(if ($ram) { [math]::Round($ram.Avg, 0) }); MaksOyunRamMB = $(if ($ram) { [math]::Round($ram.Max, 0) })
            OrtGpu = $(if ($gpu) { [math]::Round($gpu.Avg, 1) }); MaksGpu = $(if ($gpu) { [math]::Round($gpu.Max, 1) })
            OrtSistemCpu = $(if ($sc) { [math]::Round($sc.Avg, 1) }); OrtSistemRamYuzde = $(if ($sr) { [math]::Round($sr.Avg, 1) })
            MaksSistemRamYuzde = $(if ($sr) { [math]::Round($sr.Max, 1) })
            UygulananAyar = (@($s.Applied) -join '; '); KapatilanUygulama = (@($s.Closed) -join '; ')
        } | Export-Csv -LiteralPath $GameReportFile -Append -NoTypeInformation -Encoding UTF8
        if ($smp.Count -gt 0) {
            if (-not (Test-Path -LiteralPath $GameSampleDir)) { New-Item -ItemType Directory -Path $GameSampleDir -Force | Out-Null }
            $safe = ($s.Proc -replace '[^\w\-]', '_')
            $smp | Export-Csv -LiteralPath (Join-Path $GameSampleDir ("{0}-{1}.csv" -f $s.Start.ToString('yyyyMMdd-HHmmss'), $safe)) -NoTypeInformation -Encoding UTF8
            $old = @(Get-ChildItem -LiteralPath $GameSampleDir -Filter '*.csv' | Sort-Object LastWriteTime -Descending | Select-Object -Skip 30)
            foreach ($f in $old) { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue }
        }
    } catch { Write-Log ('Oyun raporu yazılamadı: ' + $_.Exception.Message) }
    Remove-Item -LiteralPath $GameSessFile -Force -ErrorAction SilentlyContinue
    if ($reason -like 'Elle*') { $script:GameSuppress = $s.Proc }
    $script:GameGridDirty = $true
    Write-Log ("Oyun oturumu bitti: {0} ({1}) - ayarlar geri yüklendi" -f $s.Proc, $reason)
}

function Resume-GameSession {
    if (-not (Test-Path -LiteralPath $GameSessFile)) { return }
    try {
        $x = Get-Content -LiteralPath $GameSessFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $items = @($script:Snap | Where-Object { $_.Name -ieq $x.Islem })
        $prof = @($script:GameProfiles | Where-Object { $_.Ad -eq $x.Ad } | Select-Object -First 1)
        if ($items.Count -gt 0 -and $prof.Count -gt 0) {
            $start = Get-Date
            try { $start = [datetime]$x.Start } catch {}
            $script:GameSession = [pscustomobject]@{
                Profile = $prof[0]; Proc = [string]$x.Islem; Start = $start; Prev = $x.Prev; Monitor = $false
                Samples = (New-Object 'System.Collections.Generic.List[object]')
                Applied = @('Önceki oturum devralındı'); Closed = @(); NotClosed = @(); Notes = @()
            }
            $script:GameGridDirty = $true
            Write-Log "Yarım kalan oyun oturumu devralındı: $($x.Islem)"
            return
        }
        $msgs = @(Restore-GamePrev $x.Prev)
        Write-Log ('Yarım kalan oyun oturumu geri yüklendi: ' + ($msgs -join '; '))
    } catch { Write-Log ('Oturum kurtarma hatası: ' + $_.Exception.Message) }
    Remove-Item -LiteralPath $GameSessFile -Force -ErrorAction SilentlyContinue
}

function Update-GameSession {
    $s = $script:GameSession
    $same = @($script:Snap | Where-Object { $_.Name -ieq $s.Proc })
    if ($same.Count -eq 0) {
        $script:GameMiss++
        if ($script:GameMiss -ge 3) { End-GameSession 'Oyun kapandı' }
        return
    }
    $script:GameMiss = 0
    $cpu = [math]::Round(($same | Measure-Object Cpu -Sum).Sum, 1)
    $ram = [math]::Round(($same | Measure-Object WsMB -Sum).Sum, 0)
    $g = Get-GpuUsage @($same | ForEach-Object { $_.Id })
    $sysRam = if ($script:Sys) { [math]::Round($script:Sys.Pct, 1) } else { $null }
    $smp = [pscustomobject][ordered]@{
        Zaman = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); OyunCpu = $cpu; OyunRamMB = $ram; OyunGpu = $g.Game
        OyunVramMB = $g.VramMB; SistemCpu = $script:TotalCpu; SistemRamYuzde = $sysRam
    }
    $s.Samples.Add($smp)
    $script:GameHist.Add($smp)
    if ($script:GameHist.Count -gt 120) { $script:GameHist.RemoveAt(0) }
}

function Find-GameStart {
    if ($script:GameSuppress) {
        if (@($script:Snap | Where-Object { $_.Name -ieq $script:GameSuppress }).Count -eq 0) { $script:GameSuppress = '' }
    }
    foreach ($p in $script:GameProfiles) {
        if ($p.Aktif -ne $true -or -not $p.Islem) { continue }
        if ($script:GameSuppress -and $p.Islem -ieq $script:GameSuppress) { continue }
        $items = @($script:Snap | Where-Object { $_.Name -ieq $p.Islem })
        if ($items.Count -gt 0) { Start-GameSession $p $items $false; return }
    }
}

function Update-GameWatch {
    try {
        if (-not $script:GameRecoveryChecked) { $script:GameRecoveryChecked = $true; Resume-GameSession }
        if ($script:GameSession) { Update-GameSession } else { Find-GameStart }
    } catch {
        if ($_.Exception.Message -ne $script:GameLastErr) {
            $script:GameLastErr = $_.Exception.Message
            Write-Log ('Oyun izleme hatası: ' + $script:GameLastErr)
        }
    }
}

function Show-ProcessPicker([string]$title, [bool]$multi) {
    $items = @($script:Snap | Where-Object { -not $_.Protection -and $_.Path } | Group-Object Name | ForEach-Object {
        $first = $_.Group | Select-Object -First 1
        [pscustomobject]@{
            Name = $_.Name; Path = $first.Path; Pub = $first.Publisher
            Ram = [math]::Round(($_.Group | Measure-Object WsMB -Sum).Sum, 0)
            Win = (@($_.Group | Where-Object { $_.HasWin }).Count -gt 0)
        }
    } | Sort-Object Ram -Descending)
    if ($items.Count -eq 0) { [L10nMsg]::Show('Listelenecek uygulama yok (ilk ölçüm bekleniyor olabilir).', 'WinOpt Suite - Developed by Leone') | Out-Null; return @() }
    $d = New-Object Windows.Forms.Form
    $d.Text = $title; $d.Size = New-Object Drawing.Size(860, 520); $d.StartPosition = 'CenterParent'
    $g = New-StdGrid @(@('İşlem', 180), @('Pencere', 70), @('RAM MB', 80), @('Yayıncı', 180), @('Dosya yolu', 320))
    $g.MultiSelect = $multi
    $d.Controls.Add($g)
    $pn = New-Object Windows.Forms.FlowLayoutPanel
    $pn.Dock = 'Bottom'; $pn.Height = 44; $pn.Padding = New-Object Windows.Forms.Padding(6)
    $d.Controls.Add($pn)
    foreach ($it in $items) {
        $win = if ($it.Win) { 'Evet' } else { 'Hayır' }
        $i = $g.Rows.Add([object[]]@($it.Name, $win, $it.Ram, $it.Pub, $it.Path))
        $g.Rows[$i].Tag = $it
    }
    $script:Pick = @{ Grid = $g; Form = $d; Result = @() }
    New-Btn $pn 'Seç' 90 {
        $script:Pick.Result = @($script:Pick.Grid.SelectedRows | ForEach-Object { $_.Tag } | Where-Object { $_ })
        $script:Pick.Form.Close()
    }
    New-Btn $pn 'İptal' 90 { $script:Pick.Result = @(); $script:Pick.Form.Close() }
    [void]$d.ShowDialog($form)
    return @($script:Pick.Result)
}

function Edit-GameProfile($p) {
    $plans = @(Get-PowerPlans)
    $d = New-Object Windows.Forms.Form
    $d.Text = 'Oyun profili'; $d.Size = New-Object Drawing.Size(610, 640); $d.StartPosition = 'CenterParent'
    $d.FormBorderStyle = 'FixedDialog'; $d.MaximizeBox = $false; $d.MinimizeBox = $false

    $mk = {
        param($text, $x, $y, $w)
        $l = New-Object Windows.Forms.Label
        $l.Text = $text; $l.Location = New-Object Drawing.Point($x, $y); $l.Size = New-Object Drawing.Size($w, 22)
        $d.Controls.Add($l)
    }
    & $mk 'Profil adı' 12 14 130
    $tAd = New-Object Windows.Forms.TextBox
    $tAd.Location = New-Object Drawing.Point(160, 10); $tAd.Width = 410; $tAd.Text = $p.Ad
    $d.Controls.Add($tAd)

    & $mk 'Oyun işlem adı (.exe)' 12 48 140
    $tProc = New-Object Windows.Forms.TextBox
    $tProc.Location = New-Object Drawing.Point(160, 44); $tProc.Width = 300; $tProc.Text = $p.Islem
    $d.Controls.Add($tProc)
    $bBrowse = New-Object Windows.Forms.Button
    $bBrowse.Text = 'Gözat...'; $bBrowse.Location = New-Object Drawing.Point(470, 42); $bBrowse.Width = 100
    $d.Controls.Add($bBrowse)

    & $mk 'Güç planı' 12 82 130
    $cPower = New-Object Windows.Forms.ComboBox
    $cPower.DropDownStyle = 'DropDownList'; $cPower.Location = New-Object Drawing.Point(160, 78); $cPower.Width = 410
    [void]$cPower.Items.Add('(Değiştirme)')
    $sel = 0
    for ($i = 0; $i -lt $plans.Count; $i++) {
        [void]$cPower.Items.Add($plans[$i].Name)
        if ($p.PowerGuid -and $plans[$i].Guid -eq ([string]$p.PowerGuid).ToLower()) { $sel = $i + 1 }
    }
    $cPower.SelectedIndex = $sel
    $d.Controls.Add($cPower)

    $kGm = New-Object Windows.Forms.CheckBox
    $kGm.Text = 'Oyun sırasında Windows Oyun Modu açık olsun'; $kGm.Location = New-Object Drawing.Point(12, 114); $kGm.Width = 560
    $kGm.Checked = [bool]$p.GameMode
    $d.Controls.Add($kGm)
    $kRec = New-Object Windows.Forms.CheckBox
    $kRec.Text = 'Oyun sırasında arka plan oyun kaydını (Game DVR) kapat'; $kRec.Location = New-Object Drawing.Point(12, 140); $kRec.Width = 560
    $kRec.Checked = [bool]$p.KayitKapat
    $d.Controls.Add($kRec)

    & $mk 'İşlem önceliği' 12 176 130
    $cPri = New-Object Windows.Forms.ComboBox
    $cPri.DropDownStyle = 'DropDownList'; $cPri.Location = New-Object Drawing.Point(160, 172); $cPri.Width = 200
    [void]$cPri.Items.AddRange(@('Değiştirme (Normal)', 'Normalin üstü', 'Yüksek'))
    $cPri.SelectedIndex = switch ([string]$p.Oncelik) { 'AboveNormal' { 1 } 'High' { 2 } default { 0 } }
    $d.Controls.Add($cPri)
    $lPri = New-Object Windows.Forms.Label
    $lPri.Text = 'Yüksek öncelik diğer işlemleri aç bırakabilir.'; $lPri.Location = New-Object Drawing.Point(370, 176); $lPri.Size = New-Object Drawing.Size(220, 36)
    $d.Controls.Add($lPri)

    & $mk 'Oyun sırasında geçici kapatılacak uygulamalar (yalnızca sizin seçtikleriniz):' 12 214 560
    $lb = New-Object Windows.Forms.ListBox
    $lb.Location = New-Object Drawing.Point(12, 238); $lb.Size = New-Object Drawing.Size(440, 140)
    $d.Controls.Add($lb)
    $bAdd = New-Object Windows.Forms.Button
    $bAdd.Text = 'Çalışanlardan Ekle...'; $bAdd.Location = New-Object Drawing.Point(462, 238); $bAdd.Width = 120
    $d.Controls.Add($bAdd)
    $bDel = New-Object Windows.Forms.Button
    $bDel.Text = 'Seçiliyi Kaldır'; $bDel.Location = New-Object Drawing.Point(462, 274); $bDel.Width = 120
    $d.Controls.Add($bDel)

    $kRe = New-Object Windows.Forms.CheckBox
    $kRe.Text = 'Oyun kapanınca kapattığım uygulamaları yeniden başlat'; $kRe.Location = New-Object Drawing.Point(12, 390); $kRe.Width = 560
    $kRe.Checked = [bool]$p.Yeniden
    $d.Controls.Add($kRe)
    $kZor = New-Object Windows.Forms.CheckBox
    $kZor.Text = 'Nazikçe kapanmazsa zorla sonlandır (kaydedilmemiş veri kaybolabilir)'; $kZor.Location = New-Object Drawing.Point(12, 416); $kZor.Width = 560
    $kZor.Checked = [bool]$p.Zorla
    $d.Controls.Add($kZor)

    $note = New-Object Windows.Forms.Label
    $note.Location = New-Object Drawing.Point(12, 450); $note.Size = New-Object Drawing.Size(570, 90)
    $note.Text = "Profil etkinleşince yalnızca burada seçtiğiniz ayarlar uygulanır; oyun kapanınca önceki değerler geri yüklenir. Kapatma önce nazik (pencere kapatma) denenir. Sistem ve güvenlik işlemleri listelenmez. Bu ayarların FPS değerini artıracağı garanti edilmez."
    $d.Controls.Add($note)

    $bOk = New-Object Windows.Forms.Button
    $bOk.Text = 'Kaydet'; $bOk.Location = New-Object Drawing.Point(380, 560); $bOk.Width = 90
    $d.Controls.Add($bOk)
    $bCancel = New-Object Windows.Forms.Button
    $bCancel.Text = 'İptal'; $bCancel.Location = New-Object Drawing.Point(480, 560); $bCancel.Width = 90
    $d.Controls.Add($bCancel)

    $script:Dlg = @{
        Form = $d; Ad = $tAd; Proc = $tProc; Power = $cPower; Plans = $plans; Gm = $kGm; Rec = $kRec; Pri = $cPri
        List = $lb; Re = $kRe; Zor = $kZor; Apps = @(@($p.Apps | Where-Object { $_ }) | ForEach-Object { [pscustomobject]@{ Ad = [string]$_.Ad; Yol = [string]$_.Yol } }); Ok = $false
    }
    $script:Dlg.Refill = {
        $script:Dlg.List.Items.Clear()
        foreach ($a in $script:Dlg.Apps) { [void]$script:Dlg.List.Items.Add(("{0}   -   {1}" -f $a.Ad, $a.Yol)) }
    }
    & $script:Dlg.Refill

    $bBrowse.Add_Click({
        $dlg = New-Object Windows.Forms.OpenFileDialog
        $dlg.Filter = 'Uygulama (*.exe)|*.exe'
        if ($dlg.ShowDialog() -eq 'OK') {
            $script:Dlg.Proc.Text = [IO.Path]::GetFileNameWithoutExtension($dlg.FileName)
            if (-not $script:Dlg.Ad.Text) { $script:Dlg.Ad.Text = $script:Dlg.Proc.Text }
        }
    })
    $bAdd.Add_Click({
        $picked = @(Show-ProcessPicker 'Kapatılacak uygulamaları seçin' $true)
        foreach ($it in $picked) {
            if (@($script:Dlg.Apps | Where-Object { $_.Ad -ieq $it.Name }).Count -eq 0) {
                $script:Dlg.Apps = @($script:Dlg.Apps) + [pscustomobject]@{ Ad = [string]$it.Name; Yol = [string]$it.Path }
            }
        }
        & $script:Dlg.Refill
    })
    $bDel.Add_Click({
        $idx = $script:Dlg.List.SelectedIndex
        if ($idx -ge 0) {
            $keep = @(); $n = 0
            foreach ($a in $script:Dlg.Apps) { if ($n -ne $idx) { $keep += $a }; $n++ }
            $script:Dlg.Apps = $keep
            & $script:Dlg.Refill
        }
    })
    $bOk.Add_Click({
        $proc = [IO.Path]::GetFileNameWithoutExtension($script:Dlg.Proc.Text.Trim())
        if (-not $script:Dlg.Ad.Text.Trim() -or -not $proc) {
            [L10nMsg]::Show('Profil adı ve oyun işlem adı boş olamaz.', 'WinOpt Suite - Developed by Leone') | Out-Null
            return
        }
        $script:Dlg.Ok = $true
        $script:Dlg.Form.Close()
    })
    $bCancel.Add_Click({ $script:Dlg.Form.Close() })
    [void]$d.ShowDialog($form)
    if (-not $script:Dlg.Ok) { return $null }
    $guid = ''
    if ($script:Dlg.Power.SelectedIndex -gt 0) { $guid = $script:Dlg.Plans[$script:Dlg.Power.SelectedIndex - 1].Guid }
    $pri = switch ($script:Dlg.Pri.SelectedIndex) { 1 { 'AboveNormal' } 2 { 'High' } default { 'Normal' } }
    return [pscustomobject]@{
        Ad = $script:Dlg.Ad.Text.Trim(); Islem = [IO.Path]::GetFileNameWithoutExtension($script:Dlg.Proc.Text.Trim()); Aktif = [bool]$p.Aktif
        PowerGuid = $guid; GameMode = $script:Dlg.Gm.Checked; KayitKapat = $script:Dlg.Rec.Checked; Oncelik = $pri
        Apps = @($script:Dlg.Apps); Yeniden = $script:Dlg.Re.Checked; Zorla = $script:Dlg.Zor.Checked
    }
}

function Get-SelectedGameProfile {
    $r = @($gridGame.SelectedRows | ForEach-Object { $_.Tag } | Where-Object { $_ } | Select-Object -First 1)
    if ($r.Count -eq 0) { [L10nMsg]::Show('Önce listeden bir profil seçin.', 'WinOpt Suite - Developed by Leone') | Out-Null; return $null }
    return $r[0]
}

function Show-GameGrid {
    $gridGame.Rows.Clear()
    $cur = if ($script:GameSession) { $script:GameSession.Profile.Ad } else { '' }
    foreach ($p in $script:GameProfiles) {
        $apps = (@($p.Apps | Where-Object { $_ } | ForEach-Object { $_.Ad }) -join ', ')
        $note = ''
        if ($cur -and $p.Ad -eq $cur) { $note = 'ŞU AN ETKİN' }
        elseif ($p.Aktif -ne $true) { $note = 'Pasif' }
        $i = $gridGame.Rows.Add([object[]]@(
            $(if ($p.Aktif -eq $true) { 'Evet' } else { 'Hayır' }), $p.Ad, $p.Islem, (Get-PlanName ([string]$p.PowerGuid)),
            $(if ($p.GameMode) { 'Aç' } else { '-' }), $(if ($p.KayitKapat) { 'Kapat' } else { '-' }),
            $script:PriLabels[[string]$p.Oncelik], $apps, $note))
        $row = $gridGame.Rows[$i]; $row.Tag = $p
        if ($note -eq 'ŞU AN ETKİN') { $row.DefaultCellStyle.BackColor = [Drawing.Color]::Honeydew }
        elseif ($p.Aktif -ne $true) { $row.DefaultCellStyle.ForeColor = [Drawing.Color]::Gray }
    }
    $gmTw = Get-TweakById 'gamemode'
    $gmText = if ($gmTw) { (Get-TweakState $gmTw).Text } else { '?' }
    $act = @($script:GameProfiles | Where-Object { $_.Aktif -eq $true }).Count
    $lblGame.Text = "  Profil: $($script:GameProfiles.Count)  |  Etkin profil: $act  |  Windows Oyun Modu: $gmText  |  Ayarların FPS artışı garanti edilmez; FPS ölçülmez, yalnızca kaynak kullanımı izlenir."
    $script:GameGridDirty = $false
}

function Show-Game {
    if (-not $script:GameLoaded) { $script:GameLoaded = $true; $script:GameGridDirty = $true }
    $s = $script:GameSession
    if ($s) {
        $dur = (Get-Date) - $s.Start
        $mode = if ($s.Monitor) { 'yalnızca izleme' } else { 'profil etkin' }
        $lblGameState.Text = ('Oyun izleniyor: {0}   |   Profil: {1} ({2})   |   Süre: {3:hh\:mm\:ss}' -f $s.Proc, $s.Profile.Ad, $mode, $dur)
        $lblGameState.ForeColor = [Drawing.Color]::DarkGreen
        $last = $null
        if ($s.Samples.Count -gt 0) { $last = $s.Samples[$s.Samples.Count - 1] }
        if ($last) {
            $gpuT = if ($null -ne $last.OyunGpu) { '%{0:N0}' -f $last.OyunGpu } else { '-' }
            $vrT = if ($null -ne $last.OyunVramMB) { '{0:N0} MB' -f $last.OyunVramMB } else { '-' }
            $lblGameMetrics.Text = ("Oyun     CPU: %{0:N1}    RAM: {1:N0} MB    GPU: {2}    VRAM: {3}`r`nSistem   CPU: %{4:N0}    RAM: %{5:N1}" -f $last.OyunCpu, $last.OyunRamMB, $gpuT, $vrT, $last.SistemCpu, $last.SistemRamYuzde)
        }
    } else {
        $lblGameState.Text = 'Oyun algılanmadı. Etkin bir profildeki oyun açıldığında profil otomatik etkinleşir.'
        $lblGameState.ForeColor = [Drawing.Color]::DimGray
        $lblGameMetrics.Text = if ($script:LastReport) { "Son oturum raporu hazır: Son Oturum Raporu düğmesine tıklayın.`r`nOyun kapandığında önceki ayarlar otomatik geri yüklenir." } else { "Henüz oturum yok.`r`n" }
    }
    $graphGame.Invalidate()
    if ($script:GameGridDirty) { Show-GameGrid }
}

function Set-GameModeState([bool]$on) {
    if ($script:GameSession) { [L10nMsg]::Show('Oyun oturumu sürerken Oyun Modu elle değiştirilemez; oturum bitince önceki değer geri yüklenir.', 'WinOpt Suite - Developed by Leone') | Out-Null; return }
    $tw = Get-TweakById 'gamemode'
    if (-not $tw) { return }
    $txt = if ($on) { 'Oyun Modu açıldı' } else { 'Oyun Modu kapatıldı' }
    try {
        $prev = @(Get-TweakPrev $tw)
        Set-TweakItems $tw $(if ($on) { 'Rec' } else { 'Alt' })
        Add-TweakBackup $tw.Id $tw.Name $txt $prev
        Write-Log $txt
    } catch { [L10nMsg]::Show('Oyun Modu ayarı değiştirilemedi: ' + $_.Exception.Message, 'WinOpt Suite - Developed by Leone') | Out-Null }
    $script:GameGridDirty = $true
    if ($script:TweakLoaded) { Update-TweakList }
    Show-Game
}

$tabGame = New-Object Windows.Forms.TabPage
$tabGame.Text = 'Oyun Optimizasyonu'
[void]$tabs.TabPages.Add($tabGame)

$gridGame = New-StdGrid @(
    @('Etkin', 50), @('Profil', 160), @('Oyun işlemi', 160), @('Güç planı', 160), @('Oyun Modu', 80), @('Oyun kaydı', 80),
    @('Öncelik', 100), @('Geçici kapatılacak uygulamalar', 300), @('Not', 130))
$tabGame.Controls.Add($gridGame)

$lblGame = New-StatusLabel
$tabGame.Controls.Add($lblGame)

$barGame = New-Bar
$barGame.Height = 116
$tabGame.Controls.Add($barGame)

$panGame = New-Object Windows.Forms.Panel
$panGame.Dock = 'Top'; $panGame.Height = 236
$tabGame.Controls.Add($panGame)

$lblGameState = New-Object Windows.Forms.Label
$lblGameState.Location = New-Object Drawing.Point(10, 8); $lblGameState.AutoSize = $true
$lblGameState.Font = New-Object Drawing.Font('Segoe UI', 11, [Drawing.FontStyle]::Bold)
$lblGameState.Text = 'Oyun algılanmadı.'
$panGame.Controls.Add($lblGameState)

$lblGameMetrics = New-Object Windows.Forms.Label
$lblGameMetrics.Location = New-Object Drawing.Point(10, 36); $lblGameMetrics.Size = New-Object Drawing.Size(900, 40)
$lblGameMetrics.Font = New-Object Drawing.Font('Consolas', 10)
$panGame.Controls.Add($lblGameMetrics)

$graphGame = New-Object Windows.Forms.Panel
$graphGame.Location = New-Object Drawing.Point(10, 82); $graphGame.Size = New-Object Drawing.Size(900, 146)
$graphGame.Anchor = 'Top,Left,Right'; $graphGame.BackColor = [Drawing.Color]::White; $graphGame.BorderStyle = 'FixedSingle'
$graphGame.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'Instance,NonPublic').SetValue($graphGame, $true, $null)
$graphGame.Add_Paint({
    param($s, $e)
    $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'
    $w = $s.ClientSize.Width; $h = $s.ClientSize.Height
    $gpen = New-Object Drawing.Pen([Drawing.Color]::Gainsboro)
    foreach ($p in 25, 50, 75) { $y = $h - ($h * $p / 100.0); $g.DrawLine($gpen, 0, [single]$y, $w, [single]$y) }
    $gpen.Dispose()
    $data = $script:GameHist.ToArray()
    if ($data.Count -ge 2) {
        $step = $w / 119.0
        foreach ($ser in @(@('OyunCpu', [Drawing.Color]::SteelBlue), @('OyunGpu', [Drawing.Color]::DarkOrange), @('SistemRamYuzde', [Drawing.Color]::SeaGreen))) {
            $pts = New-Object 'System.Collections.Generic.List[Drawing.PointF]'
            for ($i = 0; $i -lt $data.Count; $i++) {
                $v = $data[$i].($ser[0])
                if ($null -eq $v) { $v = 0 }
                $x = $w - ($data.Count - 1 - $i) * $step
                $y = $h - ($h * [math]::Min(100, [double]$v) / 100.0)
                $pts.Add((New-Object Drawing.PointF([single]$x, [single]$y)))
            }
            $pen = New-Object Drawing.Pen($ser[1], 2)
            $g.DrawLines($pen, $pts.ToArray())
            $pen.Dispose()
        }
    }
    $g.DrawString('Mavi: oyun CPU %   Turuncu: oyun GPU %   Yeşil: sistem RAM %   (son ~6 dk)', $s.Font, [Drawing.Brushes]::Gray, 4, 2)
})
$panGame.Controls.Add($graphGame)

New-Btn $barGame 'Yenile' 70 { $script:GameProfiles = @(Read-GameProfiles); Show-GameGrid; Show-Game }
New-Btn $barGame 'Profil Ekle (Dosya)' 140 {
    $dlg = New-Object Windows.Forms.OpenFileDialog
    $dlg.Filter = 'Oyun (*.exe)|*.exe'
    if ($dlg.ShowDialog() -ne 'OK') { return }
    $name = [IO.Path]::GetFileNameWithoutExtension($dlg.FileName)
    if (@($script:GameProfiles | Where-Object { $_.Islem -ieq $name }).Count -gt 0) { [L10nMsg]::Show('Bu oyun işlemi için profil zaten var.', 'WinOpt Suite - Developed by Leone') | Out-Null; return }
    $np = Edit-GameProfile (New-GameProfile $name $name)
    if ($np) { $script:GameProfiles = @($script:GameProfiles) + $np; Save-GameProfiles; Show-GameGrid }
}
New-Btn $barGame 'Profil Ekle (Çalışan)' 150 {
    $picked = @(Show-ProcessPicker 'Oyun işlemini seçin' $false)
    if ($picked.Count -eq 0) { return }
    $name = [string]$picked[0].Name
    if (@($script:GameProfiles | Where-Object { $_.Islem -ieq $name }).Count -gt 0) { [L10nMsg]::Show('Bu oyun işlemi için profil zaten var.', 'WinOpt Suite - Developed by Leone') | Out-Null; return }
    $np = Edit-GameProfile (New-GameProfile $name $name)
    if ($np) { $script:GameProfiles = @($script:GameProfiles) + $np; Save-GameProfiles; Show-GameGrid }
}
New-Btn $barGame 'Profili Düzenle' 120 {
    $p = Get-SelectedGameProfile
    if (-not $p) { return }
    if ($script:GameSession -and $script:GameSession.Profile.Ad -eq $p.Ad) { [L10nMsg]::Show('Etkin oturumdaki profil düzenlenemez; oyun kapandıktan sonra deneyin.', 'WinOpt Suite - Developed by Leone') | Out-Null; return }
    $np = Edit-GameProfile $p
    if ($np) {
        $script:GameProfiles = @($script:GameProfiles | ForEach-Object { if ($_.Ad -eq $p.Ad) { $np } else { $_ } })
        Save-GameProfiles; Show-GameGrid
    }
}
New-Btn $barGame 'Profili Sil' 90 {
    $p = Get-SelectedGameProfile
    if (-not $p) { return }
    if ($script:GameSession -and $script:GameSession.Profile.Ad -eq $p.Ad) { [L10nMsg]::Show('Etkin oturumdaki profil silinemez.', 'WinOpt Suite - Developed by Leone') | Out-Null; return }
    if ([L10nMsg]::Show("'$($p.Ad)' profili silinecek. Devam edilsin mi?", 'Profili sil', 'YesNo', 'Question') -ne 'Yes') { return }
    $script:GameProfiles = @($script:GameProfiles | Where-Object { $_.Ad -ne $p.Ad })
    Save-GameProfiles; Show-GameGrid
}
New-Btn $barGame 'Etkin / Pasif Yap' 120 {
    $p = Get-SelectedGameProfile
    if (-not $p) { return }
    $p.Aktif = ($p.Aktif -ne $true)
    Save-GameProfiles; Show-GameGrid
}
New-Btn $barGame 'Elle İzle (Çalışan)' 140 {
    if ($script:GameSession) { [L10nMsg]::Show('Zaten bir oyun oturumu sürüyor.', 'WinOpt Suite - Developed by Leone') | Out-Null; return }
    $picked = @(Show-ProcessPicker 'İzlenecek uygulamayı seçin' $false)
    if ($picked.Count -eq 0) { return }
    $name = [string]$picked[0].Name
    $items = @($script:Snap | Where-Object { $_.Name -ieq $name })
    if ($items.Count -eq 0) { return }
    $tmp = New-GameProfile $name $name
    $tmp.GameMode = $false
    Start-GameSession $tmp $items $true
    Show-Game
}
New-Btn $barGame 'Oturumu Bitir' 110 {
    if (-not $script:GameSession) { [L10nMsg]::Show('Etkin oyun oturumu yok.', 'WinOpt Suite - Developed by Leone') | Out-Null; return }
    End-GameSession 'Elle bitirildi'
    Show-Game
}
New-Btn $barGame 'Son Oturum Raporu' 140 {
    if ($script:LastReport) { Show-TextDialog 'Son oyun oturumu raporu' $script:LastReport }
    elseif ($script:GameSession) { [L10nMsg]::Show('Oturum sürüyor; rapor oyun kapanınca oluşur.', 'WinOpt Suite - Developed by Leone') | Out-Null }
    else { [L10nMsg]::Show('Bu çalıştırmada tamamlanmış oturum yok. Önceki oturumlar için Rapor Geçmişi düğmesini kullanın.', 'WinOpt Suite - Developed by Leone') | Out-Null }
}
New-Btn $barGame 'Rapor Geçmişi' 110 { Show-CsvDialog $GameReportFile 'Oyun rapor geçmişi' }
New-Btn $barGame 'Oyun Modunu Aç' 120 { Set-GameModeState $true }
New-Btn $barGame 'Oyun Modunu Kapat' 130 { Set-GameModeState $false }

$form.Add_FormClosing({
    if ($script:GameSession) { try { End-GameSession 'Uygulama kapatıldı' } catch {} }
})

$script:GameProfiles = @(Read-GameProfiles)
