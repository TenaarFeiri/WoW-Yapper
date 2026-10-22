# Mirrors .release/stage/* into the WoW Retail AddOns directory.
# Run after tools/release.ps1. Override the destination with -AddOnsDir.
param(
    [string]$AddOnsDir = 'C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns'
)

$stage = Join-Path $PSScriptRoot '..\.release\stage'
if (-not (Test-Path $stage)) {
    Write-Error "No staged release at $stage -- run tools/release.ps1 first."
    exit 1
}

foreach ($d in (Get-ChildItem $stage -Directory)) {
    robocopy $d.FullName (Join-Path $AddOnsDir $d.Name) /MIR /NFL /NDL /NJH /NJS | Out-Null
}

Get-ChildItem $AddOnsDir -Directory |
    Where-Object Name -like 'Yapper*' |
    Select-Object -ExpandProperty Name
