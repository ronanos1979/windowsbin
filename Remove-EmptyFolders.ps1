<#
.SYNOPSIS
    Removes all folders containing no files recursively under a source folder.

.DESCRIPTION
    Walks the source folder tree and deletes any directory (and its subdirectories)
    that contains zero files at any depth. Folders containing at least one file
    anywhere beneath them are left intact.

.PARAMETER Source
    The root folder to scan. Must exist.

.PARAMETER WhatIf
    Show what would be deleted without actually deleting anything.

.PARAMETER Help
    Display this help message.

.EXAMPLE
    .\Remove-EmptyFolders.ps1 -Source "D:\Duplicates_To_Review"

.EXAMPLE
    .\Remove-EmptyFolders.ps1 -Source "D:\Duplicates_To_Review" -WhatIf

.EXAMPLE
    .\Remove-EmptyFolders.ps1 -Help
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Position = 0)]
    [string]$Source,

    [switch]$Help
)

if ($Help -or (-not $Source)) {
    Get-Help $MyInvocation.MyCommand.Path -Detailed
    exit 0
}

if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
    Write-Error "Source folder not found: $Source"
    exit 1
}

$Source = (Resolve-Path -LiteralPath $Source).Path

function Get-HasFiles {
    param([string]$Path)
    # Returns $true if any file exists anywhere under $Path
    $found = Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue |
             Select-Object -First 1
    return ($null -ne $found)
}

# Collect all subdirectories, sorted deepest-first so children are removed before parents
$dirs = Get-ChildItem -LiteralPath $Source -Recurse -Directory -ErrorAction SilentlyContinue |
        Sort-Object { $_.FullName.Length } -Descending

$removed = 0
$skipped = 0

foreach ($dir in $dirs) {
    # Re-check existence — a parent may have been removed already
    if (-not (Test-Path -LiteralPath $dir.FullName)) {
        continue
    }

    if (-not (Get-HasFiles -Path $dir.FullName)) {
        if ($PSCmdlet.ShouldProcess($dir.FullName, 'Remove empty folder')) {
            try {
                Remove-Item -LiteralPath $dir.FullName -Recurse -Force -ErrorAction Stop
                Write-Host "Removed: $($dir.FullName)"
                $removed++
            } catch {
                Write-Warning "Failed to remove '$($dir.FullName)': $_"
            }
        } else {
            Write-Host "WhatIf: Would remove: $($dir.FullName)"
            $removed++
        }
    } else {
        $skipped++
    }
}

Write-Host "`nDone. Removed: $removed folder(s), skipped (contain files): $skipped folder(s)."
