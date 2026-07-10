<#
.SYNOPSIS
Copies files listed as moved in a merge_unique_files.ps1 log to a second drive.

.DESCRIPTION
Reads a CSV log created by merge_unique_files.ps1, selects rows where action is
"moved", and copies each logged destination_path into a second destination root
while preserving the relative path below the original destination root.

This is intended for creating duplicate copies of the files that were moved by
the merge script.

.PARAMETER LogFile
Path to the merge_unique_log_*.csv file created by merge_unique_files.ps1.

.PARAMETER OriginalDest
The destination root used when merge_unique_files.ps1 was run.
Example: G:\20220422_FINAL_NEW_SETUP\Pictures

.PARAMETER BackupDest
The second destination root where duplicate copies should be created.
Example: H:\20220422_FINAL_NEW_SETUP\Pictures

.PARAMETER Mode
dry-run previews the work. copy performs the copy.

.EXAMPLE
.\copy_merge_moved_to_second_drive.ps1 `
  -Mode dry-run `
  -LogFile G:\20220422_FINAL_NEW_SETUP\Pictures\_merge_logs\merge_unique_log_20260710_120000.csv `
  -OriginalDest G:\20220422_FINAL_NEW_SETUP\Pictures `
  -BackupDest H:\20220422_FINAL_NEW_SETUP\Pictures

.EXAMPLE
.\copy_merge_moved_to_second_drive.ps1 `
  -Mode copy `
  -LogFile G:\20220422_FINAL_NEW_SETUP\Pictures\_merge_logs\merge_unique_log_20260710_120000.csv `
  -OriginalDest G:\20220422_FINAL_NEW_SETUP\Pictures `
  -BackupDest H:\20220422_FINAL_NEW_SETUP\Pictures
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('dry-run','copy')]
    [string]$Mode,

    [Parameter(Mandatory=$true)]
    [string]$LogFile,

    [Parameter(Mandatory=$true)]
    [string]$OriginalDest,

    [Parameter(Mandatory=$true)]
    [string]$BackupDest
)

function Normalize-DirectoryPath {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    return $fullPath.TrimEnd('\', '/')
}

function Add-ReportRow {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ReportFile,

        [Parameter(Mandatory=$true)]
        [string]$SourcePath,

        [string]$BackupPath = '',

        [Parameter(Mandatory=$true)]
        [string]$Action,

        [Parameter(Mandatory=$true)]
        [string]$Reason
    )

    [pscustomobject]@{
        source_path = $SourcePath
        backup_path = $BackupPath
        action = $Action
        reason = $Reason
    } | ConvertTo-Csv -NoTypeInformation | Select-Object -Skip 1 | Add-Content -Path $ReportFile
}

$LogFile = [System.IO.Path]::GetFullPath($LogFile)
$OriginalDest = Normalize-DirectoryPath -Path $OriginalDest
$BackupDest = Normalize-DirectoryPath -Path $BackupDest

if (-not (Test-Path -LiteralPath $LogFile -PathType Leaf)) {
    Write-Error "Log file does not exist: $LogFile"
    exit 1
}

if (-not (Test-Path -LiteralPath $OriginalDest -PathType Container)) {
    Write-Error "Original destination does not exist: $OriginalDest"
    exit 1
}

if ($Mode -eq 'copy') {
    $null = New-Item -ItemType Directory -Path $BackupDest -Force
}

$runTimestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$reportDir = Join-Path $BackupDest '_copy_from_merge_logs'
$reportFile = Join-Path $reportDir "copy_moved_report_$runTimestamp.csv"

if ($Mode -eq 'copy') {
    $null = New-Item -ItemType Directory -Path $reportDir -Force
    Set-Content -Path $reportFile -Value "source_path,backup_path,action,reason"
}

Write-Host "Mode:                 $Mode"
Write-Host "Log file:             $LogFile"
Write-Host "Original destination: $OriginalDest"
Write-Host "Backup destination:   $BackupDest"
if ($Mode -eq 'copy') {
    Write-Host "Report:               $reportFile"
}
Write-Host ""

$rows = @(Import-Csv -LiteralPath $LogFile)
$movedRows = @($rows | Where-Object { $_.action -eq 'moved' -and -not [string]::IsNullOrWhiteSpace($_.destination_path) })

Write-Host "Rows in log:          $($rows.Count)"
Write-Host "Moved rows selected:  $($movedRows.Count)"
Write-Host ""

$copied = 0
$missing = 0
$outsideRoot = 0
$failed = 0
$total = $movedRows.Count

for ($i = 0; $i -lt $total; $i++) {
    $row = $movedRows[$i]
    $sourcePath = [System.IO.Path]::GetFullPath($row.destination_path)

    Write-Progress -Activity "Copying moved files from merge log" `
        -Status "$($i+1)/$total : $([System.IO.Path]::GetFileName($sourcePath))" `
        -PercentComplete ([int](($i / [Math]::Max($total,1)) * 100))

    if ($sourcePath -ne $OriginalDest -and -not $sourcePath.StartsWith($OriginalDest + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        $outsideRoot++
        Write-Host "[SKIP] $sourcePath"
        Write-Host "       Reason: destination_path is not under OriginalDest"
        if ($Mode -eq 'copy') {
            Add-ReportRow -ReportFile $reportFile -SourcePath $sourcePath -Action 'skipped' -Reason 'destination_path is not under OriginalDest'
        }
        continue
    }

    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        $missing++
        Write-Host "[MISSING] $sourcePath"
        if ($Mode -eq 'copy') {
            Add-ReportRow -ReportFile $reportFile -SourcePath $sourcePath -Action 'missing' -Reason 'source file no longer exists'
        }
        continue
    }

    $relativePath = $sourcePath.Substring($OriginalDest.Length).TrimStart('\', '/')
    $backupPath = Join-Path $BackupDest $relativePath
    $backupDir = [System.IO.Path]::GetDirectoryName($backupPath)

    if ($Mode -eq 'dry-run') {
        Write-Host "[DRY RUN] $sourcePath"
        Write-Host "          -> $backupPath"
        continue
    }

    try {
        $null = New-Item -ItemType Directory -Path $backupDir -Force
        Copy-Item -LiteralPath $sourcePath -Destination $backupPath -Force
        $copied++
        Write-Host "[COPIED] $sourcePath -> $backupPath"
        Add-ReportRow -ReportFile $reportFile -SourcePath $sourcePath -BackupPath $backupPath -Action 'copied' -Reason 'copied from merge destination'
    } catch {
        $failed++
        Write-Host "[FAILED] $sourcePath"
        Write-Host "         $($_.Exception.Message)"
        Add-ReportRow -ReportFile $reportFile -SourcePath $sourcePath -BackupPath $backupPath -Action 'failed' -Reason $_.Exception.Message
    }
}

Write-Progress -Activity "Copying moved files from merge log" -Completed

Write-Host ""
Write-Host "Done."
if ($Mode -eq 'copy') {
    Write-Host "Copied:       $copied"
}
Write-Host "Missing:      $missing"
Write-Host "Outside root: $outsideRoot"
Write-Host "Failed:       $failed"
if ($Mode -eq 'copy') {
    Write-Host "Report:       $reportFile"
}
