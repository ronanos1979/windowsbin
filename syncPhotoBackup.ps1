#Requires -Version 5.1

<#
.SYNOPSIS
    Mirrors a master drive/folder to a backup drive/folder.

.WARNING
    Mirror mode deletes files from the backup that do not exist on the master.
    PREVIEW mode is enabled by default.

.USAGE
    1. Update the configuration section below.
    2. Run PowerShell as a normal user.
    3. Preview:
         powershell.exe -ExecutionPolicy Bypass -File .\Sync-PhotoBackup.ps1
    4. Perform the sync:
         powershell.exe -ExecutionPolicy Bypass -File .\Sync-PhotoBackup.ps1 -Execute
    5. Perform the sync and verify every file using SHA-256:
         powershell.exe -ExecutionPolicy Bypass -File .\Sync-PhotoBackup.ps1 -Execute -VerifyHashes
#>

[CmdletBinding()]
param(
    [switch]$Help,
    [switch]$Execute,
    [switch]$VerifyHashes
)

if ($Help) {
    Get-Help $PSCommandPath -Full
    exit 0
}

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ============================================================
# CONFIGURATION — CHANGE THESE VALUES
# ============================================================

# Root folders to synchronize.
# These may be entire drives, such as "E:\" and "F:\",
# or specific folders, such as "E:\Important Files".
$MasterPath = "E:\Important Files"
$BackupPath = "F:\Important Files"

# Strongly recommended:
# Set the Windows volume labels assigned to the physical drives.
#
# In File Explorer:
#   Right-click drive -> Properties -> change the name.
#
# Leave blank only if you intentionally do not want label checking.
$ExpectedMasterDriveLabel = "PHOTO_MASTER"
$ExpectedBackupDriveLabel = "PHOTO_BACKUP"

# Folder used for logs.
$LogDirectory = Join-Path $env:USERPROFILE "Documents\Backup-Sync-Logs"

# Files and folders that should never be copied.
# Robocopy treats these as names, not full paths.
$ExcludedDirectories = @(
    '$RECYCLE.BIN',
    'System Volume Information'
)

$ExcludedFiles = @(
    'Thumbs.db',
    'desktop.ini',
    '.DS_Store'
)

# ============================================================
# FUNCTIONS
# ============================================================

function Get-NormalizedPath {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    return $fullPath.TrimEnd('\')
}

function Get-DriveRootFromPath {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $root = [System.IO.Path]::GetPathRoot($Path)

    if ([string]::IsNullOrWhiteSpace($root)) {
        throw "Could not determine the drive root for '$Path'."
    }

    return $root
}

function Get-VolumeLabel {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $root = Get-DriveRootFromPath -Path $Path
    $driveLetter = $root.Substring(0, 1)

    $volume = Get-CimInstance Win32_LogicalDisk `
        -Filter "DeviceID='$driveLetter`:'"

    if ($null -eq $volume) {
        throw "Could not read volume information for drive $driveLetter`:"
    }

    return [string]$volume.VolumeName
}

function Confirm-DriveLabel {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$ExpectedLabel,

        [Parameter(Mandatory)]
        [string]$Description
    )

    if ([string]::IsNullOrWhiteSpace($ExpectedLabel)) {
        Write-Warning "$Description label validation is disabled."
        return
    }

    $actualLabel = Get-VolumeLabel -Path $Path

    if ($actualLabel -ne $ExpectedLabel) {
        throw @"
$Description drive-label check failed.

Path:           $Path
Expected label: $ExpectedLabel
Actual label:   $actualLabel

The sync has been stopped to prevent copying in the wrong direction.
"@
    }

    Write-Host "$Description drive confirmed: $actualLabel" -ForegroundColor Green
}

function Get-RelativeFileMap {
    param(
        [Parameter(Mandatory)]
        [string]$RootPath
    )

    $root = Get-NormalizedPath -Path $RootPath
    $map = @{}

    Get-ChildItem -LiteralPath $root -File -Recurse -Force |
        ForEach-Object {
            $relativePath = $_.FullName.Substring($root.Length).TrimStart('\')
            $map[$relativePath] = $_
        }

    return $map
}

function Test-FilesByHash {
    param(
        [Parameter(Mandatory)]
        [string]$SourceRoot,

        [Parameter(Mandatory)]
        [string]$DestinationRoot
    )

    Write-Host ""
    Write-Host "Building file lists for SHA-256 verification..." -ForegroundColor Cyan

    $sourceFiles = Get-RelativeFileMap -RootPath $SourceRoot
    $destinationFiles = Get-RelativeFileMap -RootPath $DestinationRoot

    $problems = [System.Collections.Generic.List[object]]::new()
    $counter = 0
    $total = $sourceFiles.Count

    foreach ($relativePath in $sourceFiles.Keys) {
        $counter++

        if (($counter % 100) -eq 0 -or $counter -eq $total) {
            Write-Progress `
                -Activity "Verifying files with SHA-256" `
                -Status "$counter of $total files" `
                -PercentComplete (($counter / [Math]::Max($total, 1)) * 100)
        }

        if (-not $destinationFiles.ContainsKey($relativePath)) {
            $problems.Add([pscustomobject]@{
                File    = $relativePath
                Problem = "Missing from backup"
            })
            continue
        }

        $sourceFile = $sourceFiles[$relativePath]
        $destinationFile = $destinationFiles[$relativePath]

        if ($sourceFile.Length -ne $destinationFile.Length) {
            $problems.Add([pscustomobject]@{
                File    = $relativePath
                Problem = "File sizes differ"
            })
            continue
        }

        $sourceHash = (Get-FileHash -LiteralPath $sourceFile.FullName -Algorithm SHA256).Hash
        $destinationHash = (Get-FileHash -LiteralPath $destinationFile.FullName -Algorithm SHA256).Hash

        if ($sourceHash -ne $destinationHash) {
            $problems.Add([pscustomobject]@{
                File    = $relativePath
                Problem = "SHA-256 hashes differ"
            })
        }
    }

    foreach ($relativePath in $destinationFiles.Keys) {
        if (-not $sourceFiles.ContainsKey($relativePath)) {
            $problems.Add([pscustomobject]@{
                File    = $relativePath
                Problem = "Extra file exists on backup"
            })
        }
    }

    Write-Progress -Activity "Verifying files with SHA-256" -Completed

    return $problems
}

# ============================================================
# VALIDATION
# ============================================================

$MasterPath = Get-NormalizedPath -Path $MasterPath
$BackupPath = Get-NormalizedPath -Path $BackupPath

if ($MasterPath -eq $BackupPath) {
    throw "The master and backup paths cannot be the same."
}

if (-not (Test-Path -LiteralPath $MasterPath -PathType Container)) {
    throw "The master path does not exist: $MasterPath"
}

$masterRoot = Get-DriveRootFromPath -Path $MasterPath
$backupRoot = Get-DriveRootFromPath -Path $BackupPath

if ($masterRoot -eq $backupRoot) {
    throw @"
The master and backup are on the same drive: $masterRoot

A backup should be stored on a separate physical drive.
"@
}

Confirm-DriveLabel `
    -Path $MasterPath `
    -ExpectedLabel $ExpectedMasterDriveLabel `
    -Description "MASTER"

Confirm-DriveLabel `
    -Path $BackupPath `
    -ExpectedLabel $ExpectedBackupDriveLabel `
    -Description "BACKUP"

if (-not (Test-Path -LiteralPath $BackupPath)) {
    if ($Execute) {
        New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
        Write-Host "Created backup folder: $BackupPath" -ForegroundColor Green
    }
    else {
        Write-Host "Preview: backup folder would be created: $BackupPath" -ForegroundColor Yellow
    }
}

New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$modeName = if ($Execute) { "SYNC" } else { "PREVIEW" }
$logPath = Join-Path $LogDirectory "Backup-$modeName-$timestamp.log"

# ============================================================
# ROBOCOPY OPTIONS
# ============================================================

$robocopyArguments = @(
    $MasterPath,
    $BackupPath,

    # Mirror all subfolders and delete destination items
    # that no longer exist in the source.
    "/MIR",

    # Preserve data, attributes, and timestamps.
    "/COPY:DAT",
    "/DCOPY:DAT",

    # Use restartable copy mode.
    "/Z",

    # Retry failed files twice, waiting five seconds each time.
    "/R:2",
    "/W:5",

    # Multi-threaded copy.
    "/MT:16",

    # Use FAT-compatible timestamp tolerance. This is helpful
    # when one drive uses exFAT.
    "/FFT",

    # Output options.
    "/TEE",
    "/V",
    "/NP",
    "/BYTES",
    "/ETA",
    "/LOG:$logPath"
)

if ($ExcludedDirectories.Count -gt 0) {
    $robocopyArguments += "/XD"
    $robocopyArguments += $ExcludedDirectories
}

if ($ExcludedFiles.Count -gt 0) {
    $robocopyArguments += "/XF"
    $robocopyArguments += $ExcludedFiles
}

if (-not $Execute) {
    # List proposed actions without copying or deleting anything.
    $robocopyArguments += "/L"
}

# ============================================================
# RUN
# ============================================================

Write-Host ""
Write-Host "Master: $MasterPath" -ForegroundColor Cyan
Write-Host "Backup: $BackupPath" -ForegroundColor Cyan
Write-Host "Mode:   $modeName" -ForegroundColor Cyan
Write-Host "Log:    $logPath" -ForegroundColor Cyan
Write-Host ""

if (-not $Execute) {
    Write-Warning "PREVIEW ONLY: No files will be copied, changed, or deleted."
}
else {
    Write-Warning "MIRROR MODE: Files absent from the master may be deleted from the backup."
}

& robocopy.exe @robocopyArguments
$robocopyExitCode = $LASTEXITCODE

Write-Host ""
Write-Host "Robocopy exit code: $robocopyExitCode"

# Robocopy codes 0 through 7 are successful or informational.
# Code 8 or higher indicates at least one failure.
if ($robocopyExitCode -ge 8) {
    Write-Error @"
The synchronization encountered an error.

Robocopy exit code: $robocopyExitCode
Review the log:
$logPath
"@
    exit $robocopyExitCode
}

if (-not $Execute) {
    Write-Host ""
    Write-Host "Preview completed successfully." -ForegroundColor Green
    Write-Host "Review the proposed copies and deletions in:" -ForegroundColor Green
    Write-Host $logPath
    Write-Host ""
    Write-Host "To perform the actual synchronization, run:" -ForegroundColor Yellow
    Write-Host "powershell.exe -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Execute"
    exit 0
}

Write-Host ""
Write-Host "Synchronization completed successfully." -ForegroundColor Green

# ============================================================
# OPTIONAL HASH VERIFICATION
# ============================================================

if ($VerifyHashes) {
    $verificationProblems = Test-FilesByHash `
        -SourceRoot $MasterPath `
        -DestinationRoot $BackupPath

    if ($verificationProblems.Count -eq 0) {
        Write-Host ""
        Write-Host "HASH VERIFICATION PASSED." -ForegroundColor Green
        Write-Host "Every file on the master has an identical SHA-256 hash on the backup."
    }
    else {
        $verificationLog = Join-Path `
            $LogDirectory `
            "Verification-Failures-$timestamp.csv"

        $verificationProblems |
            Export-Csv -LiteralPath $verificationLog -NoTypeInformation

        Write-Host ""
        Write-Error @"
HASH VERIFICATION FAILED.

Number of problems: $($verificationProblems.Count)
Details were saved to:
$verificationLog
"@
        exit 20
    }
}
else {
    Write-Host ""
    Write-Host "Hash verification was not requested." -ForegroundColor Yellow
    Write-Host "For a full byte-level check, run:"
    Write-Host "powershell.exe -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Execute -VerifyHashes"
}

Write-Host ""
Write-Host "Finished. Safely eject the off-site backup drive before disconnecting it." -ForegroundColor Green
exit 0