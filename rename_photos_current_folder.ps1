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

    [switch]$FallbackToFileDate
)

$photoExts = @('.jpg','.jpeg','.heic','.heif','.png','.gif','.tif','.tiff',
               '.dng','.raw','.cr2','.cr3','.nef','.arw','.raf','.rw2','.webp','.bmp')
$videoExts = @('.mov','.mp4','.m4v','.avi','.mkv','.3gp','.3g2','.mts','.m2ts',
               '.mpg','.mpeg','.wmv')
$allExts   = $photoExts + $videoExts

function Test-ExifTool {
    if (-not (Get-Command exiftool -ErrorAction SilentlyContinue)) {
        Write-Error "ExifTool is required but not found.`nInstall with: winget install OliverBetz.ExifTool"
        exit 1
    }
}

function Get-DateFromFilename([string]$stem) {
    $candidate = $null
    # YYYY-MM-DD_HH-MM-SS  or  YYYY-MM-DD HH:MM:SS  or  YYYY-MM-DDTHH-MM-SS
    if ($stem -match '((?:19|20)\d{2})[_\-](\d{2})[_\-](\d{2})[T _](\d{2})[.\-:](\d{2})[.\-:](\d{2})') {
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

function Get-MetadataDate([string]$file) {
    # 1. Embedded EXIF/video metadata
    $lines = exiftool -s3 -d "%Y-%m-%d %H:%M:%S" `
        -DateTimeOriginal -SubSecDateTimeOriginal -CreateDate `
        -MediaCreateDate -TrackCreateDate -CreationDate $file 2>$null
    foreach ($line in $lines) {
        $line = $line.Trim()
        if ($line) { return $line }
    }

    # 2. Parse date from filename
    if ($script:FallbackToFilenameDate) {
        $stem = [System.IO.Path]::GetFileNameWithoutExtension($file)
        $d = Get-DateFromFilename $stem
        if ($d) { return $d }
    }

    # 3. Filesystem creation time
    if ($script:FallbackToFileDate) {
        $item = Get-Item -LiteralPath $file
        return $item.CreationTime.ToString('yyyy-MM-dd HH:mm:ss')
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
    if ((Get-TechnicalSignature $a) -eq (Get-TechnicalSignature $b)) { return 'identical' }
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

function Process-File([string]$file, [string]$targetDir, [string]$logFile, [string]$skippedFile) {
    $metaDate = Get-MetadataDate $file
    if (-not $metaDate) {
        Add-Content -Path $skippedFile -Value "`"$file`",`"No usable metadata date found`""
        return
    }
    if ($metaDate -notmatch '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$') {
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

    $filename  = [System.IO.Path]::GetFileName($file)
    $ext       = [System.IO.Path]::GetExtension($filename).ToLower()
    $stem      = [System.IO.Path]::GetFileNameWithoutExtension($filename)
    $cleanStem = Get-SanitizedName $stem
    if (-not $cleanStem) { $cleanStem = 'file' }

    $targetName = "${datetimePrefix}_${cleanStem}${ext}"
    $resolved   = Resolve-NewName $file $targetName $targetDir
    $finalName  = $resolved -replace '\|[^|]*$', ''
    $comparison = $resolved -replace '^.*\|', ''
    $finalPath  = Join-Path $targetDir $finalName

    if ($comparison -eq 'already_named') {
        Write-Host "[SKIP] Already named: $filename"
        Add-Content -Path $logFile -Value "`"$file`",`"$finalPath`",`"$metaDate`",`"already_named`",`"$comparison`""
        return
    }

    if ($Mode -eq 'dry-run') {
        Write-Host "[DRY RUN] $filename"
        Write-Host "          -> $finalPath"
        Write-Host "          comparison: $comparison"
        Add-Content -Path $logFile -Value "`"$file`",`"$finalPath`",`"$metaDate`",`"dry-run`",`"$comparison`""
        return
    }

    if (-not (Test-Path -LiteralPath $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }

    $srcDir = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($file))
    if ($srcDir -eq $targetDir) {
        Rename-Item -LiteralPath $file -NewName $finalName
        $action = 'renamed'
    } else {
        Move-Item -LiteralPath $file -Destination $finalPath
        $action = 'moved'
    }
    Write-Host "[$($action.ToUpper())] $filename -> $finalPath [$comparison]"
    Add-Content -Path $logFile -Value "`"$file`",`"$finalPath`",`"$metaDate`",`"$action`",`"$comparison`""
}

# --- Help ---

if ($Help) {
    Get-Help $PSCommandPath -Full
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
Write-Host "FallbackToFilenameDate:$($FallbackToFilenameDate.IsPresent)"
Write-Host "FallbackToFileDate:    $($FallbackToFileDate.IsPresent)"
Write-Host "Log:                   $logFile"
Write-Host "Skipped:               $skippedFile"
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
    Process-File $file.FullName $targetDir $logFile $skippedFile
}
Write-Progress -Activity "Renaming photos" -Completed

Write-Host ""
Write-Host "Done."
Write-Host "Log:     $logFile"
Write-Host "Skipped: $skippedFile"
