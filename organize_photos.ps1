<#
.SYNOPSIS
Organizes photos and videos by metadata date.

.DESCRIPTION
Reads EXIF/media metadata dates with exiftool and copies, moves, or previews
media files into DEST\YEAR\MM-MonthName\YYYY-MM-DD using filenames formatted as
YYYYMMDD_HHMMSS_originalname.ext. Existing destination conflicts are marked with
_identical or _duplicate_diff_size suffixes. CSV logs are written under
Dest\_organizer_logs.

.PARAMETER Mode
Required. Allowed values: dry-run, copy, move.

.PARAMETER Source
Required. Source directory to scan recursively for supported photo and video files.

.PARAMETER Dest
Required. Destination directory. Created if it does not exist.

.PARAMETER Help
Optional switch. Shows usage and parameter help, then exits.

.PARAMETER SplitMedia
Optional switch. When present, writes Photos, Videos, and Other subfolders under Dest.

.EXAMPLE
.\organize_photos.ps1 -Mode dry-run -Source D:\Import -Dest D:\Sorted

.EXAMPLE
.\organize_photos.ps1 -Mode copy -Source D:\Import -Dest D:\Sorted -SplitMedia

.NOTES
Requires exiftool. Install with: winget install OliverBetz.ExifTool
#>

param(
    [string]$Mode,

    [string]$Source,

    [string]$Dest,

    [switch]$Help,

    [switch]$SplitMedia
)

$photoExts = @('.jpg','.jpeg','.heic','.heif','.png','.gif','.tif','.tiff',
               '.dng','.raw','.cr2','.cr3','.nef','.arw','.raf','.rw2','.webp','.bmp')
$videoExts = @('.mov','.mp4','.m4v','.avi','.mkv','.3gp','.3g2','.mts','.m2ts',
               '.mpg','.mpeg','.wmv')
$allExts   = $photoExts + $videoExts
$modeValues = @('dry-run','copy','move')

$monthNames = @('','January','February','March','April','May','June',
                'July','August','September','October','November','December')

function Show-ParameterHelp {
    Write-Host "Usage:"
    Write-Host "  .\organize_photos.ps1 -Mode <dry-run|copy|move> -Source <path> -Dest <path> [-SplitMedia]"
    Write-Host ""
    Write-Host "Parameters:"
    Write-Host "  -Mode        Required. Allowed values: dry-run, copy, move"
    Write-Host "  -Source      Required. Existing source directory path."
    Write-Host "  -Dest        Required. Destination directory path. Created if it does not exist."
    Write-Host "  -SplitMedia  Optional switch. Allowed values: absent, present"
    Write-Host "  -Help        Optional switch. Shows this help and exits."
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\organize_photos.ps1 -Mode dry-run -Source D:\Import -Dest D:\Sorted"
    Write-Host "  .\organize_photos.ps1 -Mode copy -Source D:\Import -Dest D:\Sorted -SplitMedia"
}

function Test-ExifTool {
    if (-not (Get-Command exiftool -ErrorAction SilentlyContinue)) {
        Write-Error "ExifTool is required but not found.`nInstall with: winget install OliverBetz.ExifTool"
        exit 1
    }
}

function Get-MetadataDate([string]$file) {
    $lines = exiftool -s3 -d "%Y-%m-%d %H:%M:%S" `
        -DateTimeOriginal -SubSecDateTimeOriginal -CreateDate `
        -MediaCreateDate -TrackCreateDate -CreationDate $file 2>$null
    foreach ($line in $lines) {
        $line = $line.Trim()
        if ($line) { return $line }
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
    $width    = @(exiftool -s3 -ImageWidth  $file 2>$null)[0]
    $height   = @(exiftool -s3 -ImageHeight $file 2>$null)[0]
    $duration = @(exiftool -s3 -Duration    $file 2>$null)[0]
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

function Add-SuffixBeforeExtension([string]$path, [string]$suffix) {
    $dir  = [System.IO.Path]::GetDirectoryName($path)
    $ext  = [System.IO.Path]::GetExtension($path)
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($path)
    if ($ext) { return [System.IO.Path]::Combine($dir, "${stem}_${suffix}${ext}") }
    return [System.IO.Path]::Combine($dir, "${stem}_${suffix}")
}

function Get-UniqueDestPath([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return $path }
    $dir  = [System.IO.Path]::GetDirectoryName($path)
    $ext  = [System.IO.Path]::GetExtension($path)
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($path)
    $i = 2
    while ($true) {
        $candidate = [System.IO.Path]::Combine($dir, "${stem}_${i}${ext}")
        if (-not (Test-Path -LiteralPath $candidate)) { return $candidate }
        $i++
    }
}

function Resolve-DestPath([string]$srcFile, [string]$targetPath) {
    if (-not (Test-Path -LiteralPath $targetPath)) { return "$targetPath|new" }
    $cmp = Compare-MediaFiles $srcFile $targetPath
    if ($cmp -eq 'identical') {
        $suffixed = Add-SuffixBeforeExtension $targetPath 'identical'
    } else {
        $suffixed = Add-SuffixBeforeExtension $targetPath 'duplicate_diff_size'
    }
    $final = Get-UniqueDestPath $suffixed
    return "$final|$cmp"
}

function Get-MediaType([string]$file) {
    $ext = [System.IO.Path]::GetExtension($file).ToLower()
    if ($photoExts -contains $ext) { return 'Pictures' }
    if ($videoExts -contains $ext) { return 'Videos' }
    return 'Other'
}

function Process-File([string]$file, [string]$logFile, [string]$skippedFile) {
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

    $monthName      = $monthNames[[int]$month]
    $dateFolder     = "${year}-${month}-${day}"
    $datetimePrefix = "${year}${month}${day}_${hour}${minute}${second}"

    $filename  = [System.IO.Path]::GetFileName($file)
    $ext       = [System.IO.Path]::GetExtension($filename).ToLower()
    $stem      = [System.IO.Path]::GetFileNameWithoutExtension($filename)
    $cleanStem = Get-SanitizedName $stem
    if (-not $cleanStem) { $cleanStem = 'file' }

    $mediaType = Get-MediaType $file
    $baseDestDir = if ($SplitMedia) { [System.IO.Path]::Combine($Dest, $mediaType) } else { $Dest }

    $targetDir  = [System.IO.Path]::Combine($baseDestDir, $year, "$month-$monthName", $dateFolder)
    $targetFile = "${datetimePrefix}_${cleanStem}${ext}"
    $targetPath = [System.IO.Path]::Combine($targetDir, $targetFile)

    $null = New-Item -ItemType Directory -Path $targetDir -Force

    $resolved   = Resolve-DestPath $file $targetPath
    $finalPath  = $resolved -replace '\|[^|]*$', ''
    $comparison = $resolved -replace '^.*\|', ''

    if ($Mode -eq 'dry-run') {
        Write-Host "[DRY RUN] $file"
        Write-Host "          -> $finalPath"
        Write-Host "          media type: $mediaType"
        Write-Host "          comparison: $comparison"
        Add-Content -Path $logFile -Value "`"$file`",`"$finalPath`",`"$metaDate`",`"$mediaType`",`"dry-run`",`"$comparison`""
        return
    }

    if ($Mode -eq 'copy') {
        Copy-Item -LiteralPath $file -Destination $finalPath
        Write-Host "[COPIED] $file -> $finalPath [$mediaType/$comparison]"
        Add-Content -Path $logFile -Value "`"$file`",`"$finalPath`",`"$metaDate`",`"$mediaType`",`"copied`",`"$comparison`""
    } elseif ($Mode -eq 'move') {
        Move-Item -LiteralPath $file -Destination $finalPath
        Write-Host "[MOVED] $file -> $finalPath [$mediaType/$comparison]"
        Add-Content -Path $logFile -Value "`"$file`",`"$finalPath`",`"$metaDate`",`"$mediaType`",`"moved`",`"$comparison`""
    }
}

# --- Main ---

if ($Help) {
    Show-ParameterHelp
    exit 0
}

Write-Host "Allowed parameter values:"
Write-Host "  -Mode:       $($modeValues -join ', ')"
Write-Host "  -SplitMedia: absent, present"
Write-Host ""

$missingRequired = @()
if (-not $Mode) { $missingRequired += '-Mode' }
if (-not $Source) { $missingRequired += '-Source' }
if (-not $Dest) { $missingRequired += '-Dest' }

if ($missingRequired.Count -gt 0) {
    Write-Error "Missing required parameter(s): $($missingRequired -join ', ')"
    Write-Host ""
    Show-ParameterHelp
    exit 1
}

if ($modeValues -notcontains $Mode) {
    Write-Error "Invalid -Mode value '$Mode'. Allowed values: $($modeValues -join ', ')"
    exit 1
}

Test-ExifTool

if (-not (Test-Path -Path $Source -PathType Container)) {
    Write-Error "Source directory does not exist: $Source"
    exit 1
}

$null = New-Item -ItemType Directory -Path $Dest -Force
$logDir = [System.IO.Path]::Combine($Dest, '_organizer_logs')
$null = New-Item -ItemType Directory -Path $logDir -Force

$timestamp   = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile     = [System.IO.Path]::Combine($logDir, "organize_log_$timestamp.csv")
$skippedFile = [System.IO.Path]::Combine($logDir, "skipped_no_metadata_$timestamp.csv")

Set-Content -Path $logFile     -Value "original_path,new_path,metadata_date,media_type,action,comparison"
Set-Content -Path $skippedFile -Value "original_path,reason"

Write-Host "Mode:        $Mode"
Write-Host "Source:      $Source"
Write-Host "Destination: $Dest"
Write-Host "Split media: $($SplitMedia.IsPresent)"
Write-Host "Log:         $logFile"
Write-Host "Skipped:     $skippedFile"
Write-Host ""

$mediaFiles = @(Get-ChildItem -Path $Source -Recurse -File |
    Where-Object { $allExts -contains $_.Extension.ToLower() })

$total = $mediaFiles.Count
Write-Host "Found $total media files to process."
Write-Host ""

for ($i = 0; $i -lt $total; $i++) {
    $file = $mediaFiles[$i]
    Write-Progress -Activity "Organizing photos" `
        -Status "$($i+1)/$total : $($file.Name)" `
        -PercentComplete ([int](($i / [Math]::Max($total,1)) * 100))
    Process-File $file.FullName $logFile $skippedFile
}
Write-Progress -Activity "Organizing photos" -Completed

Write-Host ""
Write-Host "Done."
Write-Host "Log:     $logFile"
Write-Host "Skipped: $skippedFile"
