$AppDir   = Join-Path $env:APPDATA 'WinOptSuite'
$LogFile  = Join-Path $AppDir 'islem-gunlugu.txt'
$SnapFile = Join-Path $AppDir 'bilinen-baslangic-girdileri.json'
if (-not (Test-Path -LiteralPath $AppDir)) { New-Item -ItemType Directory -Path $AppDir -Force | Out-Null }

function Write-Log([string]$m) {
    Add-Content -LiteralPath $LogFile -Value ("{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $m) -Encoding UTF8
}

function Resolve-ExePath([string]$cmd) {
    if ([string]::IsNullOrWhiteSpace($cmd)) { return '' }
    $c = [Environment]::ExpandEnvironmentVariables($cmd.Trim())
    if ($c.StartsWith('"')) {
        $i = $c.IndexOf('"', 1)
        if ($i -gt 1) { return $c.Substring(1, $i - 1) }
    }
    if ($c -match '^(.+?\.(exe|bat|cmd|com|lnk|msc|cpl))(\s|$)') { return $Matches[1] }
    return ($c -split '\s+')[0]
}

$script:PubCache = @{}
function Get-Publisher([string]$p) {
    if (-not $p -or -not (Test-Path -LiteralPath $p -PathType Leaf)) { return 'Bilinmiyor (dosya bulunamadı)' }
    if ($script:PubCache.ContainsKey($p)) { return $script:PubCache[$p] }
    $r = 'Bilinmiyor'
    try {
        $v = (Get-Item -LiteralPath $p -ErrorAction Stop).VersionInfo.CompanyName
        if ($v) { $r = $v.Trim() }
    } catch {}
    $script:PubCache[$p] = $r
    return $r
}

function Test-Protected([string]$name, [string]$path, [string]$pub) {
    if ($path -and $path.StartsWith($env:windir, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    $secRegex = 'defender|securityhealth|windows security|antivirus|antimalware|kaspersky|norton|mcafee|avast|bitdefender|\beset\b|malwarebytes|sophos|trend micro|crowdstrike|\bavg\b'
    if (("$name $path $pub") -match $secRegex) { return $true }
    return $false
}

function New-Entry($type, $source, $name, $cmd, $exe, [bool]$enabled, $extra) {
    $pub = Get-Publisher $exe
    [pscustomobject]@{
        Type = $type; Source = $source; Name = $name; Command = $cmd; Path = $exe
        Publisher = $pub; Enabled = $enabled
        Protected = (Test-Protected $name $exe $pub)
        Key = "$source|$name"; Extra = $extra; IsNew = $false; Impact = 'Ölçülmedi'
    }
}
if (-not (Test-Path -LiteralPath $LogFile)) { Write-Log 'WinOpt Suite - Developed by Leone' }
