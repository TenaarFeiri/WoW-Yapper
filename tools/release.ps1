# PowerShell equivalent of release.sh for Windows
$ErrorActionPreference = "Stop"

# Extract version from TOC
$tocContent = Get-Content "Yapper.toc" -Raw
if ($tocContent -match '## Version:\s*(.+)') {
    $version = $matches[1].Trim()
} else {
    $version = "unknown"
}
$stage = ".release\stage"
$out = ".release\Yapper-$version.zip"

# Configuration
$locales = @(
    "Yapper_Dict_en"
    "Yapper_Dict_enAU"
    "Yapper_Dict_enGB"
    "Yapper_Dict_enUS"
    # "Yapper_Dict_deDE" # Not ready yet
)

Write-Host "Building Yapper v$version..."

# 0. Sync documentation before release
Write-Host "Syncing documentation..."
python "tools\sync_all_docs.py" --inject

# Clean start
Remove-Item -Path ".release" -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path "$stage\Yapper" -Force | Out-Null

# 1. Main addon — strict whitelist of user-relevant files
$mainFiles = @(
    "Src\"
    "Changelogs.md"
    "Yapper.lua"
    "Yapper.toc"
    "Bindings.xml"
    "LICENSE"
)

foreach ($file in $mainFiles) {
    $src = ".\$file"
    $dst = "$stage\Yapper\$file"
    if (Test-Path $src -PathType Container) {
        Copy-Item -Path $src -Destination $dst -Recurse -Force
    } else {
        Copy-Item -Path $src -Destination $dst -Force
    }
}

# 2. Ship these locales as sibling addons
foreach ($d in $locales) {
    $dictPath = "Dictionaries\$d"
    if (Test-Path $dictPath) {
        New-Item -ItemType Directory -Path "$stage\$d" -Force | Out-Null
        Copy-Item -Path "$dictPath\*" -Destination "$stage\$d\" -Recurse -Force -Exclude "backup"
    }
}

# 3. Zip with siblings at root
Compress-Archive -Path "$stage\*" -DestinationPath $out -Force

Write-Host "--------------------------------------------------"
Write-Host "Successfully built: $out"
Write-Host "Structure inside ZIP:"
# Show first 12 relevant files
$zipFiles = Get-ChildItem -Path "$stage" -Recurse | Where-Object { $_.Name -like "Yapper*" } | Select-Object -First 12 FullName
foreach ($file in $zipFiles) {
    Write-Host $file.FullName.Replace("$stage\", "")
}
Write-Host "..."
