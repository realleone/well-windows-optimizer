$tabSmart = New-Object Windows.Forms.TabPage
$tabSmart.Text = 'Akıllı Optimizasyon'
[void]$tabs.TabPages.Add($tabSmart)

$SmartFile = Join-Path $AppDir 'akilli-optimizasyon-gecmisi.json'
$script:SmRecs = @()
$script:SmProfile = $null
$script:SmBusy = $false
$script:SmReport = ''
$script:HpGuid = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'

$gridSm = New-StdGrid @(@('Kategori', 85), @('İşlem adı', 270), @('Açıklama', 330), @('Neden önerildi', 300), @('Risk', 65), @('Beklenen etki', 230), @('Geri alma', 260), @('Durum', 130))
$tabSmart.Controls.Add($gridSm)
$txtSmInfo = New-Object Windows.Forms.TextBox
$txtSmInfo.Multiline = $true; $txtSmInfo.ReadOnly = $true; $txtSmInfo.ScrollBars = 'Vertical'
$txtSmInfo.Dock = 'Bottom'; $txtSmInfo.Height = 135; $txtSmInfo.BackColor = [Drawing.Color]::White
$tabSmart.Controls.Add($txtSmInfo)
$lblSm = New-StatusLabel
$tabSmart.Controls.Add($lblSm)
$barSm = New-Bar
$tabSmart.Controls.Add($barSm)

function New-SmRec($cat, $name, $desc, $why, $risk, $impact, $undo, $kind, $data) {
    [pscustomobject]@{ Cat = $cat; Name = $name; Desc = $desc; Why = $why; Risk = $risk; Impact = $impact; Undo = $undo; Kind = $kind; Data = $data
        Status = $(if ($kind -eq 'Info') { 'Yalnızca öneri' } else { 'Bekliyor' }) }
}

# 1) Donanımı tanı, 2) Windows sürümünü tespit et
function Get-SmProfile {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    $gpu = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.Name } | Select-Object -First 1
    $build = 0; if ($os) { $build = [int]$os.BuildNumber }
    $ram = 0.0; if ($cs -and $cs.TotalPhysicalMemory) { $ram = [math]::Round([double]$cs.TotalPhysicalMemory / 1GB, 1) }
    $hasHdd = $false
    try { $hasHdd = (@(Get-PhysicalDisk -ErrorAction Stop | Where-Object { [string]$_.MediaType -eq 'HDD' }).Count -gt 0) } catch {}
    $laptop = $false
    try { $laptop = (@(Get-CimInstance Win32_Battery -ErrorAction Stop).Count -gt 0) } catch {}
    $cores = [Environment]::ProcessorCount
    $weak = ($ram -gt 0 -and $ram -le 8) -or $hasHdd -or ($cores -le 4)
    $strong = ($ram -ge 16) -and ($cores -ge 6) -and (-not $hasHdd)
    [pscustomobject]@{
        Win = $(if ($build -ge 22000) { 'Windows 11' } else { 'Windows 10' }); Build = $build; RamGB = $ram; Cores = $cores
        Cpu = $(if ($cpu) { ([string]$cpu.Name).Trim() } else { '?' }); Gpu = $(if ($gpu) { [string]$gpu.Name } else { '?' })
        HasHdd = $hasHdd; Laptop = $laptop; Weak = $weak; Strong = $strong
    }
}

function Get-SmLevelText($p) {
    if ($p.Weak) { return 'düşük/orta donanım' } elseif ($p.Strong) { return 'güçlü donanım' } else { return 'orta düzey donanım' }
}

# Windows ayarları (WindowsTweaks modülündeki tanımlar)
function Get-SmTweakRecs($p) {
    $out = @()
    foreach ($tw in $script:Tweaks) {
        if ($tw.Id -eq 'priv_location') { continue }
        if ($tw.Level -eq 'Dikkat') { continue }
        $st = Get-TweakState $tw
        if ($st.IsRec) { continue }
        $cosmetic = ($tw.Cat -in @('Animasyonlar', 'Görsel efektler', 'Saydamlık'))
        $cat = 'Güvenli'; $impact = 'Düşük'; $why = "Şu an: $($st.Text). Önerilen: $($tw.RecLabel)."
        if ($tw.Cat -eq 'Oyun') {
            $cat = 'Oyun'; $impact = 'Oyuna ve donanıma göre değişir; FPS artışı garanti edilmez'
        } elseif ($cosmetic) {
            if ($p.Strong) { $cat = 'Gelişmiş'; $impact = 'Çok düşük (donanımınız güçlü, fark neredeyse hissedilmez)'; $why += ' Güçlü donanımda kazanç küçüktür, bu yüzden isteğe bağlıdır.' }
            elseif ($p.Weak) { $cat = 'Güvenli'; $impact = 'Orta (düşük/orta donanımda arayüz akıcılığı artabilir; garanti edilmez)'; $why += ' Donanım seviyeniz görsel efekt yükünden daha çok etkilenir.' }
            else { if ($tw.Level -eq 'Önerilir') { $cat = 'Güvenli' } else { $cat = 'Gelişmiş' } }
        } elseif ($tw.Cat -eq 'Gizlilik') {
            $impact = 'Performans etkisi yok; gizlilik ve öneri gürültüsü azalır'
        } elseif ($tw.Id -eq 'startdelay') {
            $cat = 'Gelişmiş'; $impact = 'Başlangıç uygulamaları yaklaşık 10 sn erken başlar; masaüstü açılırken yük artabilir'
            if ($p.Strong) { $why += ' SSD ve güçlü işlemcide yük artışı genelde sorun olmaz.' } else { $why += ' Zayıf donanımda masaüstü açılışında takılma olabilir.' }
        } elseif ($tw.Level -ne 'Önerilir') { $cat = 'Gelişmiş' }
        $risk = 'Düşük'; if ($tw.Level -eq 'İsteğe bağlı' -and -not $cosmetic) { $risk = 'Orta' }
        $out += New-SmRec $cat ("{0} -> {1}" -f $tw.Name, $tw.RecLabel) ("{0} Olası yan etki: {1}" -f $tw.What, $tw.Effect) $why $risk $impact `
            'Uygulamadan önce önceki değer yedeklenir; "Son Uygulamayı Geri Al" ile eski değere döner.' 'Tweak' @{ Id = $tw.Id; When = $tw.When }
    }
    return $out
}

# 3) Başlangıç uygulamalarını incele
function Get-SmStartupRecs($p) {
    $out = @()
    $items = @($script:Items)
    if ($items.Count -eq 0) { try { $items = @(Get-RegistryEntries) + @(Get-FolderEntries) + @(Get-TaskEntries) } catch {} }
    $cand = @($items | Where-Object { $_.Enabled -and -not $_.Protected -and ($_.Type -ne 'Registry' -or $_.Extra.Manageable) -and ([string]$_.Publisher -notmatch 'Microsoft') })
    $scored = foreach ($it in $cand) {
        $sec = 0.0
        if ([string]$it.Impact -match '^([0-9]+([.,][0-9]+)?)') { $sec = [double](($Matches[1]) -replace ',', '.') }
        [pscustomobject]@{ It = $it; Sec = $sec }
    }
    foreach ($s in ($scored | Sort-Object @{e = { $_.Sec }; Descending = $true }, @{e = { $_.It.Name } } | Select-Object -First 8)) {
        $it = $s.It
        $cat = 'Gelişmiş'; $impact = 'Ölçülmedi; açılışta bir işlem ve bir miktar RAM azalır (süre kazancı garanti edilmez)'
        $why = "Windows oturum açılışında '$($it.Name)' uygulamasını otomatik başlatıyor ($($it.Source))."
        if ($s.Sec -ge 1) {
            $cat = 'Güvenli'; $impact = ('Ölçülen başlatma gecikmesi: {0:N1} sn (açılışı kısaltma garantisi yok)' -f $s.Sec)
            $why += (' Windows tanılama kaydı bu uygulamanın başlatmayı {0:N1} sn geciktirdiğini gösteriyor.' -f $s.Sec)
        }
        if ($p.Weak) { $why += ' Donanım seviyeniz için başlangıç yükünü azaltmak daha belirgin fayda sağlar.' }
        $ex = $it.Extra
        $out += New-SmRec $cat ("Başlangıçtan kaldır: $($it.Name)") "Uygulama silinmez; yalnızca Windows ile otomatik başlaması durdurulur. Yayıncı: $($it.Publisher)." $why 'Düşük' $impact `
            'Yeniden etkinleştirilebilir ("Son Uygulamayı Geri Al" veya Başlangıç sekmesi); uygulama silinmez.' 'Startup' `
            @{ Name = $it.Name; Type = $it.Type; Hive = $ex.Hive; Approved = $ex.Approved; ValueName = $ex.ValueName; TaskName = $ex.TaskName; TaskPath = $ex.TaskPath }
    }
    return $out
}

# 6) Servisleri analiz et (en fazla 5, Servisler sekmesindeki koruma kuralları geçerli)
function Get-SmServiceRecs($p) {
    $out = @()
    if (-not $script:SvcLoaded) { try { Update-ServiceList } catch {} }
    $n = 0
    foreach ($s in ($script:Svcs | Sort-Object Name)) {
        if ($n -ge 5) { break }
        if ($s.Protected) { continue }
        if ($s.StartKey -notin @('Automatic', 'AutomaticDelayed')) { continue }
        if (-not $s.Category) { continue }
        $risk = 'Orta'
        if ($s.Category -like 'İsteğe bağlı:*') {
            if ($s.Advice -like 'Yazıcı bulundu*') { continue }
            if ($s.Name -ne 'DiagTrack') { $risk = 'Düşük' }
        } elseif ($s.Category -notlike '*yardımcı/güncelleyici*') { continue }
        $note = ''
        if ($s.Category -like '*Xbox*') { $note = ' Xbox/Game Pass/oyun kaydı kullanıyorsanız bu öneriyi atlayın.' }
        $n++
        $out += New-SmRec 'Gelişmiş' ("Servis başlangıcını 'Elle' yap: $($s.Display)") ("Servis ($($s.Name)) Otomatik yerine Elle başlar; gerektiğinde Windows kendisi başlatır. Servis silinmez, çalışan servis durdurulmaz.") `
            ("Servis otomatik başlıyor ve kategorisi '$($s.Category)'. $($s.Advice).$note") $risk 'Düşük; arka plan işlemi ve az miktarda RAM/CPU azalır' `
            'Önceki başlangıç türü kaydedilir; "Son Uygulamayı Geri Al" ile geri yüklenir.' 'Service' @{ Name = $s.Name; Display = $s.Display; PrevKey = $s.StartKey }
    }
    return $out
}

# 4-5) Arka plan işlemleri ve RAM/CPU: yalnızca öneri (kapatma İşlemler sekmesinde onayla yapılır)
function Get-SmProcessRecs($p) {
    $out = @()
    foreach ($it in ($script:Snap | Where-Object { Test-CloseSuggestion $_ } | Sort-Object WsMB -Descending | Select-Object -First 5)) {
        $min = $it.Idle * $script:SampleMs / 60000
        $out += New-SmRec 'Gelişmiş' ("Kapatmayı düşünün: $($it.Name) (PID $($it.Id))") ('{0:N0} MB RAM tutuyor ve yaklaşık {1:N0} dk boşta.' -f $it.WsMB, $min) `
            ('Uzun süredir CPU kullanmayan arka plan işlemi.' + $(if ($script:Sys -and $script:Sys.Pct -ge 80) { " Sistem RAM kullanımı %$([math]::Round($script:Sys.Pct)) ile yüksek." } else { '' })) 'Orta' ('{0:N0} MB RAM serbest kalabilir' -f $it.WsMB) `
            'Uygulamayı yeniden açabilirsiniz (kaydedilmemiş veri kaybolabilir).' 'Info' @{ Pid = $it.Id }
    }
    return $out
}

# 7) Temizlenebilir dosyalar (Derin Temizlik modülünün güvenli kuralları kullanılır)
function Get-SmTempRec($p) {
    try {
        if ($script:ClBusy) { return @() }
        $script:ClCancel = $false
        $def = Get-CleanDefs | Where-Object { $_.Id -eq 'usertemp' } | Select-Object -First 1
        if (-not $def) { return @() }
        $res = Search-CleanCategory $def
        if ($res.Count -gt 0 -and $res.Bytes -ge 50MB) {
            $why = 'Kullanıcı TEMP klasöründe eski (kullanılmayan) geçici dosyalar birikmiş.'
            $sysFree = Get-SystemFree
            if ($sysFree -gt 0 -and $sysFree -lt 20GB) { $why += ' Sistem sürücüsünde boş alan az.' }
            return @(New-SmRec 'Güvenli' 'Geçici dosyaları temizle (Kullanıcı TEMP)' ("{0:N0} dosya, toplam {1}. Kullanımdaki/erişim engelli dosyalar atlanır; Windows ve sistem klasörlerine dokunulmaz." -f $res.Count, (Format-Bytes $res.Bytes)) $why 'Düşük' ("Yaklaşık {0} boş alan" -f (Format-Bytes $res.Bytes)) `
                'Geri alınamaz (geçici dosyalar silinir); uygulamalar gerekirse yeniden oluşturur.' 'Temp' @{ Res = $res })
        }
    } catch { Write-Log ('Akıllı motor temizlik taraması hatası: ' + $_.Exception.Message) }
    return @()
}

# 8) Güç planı (yalnızca masaüstü bilgisayarlarda önerilir)
function Get-SmPowerRec($p) {
    try {
        if ($p.Laptop) { return @() }
        $plans = @(Get-PowerPlans)
        $hp = $plans | Where-Object { $_.Guid -eq $script:HpGuid } | Select-Object -First 1
        $act = $plans | Where-Object { $_.Active } | Select-Object -First 1
        if ($hp -and $act -and $act.Guid -ne $hp.Guid) {
            return @(New-SmRec 'Oyun' "Güç planı: $($act.Name) -> $($hp.Name)" (Get-PlanText $hp.Guid $hp.Name) `
                'Masaüstü bilgisayar algılandı (pil yok); yüksek performans planı işlemci hızını daha yüksek tutar.' 'Düşük' 'Düşük-orta; güç tüketimi ve ısı artar, FPS artışı garanti edilmez' `
                "Önceki plan ($($act.Name)) geri yüklenir." 'Power' @{ Guid = $hp.Guid; PrevGuid = $act.Guid; PrevName = $act.Name })
        }
    } catch {}
    return @()
}

function Invoke-SmAnalyze {
    if ($script:SmBusy) { return }
    $script:SmBusy = $true; $form.Cursor = 'WaitCursor'; $script:Timer.Stop()
    try {
        $lblSm.Text = '  1/5 Donanım ve Windows sürümü tanınıyor...'; $form.Refresh()
        $p = Get-SmProfile; $script:SmProfile = $p
        $lblSm.Text = '  2/5 Windows ayarları inceleniyor...'; $form.Refresh()
        $recs = @(Get-SmTweakRecs $p)
        $lblSm.Text = '  3/5 Başlangıç uygulamaları inceleniyor...'; $form.Refresh()
        $recs += @(Get-SmStartupRecs $p)
        $lblSm.Text = '  4/5 Servisler ve arka plan işlemleri inceleniyor...'; $form.Refresh()
        $recs += @(Get-SmServiceRecs $p)
        $recs += @(Get-SmProcessRecs $p)
        $lblSm.Text = '  5/5 Temizlenebilir dosyalar ve güç planı inceleniyor...'; $form.Refresh()
        $recs += @(Get-SmTempRec $p)
        $recs += @(Get-SmPowerRec $p)
        $script:SmRecs = @($recs | Where-Object { $_ })
        Show-SmGrid
        $prof = '{0} (derleme {1}) | {2} | {3} çekirdek | {4:N1} GB RAM | {5} | {6}{7} -> {8}' -f $p.Win, $p.Build, $p.Cpu, $p.Cores, $p.RamGB, $p.Gpu, $(if ($p.Laptop) { 'dizüstü' } else { 'masaüstü' }), $(if ($p.HasHdd) { ', HDD var' } else { '' }), (Get-SmLevelText $p)
        $lblSm.Text = "  Profil: $prof  |  Öneri: $($script:SmRecs.Count)"
        if ($script:SmRecs.Count -eq 0) { $txtSmInfo.Text = 'Şu an önerilecek bir optimizasyon bulunamadı. Not: boşta işlem önerileri için uygulamanın en az 5 dk açık kalması gerekir.' }
    } catch {
        $lblSm.Text = '  Hata: ' + $_.Exception.Message
        Write-Log ('Akıllı optimizasyon analiz hatası: ' + $_.Exception.Message)
    } finally { $form.Cursor = 'Default'; $script:Timer.Start(); $script:SmBusy = $false }
}

function Show-SmGrid {
    $gridSm.Rows.Clear()
    $order = @{ 'Güvenli' = 0; 'Gelişmiş' = 1; 'Oyun' = 2 }
    foreach ($r in ($script:SmRecs | Sort-Object @{e = { $order[$_.Cat] } }, Name)) {
        if (($r.Cat -eq 'Güvenli' -and -not $chkSmSafe.Checked) -or ($r.Cat -eq 'Gelişmiş' -and -not $chkSmAdv.Checked) -or ($r.Cat -eq 'Oyun' -and -not $chkSmGame.Checked)) { continue }
        $i = $gridSm.Rows.Add([object[]]@($r.Cat, $r.Name, $r.Desc, $r.Why, $r.Risk, $r.Impact, $r.Undo, $r.Status))
        $row = $gridSm.Rows[$i]; $row.Tag = $r
        if ($r.Risk -eq 'Orta') { $row.DefaultCellStyle.BackColor = [Drawing.Color]::LightYellow }
        elseif ($r.Risk -eq 'Yüksek') { $row.DefaultCellStyle.BackColor = [Drawing.Color]::MistyRose }
        if ($r.Kind -eq 'Info') { $row.DefaultCellStyle.ForeColor = [Drawing.Color]::DimGray }
        if ($r.Status -like 'Uygulandı*') { $row.DefaultCellStyle.ForeColor = [Drawing.Color]::Gray }
    }
}

function Show-SmDetail {
    $sel = @($gridSm.SelectedRows | ForEach-Object { $_.Tag } | Where-Object { $_ })
    if ($sel.Count -eq 0) { return }
    $r = $sel[0]
    $txtSmInfo.Text = (@("İşlem adı: $($r.Name)   [Kategori: $($r.Cat)]", "Açıklama: $($r.Desc)", "Neden önerildi: $($r.Why)", "Risk seviyesi: $($r.Risk)", "Beklenen etki: $($r.Impact)", "Geri alma imkânı: $($r.Undo)") -join "`r`n")
}
$gridSm.Add_SelectionChanged({ try { Show-SmDetail } catch {} })

function Read-SmLog {
    if (Test-Path -LiteralPath $SmartFile) {
        try {
            $x = Get-Content -LiteralPath $SmartFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -eq $x) { return @() }
            return @($x | ForEach-Object { $_ })
        } catch {}
    }
    return @()
}
function Save-SmLog($recs) { ConvertTo-Json -InputObject @($recs) -Depth 8 | Set-Content -LiteralPath $SmartFile -Encoding UTF8 }

function Invoke-SmApply([object[]]$Preset = $null) {
    if ($script:SmBusy) { return }
    if ($Preset -and @($Preset).Count -gt 0) { $sel = @($Preset) }
    else { $sel = @($gridSm.SelectedRows | ForEach-Object { $_.Tag } | Where-Object { $_ }) }
    $todo = @($sel | Where-Object { $_.Kind -ne 'Info' -and $_.Status -notlike 'Uygulandı*' })
    $infoN = @($sel | Where-Object { $_.Kind -eq 'Info' }).Count
    if ($todo.Count -eq 0) {
        $m = 'Önce listeden uygulanabilir bir veya daha fazla öneri seçin.'
        if ($infoN -gt 0) { $m += "`n`n'Yalnızca öneri' satırları otomatik uygulanmaz; işlem kapatma İşlemler sekmesinde onayınızla yapılır." }
        [L10nMsg]::Show($m, 'WinOpt Suite - Developed by Leone') | Out-Null; return
    }
    $msg = "Şu $($todo.Count) değişiklik yapılacak:`n`n" + (($todo | ForEach-Object { "  • [{0}] {1}  (Risk: {2})`n      Geri alma: {3}" -f $_.Cat, $_.Name, $_.Risk, $_.Undo }) -join "`n")
    if ($infoN -gt 0) { $msg += "`n`n($infoN 'yalnızca öneri' satırı atlanacak.)" }
    $msg += "`n`nHer değişiklikten önce önceki durum kaydedilir. Devam edilsin mi?"
    if ([L10nMsg]::Show($msg, 'Değişiklikleri onayla', 'YesNo', 'Question') -ne 'Yes') { return }

    $script:SmBusy = $true; $form.Cursor = 'WaitCursor'; $script:Timer.Stop()
    $session = [guid]::NewGuid().ToString(); $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $logRecs = @(); $lines = @(); $ok = 0; $fail = 0; $failList = @()
    $free0 = Get-SystemFree; $tStart = Get-Date; $perfBefore = $null; $perfAfter = $null
    try {
        $lblSm.Text = '  İşlem öncesi CPU/RAM ölçülüyor (~5 sn)...'; [Windows.Forms.Application]::DoEvents()
        $perfBefore = Get-PerfSample
        foreach ($r in $todo) {
            $undo = $null
            try {
                $lblSm.Text = "  Uygulanıyor: $($r.Name)"; [Windows.Forms.Application]::DoEvents()
                switch ($r.Kind) {
                    'Tweak' {
                        $tw = Get-TweakById $r.Data.Id
                        $prev = Get-TweakPrev $tw
                        try { Set-TweakItems $tw 'Rec' } catch { Restore-TweakPrev $prev; throw }
                        $undo = @{ Prev = @($prev) }
                        if ($r.Data.When -and $r.Data.When -ne 'Hemen') { $r.Status = "Uygulandı ($($r.Data.When))" } else { $r.Status = 'Uygulandı' }
                    }
                    'Startup' {
                        $d = $r.Data
                        if ($d.Type -eq 'Görev') { Disable-ScheduledTask -TaskName $d.TaskName -TaskPath $d.TaskPath -ErrorAction Stop | Out-Null }
                        else { Set-ApprovedState $d.Hive $d.Approved $d.ValueName $false }
                        $undo = @{ Type = $d.Type; Hive = $d.Hive; Approved = $d.Approved; ValueName = $d.ValueName; TaskName = $d.TaskName; TaskPath = $d.TaskPath }
                        $r.Status = 'Uygulandı'
                    }
                    'Service' {
                        $live = Get-LiveSvc $r.Data.Name
                        Set-SvcStartType $r.Data.Name 'Manual'
                        $undo = @{ Name = $r.Data.Name; PrevKey = $live.StartKey }
                        $r.Status = 'Uygulandı'
                    }
                    'Power' {
                        $prevG = Get-ActivePowerGuid
                        Set-PowerPlanByGuid $r.Data.Guid
                        $undo = @{ PrevGuid = $prevG }
                        $r.Status = 'Uygulandı'
                    }
                    'Temp' {
                        $res = $r.Data.Res; $freed = [long]0; $del = 0; $skip = 0; $i = 0
                        foreach ($rec in $res.Files) {
                            $i++
                            if (($i % 50) -eq 0) { $lblSm.Text = ('  Temizleniyor: {0:N0}/{1:N0}' -f $i, $res.Count); [Windows.Forms.Application]::DoEvents() }
                            $x = Remove-CleanFile $rec $res.Roots
                            if ($x -eq 'ok') { $freed += [long]$rec[1]; $del++ } else { $skip++ }
                        }
                        $cut = $null; if ($res.MinDays -gt 0) { $cut = (Get-Date).AddDays(-$res.MinDays) }
                        if ($res.Def.RemoveDirs) { [void](Remove-CleanEmptyDirs $res.Dirs $res.Roots $cut) }
                        Add-CleanHistory $CleanHistFile ([pscustomobject][ordered]@{ 'Zaman' = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); 'Kategori' = 'Kullanıcı TEMP klasörü (Akıllı Optimizasyon)'
                            'Silinen' = $del; 'Atlanan' = $skip; 'Kazanılan bayt' = $freed; 'Kazanılan alan' = (Format-Bytes $freed) })
                        $undo = @{ Note = 'Geri alınamaz'; Freed = $freed }
                        $r.Status = ('Uygulandı ({0})' -f (Format-Bytes $freed))
                        $lines += ('    Temizlik: {0:N0} silindi, {1:N0} atlandı, {2} kazanıldı' -f $del, $skip, (Format-Bytes $freed))
                    }
                }
                $logRecs += [pscustomobject]@{ Id = [guid]::NewGuid().ToString(); Oturum = $session; Zaman = $stamp; Kind = $r.Kind; Ad = $r.Name; Risk = $r.Risk; Undo = $undo; GeriAlindi = ($r.Kind -eq 'Temp') }
                Write-Log ("AKILLI OPTİMİZASYON: {0} [{1}]" -f $r.Name, $r.Cat)
                $lines += ("  ✓ [{0}] {1}  -> {2}" -f $r.Cat, $r.Name, $r.Status)
                $ok++
            } catch {
                $r.Status = 'Hata'; $fail++
                Write-Log ("AKILLI OPTİMİZASYON HATA: {0}: {1}" -f $r.Name, $_.Exception.Message)
                $lines += ("  ✗ [{0}] {1}  -> HATA: {2}" -f $r.Cat, $r.Name, $_.Exception.Message)
                $failList += ("{0}: {1}" -f $r.Name, $_.Exception.Message)
            }
        }
        if ($logRecs.Count -gt 0) { Save-SmLog (@(Read-SmLog) + $logRecs) }
        $lblSm.Text = '  İşlem sonrası CPU/RAM ölçülüyor (~5 sn)...'; [Windows.Forms.Application]::DoEvents()
        $perfAfter = Get-PerfSample
    } finally { $form.Cursor = 'Default'; $script:Timer.Start(); $script:SmBusy = $false }

    $freed = [long](($logRecs | Where-Object { $_.Kind -eq 'Temp' } | ForEach-Object { [long]$_.Undo.Freed } | Measure-Object -Sum).Sum)
    $rv = New-PerfReport @{ Source = 'Akıllı Optimizasyon'; Slug = 'optimizasyon'; Start = $tStart; End = (Get-Date); Before = $perfBefore; After = $perfAfter; FreedBytes = $freed
        Startups = @($logRecs | Where-Object { $_.Kind -eq 'Startup' } | ForEach-Object { $_.Ad -replace '^Başlangıçtan kaldır: ', '' })
        Services = @($logRecs | Where-Object { $_.Kind -eq 'Service' } | ForEach-Object { '{0} (önceki başlangıç türü: {1} -> Elle)' -f $_.Ad, $_.Undo.PrevKey })
        Tweaks = @($logRecs | Where-Object { $_.Kind -in @('Tweak', 'Power') } | ForEach-Object { $_.Ad })
        Reversible = @($logRecs | Where-Object { $_.Kind -ne 'Temp' } | ForEach-Object { $_.Ad })
        Irreversible = @($logRecs | Where-Object { $_.Kind -eq 'Temp' } | ForEach-Object { $_.Ad + ' (silinen geçici dosyalar geri alınamaz)' })
        Failures = $failList; Notes = @('Bazı Windows ayarları (ör. Explorer gerektirenler) oturumu yeniden açınca etkili olur; bu yüzden sonrası ölçümde görünmeyebilir.') }
    $script:SmReport = $rv.Text
    Show-SmGrid
    $lblSm.Text = "  Uygulama bitti: $ok başarılı, $fail hatalı."
    Show-TextDialog 'Akıllı Optimizasyon raporu' $script:SmReport
}

function Invoke-SmUndo {
    if ($script:SmBusy) { return }
    $all = @(Read-SmLog)
    $pending = @($all | Where-Object { -not $_.GeriAlindi })
    if ($pending.Count -eq 0) { [L10nMsg]::Show('Geri alınacak bir Akıllı Optimizasyon işlemi yok (geçici dosya temizliği geri alınamaz).', 'WinOpt Suite - Developed by Leone') | Out-Null; return }
    $lastSession = ($pending | Select-Object -Last 1).Oturum
    $batch = @($pending | Where-Object { $_.Oturum -eq $lastSession })
    $msg = "Son uygulamadaki $($batch.Count) değişiklik geri alınacak:`n`n" + (($batch | ForEach-Object { '  • ' + $_.Ad }) -join "`n") + "`n`nDevam edilsin mi?"
    if ([L10nMsg]::Show($msg, 'Geri almayı onayla', 'YesNo', 'Question') -ne 'Yes') { return }
    $script:SmBusy = $true; $form.Cursor = 'WaitCursor'
    $lines = @(); $ok = 0; $fail = 0
    try {
        $rev = @($batch); [Array]::Reverse($rev)
        foreach ($b in $rev) {
            try {
                $u = $b.Undo
                switch ($b.Kind) {
                    'Tweak'   { Restore-TweakPrev $u.Prev }
                    'Startup' {
                        if ($u.Type -eq 'Görev') { Enable-ScheduledTask -TaskName $u.TaskName -TaskPath $u.TaskPath -ErrorAction Stop | Out-Null }
                        else { Set-ApprovedState $u.Hive $u.Approved $u.ValueName $true }
                    }
                    'Service' { if ($script:StartKeys -contains $u.PrevKey) { Set-SvcStartType $u.Name $u.PrevKey } else { throw 'Önceki başlangıç türü tanınmıyor' } }
                    'Power'   { if ($u.PrevGuid) { Set-PowerPlanByGuid $u.PrevGuid } }
                }
                foreach ($a in $all) { if ($a.Id -eq $b.Id) { $a.GeriAlindi = $true } }
                Write-Log ("AKILLI OPTİMİZASYON GERİ ALINDI: " + $b.Ad)
                $lines += "  ✓ Geri alındı: $($b.Ad)"; $ok++
            } catch {
                $fail++; $lines += "  ✗ Geri alınamadı: $($b.Ad) -> $($_.Exception.Message)"
                Write-Log ("AKILLI OPTİMİZASYON GERİ ALMA HATA: {0}: {1}" -f $b.Ad, $_.Exception.Message)
            }
        }
        Save-SmLog $all
    } finally { $form.Cursor = 'Default'; $script:SmBusy = $false }
    $lblSm.Text = "  Geri alma bitti: $ok başarılı, $fail hatalı. Güncel durum için Analiz Et'e basın."
    [L10nMsg]::Show((("Geri alma tamamlandı: $ok başarılı, $fail hatalı.`n`n") + ($lines -join "`n")), 'WinOpt Suite - Developed by Leone') | Out-Null
}

function Get-SmAnalysisText {
    $p = $script:SmProfile
    $t = @('Akıllı Optimizasyon - analiz özeti', ('-' * 64))
    if ($p) { $t += ('{0} (derleme {1}) | {2} | {3} çekirdek | {4:N1} GB RAM | {5}' -f $p.Win, $p.Build, $p.Cpu, $p.Cores, $p.RamGB, $p.Gpu); $t += '' }
    foreach ($r in $script:SmRecs) {
        $t += ("[{0}] {1}  (Risk: {2}, Durum: {3})" -f $r.Cat, $r.Name, $r.Risk, $r.Status)
        $t += "    Açıklama: $($r.Desc)"; $t += "    Neden: $($r.Why)"; $t += "    Beklenen etki: $($r.Impact)"; $t += "    Geri alma: $($r.Undo)"; $t += ''
    }
    if ($script:SmReport) { $t += ('=' * 64); $t += $script:SmReport }
    return ($t -join [Environment]::NewLine)
}

$chkSmSafe = New-Chk $barSm 'Güvenli' $true { Show-SmGrid }
$chkSmAdv  = New-Chk $barSm 'Gelişmiş' $true { Show-SmGrid }
$chkSmGame = New-Chk $barSm 'Oyun' $true { Show-SmGrid }
New-Btn $barSm 'Analiz Et' 100 { Invoke-SmAnalyze }
New-Btn $barSm 'Güvenli Olanları Seç' 160 { foreach ($row in $gridSm.Rows) { $row.Selected = ($row.Tag -and $row.Tag.Cat -eq 'Güvenli' -and $row.Tag.Kind -ne 'Info' -and $row.Tag.Status -notlike 'Uygulandı*') } }
New-Btn $barSm 'Tümünü Seç' 100 { foreach ($row in $gridSm.Rows) { $row.Selected = ($row.Tag -and $row.Tag.Kind -ne 'Info' -and $row.Tag.Status -notlike 'Uygulandı*') } }
New-Btn $barSm 'Seçimi Temizle' 120 { $gridSm.ClearSelection() }
New-Btn $barSm 'Seçilileri Uygula' 140 { Invoke-SmApply }
New-Btn $barSm 'Son Uygulamayı Geri Al' 180 { Invoke-SmUndo }
New-Btn $barSm 'Rapor' 80 { if ($script:SmRecs.Count -eq 0 -and -not $script:SmReport) { [L10nMsg]::Show('Önce Analiz Et düğmesine basın.', 'WinOpt Suite - Developed by Leone') | Out-Null } else { Show-TextDialog 'Akıllı Optimizasyon raporu' (Get-SmAnalysisText) } }

$lblSm.Text = '  Başlamak için "Analiz Et" düğmesine basın. Hiçbir değişiklik sizin onayınız olmadan yapılmaz.'
$tabs.Add_SelectedIndexChanged({ try { if ($tabs.SelectedTab -eq $tabSmart -and $script:SmRecs.Count -eq 0 -and -not $script:SmBusy -and -not $script:SmAutoRan) { $script:SmAutoRan = $true; Invoke-SmAnalyze } } catch {} })
