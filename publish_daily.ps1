$ErrorActionPreference = "Stop"

# Define Paths
$BasePath = "C:\Users\Bobby\Desktop\htb"
Set-Location -Path $BasePath

$StagingPath = Join-Path -Path $BasePath -ChildPath "Staging\Rooms"
$LiveRoomsPath = Join-Path -Path $BasePath -ChildPath "Rooms"

# 1. Find the first available writeup in Staging
$FirstMetadata = Get-ChildItem -Path $StagingPath -Recurse -Filter "metadata.json" | Select-Object -First 1

if (-not $FirstMetadata) {
    Write-Host "No more writeups left in Staging queue!"
    exit 0
}

# 2. Extract Metadata
$MetadataObj = Get-Content -Path $FirstMetadata.FullName | ConvertFrom-Json
$Platform = $MetadataObj.Platform
$TargetName = $MetadataObj.TargetName
$Difficulty = $MetadataObj.Difficulty
$Description = $MetadataObj.Description

# 3. Setup destination
$StagingFolder = $FirstMetadata.DirectoryName
$DestinationParent = Join-Path -Path $LiveRoomsPath -ChildPath $Platform
$DestinationFolder = Join-Path -Path $DestinationParent -ChildPath (Split-Path $StagingFolder -Leaf)

# Create Platform dir in Live if it doesn't exist
if (-not (Test-Path $DestinationParent)) {
    New-Item -ItemType Directory -Path $DestinationParent | Out-Null
}

# 4. Move the folder to live
Write-Host "Publishing $TargetName to live Rooms directory..."
Move-Item -Path $StagingFolder -Destination $DestinationFolder -Force

# 5. Clean up metadata.json from live so it doesn't clutter repository (optional)
Remove-Item -Path (Join-Path -Path $DestinationFolder -ChildPath "metadata.json") -ErrorAction SilentlyContinue

# 6. Update README.md
$ReadmePath = Join-Path -Path $BasePath -ChildPath "README.md"
$EncodedTargetName = [uri]::EscapeDataString((Split-Path $StagingFolder -Leaf))
$Row = "| ![$Platform](https://img.shields.io/badge/$Platform-red) | [**$TargetName**](./Rooms/$Platform/$EncodedTargetName/writeup.md) | $Difficulty | $Description |"

Write-Host "Appending to README.md..."
Add-Content -Path $ReadmePath -Value $Row

# 7. Git Add, Commit, Push
Write-Host "Committing and Pushing to GitHub..."
git add Rooms/ README.md
git commit -m "Publish $TargetName Writeup"
git push

Write-Host "Successfully published $TargetName!"
