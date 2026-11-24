if (-not $Maintenance) {

function Test-PresetPick($r, [string]$mode) {
    if ($r.Kind -eq 'Info' -or $r.Status -like 'Uygulandı*') { return $false }
    switch ($mode) {
        'dengeli' { return ($r.Cat -eq 'Güvenli' -and $r.Risk -eq 'Düşük') }
        'hizli'   { return ((($r.Cat -eq 'Güvenli') -or ($r.Cat -eq 'Gelişmiş')) -and $r.Risk -eq 'Düşük') }
        'enhizli' { return $true }
        'oyun'    { return ((($r.Cat -eq 'Oyun') -or ($r.Kind -eq 'Temp')) -and $r.Risk -eq 'Düşük') }
    }
    return $false
}

function Invoke-QuickPreset([string]$mode) {
    if ($script:SmBusy) { return }
    $lblQuick.Text = 'Sistem analiz ediliyor, lütfen bekleyin...'; $form.Refresh()
    try {
        Invoke-SmAnalyze
        $pick = @($script:SmRecs | Where-Object { Test-PresetPick $_ $mode })
        if ($pick.Count -eq 0) {
            $lblQuick.Text = 'Bu mod için uygulanacak yeni bir ayar bulunamadı; sisteminiz bu mod için zaten uygun görünüyor.'
            return
        }
        Invoke-SmApply -Preset $pick
        if ($lblSm.Text -like '*Uygulama bitti*' -or $lblSm.Text -like '*Apply finished*' -or $lblSm.Text -like '*应用完成*' -or $lblSm.Text -like '*انتهى التطبيق*') { $lblQuick.Text = $lblSm.Text.Trim() + '  Ayrıntılar rapor penceresinde ve Raporlar sekmesinde.' }
        else { $lblQuick.Text = 'İşlem onaylanmadı, hiçbir değişiklik yapılmadı.' }
    } catch {
        $lblQuick.Text = 'Hata: ' + $_.Exception.Message
        Write-Log ('Hızlı mod hatası: ' + $_.Exception.Message)
    }
}

function New-QuickCard($m) {
    $c = New-Card 16
    $c.Dock = 'Fill'; $c.Margin = New-Object Windows.Forms.Padding(8)
    $ic = New-IconBox ([string][char]$m.Glyph) 52 $m.Fill $m.Fg
    $ic.Location = New-Object Drawing.Point(22, 22)
    $t = New-Lbl $m.Title 15 $true; $t.Location = New-Object Drawing.Point(22, 86)
    $tg = New-Lbl $m.Tag 9 $true $m.Fg; $tg.Location = New-Object Drawing.Point(24, 120)
    $d = New-Lbl $m.Desc 9 $false $script:Th.Muted
    $d.Location = New-Object Drawing.Point(24, 148); $d.MaximumSize = New-Object Drawing.Size(170, 0)
    $c.Tag.Desc = $d
    $hostB = New-Object Windows.Forms.Panel
    $hostB.Dock = 'Bottom'; $hostB.Height = 66; $hostB.BackColor = [Drawing.Color]::Transparent
    $hostB.Padding = New-Object Windows.Forms.Padding(18, 10, 18, 16)
    $b = New-RoundBtn 'Uygula' $m.Btn ([Drawing.Color]::White) 40
    $b.Dock = 'Fill'; $b.Tag = $m.Id
    $b.Add_Click({ param($s, $e) Invoke-QuickPreset ([string]$s.Tag) })
    $hostB.Controls.Add($b)
    $c.Controls.AddRange(@($ic, $t, $tg, $d, $hostB))
    $c.Add_Resize({ param($s, $e) try { $s.Tag.Desc.MaximumSize = New-Object Drawing.Size([math]::Max(100, ($s.Width - 48)), 0) } catch {} })
    return $c
}

$qModes = @(
    @{ Id = 'dengeli'; Glyph = 0xE73E; Title = 'Dengeli'; Tag = 'En güvenli'
       Desc = 'Yalnızca düşük riskli "Güvenli" öneriler: eski geçici dosyalar, gizlilik ayarları, ölçülen yavaş başlangıç uygulamaları.'
       Fill = $script:Th.BlueDim; Fg = $script:Th.BlueTxt; Btn = $script:Th.Blue },
    @{ Id = 'hizli'; Glyph = 0xE945; Title = 'Hızlı'; Tag = 'Önerilen'
       Desc = 'Dengeli mod ve ek olarak düşük riskli gelişmiş ayarlar: başlangıç uygulamaları, gereksiz servisler, görsel efektler.'
       Fill = $script:Th.BlueDim; Fg = $script:Th.BlueTxt; Btn = $script:Th.Blue },
    @{ Id = 'enhizli'; Glyph = 0xE7BA; Title = 'En Hızlı'; Tag = 'Maksimum performans'
       Desc = 'Tüm uygulanabilir önerileri kapsar (orta riskliler dahil). Onay penceresinde her değişikliği tek tek görürsünüz.'
       Fill = $script:Th.PurpleDim; Fg = (Hx '#A78BFA'); Btn = $script:Th.Purple },
    @{ Id = 'oyun'; Glyph = 0xE7FC; Title = 'Oyun'; Tag = 'FPS odaklı'
       Desc = 'Oyun ayarları, yüksek performanslı güç planı ve güvenli geçici dosya temizliği. Başlangıç ve servislere dokunmaz.'
       Fill = $script:Th.PurpleDim; Fg = (Hx '#A78BFA'); Btn = $script:Th.Purple }
)

# Alt bölüm (Fill) en önce eklenir; üstteki parçalar sonra
$botQ = New-Object Windows.Forms.Panel
$botQ.Dock = 'Fill'; $botQ.BackColor = $script:Th.Bg
$lblQuick = New-Lbl 'Bir mod seçip "Uygula" düğmesine basın. Değişiklikler uygulanmadan önce size gösterilir ve onayınız istenir.' 10 $false $script:Th.Muted
$lblQuick.Location = New-Object Drawing.Point(30, 18); $lblQuick.MaximumSize = New-Object Drawing.Size(900, 0)
$btnQuickUndo = New-RoundBtn 'Son Uygulamayı Geri Al' $script:Th.Row $script:Th.Text 40
$btnQuickUndo.Width = 220; $btnQuickUndo.Location = New-Object Drawing.Point(30, 62)
$btnQuickUndo.Add_Click({ try { Invoke-SmUndo } catch { $lblQuick.Text = 'Geri alma hatası: ' + $_.Exception.Message } })
$btnQuickList = New-RoundBtn 'Ayrıntılı Liste (Akıllı Optimizasyon)' $script:Th.Row $script:Th.Text 40
$btnQuickList.Width = 300; $btnQuickList.Location = New-Object Drawing.Point(262, 62)
$btnQuickList.Add_Click({ $tabs.SelectedTab = $tabSmart; foreach ($x in $script:NavItems) { $x.Invalidate() } })
$brandQ = New-Lbl 'Developed by Leone' 10 $true $script:Th.BlueTxt
$brandQ.Location = New-Object Drawing.Point(30, 128)
$botQ.Controls.AddRange(@($lblQuick, $btnQuickUndo, $btnQuickList, $brandQ))
$tabQuick.Controls.Add($botQ)

$tblQ = New-Object Windows.Forms.TableLayoutPanel
$tblQ.Dock = 'Top'; $tblQ.Height = 380; $tblQ.BackColor = $script:Th.Bg
$tblQ.Padding = New-Object Windows.Forms.Padding(22, 0, 22, 0)
$tblQ.ColumnCount = 4; $tblQ.RowCount = 1
foreach ($i in 1..4) { [void]$tblQ.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 25))) }
[void]$tblQ.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent', 100)))
$qi = 0
foreach ($m in $qModes) { $tblQ.Controls.Add((New-QuickCard $m), $qi, 0); $qi++ }
$tabQuick.Controls.Add($tblQ)

$hdrQ = New-Object Windows.Forms.Panel
$hdrQ.Dock = 'Top'; $hdrQ.Height = 112; $hdrQ.BackColor = $script:Th.Bg
$hq1 = New-Lbl 'Hızlı Mod' 22 $true; $hq1.Location = New-Object Drawing.Point(28, 18)
$hq2 = New-Lbl 'Bir mod seçin; WinOpt bilgisayarınızı tarar, uygun ayarları listeler ve onayınızla uygular. Her değişiklik öncesinde yedeklenir ve geri alınabilir.' 10 $false $script:Th.Muted
$hq2.Location = New-Object Drawing.Point(30, 66); $hq2.MaximumSize = New-Object Drawing.Size(900, 0)
$hdrQ.Controls.AddRange(@($hq1, $hq2))
$tabQuick.Controls.Add($hdrQ)

$tabs.SelectedTab = $tabQuick
foreach ($x in $script:NavItems) { $x.Invalidate() }

}
