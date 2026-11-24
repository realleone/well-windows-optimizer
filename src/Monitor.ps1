$script:SampleMs    = 3000
$script:Cores       = [Environment]::ProcessorCount
$script:IdleLimit   = 100
$script:HighCpu     = 25
$script:HighRamMB   = 1024
$script:ProcPrev    = @{}
$script:PathCache   = @{}
$script:MemHist     = @{}
$script:IdleCount   = @{}
$script:LeakFlag    = @{}
$script:Snap        = @()
$script:SnapByPid   = @{}
$script:TotalCpu    = 0
$script:Sys         = $null
$script:TotalHist   = New-Object 'System.Collections.Generic.List[double]'
$script:SampleCount = 0
$script:LastErr     = ''

$RamHistFile   = Join-Path $AppDir 'ram-gecmisi.csv'
$KillHistFile  = Join-Path $AppDir 'sonlandirma-gecmisi.csv'
$SvcBackupFile = Join-Path $AppDir 'servis-yedegi.json'

$script:SecRegex = 'defender|securityhealth|windows security|antivirus|antimalware|kaspersky|norton|mcafee|avast|bitdefender|\beset\b|malwarebytes|sophos|trend micro|crowdstrike|\bavg\b|msmpeng|nissrv'
$script:CriticalNames = @('system','idle','registry','smss','csrss','wininit','winlogon','services','lsass','lsaiso','svchost',
    'fontdrvhost','dwm','explorer','sihost','ctfmon','taskhostw','runtimebroker','audiodg','spoolsv','searchindexer','searchhost',
    'startmenuexperiencehost','shellexperiencehost','textinputhost','memory compression','secure system','vmmem','wudfhost',
    'conhost','dllhost','wmiprvse','smartscreen','sgrmbroker','lockapp','applicationframehost','unsecapp','backgroundtaskhost',
    'securityhealthservice','securityhealthsystray','msmpeng','nissrv','mpdefendercoreservice','taskmgr','powershell')

try {
    if ((Test-Path -LiteralPath $RamHistFile) -and ((Get-Item -LiteralPath $RamHistFile).Length -gt 2MB)) {
        $l = Get-Content -LiteralPath $RamHistFile -Encoding UTF8
        (@($l[0]) + $l[-10000..-1]) | Set-Content -LiteralPath $RamHistFile -Encoding UTF8
    }
} catch {}

function New-StdGrid($cols) {
    $g = New-Object Windows.Forms.DataGridView
    $g.Dock = 'Fill'; $g.ReadOnly = $true; $g.AllowUserToAddRows = $false; $g.AllowUserToDeleteRows = $false
    $g.SelectionMode = 'FullRowSelect'; $g.MultiSelect = $true; $g.RowHeadersVisible = $false
    $g.AutoSizeColumnsMode = 'None'; $g.BackgroundColor = [Drawing.Color]::White
    foreach ($c in $cols) {
        $col = New-Object Windows.Forms.DataGridViewTextBoxColumn
        $col.HeaderText = $c[0]; $col.Width = $c[1]; $col.SortMode = 'Automatic'
        [void]$g.Columns.Add($col)
    }
    return $g
}
function New-Bar { $b = New-Object Windows.Forms.FlowLayoutPanel; $b.Dock = 'Top'; $b.Height = 78; $b.Padding = New-Object Windows.Forms.Padding(6); return $b }
function New-StatusLabel { $l = New-Object Windows.Forms.Label; $l.Dock = 'Bottom'; $l.Height = 26; $l.TextAlign = 'MiddleLeft'; $l.BackColor = [Drawing.SystemColors]::Control; return $l }
function New-Btn($panel, [string]$text, [int]$w, [scriptblock]$handler) {
    $b = New-Object Windows.Forms.Button; $b.Text = $text; $b.Width = $w; $b.Height = 30
    $b.Add_Click($handler); $panel.Controls.Add($b)
}
function New-Chk($panel, [string]$text, [bool]$isChecked, [scriptblock]$handler) {
    $c = New-Object Windows.Forms.CheckBox; $c.Text = $text; $c.AutoSize = $true; $c.Checked = $isChecked
    $c.Margin = New-Object Windows.Forms.Padding(8, 7, 8, 0)
    if ($handler) { $c.Add_CheckedChanged($handler) }
    $panel.Controls.Add($c)
    return $c
}

function Show-CsvDialog([string]$path, [string]$title) {
    if (-not (Test-Path -LiteralPath $path)) { [L10nMsg]::Show('Henüz kayıt yok.', $title) | Out-Null; return }
    $rows = @(Import-Csv -LiteralPath $path -Encoding UTF8)
    if ($rows.Count -eq 0) { [L10nMsg]::Show('Henüz kayıt yok.', $title) | Out-Null; return }
    $dt = New-Object System.Data.DataTable
    foreach ($c in $rows[0].PSObject.Properties.Name) { [void]$dt.Columns.Add($c) }
    foreach ($r in $rows) { [void]$dt.Rows.Add([object[]]@($r.PSObject.Properties | ForEach-Object { $_.Value })) }
    $f = New-Object Windows.Forms.Form
    $f.Text = "$title ($($rows.Count) kayıt)"; $f.Size = New-Object Drawing.Size(1000, 500); $f.StartPosition = 'CenterParent'
    $g = New-Object Windows.Forms.DataGridView
    $g.Dock = 'Fill'; $g.ReadOnly = $true; $g.AllowUserToAddRows = $false; $g.RowHeadersVisible = $false
    $g.AutoSizeColumnsMode = 'AllCells'; $g.BackgroundColor = [Drawing.Color]::White; $g.DataSource = $dt
    $f.Controls.Add($g)
    [void]$f.ShowDialog($form)
}

function Get-ProtectionReason($name, $path, $sid, $procId, $pub) {
    if ($procId -le 4 -or $procId -eq $PID) { return 'Sistem / bu uygulama' }
    if ($script:CriticalNames -contains $name.ToLower()) { return 'Kritik Windows işlemi' }
    if (("$name $path $pub") -match $script:SecRegex) { return 'Güvenlik bileşeni' }
    if ($sid -eq 0) { return 'Servis oturumu (Servisler sekmesini kullanın)' }
    if (-not $path) { return 'Dosya yolu okunamadı (yetki)' }
    if ($path.StartsWith("$env:windir\System32", [StringComparison]::OrdinalIgnoreCase) -and $pub -match 'Microsoft') { return 'Windows bileşeni' }
    return $null
}

function Test-CloseSuggestion($it) {
    return ((-not $it.Protection) -and ($it.Class -like 'Arka plan*') -and ($it.Idle -ge $script:IdleLimit) -and ($it.WsMB -ge 100))
}

function Test-LeakSuspect($h) {
    $n = $h.Count
    if ($n -lt 60) { return $false }
    $first = ($h.GetRange(0, 10) | Measure-Object -Average).Average
    $last  = ($h.GetRange($n - 10, 10) | Measure-Object -Average).Average
    if (($last - $first) -lt 100 -or $last -lt ($first * 1.2)) { return $false }
    $up = 0
    for ($i = 1; $i -lt $n; $i++) { if ($h[$i] -ge ($h[$i - 1] - 0.5)) { $up++ } }
    return (($up / ($n - 1)) -ge 0.85)
}

$script:NativePathOk = $false
try {
    if (-not ('WinOptProcPath' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class WinOptProcPath {
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool QueryFullProcessImageName(IntPtr h, int flags, StringBuilder sb, ref int size);
    public static string Get(int pid) {
        IntPtr h = OpenProcess(0x1000, false, pid);
        if (h == IntPtr.Zero) return null;
        try {
            StringBuilder sb = new StringBuilder(1024);
            int n = sb.Capacity;
            return QueryFullProcessImageName(h, 0, sb, ref n) ? sb.ToString() : null;
        } finally { CloseHandle(h); }
    }
}
'@
    }
    $script:NativePathOk = [bool]('WinOptProcPath' -as [type])
} catch { $script:NativePathOk = $false }

function Update-PathCache($procs) {
    $missing = @($procs | Where-Object { -not $script:PathCache.ContainsKey($_.Id) })
    if ($missing.Count -eq 0) { return }
    if ($script:NativePathOk) {
        foreach ($p in $missing) {
            $pth = $null
            if ($p.Id -gt 4) { try { $pth = [WinOptProcPath]::Get([int]$p.Id) } catch {} }
            $script:PathCache[$p.Id] = $pth
        }
        return
    }
    $cim = @{}
    try { foreach ($c in Get-CimInstance Win32_Process -Property ProcessId, ExecutablePath -ErrorAction Stop) { $cim[[int]$c.ProcessId] = $c.ExecutablePath } } catch {}
    foreach ($p in $missing) { $script:PathCache[$p.Id] = $cim[[int]$p.Id] }
}

function Update-Snapshot {
    $now = [DateTime]::UtcNow
    $procs = @(Get-Process -ErrorAction SilentlyContinue)
    Update-PathCache $procs
    $live = @{}; $list = New-Object System.Collections.ArrayList; $byPid = @{}; $sumCpu = 0.0
    foreach ($p in $procs) {
        try {
            $id = $p.Id; $live[$id] = $true
            $cpuSec = $null
            try { $cpuSec = $p.TotalProcessorTime.TotalSeconds } catch {}
            $cpuPct = 0.0
            if ($null -ne $cpuSec -and $script:ProcPrev.ContainsKey($id)) {
                $prev = $script:ProcPrev[$id]
                $dt = ($now - $prev.T).TotalSeconds
                if ($dt -gt 0) { $cpuPct = [math]::Max(0, [math]::Min(100, (($cpuSec - $prev.Cpu) / $dt / $script:Cores) * 100)) }
            }
            if ($null -ne $cpuSec) { $script:ProcPrev[$id] = @{ Cpu = $cpuSec; T = $now } }
            $sumCpu += $cpuPct

            $ws = [math]::Round($p.WorkingSet64 / 1MB, 1)
            $priv = [math]::Round($p.PrivateMemorySize64 / 1MB, 1)
            if ($cpuPct -lt 0.5) { $script:IdleCount[$id] = 1 + [int]$script:IdleCount[$id] } else { $script:IdleCount[$id] = 0 }
            if (-not $script:MemHist.ContainsKey($id)) { $script:MemHist[$id] = New-Object 'System.Collections.Generic.List[double]' }
            $h = $script:MemHist[$id]; $h.Add($priv); if ($h.Count -gt 200) { $h.RemoveAt(0) }

            $hasWin = $false
            try { $hasWin = ($p.MainWindowHandle -ne [IntPtr]::Zero) } catch {}
            $path = $script:PathCache[$id]
            $pub = if ($path) { Get-Publisher $path } else { 'Bilinmiyor (yol okunamadı)' }
            $prot = Get-ProtectionReason $p.ProcessName $path $p.SessionId $id $pub
            $class = if ($prot) { 'Sistem / korumalı' } elseif ($hasWin) { 'Pencereli uygulama' } else { 'Arka plan (kullanıcı)' }
            $it = [pscustomobject]@{
                Id = $id; Name = $p.ProcessName; Cpu = [math]::Round($cpuPct, 1); WsMB = $ws; PrivMB = $priv
                Path = $path; Publisher = $pub; Session = $p.SessionId; HasWin = $hasWin
                Idle = [int]$script:IdleCount[$id]; Leak = [bool]$script:LeakFlag[$id]
                Protection = $prot; Class = $class
            }
            [void]$list.Add($it); $byPid[$id] = $it
        } catch {}
    }
    foreach ($d in @($script:ProcPrev, $script:PathCache, $script:MemHist, $script:IdleCount, $script:LeakFlag)) {
        foreach ($k in @($d.Keys)) { if (-not $live.ContainsKey($k)) { $d.Remove($k) } }
    }
    $script:Snap = @($list); $script:SnapByPid = $byPid
    $script:TotalCpu = [math]::Min(100, [math]::Round($sumCpu, 0))
}

function Update-SystemMemory {
    $os = Get-CimInstance Win32_OperatingSystem -Property TotalVisibleMemorySize, FreePhysicalMemory
    $tot = $os.TotalVisibleMemorySize / 1024.0; $free = $os.FreePhysicalMemory / 1024.0; $used = $tot - $free
    $script:Sys = @{ TotalMB = $tot; FreeMB = $free; UsedMB = $used; Pct = ($used / $tot * 100) }
    $script:TotalHist.Add($script:Sys.Pct)
    if ($script:TotalHist.Count -gt 120) { $script:TotalHist.RemoveAt(0) }
}

function Update-LeakFlags {
    foreach ($k in @($script:MemHist.Keys)) {
        $h = $script:MemHist[$k]
        if ($h.Count -ge 60 -and $h[$h.Count - 1] -ge 100) { $script:LeakFlag[$k] = (Test-LeakSuspect $h) } else { $script:LeakFlag[$k] = $false }
    }
}

function Save-RamHistory {
    if (-not $script:Sys) { return }
    try {
        [pscustomobject][ordered]@{
            Zaman = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            ToplamMB = [math]::Round($script:Sys.TotalMB); KullanilanMB = [math]::Round($script:Sys.UsedMB)
            KullanilabilirMB = [math]::Round($script:Sys.FreeMB); KullanimYuzde = [math]::Round($script:Sys.Pct, 1)
        } | Export-Csv -LiteralPath $RamHistFile -Append -NoTypeInformation -Encoding UTF8
    } catch {}
}

function Invoke-RenderActive {
    $t = $tabs.SelectedTab
    if ($t -eq $tabProc) { Show-Processes }
    elseif ($t -eq $tabRam) { Show-Ram }
    elseif ($t -eq $tabSvc) { Show-ServiceUsage }
    elseif ($t -eq $tabTweak) { Show-Tweaks }
    elseif ($t -eq $tabGame) { Show-Game }
    elseif ($t -eq $tabHealth) { Show-Health }
}

function Invoke-Sample {
    Update-Snapshot
    Update-SystemMemory
    Update-GameWatch
    $script:SampleCount++
    if ($script:SampleCount % 10 -eq 0) { Update-LeakFlags }
    if ($script:SampleCount % 20 -eq 0) { Save-RamHistory }
    if ($form.WindowState -ne [Windows.Forms.FormWindowState]::Minimized) { Invoke-RenderActive }
}

$script:Timer = New-Object Windows.Forms.Timer
$script:Timer.Interval = $script:SampleMs
$script:Timer.Add_Tick({
    $script:Timer.Stop()
    try { Invoke-Sample }
    catch {
        if ($_.Exception.Message -ne $script:LastErr) { $script:LastErr = $_.Exception.Message; Write-Log ('Örnekleme hatası: ' + $script:LastErr) }
    }
    finally { $script:Timer.Start() }
})
$tabs.Add_SelectedIndexChanged({ try { Invoke-RenderActive } catch {} })
$form.Add_Shown({ try { Invoke-Sample } catch {}; $script:Timer.Start() })
$form.Add_FormClosed({ $script:Timer.Stop(); $script:Timer.Dispose() })
