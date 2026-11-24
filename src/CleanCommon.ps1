$script:ClCancel = $false

$script:ClProtectedDirs = @(
    $env:windir, $env:SystemDrive, "$env:SystemDrive\Users", $env:USERPROFILE, $env:ProgramFiles, ${env:ProgramFiles(x86)},
    $env:ProgramData, $env:LOCALAPPDATA, $env:APPDATA
) | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') }

$script:ClDenyInside = @(
    (Join-Path $env:windir 'System32'), (Join-Path $env:windir 'SysWOW64'), (Join-Path $env:windir 'WinSxS'),
    (Join-Path $env:windir 'servicing'), (Join-Path $env:windir 'SoftwareDistribution'), (Join-Path $env:windir 'Boot'),
    (Join-Path $env:windir 'Fonts'), (Join-Path $env:windir 'assembly'), (Join-Path $env:windir 'Microsoft.NET'),
    $env:ProgramFiles, ${env:ProgramFiles(x86)}
) | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') }

function Format-Bytes([double]$b) {
    if ($b -ge 1GB) { return ('{0:N2} GB' -f ($b / 1GB)) }
    if ($b -ge 1MB) { return ('{0:N1} MB' -f ($b / 1MB)) }
    if ($b -ge 1KB) { return ('{0:N0} KB' -f ($b / 1KB)) }
    return ('{0:N0} B' -f $b)
}

function Get-SystemFree {
    try { $d = New-Object IO.DriveInfo $env:SystemDrive; return [long]$d.AvailableFreeSpace } catch { return [long]0 }
}

function New-CleanRoot([string]$path, [bool]$recursive = $true, $patterns = $null, $exclude = $null) {
    return @{ Path = $path; Recursive = $recursive; Patterns = $patterns; Exclude = $exclude }
}

function Get-LongPathSafe([string]$p) {
    if ($p -notmatch '~\d') { return $p }
    try {
        if (-not ('WinOptPath' -as [type])) {
            Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class WinOptPath {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern uint GetLongPathNameW(string s, StringBuilder b, uint n);
    public static string Long(string p) {
        StringBuilder b = new StringBuilder(2048);
        uint r = GetLongPathNameW(p, b, (uint)b.Capacity);
        if (r == 0 || r > b.Capacity) return p;
        return b.ToString();
    }
}
'@
        }
        return [WinOptPath]::Long($p)
    } catch { return $p }
}

function Resolve-CleanRoot($spec, [string]$leafRx) {
    try {
        if (-not $spec.Path) { return $null }
        $p = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables([string]$spec.Path)).TrimEnd('\')
        $p = (Get-LongPathSafe $p).TrimEnd('\')
        if ($p -notmatch '^[A-Za-z]:\\[^\\]') { return $null }
        $di = New-Object IO.DirectoryInfo $p
        if (-not $di.Exists) { return $null }
        if ($di.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $null }
        if ($leafRx -and ($di.Name -notmatch $leafRx)) { return $null }
        foreach ($x in $script:ClDenyInside) {
            if ($p.Equals($x, 'OrdinalIgnoreCase') -or $p.StartsWith($x + '\', 'OrdinalIgnoreCase')) { return $null }
        }
        if ($spec.Recursive) {
            foreach ($x in $script:ClProtectedDirs) {
                if ($x.Equals($p, 'OrdinalIgnoreCase') -or $x.StartsWith($p + '\', 'OrdinalIgnoreCase')) { return $null }
            }
        } else {
            $pt = @($spec.Patterns)
            if ($pt.Count -eq 0 -or ($pt -contains '*') -or ($pt -contains '*.*')) { return $null }
        }
        return $p
    } catch { return $null }
}

function Test-UnderRoots([string]$p, $roots) {
    foreach ($r in $roots) {
        if ($p.StartsWith(([string]$r) + '\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Add-CleanFolderScan([string]$root, $spec, $cutoff, $files, $dirs, $ctr) {
    $pats = if ($spec.Patterns) { @($spec.Patterns) } else { @('*') }
    $stack = New-Object 'System.Collections.Generic.Stack[string]'
    $stack.Push($root)
    $n = 0
    while ($stack.Count -gt 0) {
        $n++
        if (($n % 40) -eq 0) { [Windows.Forms.Application]::DoEvents() }
        if ($script:ClCancel) { break }
        $cur = $stack.Pop()
        $di = New-Object IO.DirectoryInfo $cur
        foreach ($pat in $pats) {
            $fis = $null
            try { $fis = $di.GetFiles($pat) } catch { $ctr.Denied++; continue }
            foreach ($f in $fis) {
                if ($f.Name -ieq 'desktop.ini') { continue }
                if ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                if ($spec.Exclude -and ($spec.Exclude -contains $f.Name)) { continue }
                $lw = $f.LastWriteTime
                if ($cutoff) {
                    $cr = $f.CreationTime
                    $ref = if ($cr -gt $lw) { $cr } else { $lw }
                    if ($ref -gt $cutoff) { $ctr.Young++; continue }
                }
                $files.Add([object[]]@($f.FullName, [long]$f.Length, $lw))
                $ctr.Bytes += [long]$f.Length
            }
        }
        if ($spec.Recursive) {
            $subs = $null
            try { $subs = $di.GetDirectories() } catch { $ctr.Denied++; continue }
            foreach ($sd in $subs) {
                if ($sd.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                $stack.Push($sd.FullName)
                $dirs.Add($sd.FullName)
            }
        }
    }
}

function Remove-CleanFile($rec, $roots) {
    $p = [string]$rec[0]
    if (-not (Test-UnderRoots $p $roots)) { return 'unsafe' }
    try {
        $fi = New-Object IO.FileInfo $p
        if (-not $fi.Exists) { return 'gone' }
        if ($fi.Attributes -band [IO.FileAttributes]::ReparsePoint) { return 'unsafe' }
        if ($fi.Length -ne [long]$rec[1] -or $fi.LastWriteTime -ne [datetime]$rec[2]) { return 'changed' }
        if ($fi.IsReadOnly) { $fi.IsReadOnly = $false }
        $fi.Delete()
        return 'ok'
    }
    catch [System.IO.IOException] { return 'locked' }
    catch [System.UnauthorizedAccessException] { return 'denied' }
    catch { return 'denied' }
}

function Remove-CleanEmptyDirs($dirs, $roots, $cutoff) {
    $n = 0
    foreach ($d in ($dirs | Sort-Object Length -Descending)) {
        if (-not (Test-UnderRoots $d $roots)) { continue }
        try {
            $di = New-Object IO.DirectoryInfo $d
            if (-not $di.Exists) { continue }
            if ($di.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            if ($cutoff -and $di.CreationTime -gt $cutoff) { continue }
            $di.Delete($false)
            $n++
        } catch {}
    }
    return $n
}

function Add-CleanHistory([string]$file, $row) {
    try { $row | Export-Csv -LiteralPath $file -Append -NoTypeInformation -Encoding UTF8 }
    catch { Write-Log ('Temizlik geçmişi yazılamadı: ' + $_.Exception.Message) }
}

function Get-CleanTotalFreed([string]$file) {
    if (-not (Test-Path -LiteralPath $file)) { return [long]0 }
    try {
        $sum = (Import-Csv -LiteralPath $file -Encoding UTF8 | ForEach-Object { [long]$_.'Kazanılan bayt' } | Measure-Object -Sum).Sum
        return [long]$sum
    } catch { return [long]0 }
}
