<#
.SYNOPSIS
Flattens files from the current folder tree into a single output folder.

.DESCRIPTION
Recursively moves files from the current directory tree into .\output, excluding
this script and anything already under .\output. Duplicate filenames are renamed
with a _duplicate_N suffix.

.PARAMETER None
This script does not accept command-line parameters.

.EXAMPLE
.\flatten_to_output.ps1
#>

param([switch]$Help)

if ($Help) {
    Get-Help $PSCommandPath -Full
    exit 0
}

$outputDir  = '.\output'
$scriptName = Split-Path $PSCommandPath -Leaf
$null = New-Item -ItemType Directory -Path $outputDir -Force

$outputFull = (Resolve-Path $outputDir).Path

$files = @(Get-ChildItem -Path . -Recurse -File |
    Where-Object { $_.Name -ne $scriptName -and $_.FullName -notlike "$outputFull\*" })

$total = $files.Count
Write-Host "Found $total files to flatten."
Write-Host ""

for ($i = 0; $i -lt $total; $i++) {
    $file     = $files[$i]
    $filename = $file.Name
    $target   = Join-Path $outputDir $filename
    Write-Progress -Activity "Flattening files" `
        -Status "$($i+1)/$total : $filename" `
        -PercentComplete ([int](($i / [Math]::Max($total,1)) * 100))

    if (Test-Path -LiteralPath $target) {
        $stem    = [System.IO.Path]::GetFileNameWithoutExtension($filename)
        $ext     = [System.IO.Path]::GetExtension($filename)
        $counter = 1
        do {
            $target = Join-Path $outputDir "${stem}_duplicate_${counter}${ext}"
            $counter++
        } while (Test-Path -LiteralPath $target)
    }

    Write-Host "Moving: $($file.FullName) -> $target"
    Move-Item -LiteralPath $file.FullName -Destination $target
}

Write-Progress -Activity "Flattening files" -Completed

Write-Host ""
Write-Host "Done. Files moved to: $outputDir"
