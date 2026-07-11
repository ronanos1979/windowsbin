<#
.SYNOPSIS
Finds zero-byte media files under a folder.

.DESCRIPTION
Recursively scans the selected root folder for known photo, video, and audio
extensions whose file size is 0 bytes. Writes text and CSV reports.
Optionally moves or deletes the files found.

Usage (no -File needed):
  powershell c:\tools\bin\find_zero_byte_media.ps1 -Root D:\Media -MoveTo D:\Quarantine
  powershell c:\tools\bin\find_zero_byte_media.ps1 -Root D:\Media -Delete
#>

# No param() block: without param(), $args receives all arguments regardless
# of whether the script is called with or without the -File flag.
$Root   = '.'
$MoveTo = ''
$Delete = $false
$Help   = $false

$i = 0
while ($i -lt $args.Count) {
    $key = ($args[$i] -replace '^[-/]+', '').ToLower()
    switch ($key) {
        'root'   { $i++; $Root   = $args[$i] }
        'moveto' { $i++; $MoveTo = $args[$i] }
        'delete' { $Delete = $true }
        { $_ -in 'help','h','?' } { $Help = $true }
    }
    $i++
}

if ($Help -or $args.Count -eq 0) {
    Write-Host ""
    Write-Host "find_zero_byte_media.ps1"
    Write-Host "------------------------"
    Write-Host "Scans a folder tree for media files that are 0 bytes in size."
    Write-Host "Writes a .txt and .csv report of every zero-byte file found."
    Write-Host "Optionally moves or deletes them."
    Write-Host ""
    Write-Host "USAGE"
    Write-Host "  powershell c:\tools\bin\find_zero_byte_media.ps1 -Root <path> [options]"
    Write-Host ""
    Write-Host "PARAMETERS"
    Write-Host "  -Root <path>     Folder to scan. Defaults to current directory."
    Write-Host "  -MoveTo <path>   Move zero-byte files here, preserving folder structure."
    Write-Host "  -Delete          Permanently delete all zero-byte files found."
    Write-Host "  -Help            Show this help message."
    Write-Host ""
    Write-Host "NOTES"
    Write-Host "  -MoveTo and -Delete cannot be used together."
    Write-Host "  Without -MoveTo or -Delete the script reports only - nothing is changed."
    Write-Host "  Supported types: jpg jpeg png gif bmp tif webp heic raw dng cr2 nef arw"
    Write-Host "                   mov mp4 avi mkv wmv mpg 3gp mts mp3 m4a wav flac aiff"
    Write-Host ""
    Write-Host "EXAMPLES"
    Write-Host "  # Report only"
    Write-Host "  powershell c:\tools\bin\find_zero_byte_media.ps1 -Root F:\Photos"
    Write-Host ""
    Write-Host "  # Move zero-byte files to a quarantine folder"
    Write-Host "  powershell c:\tools\bin\find_zero_byte_media.ps1 -Root F:\Photos -MoveTo F:\ZeroByte"
    Write-Host ""
    Write-Host "  # Delete zero-byte files"
    Write-Host "  powershell c:\tools\bin\find_zero_byte_media.ps1 -Root F:\Photos -Delete"
    Write-Host ""
    exit 0
}

if ($Delete -and $MoveTo) {
    Write-Host "ERROR: -Delete and -MoveTo cannot be used together."
    exit 1
}

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
if ($MoveTo) { Write-Host "Move to:  $MoveTo" }
if ($Delete) { Write-Host "Action:   DELETE" }
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

Write-Host "Found $count zero-byte media file(s)."
Write-Host ""

if ($count -eq 0) {
    Write-Host "No zero-byte media files found."
    exit 0
}

Write-Host "First 50:"
$zeroFiles | Select-Object -First 50 | ForEach-Object { Write-Host $_.FullName }
Write-Host ""
Write-Host "Full list saved to:"
Write-Host "  $outFile"
Write-Host "  $csvFile"
Write-Host ""

if ($MoveTo) {
    $absRoot = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\', '/')
    $absDest = [System.IO.Path]::GetFullPath($MoveTo)
    Write-Host "Moving $count file(s) to: $absDest"
    $moved  = 0
    $failed = 0
    foreach ($f in $zeroFiles) {
        $rel      = $f.FullName.Substring($absRoot.Length).TrimStart('\', '/')
        $destPath = Join-Path $absDest $rel
        $destDir  = Split-Path $destPath -Parent
        try {
            if (-not (Test-Path $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }
            Move-Item -LiteralPath $f.FullName -Destination $destPath -Force
            $moved++
        } catch {
            Write-Host "WARN: Could not move $($f.FullName): $_"
            $failed++
        }
    }
    Write-Host "Done. Moved: $moved  Failed: $failed"
}

if ($Delete) {
    Write-Host "Deleting $count file(s)..."
    $deleted = 0
    $failed  = 0
    foreach ($f in $zeroFiles) {
        try {
            Remove-Item -LiteralPath $f.FullName -Force
            $deleted++
        } catch {
            Write-Host "WARN: Could not delete $($f.FullName): $_"
            $failed++
        }
    }
    Write-Host "Done. Deleted: $deleted  Failed: $failed"
}
