<#
.SYNOPSIS
Merges files from a source folder into a destination folder by filename uniqueness.

.DESCRIPTION
Copies, moves, or previews files from Source into Dest while preserving the
relative source folder structure. A source file is skipped when the same filename
already exists anywhere under Dest. CSV logs are written under Dest\_merge_logs.

.PARAMETER Mode
Optional. Transfer mode: dry-run, copy, or move. If omitted, the script prompts
for a value.

.PARAMETER Source
Optional. Source directory to scan recursively. If omitted, the script prompts
for a value.

.PARAMETER Dest
Optional. Destination directory. Created if it does not exist. If omitted, the
script prompts for a value.

.EXAMPLE
.\merge_unique_files.ps1 -Mode dry-run -Source D:\Src -Dest D:\Dst

.EXAMPLE
.\merge_unique_files.ps1 -Mode copy -Source D:\Src -Dest D:\Dst
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('dry-run','copy','move')]
    [string]$Mode,

    [Parameter(Mandatory=$false)]
    [string]$Source,

    [Parameter(Mandatory=$false)]
    [string]$Dest
)

function Read-RequiredValue {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Prompt,

        [string[]]$ValidValues
    )

    while ($true) {
        $value = Read-Host $Prompt
        $value = $value.Trim()

        if ([string]::IsNullOrWhiteSpace($value)) {
            Write-Host "A value is required."
            continue
        }

        if ($ValidValues -and ($ValidValues -notcontains $value)) {
            Write-Host "Valid values: $($ValidValues -join ', ')"
            continue
        }

        return $value
    }
}

if ([string]::IsNullOrWhiteSpace($Mode)) {
    $Mode = Read-RequiredValue -Prompt "Mode (dry-run, copy, or move)" -ValidValues @('dry-run','copy','move')
}

if ([string]::IsNullOrWhiteSpace($Source)) {
    $Source = Read-RequiredValue -Prompt "Source directory to merge files from"
}

if ([string]::IsNullOrWhiteSpace($Dest)) {
    $Dest = Read-RequiredValue -Prompt "Destination directory to merge unique files into"
}

$Source = [System.IO.Path]::GetFullPath($Source)
$Dest   = [System.IO.Path]::GetFullPath($Dest)

if (-not (Test-Path -Path $Source -PathType Container)) {
    Write-Error "Source directory does not exist: $Source"
    exit 1
}

$null = New-Item -ItemType Directory -Path $Dest -Force

$logDir = Join-Path $Dest '_merge_logs'
$null = New-Item -ItemType Directory -Path $logDir -Force

$timestamp   = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile     = Join-Path $logDir "merge_unique_log_$timestamp.csv"
$skippedFile = Join-Path $logDir "merge_unique_skipped_$timestamp.csv"

Set-Content -Path $logFile     -Value "source_path,destination_path,action,reason"
Set-Content -Path $skippedFile -Value "source_path,existing_destination_path,reason"

Write-Host "Mode:        $Mode"
Write-Host "Source:      $Source"
Write-Host "Destination: $Dest"
Write-Host "Log:         $logFile"
Write-Host "Skipped:     $skippedFile"
Write-Host ""

# Build in-memory filename index from DEST (name -> first matching full path)
Write-Host "Building destination filename index..."
$destIndex = @{}
Get-ChildItem -Path $Dest -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notlike "$logDir\*" } |
    ForEach-Object {
        if (-not $destIndex.ContainsKey($_.Name)) {
            $destIndex[$_.Name] = $_.FullName
        }
    }
Write-Host "  $($destIndex.Count) unique filenames indexed in destination."

Write-Host "Building source file list..."
$sourceFiles = @(Get-ChildItem -Path $Source -Recurse -File)
Write-Host "  $($sourceFiles.Count) files in source."
Write-Host ""

$total = $sourceFiles.Count

for ($i = 0; $i -lt $total; $i++) {
    $file = $sourceFiles[$i]
    Write-Progress -Activity "Merging files" `
        -Status "$($i+1)/$total : $($file.Name)" `
        -PercentComplete ([int](($i / [Math]::Max($total,1)) * 100))

    $filename = $file.Name

    if ($destIndex.ContainsKey($filename)) {
        $existingPath = $destIndex[$filename]
        Write-Host "[SKIP] $($file.FullName)"
        Write-Host "       Existing in destination: $existingPath"
        Add-Content -Path $skippedFile -Value "`"$($file.FullName)`",`"$existingPath`",`"filename already exists in destination tree`""
        Add-Content -Path $logFile     -Value "`"$($file.FullName)`",`"`",`"skipped`",`"filename already exists in destination tree`""
        continue
    }

    $relativePath = $file.FullName.Substring($Source.Length).TrimStart('\', '/')
    $targetPath   = Join-Path $Dest $relativePath
    $targetDir    = [System.IO.Path]::GetDirectoryName($targetPath)

    if ($Mode -eq 'dry-run') {
        Write-Host "[DRY RUN] $($file.FullName)"
        Write-Host "          -> $targetPath"
        Add-Content -Path $logFile -Value "`"$($file.FullName)`",`"$targetPath`",`"dry-run`",`"would transfer`""
        $destIndex[$filename] = $targetPath
        continue
    }

    $null = New-Item -ItemType Directory -Path $targetDir -Force

    if ($Mode -eq 'copy') {
        Copy-Item -LiteralPath $file.FullName -Destination $targetPath
        Write-Host "[COPIED] $($file.FullName) -> $targetPath"
        Add-Content -Path $logFile -Value "`"$($file.FullName)`",`"$targetPath`",`"copied`",`"new filename`""
    } elseif ($Mode -eq 'move') {
        Move-Item -LiteralPath $file.FullName -Destination $targetPath
        Write-Host "[MOVED] $($file.FullName) -> $targetPath"
        Add-Content -Path $logFile -Value "`"$($file.FullName)`",`"$targetPath`",`"moved`",`"new filename`""
    }

    $destIndex[$filename] = $targetPath
}

Write-Progress -Activity "Merging files" -Completed

Write-Host ""
Write-Host "Done."
Write-Host "Log:     $logFile"
Write-Host "Skipped: $skippedFile"
