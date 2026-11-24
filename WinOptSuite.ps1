param([switch]$Maintenance)
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

$script:MainScript = $PSCommandPath
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    try {
        Start-Process powershell.exe -Verb RunAs -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -STA -File `"$PSCommandPath`"" + $(if ($Maintenance) { ' -Maintenance' } else { '' }))
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Administrator permission was not granted. The application must be run as administrator.", "WinOpt Suite - Developed by Leone") | Out-Null
    }
    exit
}

. (Join-Path $PSScriptRoot 'src\Common.ps1')
. (Join-Path $PSScriptRoot 'src\Lang.ps1')
. (Join-Path $PSScriptRoot 'src\StartupApproved.ps1')
. (Join-Path $PSScriptRoot 'src\Sources.ps1')
. (Join-Path $PSScriptRoot 'src\Impact.ps1')
. (Join-Path $PSScriptRoot 'src\UI.ps1')
. (Join-Path $PSScriptRoot 'src\Monitor.ps1')
. (Join-Path $PSScriptRoot 'src\Processes.ps1')
. (Join-Path $PSScriptRoot 'src\Ram.ps1')
. (Join-Path $PSScriptRoot 'src\Services.ps1')
. (Join-Path $PSScriptRoot 'src\Registry.ps1')
. (Join-Path $PSScriptRoot 'src\CleanCommon.ps1')
. (Join-Path $PSScriptRoot 'src\Cleaner.ps1')
. (Join-Path $PSScriptRoot 'src\Browsers.ps1')
. (Join-Path $PSScriptRoot 'src\WindowsTweaks.ps1')
. (Join-Path $PSScriptRoot 'src\Gaming.ps1')
. (Join-Path $PSScriptRoot 'src\SystemHealth.ps1')
. (Join-Path $PSScriptRoot 'src\SmartEngine.ps1')
. (Join-Path $PSScriptRoot 'src\Reports.ps1')
. (Join-Path $PSScriptRoot 'src\Maintenance.ps1')
. (Join-Path $PSScriptRoot 'src\Tools.ps1')
. (Join-Path $PSScriptRoot 'src\Theme.ps1')
. (Join-Path $PSScriptRoot 'src\Presets.ps1')

if ($Maintenance) {
    try { [void](Invoke-MaintenanceRun 'Zamanlanmış') } catch { Write-Log ('Zamanlanmış bakım hatası: ' + $_.Exception.Message) }
    exit
}
[L10n]::Walk($form)
[L10n]::Start()
[void]$form.ShowDialog()
