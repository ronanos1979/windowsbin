<#
Deletes all macOS junk files (._filename sidecars) from a folder tree.

Usage:
  powershell c:\tools\bin\delete_mac_junk.ps1 -Root F:\
#>

param(
    [string]$Root,
    [switch]$Help
)

if ($Help) {
    Write-Host ""
    Write-Host "delete_mac_junk.ps1"
    Write-Host "-------------------"
    Write-Host "Deletes all macOS sidecar files (files starting with ._) from a folder tree."
    Write-Host "These are created by macOS when copying files to non-Mac drives and serve no"
    Write-Host "purpose on Windows."
    Write-Host ""
    Write-Host "USAGE"
    Write-Host "  powershell c:\tools\bin\delete_mac_junk.ps1 -Root <path>"
    Write-Host ""
    Write-Host "PARAMETERS"
    Write-Host "  -Root <path>   Folder to search. Required."
    Write-Host "  -Help          Show this help message."
    Write-Host ""
    Write-Host "EXAMPLES"
    Write-Host "  powershell c:\tools\bin\delete_mac_junk.ps1 -Root F:\"
    Write-Host "  powershell c:\tools\bin\delete_mac_junk.ps1 -Root F:\Pictures"
    Write-Host ""
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

# \\?\ prefix bypasses the 260-char MAX_PATH limit for deeply nested folders
$longRoot = if ($Root.StartsWith('\\')) { $Root } else { "\\?\$Root" }
$files = Get-ChildItem -LiteralPath $longRoot -Recurse -File -Force -ErrorAction SilentlyContinue |
         Where-Object { $_.Name -like '._*' }

if (-not $files) {
    Write-Host "No ._* files found under: $Root"
    exit 0
}

Write-Host "Found $($files.Count) file(s) to delete..."
Write-Host ""

$deleted = 0
$failed  = 0

foreach ($f in $files) {
    try {
        $longPath = if ($f.FullName.StartsWith('\\')) { $f.FullName } else { "\\?\$($f.FullName)" }
        Remove-Item -LiteralPath $longPath -Force -ErrorAction Stop
        Write-Host "  DELETED: $($f.FullName)"
        $deleted++
    } catch {
        Write-Host "  FAILED:  $($f.FullName) - $_"
        $failed++
    }
}

Write-Host ""
Write-Host "Done. Deleted: $deleted  Failed: $failed"
