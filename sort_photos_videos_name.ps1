<#
.SYNOPSIS
Sorts PHOTO- and VIDEO-named files into dated output folders.

.DESCRIPTION
Scans the current folder for names like PHOTO-YYYY-MM-DD-HH-MM-SS.ext and
VIDEO-YYYY-MM-DD-HH-MM-SS.ext, then previews or moves them into
output\Pictures\YEAR\MM-Month\YYYY-MM-DD or output\Videos\YEAR\MM-Month\YYYY-MM-DD.
Writes timestamped CSV logs for moved and skipped files.

.PARAMETER Mode
Required. Allowed values: dry-run or move. dry-run previews changes; move applies them.

.EXAMPLE
.\sort_photos_videos_name.ps1 -Mode dry-run

.EXAMPLE
.\sort_photos_videos_name.ps1 -Mode move
#>

param(
    [switch]$Help,

    [Parameter(Mandatory=$false)]
    [ValidateSet('dry-run','move')]
    [string]$Mode
)

if ($Help) {
    Get-Help $PSCommandPath -Full
    exit 0
}

if (-not $Mode) {
    Write-Error "-Mode is required (dry-run or move). Use -Help for usage information."
    exit 1
}

$outputDir  = '.\output'
$monthNames = @('','January','February','March','April','May','June',
                'July','August','September','October','November','December')
$pattern    = '^(PHOTO|VIDEO)-(\d{4})-(\d{2})-(\d{2})-\d{2}-\d{2}-\d{2}\..+'

function Get-UniqueDestPath([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return $path }
    $dir  = [System.IO.Path]::GetDirectoryName($path)
    $ext  = [System.IO.Path]::GetExtension($path)
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($path)
    $i = 1
    while ($true) {
        $candidate = Join-Path $dir "${stem}_duplicate_${i}${ext}"
        if (-not (Test-Path -LiteralPath $candidate)) { return $candidate }
        $i++
    }
}

$timestamp   = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile     = ".\sort_photos_videos_name_$timestamp.csv"
$skippedFile = ".\sort_photos_videos_name_skipped_$timestamp.csv"

Set-Content -Path $logFile     -Value "source,target,action"
Set-Content -Path $skippedFile -Value "source,reason"

Write-Host "Mode:          $Mode"
Write-Host "Output folder: $outputDir"
Write-Host "Log:           $logFile"
Write-Host "Skipped:       $skippedFile"
Write-Host ""

$scriptName = Split-Path $PSCommandPath -Leaf
$files = @(Get-ChildItem -Path . -File |
    Where-Object { $_.Name -ne $scriptName -and $_.Name -notmatch '^sort_photos_videos_name_.*\.csv$' })

$total = $files.Count
Write-Host "Found $total files in current folder."
Write-Host ""

for ($i = 0; $i -lt $total; $i++) {
    $file     = $files[$i]
    $filename = $file.Name
    Write-Progress -Activity "Sorting files" `
        -Status "$($i+1)/$total : $filename" `
        -PercentComplete ([int](($i / [Math]::Max($total,1)) * 100))

    if ($filename -imatch $pattern) {
        $prefix    = $Matches[1].ToUpper()
        $year      = $Matches[2]
        $month     = $Matches[3]
        $day       = $Matches[4]
        $media     = if ($prefix -eq 'PHOTO') { 'Pictures' } else { 'Videos' }
        $monthName = $monthNames[[int]$month]
        $dateFolder = "${year}-${month}-${day}"
        $targetDir  = Join-Path $outputDir "$media\$year\$month-$monthName\$dateFolder"
        $targetPath = Get-UniqueDestPath (Join-Path $targetDir $filename)

        if ($Mode -eq 'dry-run') {
            Write-Host "[DRY RUN] $filename"
            Write-Host "          -> $targetPath"
            Add-Content -Path $logFile -Value "`"$($file.FullName)`",`"$targetPath`",`"dry-run`""
        } else {
            $null = New-Item -ItemType Directory -Path $targetDir -Force
            Move-Item -LiteralPath $file.FullName -Destination $targetPath
            Write-Host "[MOVED] $filename -> $targetPath"
            Add-Content -Path $logFile -Value "`"$($file.FullName)`",`"$targetPath`",`"moved`""
        }
    } else {
        Write-Host "[SKIP] $filename - does not match PHOTO/VIDEO-YYYY-MM-DD-HH-MM-SS pattern"
        Add-Content -Path $skippedFile `
            -Value "`"$($file.FullName)`",`"Does not match PHOTO-YYYY-MM-DD-HH-MM-SS or VIDEO-YYYY-MM-DD-HH-MM-SS pattern`""
    }
}

Write-Progress -Activity "Sorting files" -Completed

Write-Host ""
Write-Host "Done."
Write-Host "Log:     $logFile"
Write-Host "Skipped: $skippedFile"
