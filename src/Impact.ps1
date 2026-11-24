function Get-StartupImpact {
    $map = @{}; $boot = $null
    $log = 'Microsoft-Windows-Diagnostics-Performance/Operational'
    try {
        $e = Get-WinEvent -FilterHashtable @{LogName=$log; Id=100} -MaxEvents 1 -ErrorAction Stop
        $x = [xml]$e.ToXml()
        $bt = ($x.Event.EventData.Data | Where-Object { $_.Name -eq 'BootTime' }).'#text'
        if ($bt) { $boot = [math]::Round([double]$bt / 1000, 1) }
    } catch {}
    try {
        foreach ($e in Get-WinEvent -FilterHashtable @{LogName=$log; Id=101} -MaxEvents 300 -ErrorAction Stop) {
            $x = [xml]$e.ToXml(); $d = @{}
            foreach ($n in $x.Event.EventData.Data) { $d[$n.Name] = $n.'#text' }
            if (-not $d['TotalTime']) { continue }
            foreach ($cand in @($d['Name'], $d['Path'], $d['FriendlyName'])) {
                if (-not $cand) { continue }
                $k = ([IO.Path]::GetFileName($cand)).ToLower()
                if ($k -and -not $map.ContainsKey($k)) { $map[$k] = [math]::Round([double]$d['TotalTime'] / 1000, 1) }
            }
        }
    } catch {}
    return @{ Map = $map; Boot = $boot }
}
