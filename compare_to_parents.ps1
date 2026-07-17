<#
.SYNOPSIS
Compares files in the current folder with files of the same name in the parent folder.

.DESCRIPTION
Scans the current directory only, excluding this script, and reports files that
are missing from the parent directory or whose SHA-256 hash differs from the
matching parent file.

.PARAMETER None
This script does not accept command-line parameters. Run it from the child
folder you want to compare against its parent.

.EXAMPLE
.\compare_to_parents.ps1
#>

param([switch]$Help)

if ($Help) {
    Get-Help $PSCommandPath -Full
    exit 0
}

$scriptName = Split-Path $PSCommandPath -Leaf
$files      = @(Get-ChildItem -Path . -File | Where-Object { $_.Name -ne $scriptName })
$total      = $files.Count

$differentFiles = [System.Collections.Generic.List[string]]::new()

for ($i = 0; $i -lt $total; $i++) {
    $file = $files[$i]
    Write-Progress -Activity "Comparing files to parent" `
        -Status "$($i+1)/$total : $($file.Name)" `
        -PercentComplete ([int](($i / [Math]::Max($total,1)) * 100))

    $parentFile = Join-Path '..' $file.Name

    if (-not (Test-Path -LiteralPath $parentFile -PathType Leaf)) {
        $differentFiles.Add("$($file.Name) - missing from parent folder")
        continue
    }

    $currentHash = (Get-FileHash -LiteralPath $file.FullName  -Algorithm SHA256).Hash
    $parentHash  = (Get-FileHash -LiteralPath $parentFile -Algorithm SHA256).Hash

    if ($currentHash -ne $parentHash) {
        $differentFiles.Add("$($file.Name) - exists in parent but is different")
    }
}

Write-Progress -Activity "Comparing files to parent" -Completed

Write-Host ""
Write-Host "Comparison complete."
Write-Host ""

if ($differentFiles.Count -eq 0) {
    Write-Host "No differences found. Every file in the current folder exists identically in the parent folder."
} else {
    Write-Host "Files missing or different in parent folder:"
    Write-Host "--------------------------------------------"
    foreach ($item in $differentFiles) {
        Write-Host $item
    }
}
