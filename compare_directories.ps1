<#
.SYNOPSIS
Compares matching directories on two drives or folder roots.

.DESCRIPTION
Compares files on a directory-by-directory basis. By default, you provide
two root paths and one directory name, and the script compares only that
directory under both roots.

Use -CompareTopLevel to compare each first-level directory under LeftRoot
against a directory with the same name under RightRoot. Each top-level
directory is reported separately so the output tells you which folder differs.

The script compares relative file paths and file sizes by default. Use
-CheckHash when you need byte-for-byte content verification. Hash checking is
slower but catches files with the same name and size but different contents.

.PARAMETER LeftRoot
Required. First drive or folder root, such as E:\ or E:\Photos.

.PARAMETER RightRoot
Required. Second drive or folder root, such as F:\ or F:\Photos.

.PARAMETER DirectoryName
Optional unless -CompareTopLevel is used. Name of the directory to compare
under both roots, such as "2024 Photos". This compares:
LeftRoot\DirectoryName against RightRoot\DirectoryName.

.PARAMETER CompareTopLevel
Optional switch. Compares every first-level directory under LeftRoot as a
separate directory comparison against the same directory name under RightRoot.
Also reports first-level directories that exist only on RightRoot.

.PARAMETER CheckHash
Optional switch. Computes SHA256 hashes for files that have matching relative
paths and sizes. This is slower, especially on external hard drives.

.PARAMETER ReportPath
Optional. CSV file path for detailed differences. If omitted, a timestamped
report is written to the current directory.

.PARAMETER Help
Optional switch. Shows usage and exits.

.EXAMPLE
.\compare_directories.ps1 -LeftRoot E:\ -RightRoot F:\ -DirectoryName "Photos"

Compares E:\Photos against F:\Photos.

.EXAMPLE
.\compare_directories.ps1 -LeftRoot E:\ -RightRoot F:\ -DirectoryName "Photos" -CheckHash

Compares E:\Photos against F:\Photos and hashes same-size files to verify
byte-for-byte matches.

.EXAMPLE
.\compare_directories.ps1 -LeftRoot E:\ -RightRoot F:\ -CompareTopLevel

Compares each first-level directory under E:\ separately against the same
directory name under F:\.

.EXAMPLE
.\compare_directories.ps1 -LeftRoot E:\ -RightRoot F:\ -CompareTopLevel -ReportPath C:\Temp\drive_compare.csv

Writes detailed differences to C:\Temp\drive_compare.csv.
#>

param(
    [string]$LeftRoot,
    [string]$RightRoot,
    [string]$DirectoryName,
    [switch]$CompareTopLevel,
    [switch]$CheckHash,
    [string]$ReportPath,
    [switch]$Help
)

function Show-Help {
    Write-Host "Usage:"
    Write-Host "  .\compare_directories.ps1 -LeftRoot <path> -RightRoot <path> -DirectoryName <folder name> [-CheckHash] [-ReportPath <csv>]"
    Write-Host "  .\compare_directories.ps1 -LeftRoot <path> -RightRoot <path> -CompareTopLevel [-CheckHash] [-ReportPath <csv>]"
    Write-Host ""
    Write-Host "What it does:"
    Write-Host "  - Compares directories separately, not the whole drive as one combined scan."
    Write-Host "  - Default mode compares one named directory under both roots."
    Write-Host "  - -CompareTopLevel compares each first-level directory under LeftRoot separately."
    Write-Host "  - Default checks relative paths and file sizes."
    Write-Host "  - -CheckHash adds SHA256 content checks for files with matching path and size."
    Write-Host ""
    Write-Host "Parameters:"
    Write-Host "  -LeftRoot         Required. First drive/folder root. Example: E:\"
    Write-Host "  -RightRoot        Required. Second drive/folder root. Example: F:\"
    Write-Host "  -DirectoryName    Folder name to compare under both roots. Example: Photos"
    Write-Host "  -CompareTopLevel  Compare every first-level folder separately."
    Write-Host "  -CheckHash        Slower SHA256 verification of same-size files."
    Write-Host "  -ReportPath       Optional CSV output path. Defaults to current directory."
    Write-Host "  -Help             Shows this help and exits."
    Write-Host ""
    Write-Host "Examples:"
    Write-Host '  .\compare_directories.ps1 -LeftRoot E:\ -RightRoot F:\ -DirectoryName "Photos"'
    Write-Host '  .\compare_directories.ps1 -LeftRoot E:\ -RightRoot F:\ -DirectoryName "Photos" -CheckHash'
    Write-Host '  .\compare_directories.ps1 -LeftRoot E:\ -RightRoot F:\ -CompareTopLevel'
}

function Resolve-DirectoryPath {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        Write-Error "$Label does not exist or is not a directory: $Path"
        exit 1
    }

    return (Resolve-Path -LiteralPath $Path).Path.TrimEnd('\')
}

function Get-RelativePath {
    param(
        [Parameter(Mandatory=$true)][string]$Root,
        [Parameter(Mandatory=$true)][string]$FullName
    )

    return $FullName.Substring($Root.Length).TrimStart('\')
}

function Get-FileMap {
    param([Parameter(Mandatory=$true)][string]$Root)

    $map = @{}
    Get-ChildItem -LiteralPath $Root -Recurse -File -Force -ErrorAction SilentlyContinue |
        ForEach-Object {
            $relativePath = Get-RelativePath -Root $Root -FullName $_.FullName
            $key = $relativePath.ToLowerInvariant()
            $map[$key] = [pscustomobject]@{
                RelativePath = $relativePath
                FullName = $_.FullName
                Length = $_.Length
                LastWriteTime = $_.LastWriteTime
            }
        }

    return $map
}

function New-Difference {
    param(
        [string]$Directory,
        [string]$DifferenceType,
        [string]$RelativePath,
        [nullable[long]]$LeftSize,
        [nullable[long]]$RightSize,
        [string]$LeftPath,
        [string]$RightPath,
        [string]$Notes
    )

    return [pscustomobject]@{
        Directory = $Directory
        DifferenceType = $DifferenceType
        RelativePath = $RelativePath
        LeftSize = $LeftSize
        RightSize = $RightSize
        LeftPath = $LeftPath
        RightPath = $RightPath
        Notes = $Notes
    }
}

function Compare-OneDirectory {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$LeftPath,
        [Parameter(Mandatory=$true)][string]$RightPath
    )

    $differences = @()

    if (-not (Test-Path -LiteralPath $LeftPath -PathType Container)) {
        $differences += New-Difference -Directory $Name -DifferenceType 'DirectoryMissingOnLeft' -RelativePath '' -LeftSize $null -RightSize $null -LeftPath $LeftPath -RightPath $RightPath -Notes 'Directory exists only on right side.'
        return $differences
    }

    if (-not (Test-Path -LiteralPath $RightPath -PathType Container)) {
        $differences += New-Difference -Directory $Name -DifferenceType 'DirectoryMissingOnRight' -RelativePath '' -LeftSize $null -RightSize $null -LeftPath $LeftPath -RightPath $RightPath -Notes 'Directory exists only on left side.'
        return $differences
    }

    Write-Host "Scanning: $Name"
    $leftMap = Get-FileMap -Root $LeftPath
    $rightMap = Get-FileMap -Root $RightPath

    foreach ($key in $leftMap.Keys) {
        $leftFile = $leftMap[$key]

        if (-not $rightMap.ContainsKey($key)) {
            $differences += New-Difference -Directory $Name -DifferenceType 'FileMissingOnRight' -RelativePath $leftFile.RelativePath -LeftSize $leftFile.Length -RightSize $null -LeftPath $leftFile.FullName -RightPath '' -Notes 'File exists only on left side.'
            continue
        }

        $rightFile = $rightMap[$key]
        if ($leftFile.Length -ne $rightFile.Length) {
            $differences += New-Difference -Directory $Name -DifferenceType 'SizeDifferent' -RelativePath $leftFile.RelativePath -LeftSize $leftFile.Length -RightSize $rightFile.Length -LeftPath $leftFile.FullName -RightPath $rightFile.FullName -Notes 'Relative path matches, but file sizes differ.'
            continue
        }

        if ($CheckHash) {
            $leftHash = (Get-FileHash -LiteralPath $leftFile.FullName -Algorithm SHA256).Hash
            $rightHash = (Get-FileHash -LiteralPath $rightFile.FullName -Algorithm SHA256).Hash

            if ($leftHash -ne $rightHash) {
                $differences += New-Difference -Directory $Name -DifferenceType 'HashDifferent' -RelativePath $leftFile.RelativePath -LeftSize $leftFile.Length -RightSize $rightFile.Length -LeftPath $leftFile.FullName -RightPath $rightFile.FullName -Notes 'Same relative path and size, but SHA256 hashes differ.'
            }
        }
    }

    foreach ($key in $rightMap.Keys) {
        if (-not $leftMap.ContainsKey($key)) {
            $rightFile = $rightMap[$key]
            $differences += New-Difference -Directory $Name -DifferenceType 'FileMissingOnLeft' -RelativePath $rightFile.RelativePath -LeftSize $null -RightSize $rightFile.Length -LeftPath '' -RightPath $rightFile.FullName -Notes 'File exists only on right side.'
        }
    }

    return $differences
}

if ($Help) {
    Show-Help
    exit 0
}

$missing = @()
if (-not $LeftRoot) { $missing += '-LeftRoot' }
if (-not $RightRoot) { $missing += '-RightRoot' }

if ($missing.Count -gt 0) {
    Write-Error "Missing required parameter(s): $($missing -join ', ')"
    Write-Host ""
    Show-Help
    exit 1
}

if ($CompareTopLevel -and $DirectoryName) {
    Write-Error "Use either -DirectoryName or -CompareTopLevel, not both."
    exit 1
}

if (-not $CompareTopLevel -and -not $DirectoryName) {
    Write-Error "Provide -DirectoryName for one folder comparison, or use -CompareTopLevel."
    Write-Host ""
    Show-Help
    exit 1
}

$leftRootPath = Resolve-DirectoryPath -Path $LeftRoot -Label '-LeftRoot'
$rightRootPath = Resolve-DirectoryPath -Path $RightRoot -Label '-RightRoot'

if (-not $ReportPath) {
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $ReportPath = Join-Path (Get-Location) "directory_compare_$stamp.csv"
}

$comparisons = @()

if ($CompareTopLevel) {
    $leftDirs = @(Get-ChildItem -LiteralPath $leftRootPath -Directory -Force)
    $rightDirs = @(Get-ChildItem -LiteralPath $rightRootPath -Directory -Force)
    $rightDirNames = @{}

    foreach ($dir in $rightDirs) {
        $rightDirNames[$dir.Name.ToLowerInvariant()] = $dir
    }

    foreach ($leftDir in $leftDirs) {
        $comparisons += [pscustomobject]@{
            Name = $leftDir.Name
            LeftPath = $leftDir.FullName
            RightPath = Join-Path $rightRootPath $leftDir.Name
        }
        $rightDirNames.Remove($leftDir.Name.ToLowerInvariant())
    }

    foreach ($rightDir in $rightDirNames.Values) {
        $comparisons += [pscustomobject]@{
            Name = $rightDir.Name
            LeftPath = Join-Path $leftRootPath $rightDir.Name
            RightPath = $rightDir.FullName
        }
    }
} else {
    $comparisons += [pscustomobject]@{
        Name = $DirectoryName
        LeftPath = Join-Path $leftRootPath $DirectoryName
        RightPath = Join-Path $rightRootPath $DirectoryName
    }
}

$allDifferences = @()
$summary = @()

foreach ($comparison in $comparisons | Sort-Object Name) {
    $diffs = @(Compare-OneDirectory -Name $comparison.Name -LeftPath $comparison.LeftPath -RightPath $comparison.RightPath)
    $allDifferences += $diffs

    $summary += [pscustomobject]@{
        Directory = $comparison.Name
        Differences = $diffs.Count
        Status = if ($diffs.Count -eq 0) { 'Match' } else { 'Different' }
        LeftPath = $comparison.LeftPath
        RightPath = $comparison.RightPath
    }
}

Write-Host ""
Write-Host "Summary:"
$summary | Format-Table -AutoSize

if ($allDifferences.Count -gt 0) {
    $reportParent = Split-Path -Parent $ReportPath
    if ($reportParent -and -not (Test-Path -LiteralPath $reportParent -PathType Container)) {
        New-Item -ItemType Directory -Path $reportParent -Force | Out-Null
    }

    $allDifferences | Export-Csv -Path $ReportPath -NoTypeInformation
    Write-Host ""
    Write-Host "Differences found: $($allDifferences.Count)"
    Write-Host "Detailed CSV report: $ReportPath"
    exit 2
}

Write-Host ""
Write-Host "No differences found."
Write-Host "No CSV report was written because there were no differences."
exit 0
