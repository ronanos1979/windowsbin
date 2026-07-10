<#
.SYNOPSIS
Lists iCloud files that are actually downloaded (locally present) vs cloud-only placeholders.

.DESCRIPTION
iCloud placeholder files report a non-zero size via Explorer/ls but carry the
RecallOnDataAccess or Offline attribute, meaning the content isn't on disk.
This script filters them out and reports only files whose content is local.

.PARAMETER Path
Directory to scan. Defaults to C:\Users\$env:USERNAME\iCloudPhotos\Photos

.PARAMETER ShowMissing
When present, show cloud-only (not downloaded) files instead of downloaded ones.

.PARAMETER ExportCsv
Optional path to write results as CSV.

.EXAMPLE
.\find_downloaded_icloud.ps1

.EXAMPLE
.\find_downloaded_icloud.ps1 -Path "C:\Users\ronan\iCloudPhotos\Photos" -ShowMissing

.EXAMPLE
.\find_downloaded_icloud.ps1 -ExportCsv C:\temp\downloaded.csv
#>

param(
    [string]$Path = "C:\Users\$env:USERNAME\iCloudPhotos\Photos",
    [switch]$ShowMissing,
    [string]$ExportCsv
)

if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    Write-Error "Directory not found: $Path"
    exit 1
}

# FILE_ATTRIBUTE_OFFLINE (0x1000) — content not on local disk
# FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS (0x400000) — cloud placeholder, fetched on access
# FILE_ATTRIBUTE_RECALL_ON_OPEN (0x40000) — similar, triggers recall on open
$cloudFlags = [System.IO.FileAttributes]::Offline `
            -bor [int]0x400000 `
            -bor [int]0x40000

Write-Host "Scanning: $Path"
Write-Host ""

$files = Get-ChildItem -LiteralPath $Path -File

$downloaded = [System.Collections.Generic.List[object]]::new()
$notDownloaded = [System.Collections.Generic.List[object]]::new()

foreach ($f in $files) {
    $isCloud = ($f.Attributes.value__ -band $cloudFlags) -ne 0
    if ($isCloud) {
        $notDownloaded.Add($f)
    } else {
        $downloaded.Add($f)
    }
}

$target = if ($ShowMissing) { $notDownloaded } else { $downloaded }
$label  = if ($ShowMissing) { "cloud-only (not downloaded)" } else { "downloaded (local)" }

Write-Host "Total files:       $($files.Count)"
Write-Host "Downloaded:        $($downloaded.Count)"
Write-Host "Not downloaded:    $($notDownloaded.Count)"
Write-Host ""
Write-Host "Showing $label files ($($target.Count)):"
Write-Host ""

$results = $target | ForEach-Object {
    [PSCustomObject]@{
        Name      = $_.Name
        SizeMB    = [math]::Round($_.Length / 1MB, 2)
        Extension = $_.Extension.ToLower()
        Modified  = $_.LastWriteTime
        FullPath  = $_.FullName
    }
}

$results | Format-Table -AutoSize

if ($ExportCsv) {
    $results | Export-Csv -Path $ExportCsv -NoTypeInformation
    Write-Host "Exported to: $ExportCsv"
}
