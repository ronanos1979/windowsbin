<#
.SYNOPSIS
Finds duplicate files in the current folder.

.DESCRIPTION
Scans the current directory only, excluding this script, and groups duplicate
files by matching file size and MD5 hash. Writes a timestamped text report in
the current folder.

.PARAMETER None
This script does not accept command-line parameters.

.EXAMPLE
.\find_duplicates_current_folder.ps1
#>

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outFile   = ".\duplicates_$timestamp.txt"

Write-Host "Scanning current folder only: $(Get-Location)"
Write-Host "Output file: $outFile"
Write-Host ""

$scriptName = Split-Path $PSCommandPath -Leaf
$files      = @(Get-ChildItem -Path . -File | Where-Object { $_.Name -ne $scriptName })
$total      = $files.Count
$records    = [System.Collections.Generic.List[PSObject]]::new()

for ($i = 0; $i -lt $total; $i++) {
    $file = $files[$i]
    Write-Progress -Activity "Computing hashes" `
        -Status "$($i+1)/$total : $($file.Name)" `
        -PercentComplete ([int](($i / [Math]::Max($total,1)) * 100))
    $md5 = (Get-FileHash -LiteralPath $file.FullName -Algorithm MD5).Hash
    $records.Add([PSCustomObject]@{
        Size = $file.Length
        MD5  = $md5
        Name = $file.Name
    })
}
Write-Progress -Activity "Computing hashes" -Completed

$groups = $records |
    Group-Object -Property @{E={$_.Size}}, @{E={$_.MD5}} |
    Where-Object { $_.Count -gt 1 }

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add("Duplicate report")
$lines.Add("Folder: $(Get-Location)")
$lines.Add("Generated: $(Get-Date)")
$lines.Add("")

if ($groups.Count -eq 0) {
    $lines.Add("No duplicates found.")
} else {
    $gNum      = 0
    $totalDups = 0
    foreach ($g in $groups) {
        $gNum++
        $totalDups += $g.Count
        $sample = $g.Group[0]
        $lines.Add("Duplicate group ${gNum}:")
        $lines.Add("  Size: $($sample.Size) bytes")
        $lines.Add("  MD5:  $($sample.MD5)")
        foreach ($item in $g.Group) { $lines.Add("  $($item.Name)") }
        $lines.Add("")
    }
    $lines.Add("Summary:")
    $lines.Add("  Duplicate groups: $gNum")
    $lines.Add("  Files in duplicate groups: $totalDups")
}

$lines | Tee-Object -FilePath $outFile

Write-Host ""
Write-Host "Done."
Write-Host "Report saved to: $outFile"
