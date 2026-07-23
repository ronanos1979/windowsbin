<#
Finds and deletes iPhone thumbnail cache files -- small JPEGs that iOS stores
inside folders whose names end with a media-file extension (e.g. a folder called
"780EAE25.HEIC" contains "5005.JPG"). This structure appears in iPhone backups
under PhotoData\Thumbnails\V2\PhotoData\CPLAssets\.

A file is considered a thumbnail when its immediate parent directory name ends
with one of: .heic .heif .jpg .jpeg .png .mov .mp4 .m4v .avi .mkv .3gp .wmv

Usage:
  powershell c:\tools\bin\delete_iphone_thumbnails.ps1 -Root F:\SortOutAllTheseFiles
  powershell c:\tools\bin\delete_iphone_thumbnails.ps1 -Root F:\SortOutAllTheseFiles -WhatIf
#>

param(
    [string]$Root,
    [switch]$WhatIf,
    [switch]$Help
)

function Show-Help {
    Write-Host "Usage:"
    Write-Host "  .\delete_iphone_thumbnails.ps1 -Root PATH [-WhatIf] [-Help]"
    Write-Host ""
    Write-Host "What it does:"
    Write-Host "  Recursively scans PATH for iPhone thumbnail cache files. A file is"
    Write-Host "  identified as a thumbnail when its immediate parent folder name ends with"
    Write-Host "  a media extension (.heic, .jpg, .mov, .mp4, etc.) -- the iOS pattern is"
    Write-Host "  UUID.HEIC\5005.JPG inside PhotoData\Thumbnails\V2\...\"
    Write-Host "  Matched files are deleted. Use -WhatIf to preview without deleting."
    Write-Host ""
    Write-Host "Parameters:"
    Write-Host "  -Root PATH   Root folder to scan recursively. Required."
    Write-Host "  -WhatIf      Preview what would be deleted without deleting anything."
    Write-Host "  -Help        Show this help and exit."
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  # Preview"
    Write-Host "  powershell c:\tools\bin\delete_iphone_thumbnails.ps1 -Root F:\SortOutAllTheseFiles -WhatIf"
    Write-Host ""
    Write-Host "  # Delete"
    Write-Host "  powershell c:\tools\bin\delete_iphone_thumbnails.ps1 -Root F:\SortOutAllTheseFiles"
}

if ($Help) {
    Show-Help
    exit 0
}

if (-not $Root) {
    Write-Host "ERROR: -Root is required."
    Write-Host "Run with -Help for usage information."
    exit 1
}

if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
    Write-Host "ERROR: -Root does not exist: $Root"
    exit 1
}

$mediaExts = @('.heic','.heif','.jpg','.jpeg','.png','.gif','.tif','.tiff',
               '.mov','.mp4','.m4v','.avi','.mkv','.3gp','.3g2','.wmv','.mpg','.mpeg')

$longRoot = if ($Root -match '^\\\\') { $Root } else { '\\?\' + $Root }

Write-Host "Scanning: $Root"
if ($WhatIf) { Write-Host "(WhatIf - nothing will be deleted)" }
Write-Host ""

$found   = 0
$deleted = 0
$failed  = 0

Get-ChildItem -LiteralPath $longRoot -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
    $parentName = [System.IO.Path]::GetFileName($_.DirectoryName)
    $parentExt  = [System.IO.Path]::GetExtension($parentName).ToLower()
    if ($parentExt -notin $mediaExts) { return }

    $found++
    $longPath = if ($_.FullName -match '^\\\\') { $_.FullName } else { '\\?\' + $_.FullName }

    if ($WhatIf) {
        Write-Host "  WOULD DELETE: $($_.FullName)"
        return
    }

    try {
        Remove-Item -LiteralPath $longPath -Force -ErrorAction Stop
        Write-Host "  DELETED: $($_.FullName)"
        $deleted++
    } catch {
        Write-Host "  FAILED : $($_.FullName)"
        Write-Host "           $_"
        $failed++
    }
}

Write-Host ""
Write-Host "Done."
if ($WhatIf) {
    Write-Host "  Would delete: $found"
} else {
    Write-Host "  Found:        $found"
    Write-Host "  Deleted:      $deleted"
    Write-Host "  Failed:       $failed"
}
