$tabProc = New-Object Windows.Forms.TabPage
$tabProc.Text = 'İşlemler'
[void]$tabs.TabPages.Add($tabProc)

$gridProc = New-StdGrid @(
    @('PID', 60), @('İşlem', 170), @('CPU %', 60), @('RAM MB', 80), @('Dosya yolu', 320),
    @('Yayıncı', 150), @('Dijital imza', 190), @('Tür', 140), @('Not', 340))
$gridProc.Columns[2].DefaultCellStyle.Format = 'N1'
$gridProc.Columns[3].DefaultCellStyle.Format = 'N1'
$tabProc.Controls.Add($gridProc)
$barProc = New-Bar
$tabProc.Controls.Add($barProc)
$lblProc = New-StatusLabel
$tabProc.Controls.Add($lblProc)

$script:ProcRows = @{}
$script:SigCache = @{}
$script:ProcSorted = $false

function Test-FileSignature([string]$path) {
    if (-not $path -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { return 'Doğrulanamadı' }
    $key = $path.ToLower()
    if ($script:SigCache.ContainsKey($key)) { return $script:SigCache[$key] }
    $r = 'Doğrulanamadı'
    try {
        $s = Get-AuthenticodeSignature -LiteralPath $path -ErrorAction Stop
        switch ($s.Status.ToString()) {
            'Valid'     { $cn = ''; if ($s.SignerCertificate -and $s.SignerCertificate.Subject -match 'CN=([^,]+)') { $cn = $Matches[1].Trim('"') }; $r = "Geçerli: $cn" }
            'NotSigned' { $r = 'İmzasız' }
            default     { $r = "Geçersiz ($($s.Status))" }
        }
    } catch {}
    $script:SigCache[$key] = $r
    return $r
}

function Get-CachedSig([string]$path) {
    if (-not $path) { return 'Doğrulanamadı' }
    $key = $path.ToLower()
    if ($script:SigCache.ContainsKey($key)) { return $script:SigCache[$key] }
    return 'Doğrulanmadı'
}

function Get-ProcNote($it, [string]$sig) {
    $n = @()
    if ($it.Protection) { $n += "Korumalı: $($it.Protection)" }
    if ($it.Cpu -ge $script:HighCpu) { $n += 'Yüksek CPU' }
    if ($it.WsMB -ge $script:HighRamMB) { $n += 'Yüksek RAM' }
    if ($it.Leak) { $n += 'Bellek sızıntısı şüphesi' }
    if (Test-CloseSuggestion $it) { $n += ('Öneri: yaklaşık {0:N0} dk boşta, kapatılabilir' -f ($it.Idle * $script:SampleMs / 60000)) }
    if ($sig -like 'İmzasız*' -or $sig -like 'Geçersiz*') { $n += 'İmza sorunu (bilgi amaçlı)' }
    return ($n -join '; ')
}

function Show-Processes([switch]$Force) {
    if (-not $Force -and -not $chkProcLive.Checked -and $script:ProcRows.Count -gt 0) { return }
    $items = @($script:Snap | Where-Object {
        (-not $chkProcBg.Checked -or $_.Class -like 'Arka plan*') -and
        (-not $chkProcHigh.Checked -or $_.Cpu -ge $script:HighCpu -or $_.WsMB -ge $script:HighRamMB) })
    $seen = @{}
    $gridProc.SuspendLayout()
    try {
        foreach ($it in $items) {
            $seen[$it.Id] = $true
            $sig = Get-CachedSig $it.Path
            $vals = @($it.Id, $it.Name, $it.Cpu, $it.WsMB, $it.Path, $it.Publisher, $sig, $it.Class, (Get-ProcNote $it $sig))
            if ($script:ProcRows.ContainsKey($it.Id)) {
                $row = $script:ProcRows[$it.Id]
                for ($c = 0; $c -lt 9; $c++) { if ($row.Cells[$c].Value -ne $vals[$c]) { $row.Cells[$c].Value = $vals[$c] } }
            } else {
                $i = $gridProc.Rows.Add([object[]]$vals)
                $row = $gridProc.Rows[$i]; $script:ProcRows[$it.Id] = $row
            }
            $row.Tag = $it
            if ($it.Protection) { $row.DefaultCellStyle.BackColor = [Drawing.Color]::Gainsboro }
            elseif ($it.Cpu -ge $script:HighCpu -or $it.WsMB -ge $script:HighRamMB) { $row.DefaultCellStyle.BackColor = [Drawing.Color]::MistyRose }
            elseif (Test-CloseSuggestion $it) { $row.DefaultCellStyle.BackColor = [Drawing.Color]::LightYellow }
            else { $row.DefaultCellStyle.BackColor = [Drawing.Color]::White }
        }
        foreach ($k in @($script:ProcRows.Keys)) {
            if (-not $seen.ContainsKey($k)) { $gridProc.Rows.Remove($script:ProcRows[$k]); $script:ProcRows.Remove($k) }
        }
        if (-not $script:ProcSorted -and $gridProc.Rows.Count -gt 0) { $gridProc.Sort($gridProc.Columns[3], 'Descending'); $script:ProcSorted = $true }
        elseif ($gridProc.SortedColumn) {
            $dir = if ($gridProc.SortOrder -eq 'Descending') { 'Descending' } else { 'Ascending' }
            $gridProc.Sort($gridProc.SortedColumn, $dir)
        }
    } finally { $gridProc.ResumeLayout() }
    $hi  = @($script:Snap | Where-Object { -not $_.Protection -and ($_.Cpu -ge $script:HighCpu -or $_.WsMB -ge $script:HighRamMB) }).Count
    $sug = @($script:Snap | Where-Object { Test-CloseSuggestion $_ }).Count
    $lblProc.Text = "  İşlem: $($script:Snap.Count) (gösterilen $($items.Count))  |  Toplam CPU: %$($script:TotalCpu)  |  Yüksek tüketen: $hi  |  Kapatma önerisi: $sug  |  İmzasız/bilinmeyen işlemler zararlı sayılmaz, yalnızca bilgi verilir."
}

function Get-SelectedProcs { @($gridProc.SelectedRows | ForEach-Object { $_.Tag } | Where-Object { $_ }) }

function Confirm-Signatures($items) {
    $paths = @($items | Where-Object { $_.Path } | Select-Object -ExpandProperty Path -Unique)
    if ($paths.Count -eq 0) { return }
    $script:Timer.Stop(); $form.Cursor = 'WaitCursor'
    try {
        $i = 0
        foreach ($p in $paths) {
            $i++; $lblProc.Text = "  İmza doğrulanıyor ($i/$($paths.Count))..."
            [void](Test-FileSignature $p)
            if ($i % 3 -eq 0) { [Windows.Forms.Application]::DoEvents() }
        }
    } finally { $form.Cursor = 'Default'; $script:Timer.Start(); Show-Processes -Force }
}

function Stop-SelectedProcs {
    $sel = Get-SelectedProcs
    if ($sel.Count -eq 0) { [L10nMsg]::Show('Önce listeden işlem seçin.', 'WinOpt Suite - Developed by Leone') | Out-Null; return }
    $blocked = @($sel | Where-Object { $_.Protection })
    $ok = @($sel | Where-Object { -not $_.Protection })
    if ($blocked.Count -gt 0) {
        [L10nMsg]::Show("Şu işlemler korumalıdır ve sonlandırılamaz:`n`n" + (($blocked | ForEach-Object { "$($_.Name) (PID $($_.Id)): $($_.Protection)" }) -join "`n"), 'Korumalı işlemler') | Out-Null
    }
    if ($ok.Count -eq 0) { return }
    $msg = "Şu işlemler sonlandırılacak. Kaydedilmemiş veriler kaybolabilir:`n`n" + (($ok | ForEach-Object { "$($_.Name) (PID $($_.Id)) - $($_.WsMB) MB" }) -join "`n") + "`n`nDevam edilsin mi?"
    if ([L10nMsg]::Show($msg, 'Sonlandırmayı onayla', 'YesNo', 'Warning') -ne 'Yes') { return }
    $done = 0; $fail = @()
    foreach ($it in $ok) {
        $how = ''; $result = ''
        try {
            $p = Get-Process -Id $it.Id -ErrorAction Stop
            if ($p.ProcessName -ne $it.Name) { throw 'İşlem artık mevcut değil (PID yeniden kullanılmış).' }
            $closed = $false
            if ($it.HasWin) { [void]$p.CloseMainWindow(); if ($p.WaitForExit(3000)) { $closed = $true; $how = 'Nazik kapatma' } }
            if (-not $closed) { Stop-Process -Id $it.Id -Force -ErrorAction Stop; $how = 'Zorla sonlandırma' }
            $result = 'Başarılı'; $done++
        } catch {
            $result = 'Başarısız: ' + $_.Exception.Message
            $fail += "$($it.Name): $($_.Exception.Message)"
        }
        try {
            [pscustomobject][ordered]@{
                Zaman = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); Islem = $it.Name; PID = $it.Id; Yol = $it.Path
                Yayinci = $it.Publisher; RamMB = $it.WsMB; Yontem = $how; Sonuc = $result
            } | Export-Csv -LiteralPath $KillHistFile -Append -NoTypeInformation -Encoding UTF8
        } catch {}
        Write-Log ("İşlem sonlandırma: {0} (PID {1}) -> {2}" -f $it.Name, $it.Id, $result)
    }
    Invoke-Sample; Show-Processes -Force
    $m = "$done işlem sonlandırıldı."
    if ($fail.Count) { $m += "`n`nBaşarısız (yetki yetersiz olabilir):`n" + ($fail -join "`n") }
    [L10nMsg]::Show($m, 'WinOpt Suite - Developed by Leone') | Out-Null
}

New-Btn $barProc 'Şimdi Yenile' 90 { Invoke-Sample; Show-Processes -Force }
New-Btn $barProc 'Seçili İşlemi Sonlandır' 160 { Stop-SelectedProcs }
New-Btn $barProc 'İmzayı Doğrula (Seçili)' 150 { Confirm-Signatures (Get-SelectedProcs) }
New-Btn $barProc 'Tüm İmzaları Doğrula' 150 { Confirm-Signatures $script:Snap }
New-Btn $barProc 'Dosya Konumunu Aç' 140 {
    foreach ($it in (Get-SelectedProcs | Select-Object -First 1)) {
        if ($it.Path -and (Test-Path -LiteralPath $it.Path)) { Start-Process explorer.exe -ArgumentList "/select,`"$($it.Path)`"" }
        else { [L10nMsg]::Show('Dosya yolu bulunamadı.', 'WinOpt Suite - Developed by Leone') | Out-Null }
    }
}
New-Btn $barProc 'Sonlandırma Geçmişi' 140 { Show-CsvDialog $KillHistFile 'İşlem sonlandırma geçmişi' }
$chkProcLive = New-Chk $barProc 'Canlı takip' $true $null
$chkProcBg   = New-Chk $barProc 'Yalnızca arka plan kullanıcı uygulamaları' $false { Show-Processes -Force }
$chkProcHigh = New-Chk $barProc 'Yalnızca yüksek tüketenler' $false { Show-Processes -Force }
