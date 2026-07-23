<#
.SYNOPSIS
Renames media files by metadata date, with optional recursion and destination move.

.DESCRIPTION
Scans the current directory (and subdirectories if -Recurse is set) for supported
photo and video files, reads metadata dates with exiftool, and renames files to
YYYYMMDD_HHMMSS_originalname.ext. By default files are renamed in place. Use
-Destination to move renamed files to another folder, and -PreserveStructure to
mirror the source subdirectory layout under that folder. Existing name conflicts
are marked with _identical or _duplicate_diff_size suffixes. CSV logs are written
in the current folder.

.PARAMETER Mode
Required. Allowed values: dry-run or rename. dry-run previews changes; rename
applies them.

.PARAMETER Recurse
Optional. When set, scans subdirectories recursively. Default: current folder only.

.PARAMETER Destination
Optional. When provided, renamed files are moved to this folder instead of renamed
in place.

.PARAMETER PreserveStructure
Optional. When used with -Destination, recreates the source subdirectory structure
under the destination folder. Requires -Destination.

.PARAMETER FallbackToFilenameDate
Optional. When no embedded metadata date is found, attempt to parse a date from
the filename. Supports patterns: YYYY-MM-DD_HH-MM-SS, YYYYMMDD_HHMMSS,
YYYY-MM-DD, and YYYYMMDD at the start of the name.

.PARAMETER FallbackToFileDate
Optional. When no embedded metadata date (or filename date, if that switch is also
set) is found, use the file's filesystem creation time. This reflects when the
file was created on disk, not necessarily when the photo was taken.

.EXAMPLE
.\rename_photos_current_folder.ps1 -Mode dry-run

.EXAMPLE
.\rename_photos_current_folder.ps1 -Mode rename -Recurse

.EXAMPLE
.\rename_photos_current_folder.ps1 -Mode rename -Destination D:\Sorted

.EXAMPLE
.\rename_photos_current_folder.ps1 -Mode rename -Recurse -Destination D:\Sorted -PreserveStructure

.NOTES
Requires exiftool. Install with: winget install OliverBetz.ExifTool
#>

param(
    [switch]$Help,

    [Parameter(Mandatory=$false)]
    [ValidateSet('dry-run','rename')]
    [string]$Mode,

    [switch]$Recurse,

    [string]$Destination,

    [switch]$PreserveStructure,

    [switch]$FallbackToFilenameDate,

    [switch]$FallbackToFolderDate,

    [switch]$FallbackToFileDate,

    [string]$SkippedDestination
)

$photoExts = @('.jpg','.jpeg','.heic','.heif','.png','.gif','.tif','.tiff',
               '.dng','.raw','.cr2','.cr3','.nef','.arw','.raf','.rw2','.webp','.bmp')
$videoExts = @('.mov','.mp4','.m4v','.avi','.mkv','.3gp','.3g2','.mts','.m2ts',
               '.mpg','.mpeg','.wmv')
$allExts   = $photoExts + $videoExts

function Show-Help {
    Write-Host "Usage:"
    Write-Host "  .\rename_photos_current_folder.ps1 -Mode <dry-run|rename> [options]"
    Write-Host ""
    Write-Host "What it does:"
    Write-Host "  Scans the current folder for photo and video files, reads metadata dates"
    Write-Host "  with exiftool, and renames files to YYYYMMDD_HHMMSS_originalname.ext."
    Write-Host "  By default renames in place. Use -Destination to move files elsewhere."
    Write-Host "  Conflicts are marked with _identical or _duplicate_diff_size suffixes."
    Write-Host "  CSV logs are written in the current folder."
    Write-Host ""
    Write-Host "Parameters:"
    Write-Host "  -Mode                   Required. dry-run previews changes; rename applies them."
    Write-Host "  -Recurse                Scan subdirectories recursively."
    Write-Host "  -Destination <path>     Move renamed files here instead of renaming in place."
    Write-Host "  -PreserveStructure      Mirror source subfolder layout under -Destination."
    Write-Host "  -FallbackToFilenameDate Parse date from filename when no metadata date found."
    Write-Host "                          Supports: YYYY-MM-DD_HH-MM-SS, YYYYMMDD_HHMMSS,"
    Write-Host "                          YYYY-MM-DD-HH-MM-SS, YYYY-MM-DD, YYYYMMDD at start."
    Write-Host "  -FallbackToFolderDate   Parse date from parent folder name when no metadata"
    Write-Host "                          or filename date is found. Handles patterns like"
    Write-Host "                          'August 6, 2020' or 'Boston, February 14, 2020'."
    Write-Host "  -FallbackToFileDate     Use filesystem creation time when no metadata date"
    Write-Host "                          (or filename/folder date) is found."
    Write-Host "  -SkippedDestination     Move files with no date to this folder instead of"
    Write-Host "                          just logging them. Files are renamed with _noexif"
    Write-Host "                          suffix and a counter if names collide."
    Write-Host "  -Help                   Show this help and exit."
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\rename_photos_current_folder.ps1 -Mode dry-run"
    Write-Host "  .\rename_photos_current_folder.ps1 -Mode rename -Recurse"
    Write-Host "  .\rename_photos_current_folder.ps1 -Mode rename -Destination D:\Sorted"
    Write-Host "  .\rename_photos_current_folder.ps1 -Mode rename -Recurse -Destination D:\Sorted -PreserveStructure"
    Write-Host ""
    Write-Host "Requires exiftool. Install with: winget install OliverBetz.ExifTool"
}

function Test-ExifTool {
    if (-not (Get-Command exiftool -ErrorAction SilentlyContinue)) {
        Write-Error "ExifTool is required but not found.`nInstall with: winget install OliverBetz.ExifTool"
        exit 1
    }
}

function Get-DateFromFilename([string]$stem) {
    $candidate = $null
    # YYYY-MM-DD_HH-MM-SS  or  YYYY-MM-DD HH:MM:SS  or  YYYY-MM-DDTHH-MM-SS  or  YYYY-MM-DD-HH-MM-SS
    if ($stem -match '((?:19|20)\d{2})[_\-](\d{2})[_\-](\d{2})[T _\-](\d{2})[.\-:](\d{2})[.\-:](\d{2})') {
        $candidate = "$($Matches[1])-$($Matches[2])-$($Matches[3]) $($Matches[4]):$($Matches[5]):$($Matches[6])"
    }
    # YYYYMMDD_HHMMSS
    elseif ($stem -match '((?:19|20)\d{2})(\d{2})(\d{2})[_\-](\d{2})(\d{2})(\d{2})') {
        $candidate = "$($Matches[1])-$($Matches[2])-$($Matches[3]) $($Matches[4]):$($Matches[5]):$($Matches[6])"
    }
    # YYYY-MM-DD
    elseif ($stem -match '((?:19|20)\d{2})[_\-](\d{2})[_\-](\d{2})') {
        $candidate = "$($Matches[1])-$($Matches[2])-$($Matches[3]) 00:00:00"
    }
    # YYYYMMDD at start of filename
    elseif ($stem -match '^((?:19|20)\d{2})(\d{2})(\d{2})') {
        $candidate = "$($Matches[1])-$($Matches[2])-$($Matches[3]) 00:00:00"
    }
    if (-not $candidate) { return $null }
    try {
        [datetime]::ParseExact($candidate, 'yyyy-MM-dd HH:mm:ss', $null) | Out-Null
        return $candidate
    } catch {
        return $null
    }
}

function Get-DateFromFolderName([string]$file) {
    $months = @{
        'January'=1;'February'=2;'March'=3;'April'=4;'May'=5;'June'=6
        'July'=7;'August'=8;'September'=9;'October'=10;'November'=11;'December'=12
    }
    $dirName = Split-Path ([System.IO.Path]::GetDirectoryName($file)) -Leaf
    # Matches: "August 6, 2020"  or  "Boston, February 14, 2020"  or  "Home, July 5, 2020"
    if ($dirName -match '(?:^|,\s*)(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{1,2}),\s*((?:19|20)\d{2})\s*$') {
        $candidate = '{0:D4}-{1:D2}-{2:D2} 00:00:00' -f [int]$Matches[3], $months[$Matches[1]], [int]$Matches[2]
        try {
            [datetime]::ParseExact($candidate, 'yyyy-MM-dd HH:mm:ss', $null) | Out-Null
            return $candidate
        } catch {
            return $null
        }
    }
    return $null
}

function Get-MetadataDate([string]$file) {
    # 1. Embedded EXIF/video metadata
    $lines = exiftool -s3 -d "%Y-%m-%d %H:%M:%S" `
        -DateTimeOriginal -SubSecDateTimeOriginal -CreateDate `
        -MediaCreateDate -TrackCreateDate -CreationDate $file 2>$null
    foreach ($line in $lines) {
        $line = $line.Trim() -replace '[+-]\d{2}:\d{2}$', ''
        if ($line -and $line.Substring(0,4) -ne '0000') {
            return [PSCustomObject]@{ Date = $line; Source = 'exif' }
        }
    }

    # 2. Parse date from filename
    if ($script:FallbackToFilenameDate) {
        $stem = [System.IO.Path]::GetFileNameWithoutExtension($file)
        $d = Get-DateFromFilename $stem
        if ($d) { return [PSCustomObject]@{ Date = $d; Source = 'filename' } }
    }

    # 3. Parse date from parent folder name
    if ($script:FallbackToFolderDate) {
        $d = Get-DateFromFolderName $file
        if ($d) { return [PSCustomObject]@{ Date = $d; Source = 'folder' } }
    }

    # 4. Filesystem creation time
    if ($script:FallbackToFileDate) {
        $item = Get-Item -LiteralPath $file
        return [PSCustomObject]@{ Date = $item.CreationTime.ToString('yyyy-MM-dd HH:mm:ss'); Source = 'filedate' }
    }

    return $null
}

function Get-SanitizedName([string]$name) {
    $name = $name.ToLower()
    $name = $name -replace '[^a-z0-9._\-]', '_'
    $name = $name -replace '_+', '_'
    return $name.Trim('_')
}

function Get-FileHashSHA256([string]$file) {
    return (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
}

function Get-TechnicalSignature([string]$file) {
    $width    = (exiftool -s3 -ImageWidth  $file 2>$null)[0]
    $height   = (exiftool -s3 -ImageHeight $file 2>$null)[0]
    $duration = (exiftool -s3 -Duration    $file 2>$null)[0]
    $size     = (Get-Item -LiteralPath $file).Length
    $width    = if ($width)    { $width.Trim()                          } else { '' }
    $height   = if ($height)   { $height.Trim()                         } else { '' }
    $duration = if ($duration) { ($duration.Trim() -replace '\s+', '') } else { '' }
    return "width=$width;height=$height;duration=$duration;size=$size"
}

function Compare-MediaFiles([string]$a, [string]$b) {
    if ((Get-FileHashSHA256 $a) -eq (Get-FileHashSHA256 $b)) { return 'identical' }
    if ((Get-TechnicalSignature $a) -eq (Get-TechnicalSignature $b)) { return 'duplicate_diff_size' }
    return 'duplicate_diff_size'
}

function Add-SuffixBeforeExtension([string]$name, [string]$suffix) {
    $ext  = [System.IO.Path]::GetExtension($name)
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($name)
    if ($ext) { return "${stem}_${suffix}${ext}" }
    return "${stem}_${suffix}"
}

function Get-UniqueName([string]$dir, [string]$name) {
    if (-not (Test-Path -LiteralPath (Join-Path $dir $name))) { return $name }
    $ext  = [System.IO.Path]::GetExtension($name)
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($name)
    $i = 2
    while ($true) {
        $candidate = "${stem}_${i}${ext}"
        if (-not (Test-Path -LiteralPath (Join-Path $dir $candidate))) { return $candidate }
        $i++
    }
}

function Resolve-NewName([string]$srcFile, [string]$targetName, [string]$targetDir) {
    $srcBase = [System.IO.Path]::GetFileName($srcFile)
    $srcDir  = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($srcFile))

    if ($srcBase -eq $targetName -and $srcDir -eq $targetDir) {
        return "$targetName|already_named"
    }

    $targetPath = Join-Path $targetDir $targetName
    if (-not (Test-Path -LiteralPath $targetPath)) { return "$targetName|new" }

    $cmp = Compare-MediaFiles $srcFile $targetPath
    if ($cmp -eq 'identical') {
        $suffixed = Add-SuffixBeforeExtension $targetName 'identical'
    } else {
        $suffixed = Add-SuffixBeforeExtension $targetName 'duplicate_diff_size'
    }
    $final = Get-UniqueName $targetDir $suffixed
    return "$final|$cmp"
}

function Move-ToDirectory([string]$file, [string]$dir, [string]$targetName, [string]$logFile, [string]$skippedFile, [string]$logDate, [string]$logAction) {
    if (-not (Test-Path -LiteralPath $dir)) {
        try {
            New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
        } catch {
            Write-Warning "  [ERROR] Could not create directory '$dir': $_"
            Add-Content -Path $skippedFile -Value "`"$file`",`"Could not create directory: $_`""
            return
        }
    }
    $finalName = Get-UniqueName $dir $targetName
    $finalPath = Join-Path $dir $finalName
    $filename  = [System.IO.Path]::GetFileName($file)
    try {
        Move-Item -LiteralPath $file -Destination $finalPath -ErrorAction Stop
    } catch {
        Write-Warning "  [ERROR] $filename -> $finalPath : $_"
        Add-Content -Path $skippedFile -Value "`"$file`",`"$_`""
        return
    }
    Write-Host "  [$logAction] $filename -> $finalPath"
    Add-Content -Path $logFile -Value "`"$file`",`"$finalPath`",`"$logDate`",`"$logAction`",`"new`""
}

function Process-File([string]$file, [string]$targetDir, [string]$logFile, [string]$skippedFile) {
    $filename  = [System.IO.Path]::GetFileName($file)
    $ext       = [System.IO.Path]::GetExtension($filename).ToLower()
    $stem      = [System.IO.Path]::GetFileNameWithoutExtension($filename)
    $cleanStem = Get-SanitizedName $stem
    if (-not $cleanStem) { $cleanStem = 'file' }

    $metaResult = Get-MetadataDate $file
    if (-not $metaResult) {
        if ($script:SkippedDestination) {
            $targetName = "${cleanStem}_noexif${ext}"
            Move-ToDirectory $file $script:SkippedDestination $targetName $logFile $skippedFile '' 'moved_nodate'
        } else {
            Write-Host "  [SKIP] No date found"
            Add-Content -Path $skippedFile -Value "`"$file`",`"No usable metadata date found`""
        }
        return
    }

    $metaDate = $metaResult.Date
    $noexif   = $metaResult.Source -ne 'exif'

    if ($metaDate -notmatch '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$') {
        Write-Host "  [SKIP] Invalid date: $metaDate"
        Add-Content -Path $skippedFile -Value "`"$file`",`"Invalid metadata date: $metaDate`""
        return
    }

    $year   = $metaDate.Substring(0,4)
    $month  = $metaDate.Substring(5,2)
    $day    = $metaDate.Substring(8,2)
    $hour   = $metaDate.Substring(11,2)
    $minute = $metaDate.Substring(14,2)
    $second = $metaDate.Substring(17,2)
    $datetimePrefix = "${year}${month}${day}_${hour}${minute}${second}"

    $noexifSuffix = if ($noexif) { '_noexif' } else { '' }
    $targetName   = "${datetimePrefix}_${cleanStem}${noexifSuffix}${ext}"
    $resolved     = Resolve-NewName $file $targetName $targetDir
    $finalName    = $resolved -replace '\|[^|]*$', ''
    $comparison   = $resolved -replace '^.*\|', ''
    $finalPath    = Join-Path $targetDir $finalName

    if ($comparison -eq 'already_named') {
        Write-Host "  [SKIP] Already named: $filename"
        Add-Content -Path $logFile -Value "`"$file`",`"$finalPath`",`"$metaDate`",`"already_named`",`"$comparison`""
        return
    }

    if ($Mode -eq 'dry-run') {
        $tag = if ($noexif) { 'DRY RUN noexif' } else { 'DRY RUN' }
        Write-Host "  [$tag] $filename"
        Write-Host "          -> $finalPath"
        Write-Host "          source: $($metaResult.Source)  comparison: $comparison"
        Add-Content -Path $logFile -Value "`"$file`",`"$finalPath`",`"$metaDate`",`"dry-run`",`"$comparison`""
        return
    }

    if (-not (Test-Path -LiteralPath $targetDir)) {
        try {
            New-Item -ItemType Directory -Path $targetDir -Force -ErrorAction Stop | Out-Null
        } catch {
            Write-Warning "  [ERROR] Could not create directory '$targetDir': $_"
            Add-Content -Path $skippedFile -Value "`"$file`",`"Could not create target directory: $_`""
            return
        }
    }

    $srcDir = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($file))
    try {
        if ($srcDir -eq $targetDir) {
            Rename-Item -LiteralPath $file -NewName $finalName -ErrorAction Stop
            $action = 'renamed'
        } else {
            Move-Item -LiteralPath $file -Destination $finalPath -ErrorAction Stop
            $action = 'moved'
        }
    } catch {
        Write-Warning "  [ERROR] $filename -> $finalPath : $_"
        Add-Content -Path $skippedFile -Value "`"$file`",`"$_`""
        return
    }
    $tag = if ($noexif) { "$($action.ToUpper()) noexif" } else { $action.ToUpper() }
    Write-Host "  [$tag] $filename -> $finalPath [$comparison]"
    Add-Content -Path $logFile -Value "`"$file`",`"$finalPath`",`"$metaDate`",`"$action`",`"$comparison`""
}

# --- Help ---

if ($Help) {
    Show-Help
    exit 0
}

# --- Validation ---

if (-not $Mode) {
    Write-Error "-Mode is required (dry-run or rename). Use -Help for usage information."
    exit 1
}

if ($PreserveStructure -and -not $Destination) {
    Write-Error "-PreserveStructure requires -Destination to be specified."
    exit 1
}

if ($Destination) {
    $Destination = [System.IO.Path]::GetFullPath($Destination)
}

if ($SkippedDestination) {
    $SkippedDestination = [System.IO.Path]::GetFullPath($SkippedDestination)
}

# --- Main ---

Test-ExifTool

$timestamp   = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile     = ".\rename_log_$timestamp.csv"
$skippedFile = ".\rename_skipped_$timestamp.csv"

Set-Content -Path $logFile     -Value "source_path,new_path,metadata_date,action,comparison"
Set-Content -Path $skippedFile -Value "source_path,reason"

$root = (Get-Location).Path

Write-Host "Mode:                  $Mode"
Write-Host "Folder:                $root"
Write-Host "Recurse:               $($Recurse.IsPresent)"
Write-Host "Destination:           $(if ($Destination) { $Destination } else { '(in place)' })"
Write-Host "PreserveStructure:     $($PreserveStructure.IsPresent)"
Write-Host "FallbackToFilenameDate: $($FallbackToFilenameDate.IsPresent)"
Write-Host "FallbackToFolderDate:   $($FallbackToFolderDate.IsPresent)"
Write-Host "FallbackToFileDate:     $($FallbackToFileDate.IsPresent)"
Write-Host "SkippedDestination:     $(if ($SkippedDestination) { $SkippedDestination } else { '(log only)' })"
Write-Host "Log:                    $logFile"
Write-Host "Skipped:                $skippedFile"
Write-Host ""

$scriptName = Split-Path $PSCommandPath -Leaf
$gciParams  = @{ Path = '.'; File = $true }
if ($Recurse) { $gciParams['Recurse'] = $true }

$mediaFiles = @(Get-ChildItem @gciParams |
    Where-Object { $_.Name -ne $scriptName -and $allExts -contains $_.Extension.ToLower() })

$total = $mediaFiles.Count
Write-Host "Found $total media files$(if ($Recurse) { ' (recursive)' } else { ' in current folder' })."
Write-Host ""

for ($i = 0; $i -lt $total; $i++) {
    $file = $mediaFiles[$i]

    if ($Destination) {
        if ($PreserveStructure) {
            $relDir    = [System.IO.Path]::GetRelativePath($root, $file.DirectoryName)
            $targetDir = Join-Path $Destination $relDir
        } else {
            $targetDir = $Destination
        }
    } else {
        $targetDir = $file.DirectoryName
    }

    Write-Progress -Activity "Renaming photos" `
        -Status "$($i+1)/$total : $($file.Name)" `
        -PercentComplete ([int](($i / [Math]::Max($total,1)) * 100))
    Write-Host "[$($i+1)/$total] $($file.FullName)"
    Process-File $file.FullName $targetDir $logFile $skippedFile
}
Write-Progress -Activity "Renaming photos" -Completed

Write-Host ""
Write-Host "Done."
Write-Host "Log:     $logFile"
Write-Host "Skipped: $skippedFile"
