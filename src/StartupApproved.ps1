function Get-ApprovedState([string]$hive, [string]$sub, [string]$valueName) {
    try {
        $k = Get-Item -LiteralPath "Registry::$hive\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\$sub" -ErrorAction Stop
        $b = $k.GetValue($valueName)
        if ($b -is [byte[]] -and $b.Length -gt 0) { return (($b[0] -band 1) -eq 0) }
    } catch {}
    return $true
}

function Set-ApprovedState([string]$hive, [string]$sub, [string]$valueName, [bool]$enable) {
    $root = if ($hive -eq 'HKCU') { [Microsoft.Win32.Registry]::CurrentUser } else { [Microsoft.Win32.Registry]::LocalMachine }
    $k = $root.CreateSubKey("Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\$sub")
    try {
        if ($enable) { $d = [byte[]](2,0,0,0,0,0,0,0,0,0,0,0) }
        else { $d = [byte[]]([byte[]](3,0,0,0) + [BitConverter]::GetBytes([DateTime]::Now.ToFileTime())) }
        $k.SetValue($valueName, $d, [Microsoft.Win32.RegistryValueKind]::Binary)
    } finally { $k.Close() }
}
