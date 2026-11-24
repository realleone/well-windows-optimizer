$tabRam = New-Object Windows.Forms.TabPage
$tabRam.Text = 'RAM'
[void]$tabs.TabPages.Add($tabRam)

$gridRam = New-StdGrid @(@('İşlem', 200), @('Örnek', 70), @('RAM MB', 100), @('Toplam RAM %', 100), @('Not', 480))
$gridRam.Columns[2].DefaultCellStyle.Format = 'N0'
$gridRam.Columns[3].DefaultCellStyle.Format = 'N1'
$tabRam.Controls.Add($gridRam)

$txtRamAdvice = New-Object Windows.Forms.TextBox
$txtRamAdvice.Multiline = $true; $txtRamAdvice.ReadOnly = $true; $txtRamAdvice.ScrollBars = 'Vertical'
$txtRamAdvice.Dock = 'Bottom'; $txtRamAdvice.Height = 120; $txtRamAdvice.BackColor = [Drawing.Color]::White
$tabRam.Controls.Add($txtRamAdvice)

$panRamTop = New-Object Windows.Forms.Panel
$panRamTop.Dock = 'Top'; $panRamTop.Height = 252
$tabRam.Controls.Add($panRamTop)

$lblRam = New-Object Windows.Forms.Label
$lblRam.Location = New-Object Drawing.Point(10, 8); $lblRam.AutoSize = $true
$lblRam.Font = New-Object Drawing.Font('Segoe UI', 11, [Drawing.FontStyle]::Bold)
$lblRam.Text = 'Ölçülüyor...'
$panRamTop.Controls.Add($lblRam)

$pbRam = New-Object Windows.Forms.ProgressBar
$pbRam.Location = New-Object Drawing.Point(10, 38); $pbRam.Size = New-Object Drawing.Size(900, 20)
$pbRam.Anchor = 'Top,Left,Right'
$panRamTop.Controls.Add($pbRam)

$graphRam = New-Object Windows.Forms.Panel
$graphRam.Location = New-Object Drawing.Point(10, 64); $graphRam.Size = New-Object Drawing.Size(900, 140)
$graphRam.Anchor = 'Top,Left,Right'; $graphRam.BackColor = [Drawing.Color]::White; $graphRam.BorderStyle = 'FixedSingle'
$graphRam.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'Instance,NonPublic').SetValue($graphRam, $true, $null)
$graphRam.Add_Paint({
    param($s, $e)
    $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'
    $w = $s.ClientSize.Width; $h = $s.ClientSize.Height
    $gpen = New-Object Drawing.Pen([Drawing.Color]::Gainsboro)
    foreach ($p in 25, 50, 75) { $y = $h - ($h * $p / 100.0); $g.DrawLine($gpen, 0, [single]$y, $w, [single]$y) }
    $gpen.Dispose()
    $data = $script:TotalHist.ToArray()
    if ($data.Count -ge 2) {
        $step = $w / 119.0
        $pts = New-Object 'System.Collections.Generic.List[Drawing.PointF]'
        for ($i = 0; $i -lt $data.Count; $i++) {
            $x = $w - ($data.Count - 1 - $i) * $step
            $y = $h - ($h * $data[$i] / 100.0)
            $pts.Add((New-Object Drawing.PointF([single]$x, [single]$y)))
        }
        $pen = New-Object Drawing.Pen([Drawing.Color]::SteelBlue, 2)
        $g.DrawLines($pen, $pts.ToArray())
        $pen.Dispose()
    }
    $g.DrawString('Sistem RAM kullanımı % (son ~6 dk)', $s.Font, [Drawing.Brushes]::Gray, 4, 2)
})
$panRamTop.Controls.Add($graphRam)

New-Btn $panRamTop 'Bellek Geçmişini Göster' 170 { Show-CsvDialog $RamHistFile 'Bellek kullanım geçmişi' }
$panRamTop.Controls[$panRamTop.Controls.Count - 1].Location = New-Object Drawing.Point(10, 212)
$lblRamNote = New-Object Windows.Forms.Label
$lblRamNote.Location = New-Object Drawing.Point(190, 219); $lblRamNote.AutoSize = $true
$lblRamNote.Text = 'Bu sekme belleği zorla boşaltmaz ve uygulama kapatmaz. Geçmiş, uygulama açıkken dakikada bir kaydedilir.'
$panRamTop.Controls.Add($lblRamNote)

function Show-Ram {
    if (-not $script:Sys) { return }
    $s = $script:Sys
    $lblRam.Text = ('Toplam: {0:N1} GB      Kullanılan: {1:N1} GB (%{2:N0})      Kullanılabilir: {3:N1} GB' -f ($s.TotalMB / 1024), ($s.UsedMB / 1024), $s.Pct, ($s.FreeMB / 1024))
    $pbRam.Value = [int][math]::Min(100, [math]::Max(0, $s.Pct))
    $graphRam.Invalidate()

    $groups = @($script:Snap | Group-Object Name | ForEach-Object {
        $g = @($_.Group)
        [pscustomobject]@{
            Name = $_.Name; Count = $g.Count
            MB = ($g | Measure-Object WsMB -Sum).Sum
            Leak = (@($g | Where-Object { $_.Leak }).Count -gt 0)
            Sys = (@($g | Where-Object { $_.Protection }).Count -eq $g.Count)
            Sug = (@($g | Where-Object { Test-CloseSuggestion $_ }).Count -gt 0)
        } } | Sort-Object MB -Descending | Select-Object -First 15)

    $gridRam.Rows.Clear()
    foreach ($g in $groups) {
        $n = @()
        if ($g.Sys) { $n += 'Sistem bileşeni' }
        if ($g.Leak) { $n += 'Bellek sızıntısı şüphesi' }
        if ($g.Sug) { $n += 'Kapatma önerisi' }
        [void]$gridRam.Rows.Add([object[]]@($g.Name, $g.Count, $g.MB, ($g.MB / $s.TotalMB * 100), ($n -join '; ')))
    }

    $obs = $script:SampleCount * $script:SampleMs / 60000
    $lines = @()
    foreach ($it in ($script:Snap | Where-Object { Test-CloseSuggestion $_ } | Sort-Object WsMB -Descending | Select-Object -First 5)) {
        $lines += ('• {0} (PID {1}): {2:N0} MB tutuyor, yaklaşık {3:N0} dk boşta. Kullanmıyorsanız İşlemler sekmesinden onayınızla kapatabilirsiniz.' -f $it.Name, $it.Id, $it.WsMB, ($it.Idle * $script:SampleMs / 60000))
    }
    foreach ($it in ($script:Snap | Where-Object { $_.Leak } | Sort-Object PrivMB -Descending | Select-Object -First 5)) {
        $h = $script:MemHist[$it.Id]
        $lines += ('• {0} (PID {1}): özel bellek gözlem boyunca {2:N0} MB -> {3:N0} MB arttı (sızıntı şüphesi, kesin değildir). Uygulamayı yeniden başlatmak sorunu çözebilir.' -f $it.Name, $it.Id, $h[0], $h[$h.Count - 1])
    }
    if ($lines.Count -eq 0) { $lines = @(('Şu an öneri yok. Gözlem süresi: {0:N0} dk (sızıntı tespiti için en az 3 dk, boşta tespiti için 5 dk gerekir).' -f $obs)) }
    $txtRamAdvice.Text = ($lines -join [Environment]::NewLine)
}
