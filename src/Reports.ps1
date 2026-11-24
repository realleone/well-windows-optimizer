$ReportDir = Join-Path $AppDir 'raporlar'
$ReportCsv = Join-Path $AppDir 'rapor-ozeti.csv'
if (-not (Test-Path -LiteralPath $ReportDir)) { New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null }

function Wait-Ms([int]$ms) {
    $end = [DateTime]::UtcNow.AddMilliseconds($ms)
    while ([DateTime]::UtcNow -lt $end) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 50 }
}

# Önce/sonra ölçümü her seferinde aynı yöntemle yapılır: 5 ardışık örnek (1 sn aralık), ilk örnek atılır, ortalama alınır.
function Get-PerfSample([int]$n = 5) {
    $cpu = New-Object 'System.Collections.Generic.List[double]'
    $ram = New-Object 'System.Collections.Generic.List[double]'
    $pct = New-Object 'System.Collections.Generic.List[double]'
    for ($i = 0; $i -le $n; $i++) {
        $c = $null; $u = $null; $p = $null
        try { $c = [double](Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -ErrorAction Stop).PercentProcessorTime } catch {}
        try {
            $o = Get-CimInstance Win32_OperatingSystem -Property TotalVisibleMemorySize, FreePhysicalMemory -ErrorAction Stop
            $u = ($o.TotalVisibleMemorySize - $o.FreePhysicalMemory) / 1024.0
            $p = $u / ($o.TotalVisibleMemorySize / 1024.0) * 100
        } catch {}
        if ($i -gt 0) {
            if ($null -ne $c) { $cpu.Add($c) }
            if ($null -ne $u) { $ram.Add($u); $pct.Add($p) }
        }
        if ($i -lt $n) { Wait-Ms 1000 }
    }
    $r = @{ N = $n; CpuOk = ($cpu.Count -gt 0); RamOk = ($ram.Count -gt 0) }
    if ($r.CpuOk) { $m = $cpu | Measure-Object -Average -Minimum -Maximum; $r.Cpu = $m.Average; $r.CpuMin = $m.Minimum; $r.CpuMax = $m.Maximum }
    if ($r.RamOk) {
        $m = $ram | Measure-Object -Average -Minimum -Maximum; $r.RamMB = $m.Average; $r.RamMin = $m.Minimum; $r.RamMax = $m.Maximum
        $r.RamPct = ($pct | Measure-Object -Average).Average
    }
    return $r
}

function Get-PerfCompareLines($b, $a) {
    $L = @()
    if ($b -and $a -and $b.CpuOk -and $a.CpuOk) {
        $d = $a.Cpu - $b.Cpu
        $spread = [math]::Max(($b.CpuMax - $b.CpuMin), ($a.CpuMax - $a.CpuMin))
        $v = if ([math]::Abs($d) -le $spread) { 'fark ölçüm dalgalanması içinde; anlamlı değişiklik sayılmaz' } elseif ($d -lt 0) { 'düşük ölçüldü' } else { 'yüksek ölçüldü' }
        $L += ('CPU kullanımı : önce %{0:N1} (aralık %{1:N0}-%{2:N0})  ->  sonra %{3:N1} (aralık %{4:N0}-%{5:N0})   fark {6:+0.0;-0.0;0.0} puan: {7}' -f $b.Cpu, $b.CpuMin, $b.CpuMax, $a.Cpu, $a.CpuMin, $a.CpuMax, $d, $v)
    } else { $L += 'CPU kullanımı : ölçülemedi (Windows performans sayacı okunamadı)' }
    if ($b -and $a -and $b.RamOk -and $a.RamOk) {
        $d = $a.RamMB - $b.RamMB
        $spread = [math]::Max(($b.RamMax - $b.RamMin), ($a.RamMax - $a.RamMin))
        $v = if ([math]::Abs($d) -le $spread) { 'fark ölçüm dalgalanması içinde; anlamlı değişiklik sayılmaz' } elseif ($d -lt 0) { 'düşük ölçüldü' } else { 'yüksek ölçüldü' }
        $L += ('RAM kullanımı : önce {0:N0} MB (%{1:N1})  ->  sonra {2:N0} MB (%{3:N1})   fark {4:+0;-0;0} MB: {5}' -f $b.RamMB, $b.RamPct, $a.RamMB, $a.RamPct, $d, $v)
    } else { $L += 'RAM kullanımı : ölçülemedi' }
    return $L
}

function New-PerfReport($d) {
    $end = $d.End; if (-not $end) { $end = Get-Date }
    $t = @()
    $t += 'WinOpt Suite - Performans Raporu  |  Developed by Leone'
    $t += ('=' * 72)
    $t += ('Kaynak   : {0}' -f $d.Source)
    $t += ('Başlangıç: {0:yyyy-MM-dd HH:mm:ss}   Bitiş: {1:yyyy-MM-dd HH:mm:ss}   Süre: {2:N0} sn' -f $d.Start, $end, ($end - $d.Start).TotalSeconds)
    $t += ''
    $t += 'ÖLÇÜMLER (işlem öncesi / sonrası)'
    $t += '-' * 72
    $t += Get-PerfCompareLines $d.Before $d.After
    $t += 'Ölçüm koşulları: her değer, aynı yöntemle (5 ardışık örnek, 1 sn aralık, ortalama) işlemden hemen önce ve hemen sonra alınmıştır.'
    $t += 'Anlık ölçümlerdir; çalışan diğer uygulamalar sonucu etkileyebilir. Bu rapor "performans artışı yüzdesi" hesaplamaz ve hız kazancı iddia etmez.'
    $t += ''
    $t += 'TEMİZLENEN DİSK ALANI'
    $t += '-' * 72
    $t += $(if ($d.FreedBytes -gt 0) { Format-Bytes $d.FreedBytes } else { 'Yok (bu işlemde dosya silinmedi)' })
    $sections = @(
        @('DEVRE DIŞI BIRAKILAN BAŞLANGIÇ UYGULAMALARI', $d.Startups, 'Yok'),
        @('DEĞİŞTİRİLEN SERVİSLER', $d.Services, 'Yok'),
        @('UYGULANAN WINDOWS AYARLARI', $d.Tweaks, 'Yok'),
        @('GERİ ALINABİLİR DEĞİŞİKLİKLER', $d.Reversible, 'Yok'),
        @('GERİ ALINAMAYAN İŞLEMLER', $d.Irreversible, 'Yok'),
        @('BAŞARISIZ İŞLEMLER', $d.Failures, 'Yok')
    )
    foreach ($s in $sections) {
        $t += ''; $t += $s[0]; $t += '-' * 72
        $items = @($s[1] | Where-Object { $_ })
        if ($items.Count -eq 0) { $t += $s[2] } else { foreach ($i in $items) { $t += "  • $i" } }
    }
    if ($d.Notes) { $t += ''; $t += 'NOTLAR'; $t += '-' * 72; foreach ($n in @($d.Notes)) { $t += "  $n" } }
    if (@($d.Reversible | Where-Object { $_ }).Count -gt 0) { $t += ''; $t += 'Geri alma: Akıllı Optimizasyon sekmesinde "Son Uygulamayı Geri Al" düğmesi.' }
    $text = ($t -join [Environment]::NewLine)

    $path = $null
    try {
        $path = Join-Path $ReportDir ('{0:yyyyMMdd-HHmmss}-{1}.txt' -f $end, $d.Slug)
        [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding($true)))
        $b = $d.Before; $a = $d.After
        [pscustomobject][ordered]@{
            'Zaman' = $end.ToString('yyyy-MM-dd HH:mm:ss'); 'Kaynak' = $d.Source
            'CPU önce %' = $(if ($b -and $b.CpuOk) { [math]::Round($b.Cpu, 1) } else { '' }); 'CPU sonra %' = $(if ($a -and $a.CpuOk) { [math]::Round($a.Cpu, 1) } else { '' })
            'RAM önce %' = $(if ($b -and $b.RamOk) { [math]::Round($b.RamPct, 1) } else { '' }); 'RAM sonra %' = $(if ($a -and $a.RamOk) { [math]::Round($a.RamPct, 1) } else { '' })
            'Kazanılan bayt' = [long]$d.FreedBytes
            'Başlangıç' = @($d.Startups | Where-Object { $_ }).Count; 'Servis' = @($d.Services | Where-Object { $_ }).Count
            'Ayar' = @($d.Tweaks | Where-Object { $_ }).Count; 'Hata' = @($d.Failures | Where-Object { $_ }).Count
            'Rapor dosyası' = (Split-Path $path -Leaf)
        } | Export-Csv -LiteralPath $ReportCsv -Append -NoTypeInformation -Encoding UTF8
    } catch { Write-Log ('Rapor yazılamadı: ' + $_.Exception.Message) }
    return @{ Text = $text; Path = $path }
}

# ---------------- Raporlar sekmesi ----------------
$tabReports = New-Object Windows.Forms.TabPage
$tabReports.Text = 'Raporlar'
[void]$tabs.TabPages.Add($tabReports)
$gridRep = New-StdGrid @(@('Zaman', 160), @('Kaynak', 160), @('Dosya', 300))
$tabReports.Controls.Add($gridRep)
$barRep = New-Bar
$barRep.Height = 46
$tabReports.Controls.Add($barRep)

function Update-ReportList {
    $gridRep.Rows.Clear()
    foreach ($f in (Get-ChildItem -LiteralPath $ReportDir -Filter *.txt -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 200)) {
        $src = if ($f.Name -like '*-bakim.txt') { 'Otomatik Bakım' } elseif ($f.Name -like '*-optimizasyon.txt') { 'Akıllı Optimizasyon' } else { 'Diğer' }
        $i = $gridRep.Rows.Add([object[]]@($f.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'), $src, $f.Name))
        $gridRep.Rows[$i].Tag = $f.FullName
    }
}
function Open-SelectedReport {
    $r = @($gridRep.SelectedRows | ForEach-Object { $_.Tag } | Where-Object { $_ }) | Select-Object -First 1
    if ($r -and (Test-Path -LiteralPath $r)) { Show-TextDialog 'Performans raporu' ([IO.File]::ReadAllText($r, [Text.Encoding]::UTF8)) }
}
New-Btn $barRep 'Yenile' 90 { Update-ReportList }
New-Btn $barRep 'Raporu Aç' 110 { Open-SelectedReport }
New-Btn $barRep 'Klasörü Aç' 110 { Start-Process explorer.exe -ArgumentList "`"$ReportDir`"" }
New-Btn $barRep 'Özet CSV' 90 { if (Test-Path -LiteralPath $ReportCsv) { Show-CsvDialog $ReportCsv 'Rapor özeti' } else { [L10nMsg]::Show('Henüz rapor yok.', 'WinOpt Suite - Developed by Leone') | Out-Null } }
$gridRep.Add_CellDoubleClick({ try { Open-SelectedReport } catch {} })
$tabs.Add_SelectedIndexChanged({ try { if ($tabs.SelectedTab -eq $tabReports) { Update-ReportList } } catch {} })
