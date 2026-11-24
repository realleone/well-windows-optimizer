function Get-RegistryEntries {
    $defs = @(
        @{H='HKCU'; P='Software\Microsoft\Windows\CurrentVersion\Run';                  A='Run';   S='Registry Run (Kullanıcı)'},
        @{H='HKLM'; P='Software\Microsoft\Windows\CurrentVersion\Run';                  A='Run';   S='Registry Run (Sistem)'},
        @{H='HKLM'; P='Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run';      A='Run32'; S='Registry Run (Sistem, 32-bit)'},
        @{H='HKCU'; P='Software\Microsoft\Windows\CurrentVersion\RunOnce';              A=$null;   S='Registry RunOnce (Kullanıcı)'},
        @{H='HKLM'; P='Software\Microsoft\Windows\CurrentVersion\RunOnce';              A=$null;   S='Registry RunOnce (Sistem)'}
    )
    foreach ($d in $defs) {
        try { $k = Get-Item -LiteralPath "Registry::$($d.H)\$($d.P)" -ErrorAction Stop } catch { continue }
        foreach ($n in $k.GetValueNames()) {
            if ($n -eq '') { continue }
            $cmd = [string]$k.GetValue($n, '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            $exe = Resolve-ExePath $cmd
            $en = if ($d.A) { Get-ApprovedState $d.H $d.A $n } else { $true }
            New-Entry 'Registry' $d.S $n $cmd $exe $en @{Hive=$d.H; Approved=$d.A; ValueName=$n; Manageable=[bool]$d.A}
        }
    }
}

function Get-FolderEntries {
    $sh = New-Object -ComObject WScript.Shell
    $defs = @(
        @{P=[Environment]::GetFolderPath('Startup');       H='HKCU'; S='Başlangıç klasörü (Kullanıcı)'},
        @{P=[Environment]::GetFolderPath('CommonStartup'); H='HKLM'; S='Başlangıç klasörü (Genel)'}
    )
    foreach ($d in $defs) {
        if (-not $d.P -or -not (Test-Path -LiteralPath $d.P)) { continue }
        foreach ($f in Get-ChildItem -LiteralPath $d.P -File -Force -ErrorAction SilentlyContinue) {
            if ($f.Name -ieq 'desktop.ini') { continue }
            $cmd = $f.FullName; $exe = $f.FullName
            if ($f.Extension -ieq '.lnk') {
                try { $l = $sh.CreateShortcut($f.FullName); $exe = $l.TargetPath; $cmd = ("$($l.TargetPath) $($l.Arguments)").Trim() } catch {}
            }
            $en = Get-ApprovedState $d.H 'StartupFolder' $f.Name
            New-Entry 'Klasör' $d.S $f.Name $cmd $exe $en @{Hive=$d.H; Approved='StartupFolder'; ValueName=$f.Name; Manageable=$true}
        }
    }
}

function Get-TaskEntries {
    try { $tasks = Get-ScheduledTask -ErrorAction Stop } catch { return }
    foreach ($t in $tasks) {
        if ($t.TaskPath -like '\Microsoft\*') { continue }
        $trg = @($t.Triggers | Where-Object { $_.CimClass.CimClassName -in 'MSFT_TaskLogonTrigger', 'MSFT_TaskBootTrigger' })
        if ($trg.Count -eq 0) { continue }
        $a = $t.Actions | Select-Object -First 1
        $cmd = ''; $exe = ''
        if ($a -and $a.Execute) { $cmd = ("$($a.Execute) $($a.Arguments)").Trim(); $exe = Resolve-ExePath $a.Execute }
        New-Entry 'Görev' 'Görev Zamanlayıcı' ($t.TaskPath + $t.TaskName) $cmd $exe ($t.State -ne 'Disabled') @{TaskName=$t.TaskName; TaskPath=$t.TaskPath; Manageable=$true}
    }
}
