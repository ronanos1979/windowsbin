<#
Finds every file with "identical" in the filename under -Root and moves it
to -Dest, preserving the original folder structure.

Usage:
  powershell c:\tools\bin\move_identical_files.ps1 -Root F:\ -Dest F:\moved_identical
#>

param(
    [Parameter(Mandatory)][string]$Root,
    [Parameter(Mandatory)][string]$Dest,
    [switch]$Help
)

if ($Help) {
    Write-Host ""
    Write-Host "move_identical_files.ps1"
    Write-Host "------------------------"
    Write-Host "Moves every file containing 'identical' in its name to a destination"
    Write-Host "folder, preserving the original folder structure."
    Write-Host ""
    Write-Host "USAGE"
    Write-Host "  powershell c:\tools\bin\move_identical_files.ps1 -Root <path> -Dest <path>"
    Write-Host ""
    Write-Host "PARAMETERS"
    Write-Host "  -Root <path>   Folder to search. Required."
    Write-Host "  -Dest <path>   Folder to move files into. Created if it does not exist. Required."
    Write-Host "  -Help          Show this help message."
    Write-Host ""
    Write-Host "EXAMPLES"
    Write-Host "  powershell c:\tools\bin\move_identical_files.ps1 -Root F:\ -Dest F:\moved_identical"
    Write-Host "  powershell c:\tools\bin\move_identical_files.ps1 -Root F:\Photos -Dest D:\quarantine"
    Write-Host ""
    exit 0
}

if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
    Write-Host "ERROR: -Root does not exist: $Root"
    exit 1
}

$Root = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\')

$files = Get-ChildItem -LiteralPath $Root -Recurse -File -Force -ErrorAction SilentlyContinue |
         Where-Object { $_.Name -like '*identical*' }

if (-not $files) {
    Write-Host "No files with 'identical' in the name found under: $Root"
    exit 0
}

Write-Host "Found $($files.Count) file(s). Moving to: $Dest"
Write-Host ""

$moved  = 0
$failed = 0

foreach ($f in $files) {
    # Reproduce the relative path under $Dest
    $relative  = $f.FullName.Substring($Root.Length).TrimStart('\')
    $destPath  = Join-Path $Dest $relative
    $destDir   = Split-Path $destPath -Parent

    if (-not (Test-Path -LiteralPath $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    try {
        Move-Item -LiteralPath $f.FullName -Destination $destPath -Force -ErrorAction Stop
        Write-Host "  MOVED: $($f.FullName)"
        Write-Host "      -> $destPath"
        $moved++
    } catch {
        Write-Host "  FAILED: $($f.FullName) - $_"
        $failed++
    }
}

Write-Host ""
Write-Host "Done. Moved: $moved  Failed: $failed"
