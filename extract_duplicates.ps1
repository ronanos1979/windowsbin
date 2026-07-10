<#
.SYNOPSIS
Moves _identical and _duplicate_diff_size files to a parallel folder tree.

.DESCRIPTION
Searches Source recursively for files whose names contain _identical or
_duplicate_diff_size (as produced by organize_photos.ps1), then moves them
to Dest preserving the relative directory structure. Files that already exist
at the destination are skipped with a warning.

.PARAMETER Source
Required. Root directory to scan.

.PARAMETER Dest
Required. Destination root. Created if it does not exist.

.PARAMETER Mode
Required. Allowed values: dry-run, move.

.PARAMETER Help
Optional switch. Shows usage and exits.

.EXAMPLE
.\extract_duplicates.ps1 -Mode dry-run -Source D:\Sorted -Dest D:\Duplicates

.EXAMPLE
.\extract_duplicates.ps1 -Mode move -Source D:\Sorted -Dest D:\Duplicates
#>

param(
    [string]$Source,
    [string]$Dest,
    [string]$Mode,
    [switch]$Help
)

$modeValues = @('dry-run', 'move')
$namePattern = '_identical|_duplicate_diff_size'

function Show-Help {
    Write-Host "Usage:"
    Write-Host "  .\extract_duplicates.ps1 -Mode <dry-run|move> -Source <path> -Dest <path>"
    Write-Host ""
    Write-Host "Parameters:"
    Write-Host "  -Mode    Required. dry-run previews; move performs the move."
    Write-Host "  -Source  Required. Root directory produced by organize_photos.ps1."
    Write-Host "  -Dest    Required. Destination root for extracted duplicates."
    Write-Host "  -Help    Optional switch. Shows this help and exits."
}

if ($Help) { Show-Help; exit 0 }

$missing = @()
if (-not $Source) { $missing += '-Source' }
if (-not $Dest)   { $missing += '-Dest' }
if (-not $Mode)   { $missing += '-Mode' }

if ($missing.Count -gt 0) {
    Write-Error "Missing required parameter(s): $($missing -join ', ')"
    Write-Host ""
    Show-Help
    exit 1
}

if ($modeValues -notcontains $Mode) {
    Write-Error "Invalid -Mode '$Mode'. Allowed: $($modeValues -join ', ')"
    exit 1
}

if (-not (Test-Path -Path $Source -PathType Container)) {
    Write-Error "Source does not exist: $Source"
    exit 1
}

$sourceRoot = (Resolve-Path $Source).Path.TrimEnd('\')

$files = @(Get-ChildItem -Path $sourceRoot -Recurse -File |
    Where-Object { $_.Name -match $namePattern })

$total   = $files.Count
$moved   = 0
$skipped = 0

Write-Host "Mode:    $Mode"
Write-Host "Source:  $sourceRoot"
Write-Host "Dest:    $Dest"
Write-Host "Found:   $total file(s) matching _identical or _duplicate_diff_size"
Write-Host ""

foreach ($file in $files) {
    $relative = $file.FullName.Substring($sourceRoot.Length).TrimStart('\')
    $destPath = [System.IO.Path]::Combine($Dest, $relative)
    $destDir  = [System.IO.Path]::GetDirectoryName($destPath)

    if ($Mode -eq 'dry-run') {
        Write-Host "[DRY RUN] $($file.FullName)"
        Write-Host "       -> $destPath"
        $moved++
        continue
    }

    if (Test-Path -LiteralPath $destPath) {
        Write-Warning "SKIP (already exists at dest): $destPath"
        $skipped++
        continue
    }

    $null = New-Item -ItemType Directory -Path $destDir -Force
    Move-Item -LiteralPath $file.FullName -Destination $destPath
    Write-Host "[MOVED] $($file.FullName)"
    Write-Host "     -> $destPath"
    $moved++
}

Write-Host ""
if ($Mode -eq 'dry-run') {
    Write-Host "Dry run complete. $moved file(s) would be moved."
} else {
    Write-Host "Done. Moved: $moved  Skipped: $skipped"
}
