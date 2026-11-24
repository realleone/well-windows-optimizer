$root = $PSScriptRoot
$out  = Join-Path $root 'dist'
New-Item -ItemType Directory -Path $out -Force | Out-Null
$lines = Get-Content -LiteralPath (Join-Path $root 'WinOptSuite.ps1') -Encoding UTF8
$merged = foreach ($l in $lines) {
    if ($l -match "^\.\s+\(Join-Path \`$PSScriptRoot '(.+?)'\)") {
        Get-Content -LiteralPath (Join-Path $root $Matches[1]) -Encoding UTF8
    } else { $l }
}
$single = Join-Path $out 'WinOptSuite-tek-dosya.ps1'
[IO.File]::WriteAllLines($single, [string[]]$merged, (New-Object Text.UTF8Encoding($true)))
Write-Host "Tek dosya: $single"
if (Get-Command Invoke-ps2exe -ErrorAction SilentlyContinue) {
    Invoke-ps2exe -inputFile $single -outputFile (Join-Path $out 'WinOptSuite.exe') -requireAdmin -noConsole -title 'WinOpt Suite' -company 'Leone' -copyright 'Developed by Leone'
    Write-Host "EXE: $(Join-Path $out 'WinOptSuite.exe')"
} else {
    Write-Host "EXE için: Install-Module ps2exe -Scope CurrentUser  komutunu çalıştırıp Build.ps1'i tekrar çalıştırın."
}
