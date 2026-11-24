if (-not $Maintenance) {

function Hx([string]$h) { [Drawing.ColorTranslator]::FromHtml($h) }
$script:Th = @{
    Bg = (Hx '#0B1020'); Side = (Hx '#0D1327'); Card = (Hx '#141B34'); Row = (Hx '#19213F'); Border = (Hx '#232C4D')
    Text = (Hx '#F2F5FF'); Muted = (Hx '#8791B3'); Blue = (Hx '#1E63E9'); BlueTxt = (Hx '#2F73F2'); BlueDim = (Hx '#183063')
    Purple = (Hx '#7C3AED'); PurpleDim = (Hx '#2A2058'); Grid = (Hx '#101730')
    IconFont = (New-Object Drawing.Font('Segoe MDL2 Assets', 11)); NavFont = (New-Object Drawing.Font('Segoe UI', 10, [Drawing.FontStyle]::Bold))
}

if (-not ('WinOptNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class WinOptNative {
    [DllImport("user32.dll")] public static extern bool ReleaseCapture();
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, int m, int w, int l);
}
'@
}

function Set-DB($c) { try { $c.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'Instance,NonPublic').SetValue($c, $true, $null) } catch {} }

function New-RoundPath([Drawing.RectangleF]$r, [single]$rad) {
    $p = New-Object Drawing.Drawing2D.GraphicsPath
    $d = [single]($rad * 2)
    $p.AddArc([single]$r.X, [single]$r.Y, $d, $d, [single]180, [single]90)
    $p.AddArc([single]($r.Right - $d), [single]$r.Y, $d, $d, [single]270, [single]90)
    $p.AddArc([single]($r.Right - $d), [single]($r.Bottom - $d), $d, $d, [single]0, [single]90)
    $p.AddArc([single]$r.X, [single]($r.Bottom - $d), $d, $d, [single]90, [single]90)
    $p.CloseFigure()
    return $p
}

# ---------- Koyu tema (mevcut tüm sekmelere) ----------
function Set-DarkTheme($ctl) {
    $th = $script:Th
    $defBack = @([Drawing.SystemColors]::Control.ToArgb(), [Drawing.SystemColors]::Window.ToArgb(), [Drawing.Color]::White.ToArgb())
    $defFore = @([Drawing.SystemColors]::ControlText.ToArgb(), [Drawing.SystemColors]::WindowText.ToArgb())

    if ($ctl -is [Windows.Forms.DataGridView]) {
        $ctl.BackgroundColor = $th.Bg; $ctl.GridColor = $th.Border; $ctl.BorderStyle = 'None'
        $ctl.EnableHeadersVisualStyles = $false; $ctl.ColumnHeadersBorderStyle = 'None'; $ctl.CellBorderStyle = 'SingleHorizontal'
        $h = $ctl.ColumnHeadersDefaultCellStyle
        $h.BackColor = $th.Card; $h.ForeColor = $th.Muted; $h.SelectionBackColor = $th.Card; $h.SelectionForeColor = $th.Muted
        $d = $ctl.DefaultCellStyle
        $d.BackColor = $th.Grid; $d.ForeColor = $th.Text; $d.SelectionBackColor = (Hx '#1B3F8F'); $d.SelectionForeColor = [Drawing.Color]::White
        try {
            $ctl.ColumnHeadersHeightSizeMode = 'DisableResizing'; $ctl.ColumnHeadersHeight = 36
            $ctl.RowTemplate.Height = 30
            $ctl.ColumnHeadersDefaultCellStyle.Font = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Bold)
            $ctl.ColumnHeadersDefaultCellStyle.Padding = New-Object Windows.Forms.Padding(8, 0, 8, 0)
            $d.Font = New-Object Drawing.Font('Segoe UI', 9.5)
            $d.Padding = New-Object Windows.Forms.Padding(8, 0, 8, 0)
            $ctl.AlternatingRowsDefaultCellStyle.BackColor = (Hx '#131B38')
        } catch {}
        $ctl.Add_CellFormatting({
            param($s, $e)
            try {
                $bc = $e.CellStyle.BackColor
                if ($bc.A -gt 0 -and $bc.GetBrightness() -gt 0.6) {
                    $f = { param($v) [int](14 + 75 * [math]::Pow($v / 255.0, 6)) }
                    $e.CellStyle.BackColor = [Drawing.Color]::FromArgb((& $f $bc.R), (& $f $bc.G), (& $f $bc.B))
                    if ($e.CellStyle.ForeColor.GetBrightness() -lt 0.35) { $e.CellStyle.ForeColor = $script:Th.Text }
                }
            } catch {}
        })
        return
    }
    if ($ctl -is [Windows.Forms.StatusStrip]) {
        $ctl.BackColor = $th.Card
        foreach ($i in $ctl.Items) { $i.ForeColor = $th.Text }
        return
    }
    if ($ctl -is [Windows.Forms.TabPage]) { $ctl.UseVisualStyleBackColor = $false; $ctl.BackColor = $th.Bg; $ctl.ForeColor = $th.Text }
    elseif ($ctl -is [Windows.Forms.Button]) {
        $primary = (($ctl.Text -match '^(Seçilileri Uygula|Analiz Et|Taramayı Başlat|Geri Yükleme Noktası Oluştur)') -or (@($script:PrimaryBtn | Where-Object { $_ -and $ctl.Text.StartsWith($_) }).Count -gt 0))
        $bbg = if ($primary) { $th.Blue } else { $th.Row }
        $ctl.FlatStyle = 'Flat'; $ctl.FlatAppearance.BorderSize = 0
        $ctl.FlatAppearance.MouseOverBackColor = [Windows.Forms.ControlPaint]::Light($bbg, 0.2)
        $ctl.BackColor = $bbg; $ctl.ForeColor = $th.Text; $ctl.Cursor = 'Hand'; $ctl.UseVisualStyleBackColor = $false
        try {
            $ctl.Font = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Bold)
            $ctl.Add_SizeChanged({ param($s, $e) try { if ($s.Width -gt 4 -and $s.Height -gt 4) { $s.Region = New-Object Drawing.Region((New-RoundPath (New-Object Drawing.RectangleF(0, 0, $s.Width, $s.Height)) 8)) } } catch {} })
            if ($ctl.Width -gt 4 -and $ctl.Height -gt 4) { $ctl.Region = New-Object Drawing.Region((New-RoundPath (New-Object Drawing.RectangleF(0, 0, $ctl.Width, $ctl.Height)) 8)) }
        } catch {}
    }
    elseif ($ctl -is [Windows.Forms.ComboBox]) { $ctl.FlatStyle = 'Flat'; $ctl.BackColor = $th.Row; $ctl.ForeColor = $th.Text }
    elseif ($ctl -is [Windows.Forms.TextBox] -or $ctl -is [Windows.Forms.RichTextBox] -or $ctl -is [Windows.Forms.ListBox] -or $ctl -is [Windows.Forms.ListView] -or $ctl -is [Windows.Forms.NumericUpDown]) {
        $ctl.BackColor = $th.Row; $ctl.ForeColor = $th.Text
    }
    elseif ($ctl -is [Windows.Forms.FlowLayoutPanel] -and $ctl.Dock -eq 'Top') { $ctl.BackColor = $th.Card }
    elseif ($ctl -isnot [Windows.Forms.TabControl] -and $ctl -isnot [Windows.Forms.ProgressBar]) {
        if ($defBack -contains $ctl.BackColor.ToArgb()) {
            $pbc = $th.Bg
            if ($ctl.Parent -and $ctl.Parent -isnot [Windows.Forms.TabControl] -and $ctl.Parent.BackColor.A -gt 0) { $pbc = $ctl.Parent.BackColor }
            $ctl.BackColor = $pbc
        }
        if ($defFore -contains $ctl.ForeColor.ToArgb()) { $ctl.ForeColor = $th.Text }
    }
    foreach ($c in $ctl.Controls) { Set-DarkTheme $c }
}

# ---------- Yardımcı çizim bileşenleri ----------
function New-Card([int]$radius = 14, $fill = $null, $border = $null) {
    $p = New-Object Windows.Forms.Panel
    Set-DB $p
    $p.BackColor = $script:Th.Bg
    $p.Tag = @{ Fill = $(if ($fill) { $fill } else { $script:Th.Card }); Border = $(if ($border) { $border } else { $script:Th.Border }); Rad = $radius }
    $p.Add_Paint({
        param($s, $e)
        $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'
        $path = New-RoundPath (New-Object Drawing.RectangleF(0.5, 0.5, ($s.Width - 2), ($s.Height - 2))) $s.Tag.Rad
        $b = New-Object Drawing.SolidBrush $s.Tag.Fill; $g.FillPath($b, $path)
        $pen = New-Object Drawing.Pen $s.Tag.Border; $g.DrawPath($pen, $path)
        $b.Dispose(); $pen.Dispose(); $path.Dispose()
    })
    $p.Add_Resize({ param($s, $e) $s.Invalidate() })
    return $p
}

function New-Lbl([string]$text, [single]$size = 10, [bool]$bold = $false, $color = $null) {
    $l = New-Object Windows.Forms.Label
    $l.Text = $text; $l.AutoSize = $true; $l.BackColor = [Drawing.Color]::Transparent
    $l.ForeColor = $(if ($color) { $color } else { $script:Th.Text })
    $st = if ($bold) { [Drawing.FontStyle]::Bold } else { [Drawing.FontStyle]::Regular }
    $l.Font = New-Object Drawing.Font('Segoe UI', $size, $st)
    return $l
}

function New-IconBox([string]$glyph, [int]$size, $fill, $fg) {
    $b = New-Card 10 $fill $fill
    $b.Size = New-Object Drawing.Size($size, $size)
    $l = New-Object Windows.Forms.Label
    $l.Dock = 'Fill'; $l.TextAlign = 'MiddleCenter'; $l.BackColor = [Drawing.Color]::Transparent; $l.ForeColor = $fg
    $l.Font = New-Object Drawing.Font('Segoe MDL2 Assets', [single]($size * 0.38)); $l.Text = $glyph
    $b.Controls.Add($l)
    return $b
}

function New-RoundBtn([string]$text, $bg, $fg, [int]$h = 44) {
    $b = New-Object Windows.Forms.Button
    $b.Text = $text; $b.Height = $h; $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderSize = 0
    $b.FlatAppearance.MouseOverBackColor = [Windows.Forms.ControlPaint]::Light($bg, 0.15)
    $b.BackColor = $bg; $b.ForeColor = $fg; $b.Cursor = 'Hand'; $b.UseVisualStyleBackColor = $false
    $b.Font = New-Object Drawing.Font('Segoe UI', 10, [Drawing.FontStyle]::Bold)
    $b.Add_SizeChanged({
        param($s, $e)
        if ($s.Width -gt 4 -and $s.Height -gt 4) { $s.Region = New-Object Drawing.Region((New-RoundPath (New-Object Drawing.RectangleF(0, 0, $s.Width, $s.Height)) 10)) }
    })
    return $b
}

function New-LinkLbl([string]$text, [scriptblock]$handler) {
    $l = New-Lbl $text 9 $true $script:Th.BlueTxt
    $l.Cursor = 'Hand'; $l.Margin = New-Object Windows.Forms.Padding(10, 4, 0, 0)
    $l.Add_Click($handler)
    return $l
}

function Invoke-ClButton([string]$text) {
    $b = @($barCl.Controls | Where-Object { $_ -is [Windows.Forms.Button] -and ($_.Text -eq $text -or $_.Text -eq (T $text)) }) | Select-Object -First 1
    if ($b) { $b.PerformClick() }
}

# ---------- Mevcut sekmelere temayı uygula ----------
$form.BackColor = $script:Th.Bg; $form.ForeColor = $script:Th.Text
foreach ($tp in $tabs.TabPages) { Set-DarkTheme $tp }

# ---------- Pencere iskeleti: başlık çubuğu + sol menü + içerik ----------
$tabClean.Text = 'Dosya Temizliği'
$form.FormBorderStyle = 'None'
$wa = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.Size = New-Object Drawing.Size(1200, [int][math]::Min(800, $wa.Height - 10))
$form.MinimumSize = New-Object Drawing.Size(1000, 600)
$form.Text = 'WinOpt Suite - Windows Sistem Optimize Edici | Developed by Leone'
$form.Add_Paint({ param($s, $e) $pen = New-Object Drawing.Pen $script:Th.Border; $e.Graphics.DrawRectangle($pen, 0, 0, ($s.Width - 1), ($s.Height - 1)); $pen.Dispose() })

$form.Controls.Remove($tabs)
$hostPnl = New-Object Windows.Forms.Panel
$hostPnl.Dock = 'Fill'; $hostPnl.BackColor = $script:Th.Bg
$tabs.Dock = 'None'; $tabs.Appearance = 'FlatButtons'; $tabs.SizeMode = 'Fixed'; $tabs.ItemSize = New-Object Drawing.Size(0, 1)
$tabs.Location = New-Object Drawing.Point(-3, -4); $tabs.Size = New-Object Drawing.Size(($hostPnl.Width + 6), ($hostPnl.Height + 8))
$tabs.BackColor = $script:Th.Bg
$hostPnl.Controls.Add($tabs)
$hostPnl.Add_Resize({ param($s, $e) $tabs.Size = New-Object Drawing.Size(($s.Width + 6), ($s.Height + 8)) })
$form.Controls.Add($hostPnl)

# Sol menü
$side = New-Object Windows.Forms.Panel
$side.Dock = 'Left'; $side.Width = 250; $side.BackColor = $script:Th.Side; Set-DB $side
$side.Add_Paint({ param($s, $e) $pen = New-Object Drawing.Pen $script:Th.Border; $e.Graphics.DrawLine($pen, ($s.Width - 1), 0, ($s.Width - 1), $s.Height); $pen.Dispose() })

$navHost = New-Object Windows.Forms.Panel
$navHost.Dock = 'Fill'; $navHost.AutoScroll = $true; $navHost.BackColor = $script:Th.Side
$side.Controls.Add($navHost)

$foot = New-Object Windows.Forms.Label
$foot.Dock = 'Bottom'; $foot.Height = 44; $foot.TextAlign = 'MiddleCenter'; $foot.ForeColor = $script:Th.Muted
$foot.Font = New-Object Drawing.Font('Segoe UI', 8); $foot.Text = 'Developed by Leone' + [Environment]::NewLine + [string]([char]0x25CF) + '  v5'
$side.Controls.Add($foot)

$logo = New-Object Windows.Forms.Panel
$logo.Dock = 'Top'; $logo.Height = 100; $logo.BackColor = $script:Th.Side; Set-DB $logo
$logo.Add_Paint({
    param($s, $e)
    $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'ClearTypeGridFit'
    $sf = New-Object Drawing.StringFormat; $sf.LineAlignment = 'Center'
    $bb = New-Object Drawing.SolidBrush $script:Th.BlueTxt
    $g.DrawString([string][char]0xE945, (New-Object Drawing.Font('Segoe MDL2 Assets', 24)), $bb, (New-Object Drawing.RectangleF(30, 0, 50, 100)), $sf)
    $g.DrawString('WinOpt', (New-Object Drawing.Font('Segoe UI', 22, [Drawing.FontStyle]::Bold)), $bb, (New-Object Drawing.RectangleF(78, 0, 170, 100)), $sf)
    $bb.Dispose()
})
$side.Controls.Add($logo)
$form.Controls.Add($side)

# Başlık çubuğu
$title = New-Object Windows.Forms.Panel
$title.Dock = 'Top'; $title.Height = 40; $title.BackColor = $script:Th.Side
$tl = New-Lbl 'WinOpt Suite - Windows Sistem Optimize Edici   |   Developed by Leone' 9 $true
$tl.Location = New-Object Drawing.Point(46, 11)
$ti = New-Lbl ([string][char]0xE945) 11 $false $script:Th.BlueTxt; $ti.Font = New-Object Drawing.Font('Segoe MDL2 Assets', 12); $ti.Location = New-Object Drawing.Point(18, 10)
$drag = { [WinOptNative]::ReleaseCapture() | Out-Null; [WinOptNative]::SendMessage($form.Handle, 0xA1, 2, 0) | Out-Null }
$title.Add_MouseDown($drag); $tl.Add_MouseDown($drag); $ti.Add_MouseDown($drag)
$btnClose = New-Lbl ([string][char]0xE8BB) 9 $false $script:Th.Text
$btnMin = New-Lbl ([string][char]0xE921) 9 $false $script:Th.Text
foreach ($b in @($btnClose, $btnMin)) { $b.Font = New-Object Drawing.Font('Segoe MDL2 Assets', 9); $b.AutoSize = $false; $b.Size = New-Object Drawing.Size(46, 40); $b.TextAlign = 'MiddleCenter'; $b.Cursor = 'Hand'; $b.Anchor = 'Top,Right' }
$btnClose.Location = New-Object Drawing.Point(($title.Width - 46), 0); $btnMin.Location = New-Object Drawing.Point(($title.Width - 92), 0)
$btnClose.Add_Click({ $form.Close() }); $btnMin.Add_Click({ $form.WindowState = 'Minimized' })
$btnClose.Add_MouseEnter({ param($s, $e) $s.BackColor = (Hx '#C42B1C') }); $btnClose.Add_MouseLeave({ param($s, $e) $s.BackColor = [Drawing.Color]::Transparent })
$btnMin.Add_MouseEnter({ param($s, $e) $s.BackColor = $script:Th.Border }); $btnMin.Add_MouseLeave({ param($s, $e) $s.BackColor = [Drawing.Color]::Transparent })
$title.Controls.AddRange(@($ti, $tl, $btnMin, $btnClose))
$form.Controls.Add($title)

# Menü öğeleri
$glyphs = @{
    'Dosya Temizliği' = 0xE74D; 'Başlangıç' = 0xE768; 'İşlemler' = 0xE9D9; 'RAM' = 0xE950; 'Servisler' = 0xE713; 'Kayıt Defteri' = 0xE8F1
    'Tarayıcılar' = 0xE774; 'Windows Ayarları' = 0xE713; 'Oyun Optimizasyonu' = 0xE7FC; 'Sistem Sağlığı' = 0xE95E
    'Akıllı Optimizasyon' = 0xE945; 'Otomatik Bakım' = 0xE895; 'Raporlar' = 0xE9D2; 'Araçlar' = 0xE90F; 'Hızlı Mod' = 0xE734
}
$script:NavItems = @()
$order = @($tabQuick, $tabClean, $tabStartup, $tabProc, $tabRam, $tabSvc, $tabReg, $tabBrowser, $tabTweak, $tabGame, $tabHealth, $tabSmart, $tabMaint, $tabReports)
foreach ($tp in $tabs.TabPages) { if ($order -notcontains $tp) { $order += $tp } }
$ny = 8
foreach ($tp in $order) {
    if (-not $tp) { continue }
    $g = if ($glyphs.ContainsKey($tp.Text)) { [int]$glyphs[$tp.Text] } else { 0xE80F }
    $n = New-Object Windows.Forms.Panel
    Set-DB $n
    $n.SetBounds(14, $ny, 222, 44); $n.Anchor = 'Top,Left,Right'; $n.Cursor = 'Hand'; $n.BackColor = $script:Th.Side
    $n.Tag = @{ Tab = $tp; Text = $tp.Text; Glyph = [string][char]$g; Hover = $false }
    $n.Add_Paint({
        param($s, $e)
        $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'ClearTypeGridFit'
        $act = [object]::ReferenceEquals($tabs.SelectedTab, $s.Tag.Tab)
        if ($act -or $s.Tag.Hover) {
            $path = New-RoundPath (New-Object Drawing.RectangleF(0, 0, ($s.Width - 1), ($s.Height - 1))) 10
            $fb = New-Object Drawing.SolidBrush $(if ($act) { $script:Th.Blue } else { $script:Th.Row })
            $g.FillPath($fb, $path); $fb.Dispose(); $path.Dispose()
        }
        $fg = if ($act) { [Drawing.Color]::White } else { (Hx '#C5CCE6') }
        $tb = New-Object Drawing.SolidBrush $fg
        $sf = New-Object Drawing.StringFormat; $sf.LineAlignment = 'Center'; $sf.Trimming = 'EllipsisCharacter'; $sf.FormatFlags = 'NoWrap'
        $g.DrawString($s.Tag.Glyph, $script:Th.IconFont, $tb, (New-Object Drawing.RectangleF(14, 0, 26, $s.Height)), $sf)
        $g.DrawString($s.Tag.Text, $script:Th.NavFont, $tb, (New-Object Drawing.RectangleF(46, 0, ($s.Width - 52), $s.Height)), $sf)
        $tb.Dispose()
    })
    $n.Add_MouseEnter({ param($s, $e) $s.Tag.Hover = $true; $s.Invalidate() })
    $n.Add_MouseLeave({ param($s, $e) $s.Tag.Hover = $false; $s.Invalidate() })
    $n.Add_Click({ param($s, $e) $tabs.SelectedTab = $s.Tag.Tab; foreach ($x in $script:NavItems) { $x.Invalidate() } })
    $navHost.Controls.Add($n)
    $script:NavItems += $n
    $ny += 50
}
$tabs.Add_SelectedIndexChanged({ foreach ($x in $script:NavItems) { $x.Invalidate() } })

# ---------- "Dosya Temizliği" sayfası ----------
foreach ($c in @($gridCl, $lblClDetail, $gridClDetail, $barCl)) { $c.Visible = $false }
$tabClean.Controls.Remove($pbClean); $tabClean.Controls.Remove($lblClStatus)
$cmbClAge.Parent.Controls.Remove($cmbClAge)

$page = New-Object Windows.Forms.Panel
$page.Dock = 'Fill'; $page.BackColor = $script:Th.Bg; $page.Padding = New-Object Windows.Forms.Padding(20, 14, 20, 6)

$main = New-Object Windows.Forms.TableLayoutPanel
$main.Dock = 'Fill'; $main.ColumnCount = 2; $main.RowCount = 1; $main.BackColor = $script:Th.Bg
[void]$main.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 62)))
[void]$main.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 38)))
[void]$main.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent', 100)))

# Sol: kategori listesi
$catCard = New-Card 14
$catCard.Size = New-Object Drawing.Size(560, 520); $catCard.Dock = 'Fill'; $catCard.Margin = New-Object Windows.Forms.Padding(0, 0, 12, 0)
$ct = New-Lbl 'Temizlik Kategorileri' 13 $true; $ct.Location = New-Object Drawing.Point(20, 16)
$catCard.Controls.Add($ct)
$links = New-Object Windows.Forms.FlowLayoutPanel
$links.FlowDirection = 'RightToLeft'; $links.WrapContents = $false; $links.BackColor = [Drawing.Color]::Transparent
$links.Size = New-Object Drawing.Size(300, 26); $links.Location = New-Object Drawing.Point(240, 18); $links.Anchor = 'Top,Right'
$links.Controls.Add((New-LinkLbl 'CSV' { Invoke-ClButton 'CSV Raporu' }))
$links.Controls.Add((New-LinkLbl 'Geçmiş' { Invoke-ClButton 'Temizleme Geçmişi' }))
$links.Controls.Add((New-LinkLbl 'Kaldır' { Invoke-ClButton 'Seçimi Kaldır' }))
$links.Controls.Add((New-LinkLbl 'Tümünü Seç' { Invoke-ClButton 'Tümünü Seç' }))
$catCard.Controls.Add($links)
$script:ClList = New-Object Windows.Forms.Panel
$script:ClList.Location = New-Object Drawing.Point(14, 58); $script:ClList.Size = New-Object Drawing.Size(532, 450)
$script:ClList.Anchor = 'Top,Bottom,Left,Right'; $script:ClList.AutoScroll = $true; $script:ClList.BackColor = $script:Th.Card
$catCard.Controls.Add($script:ClList)
$main.Controls.Add($catCard, 0, 0)

# Sağ sütun
$right = New-Object Windows.Forms.TableLayoutPanel
$right.Dock = 'Fill'; $right.ColumnCount = 1; $right.RowCount = 3; $right.BackColor = $script:Th.Bg
[void]$right.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 100)))
[void]$right.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute', 168)))
[void]$right.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute', 204)))
[void]$right.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent', 100)))

# Sürücü kartı
$drv = New-Card 14; $drv.Size = New-Object Drawing.Size(330, 156); $drv.Dock = 'Fill'; $drv.Margin = New-Object Windows.Forms.Padding(0, 0, 0, 12)
$drv.Controls.Add((& { $l = New-Lbl 'Sürücü Kullanımı' 12 $true; $l.Location = New-Object Drawing.Point(20, 14); $l }))
$sysDrive = $env:SystemDrive
$tot = [double]0; $free = [double]0; $fmt = 'NTFS'
try { $di = New-Object IO.DriveInfo $sysDrive; $tot = [double]$di.TotalSize; $free = [double]$di.AvailableFreeSpace; $fmt = [string]$di.DriveFormat } catch {}
$used = $tot - $free; $pct = if ($tot -gt 0) { [int][math]::Round($used * 100 / $tot) } else { 0 }
$dl = New-Lbl $sysDrive 11 $true; $dl.Location = New-Object Drawing.Point(20, 52); $drv.Controls.Add($dl)
$badge = New-Card 6 $script:Th.BlueDim $script:Th.BlueTxt; $badge.Size = New-Object Drawing.Size(52, 22); $badge.Location = New-Object Drawing.Point(54, 54)
$bl = New-Lbl $fmt 8 $true $script:Th.BlueTxt; $bl.AutoSize = $false; $bl.Dock = 'Fill'; $bl.TextAlign = 'MiddleCenter'; $badge.Controls.Add($bl); $drv.Controls.Add($badge)
$dt = New-Lbl ('Toplam {0:N0} GB' -f ($tot / 1GB)) 9 $true; $dt.AutoSize = $false; $dt.Size = New-Object Drawing.Size(150, 22); $dt.TextAlign = 'MiddleRight'
$dt.Location = New-Object Drawing.Point(160, 54); $dt.Anchor = 'Top,Right'; $drv.Controls.Add($dt)
$barP = New-Object Windows.Forms.Panel
Set-DB $barP; $barP.Location = New-Object Drawing.Point(20, 90); $barP.Size = New-Object Drawing.Size(290, 8); $barP.Anchor = 'Top,Left,Right'; $barP.BackColor = $script:Th.Card; $barP.Tag = $pct
$barP.Add_Paint({
    param($s, $e)
    $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'
    $tr = New-RoundPath (New-Object Drawing.RectangleF(0, 0, ($s.Width - 1), ($s.Height - 1))) 4
    $b1 = New-Object Drawing.SolidBrush $script:Th.Row; $g.FillPath($b1, $tr); $b1.Dispose(); $tr.Dispose()
    $w = [math]::Max(8, [int](($s.Width - 1) * [math]::Min(100, [int]$s.Tag) / 100))
    $fp = New-RoundPath (New-Object Drawing.RectangleF(0, 0, $w, ($s.Height - 1))) 4
    $b2 = New-Object Drawing.SolidBrush $script:Th.Blue; $g.FillPath($b2, $fp); $b2.Dispose(); $fp.Dispose()
})
$drv.Controls.Add($barP)
$u1 = New-Lbl ([string][char]0x25CF + ' Kullanılan {0:N0} GB' -f ($used / 1GB)) 8.5 $true; $u1.Location = New-Object Drawing.Point(20, 112); $drv.Controls.Add($u1)
$u2 = New-Lbl ([string][char]0x25CF + ' Boş {0:N0} GB' -f ($free / 1GB)) 8.5 $true; $u2.Location = New-Object Drawing.Point(150, 112); $drv.Controls.Add($u2)
$u3 = New-Lbl ('%{0} kullanıldı' -f $pct) 8.5 $true $script:Th.BlueTxt; $u3.AutoSize = $false; $u3.Size = New-Object Drawing.Size(100, 20); $u3.TextAlign = 'MiddleRight'
$u3.Location = New-Object Drawing.Point(210, 112); $u3.Anchor = 'Top,Right'; $drv.Controls.Add($u3)
$right.Controls.Add($drv, 0, 0)

# Hızlı işlemler
$qa = New-Card 14; $qa.Size = New-Object Drawing.Size(330, 192); $qa.Dock = 'Fill'; $qa.Margin = New-Object Windows.Forms.Padding(0, 0, 0, 12)
$qa.Controls.Add((& { $l = New-Lbl 'Hızlı İşlemler' 12 $true; $l.Location = New-Object Drawing.Point(20, 14); $l }))
$cancelLnk = New-Lbl 'İptal' 9 $true $script:Th.BlueTxt; $cancelLnk.Cursor = 'Hand'; $cancelLnk.Location = New-Object Drawing.Point(274, 18); $cancelLnk.Anchor = 'Top,Right'
$cancelLnk.Add_Click({ Invoke-ClButton 'İptal' }); $qa.Controls.Add($cancelLnk)
$bScan = New-RoundBtn 'Gereksiz Dosyaları Tara' $script:Th.Blue ([Drawing.Color]::White)
$bScan.Location = New-Object Drawing.Point(20, 48); $bScan.Size = New-Object Drawing.Size(290, 42); $bScan.Anchor = 'Top,Left,Right'; $bScan.Add_Click({ Invoke-CleanScan })
$bClean = New-RoundBtn 'Seçilenleri Temizle' $script:Th.Row $script:Th.Text
$bClean.Location = New-Object Drawing.Point(20, 98); $bClean.Size = New-Object Drawing.Size(290, 42); $bClean.Anchor = 'Top,Left,Right'; $bClean.Add_Click({ Invoke-CleanSelected })
$qa.Controls.AddRange(@($bScan, $bClean))
$al = New-Lbl 'Dosya yaşı' 8.5 $false $script:Th.Muted; $al.Location = New-Object Drawing.Point(22, 158); $qa.Controls.Add($al)
$cmbClAge.Location = New-Object Drawing.Point(94, 154); $cmbClAge.Size = New-Object Drawing.Size(216, 26); $cmbClAge.Margin = New-Object Windows.Forms.Padding(0); $cmbClAge.Anchor = 'Top,Left,Right'
$qa.Controls.Add($cmbClAge)
$right.Controls.Add($qa, 0, 1)

# Tarayıcı temizleyici kartı
$br = New-Card 14; $br.Size = New-Object Drawing.Size(330, 150); $br.Dock = 'Fill'
$br.Controls.Add((& { $l = New-Lbl 'Tarayıcı Temizleyici' 12 $true; $l.Location = New-Object Drawing.Point(20, 14); $l }))
$bi = New-Lbl ([string][char]0xE774) 14 $false $script:Th.Purple; $bi.Font = New-Object Drawing.Font('Segoe MDL2 Assets', 15); $bi.Location = New-Object Drawing.Point(284, 14); $bi.Anchor = 'Top,Right'; $br.Controls.Add($bi)
$bd = New-Lbl 'Tarayıcı önbelleği, çerez ve geçmişini ayrı modülde temizleyin.' 9 $false $script:Th.Muted
$bd.AutoSize = $false; $bd.Size = New-Object Drawing.Size(290, 36); $bd.Location = New-Object Drawing.Point(20, 44); $bd.Anchor = 'Top,Left,Right'; $br.Controls.Add($bd)
$bBr = New-RoundBtn 'Tarayıcılara Git   >' $script:Th.Purple ([Drawing.Color]::White) 40
$bBr.Location = New-Object Drawing.Point(20, 88); $bBr.Size = New-Object Drawing.Size(290, 40); $bBr.Anchor = 'Top,Left,Right'
$bBr.Add_Click({ $tabs.SelectedTab = $tabBrowser; foreach ($x in $script:NavItems) { $x.Invalidate() } }); $br.Controls.Add($bBr)
$right.Controls.Add($br, 0, 2)
$main.Controls.Add($right, 1, 0)

# Üst istatistik kartları
function New-StatCard([string]$title, [int]$glyph, $iconFill, $iconFg) {
    $c = New-Card 14; $c.Size = New-Object Drawing.Size(215, 92); $c.Dock = 'Fill'; $c.Margin = New-Object Windows.Forms.Padding(0, 0, 12, 0)
    $ib = New-IconBox ([string][char]$glyph) 46 $iconFill $iconFg; $ib.Location = New-Object Drawing.Point(14, 23); $c.Controls.Add($ib)
    $t = New-Lbl $title 8.5 $true $script:Th.Text; $t.AutoSize = $false; $t.Size = New-Object Drawing.Size(140, 18); $t.Location = New-Object Drawing.Point(68, 14); $t.Anchor = 'Top,Left,Right'
    $v = New-Lbl '-' 14 $true; $v.AutoSize = $false; $v.Size = New-Object Drawing.Size(140, 28); $v.Location = New-Object Drawing.Point(68, 32); $v.Anchor = 'Top,Left,Right'
    $s = New-Lbl '' 8 $false $script:Th.Muted; $s.AutoSize = $false; $s.Size = New-Object Drawing.Size(140, 16); $s.Location = New-Object Drawing.Point(68, 62); $s.Anchor = 'Top,Left,Right'
    foreach ($x in @($t, $v, $s)) { $x.AutoEllipsis = $true; $c.Controls.Add($x) }
    return @{ Card = $c; Value = $v; Sub = $s }
}
$stats = New-Object Windows.Forms.TableLayoutPanel
$stats.Dock = 'Top'; $stats.Height = 104; $stats.ColumnCount = 4; $stats.RowCount = 1; $stats.BackColor = $script:Th.Bg
for ($i = 0; $i -lt 4; $i++) { [void]$stats.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 25))) }
[void]$stats.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent', 100)))
$script:StTotal = New-StatCard 'Taranabilir Toplam' 0xE8B7 $script:Th.BlueDim $script:Th.BlueTxt
$script:StLast  = New-StatCard 'Son Tarama' 0xE787 $script:Th.BlueDim $script:Th.BlueTxt
$script:StFreed = New-StatCard 'Toplam Temizlenen' 0xE74D $script:Th.BlueDim $script:Th.BlueTxt
$script:StState = New-StatCard 'Mevcut Durum' 0xE73E $script:Th.PurpleDim $script:Th.Purple
$stats.Controls.Add($script:StTotal.Card, 0, 0); $stats.Controls.Add($script:StLast.Card, 1, 0)
$stats.Controls.Add($script:StFreed.Card, 2, 0); $stats.Controls.Add($script:StState.Card, 3, 0)
$script:StFreed.Card.Margin = New-Object Windows.Forms.Padding(0, 0, 12, 0); $script:StState.Card.Margin = New-Object Windows.Forms.Padding(0)

# Başlık
$hdr = New-Object Windows.Forms.Panel
$hdr.Dock = 'Top'; $hdr.Height = 58; $hdr.BackColor = $script:Th.Bg
$hi = New-IconBox ([string][char]0xE74D) 34 $script:Th.BlueDim $script:Th.BlueTxt; $hi.Location = New-Object Drawing.Point(0, 8); $hdr.Controls.Add($hi)
$ht = New-Lbl 'Dosya Temizliği' 18 $true; $ht.Location = New-Object Drawing.Point(46, 8); $hdr.Controls.Add($ht)

# Alt durum + ilerleme (orijinal denetimler taşındı)
$pbClean.Dock = 'Bottom'; $pbClean.Height = 5
$lblClStatus.Dock = 'Bottom'; $lblClStatus.Height = 26; $lblClStatus.BackColor = $script:Th.Bg; $lblClStatus.ForeColor = $script:Th.Muted

# Dock sırası: Fill önce, sonra alt/üst parçalar
$page.Controls.Add($main)
$page.Controls.Add($pbClean)
$page.Controls.Add($lblClStatus)
$page.Controls.Add($stats)
$page.Controls.Add($hdr)
$tabClean.Controls.Add($page)

# ---------- Kategori kartları + istatistik güncelleme ----------
$script:ClCheckBoxes = @()

function Get-CleanGlyph([string]$name) {
    if ($name -match 'Tarayıc|Edge|Chrome|Firefox') { return 0xE774 }
    if ($name -match 'günlük|log|rapor|Rapor') { return 0xE7C3 }
    if ($name -match 'küçük|Küçük|resim|Resim') { return 0xE91B }
    if ($name -match 'Geri Dönüşüm|Çöp') { return 0xE74D }
    return 0xE8B7
}

function Switch-CleanRow($cb) {
    if (-not $cb.Tag.Enabled -or $cb.Tag.Idx -lt 0 -or $cb.Tag.Idx -ge $gridCl.Rows.Count) { return }
    $new = -not $cb.Tag.On
    $gridCl.Rows[$cb.Tag.Idx].Cells[0].Value = $new
    $cb.Tag.On = $new; $cb.Invalidate()
}

function Build-CleanCards {
    $lp = $script:ClList
    $lp.SuspendLayout()
    foreach ($c in @($lp.Controls)) { $lp.Controls.Remove($c); $c.Dispose() }
    $script:ClCheckBoxes = @()
    $w = [math]::Max(300, $lp.ClientSize.Width - 4)
    $rows = @()
    if ($script:ClResults.Count -gt 0) {
        for ($i = 0; $i -lt $script:ClResults.Count; $i++) {
            $r = $script:ClResults[$i]
            $rows += @{ Name = $r.Name; Note = [string]$r.Def.Note; Size = (Format-Bytes $r.Bytes); Idx = $i; Has = ($r.Count -gt 0); On = ($gridCl.Rows.Count -gt $i -and $gridCl.Rows[$i].Cells[0].Value -eq $true) }
        }
    } else {
        foreach ($d in @(Get-CleanDefs)) { $rows += @{ Name = $d.Name; Note = [string]$d.Note; Size = '-'; Idx = -1; Has = $false; On = $false } }
    }
    $k = 0
    foreach ($it in $rows) {
        $card = New-Card 10 $script:Th.Row $script:Th.Row
        $card.SetBounds(0, ($k * 66), $w, 58); $card.Anchor = 'Top,Left,Right'
        $card.Cursor = 'Hand'
        $ib = New-IconBox ([string][char](Get-CleanGlyph $it.Name)) 36 $script:Th.BlueDim $script:Th.BlueTxt; $ib.Location = New-Object Drawing.Point(12, 11)
        $nm = New-Lbl $it.Name 10 $true; $nm.AutoSize = $false; $nm.AutoEllipsis = $true; $nm.SetBounds(60, 8, ($w - 60 - 140), 20); $nm.Anchor = 'Top,Left,Right'
        $ds = New-Lbl $it.Note 8.5 $false $script:Th.Muted; $ds.AutoSize = $false; $ds.AutoEllipsis = $true; $ds.SetBounds(60, 30, ($w - 60 - 140), 18); $ds.Anchor = 'Top,Left,Right'
        $sz = New-Lbl $it.Size 11 $true $script:Th.BlueTxt; $sz.AutoSize = $false; $sz.TextAlign = 'MiddleRight'; $sz.SetBounds(($w - 140), 15, 90, 28); $sz.Anchor = 'Top,Right'
        $cb = New-Object Windows.Forms.Panel
        Set-DB $cb
        $cb.SetBounds(($w - 40), 17, 24, 24); $cb.Anchor = 'Top,Right'; $cb.BackColor = $script:Th.Row; $cb.Cursor = 'Hand'
        $cb.Tag = @{ Idx = $it.Idx; On = [bool]$it.On; Enabled = [bool]$it.Has }
        $cb.Add_Paint({
            param($s, $e)
            $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'
            $path = New-RoundPath (New-Object Drawing.RectangleF(0.5, 0.5, ($s.Width - 2), ($s.Height - 2))) 6
            if ($s.Tag.On -and $s.Tag.Enabled) {
                $fb = New-Object Drawing.SolidBrush $script:Th.Blue; $g.FillPath($fb, $path); $fb.Dispose()
                $pen = New-Object Drawing.Pen([Drawing.Color]::White, 2)
                $g.DrawLines($pen, [Drawing.Point[]]@((New-Object Drawing.Point(6, 12)), (New-Object Drawing.Point(10, 16)), (New-Object Drawing.Point(18, 8))))
                $pen.Dispose()
            } else {
                $pen = New-Object Drawing.Pen $(if ($s.Tag.Enabled) { $script:Th.Muted } else { $script:Th.Border }), 1.5
                $g.DrawPath($pen, $path); $pen.Dispose()
            }
            $path.Dispose()
        })
        $script:ClCheckBoxes += $cb
        $h = { param($s, $e) Switch-CleanRow $cb }.GetNewClosure()
        foreach ($x in @($cb, $card, $nm, $ds, $sz, $ib)) { $x.Add_Click($h) }
        $card.Controls.AddRange(@($ib, $nm, $ds, $sz, $cb))
        $lp.Controls.Add($card)
        $k++
    }
    $lp.ResumeLayout($true)
}

function Sync-CleanCards {
    foreach ($cb in $script:ClCheckBoxes) {
        $i = $cb.Tag.Idx
        if ($i -ge 0 -and $i -lt $gridCl.Rows.Count) { $cb.Tag.On = ($gridCl.Rows[$i].Cells[0].Value -eq $true); $cb.Invalidate() }
    }
}

function Update-CleanStats([string]$state = '') {
    $b = [long]0
    foreach ($r in $script:ClResults) { $b += $r.Bytes }
    $script:StTotal.Value.Text = $(if ($script:ClResults.Count -gt 0) { Format-Bytes $b } else { '-' })
    $script:StTotal.Sub.Text = 'Tahmini boyut'
    if ($script:ClScanTime) {
        $m = [int]((Get-Date) - $script:ClScanTime).TotalMinutes
        $script:StLast.Value.Text = $(if ($m -lt 1) { 'Az önce' } elseif ($m -lt 60) { "$m dk önce" } else { $script:ClScanTime.ToString('HH:mm') })
    } else { $script:StLast.Value.Text = 'Henüz yok' }
    $script:StLast.Sub.Text = 'Derin Temizlik taraması'
    $fr = [long]0; try { $fr = Get-CleanTotalFreed $CleanHistFile } catch {}
    $script:StFreed.Value.Text = Format-Bytes $fr; $script:StFreed.Sub.Text = 'Tüm zamanlar'
    if ($state) { $script:StState.Value.Text = $state; $script:StState.Sub.Text = 'Lütfen bekleyin' }
    elseif ($script:ClResults.Count -gt 0) { $script:StState.Value.Text = 'Hazır'; $script:StState.Sub.Text = 'Temizlemeye hazır' }
    else { $script:StState.Value.Text = 'Beklemede'; $script:StState.Sub.Text = 'Taramak için tıklayın' }
}

# Orijinal fonksiyonları sar: tablo güncellenince kartlar da güncellensin
$script:OrigShowGrid = ${function:Show-CleanGrid}
$script:OrigTotals   = ${function:Update-CleanTotals}
$script:OrigScan     = ${function:Invoke-CleanScan}
function Show-CleanGrid { & $script:OrigShowGrid; Build-CleanCards; Update-CleanStats }
function Update-CleanTotals { & $script:OrigTotals; if (-not $script:ClLoading) { Sync-CleanCards } }
function Invoke-CleanScan { if (-not $script:ClBusy) { Update-CleanStats 'Taranıyor' }; & $script:OrigScan; Update-CleanStats }

Build-CleanCards
Update-CleanStats
$tabs.SelectedTab = $tabClean

# Tema uygulandıktan sonra oluşturulan alt pencereler (CSV, geçmiş) için kalan koyu stil
$form.Add_Shown({ foreach ($x in $script:NavItems) { $x.Invalidate() } })

}
