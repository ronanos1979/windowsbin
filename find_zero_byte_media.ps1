<#
.SYNOPSIS
Finds zero-byte media files under a folder.

.DESCRIPTION
Recursively scans the selected root folder for known photo, video, and audio
extensions whose file size is 0 bytes. The script is read-only and writes both
text and CSV reports in the current directory.

.PARAMETER Root
Optional. Folder to scan recursively. Defaults to the current folder.

.EXAMPLE
.\find_zero_byte_media.ps1

.EXAMPLE
.\find_zero_byte_media.ps1 -Root D:\Media
#>

param(
    [string]$Root = '.'
)

$mediaExts = @(
    '.jpg', '.jpeg', '.jpe', '.png', '.gif', '.bmp',
    '.tif', '.tiff', '.webp', '.heic', '.heif',
    '.raw', '.dng', '.cr2', '.nef', '.arw', '.orf', '.rw2',
    '.mov', '.mp4', '.m4v', '.avi', '.mkv', '.wmv',
    '.mpg', '.mpeg', '.3gp', '.mts', '.m2ts',
    '.mp3', '.m4a', '.aac', '.wav', '.flac', '.aiff', '.aif'
)

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outFile   = "zero_byte_media_$timestamp.txt"
$csvFile   = "zero_byte_media_$timestamp.csv"

Write-Host "Scanning: $Root"
Write-Host "Output text: $outFile"
Write-Host "Output CSV:  $csvFile"
Write-Host ""

$zeroFiles = @(
    Get-ChildItem -Path $Root -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Length -eq 0 -and $mediaExts -contains $_.Extension.ToLower() } |
    Sort-Object FullName
)

$count = $zeroFiles.Count

$zeroFiles | ForEach-Object { $_.FullName } | Set-Content -Path $outFile -Encoding UTF8

'path' | Set-Content -Path $csvFile -Encoding UTF8
$zeroFiles | ForEach-Object { '"' + $_.FullName.Replace('"', '""') + '"' } |
    Add-Content -Path $csvFile -Encoding UTF8

Write-Host ""
Write-Host "Found $count zero-byte media files."
Write-Host ""

if ($count -gt 0) {
    Write-Host "First 50:"
    $zeroFiles | Select-Object -First 50 | ForEach-Object { Write-Host $_.FullName }
    Write-Host ""
    Write-Host "Full list saved to:"
    Write-Host "  $outFile"
    Write-Host "  $csvFile"
} else {
    Write-Host "No zero-byte media files found."
}
