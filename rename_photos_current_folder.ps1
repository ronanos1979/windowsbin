<#
.SYNOPSIS
Renames media files in the current folder by metadata date.

.DESCRIPTION
Scans only the current directory for supported photo and video files, reads
metadata dates with exiftool, and renames files to
YYYYMMDD_HHMMSS_originalname.ext. It does not move files. Existing name conflicts
are marked with _identical or _duplicate_diff_size suffixes. CSV logs are written
in the current folder.

.PARAMETER Mode
Required. Allowed values: dry-run or rename. dry-run previews changes; rename
applies them.

.EXAMPLE
.\rename_photos_current_folder.ps1 -Mode dry-run

.EXAMPLE
.\rename_photos_current_folder.ps1 -Mode rename

.NOTES
Requires exiftool. Install with: winget install OliverBetz.ExifTool
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('dry-run','rename')]
    [string]$Mode
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

function Get-UniqueName([string]$name) {
    if (-not (Test-Path -LiteralPath $name)) { return $name }
    $ext  = [System.IO.Path]::GetExtension($name)
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($name)
    $i = 2
    while ($true) {
        $candidate = "${stem}_${i}${ext}"
        if (-not (Test-Path -LiteralPath $candidate)) { return $candidate }
        $i++
    }
}

function Resolve-NewName([string]$srcFile, [string]$targetName) {
    $srcBase = [System.IO.Path]::GetFileName($srcFile)
    if ($srcBase -eq $targetName) { return "$targetName|already_named" }
    if (-not (Test-Path -LiteralPath $targetName)) { return "$targetName|new" }

    $cmp = Compare-MediaFiles $srcFile $targetName
    if ($cmp -eq 'identical') {
        $suffixed = Add-SuffixBeforeExtension $targetName 'identical'
    } else {
        $suffixed = Add-SuffixBeforeExtension $targetName 'duplicate_diff_size'
    }
    $final = Get-UniqueName $suffixed
    return "$final|$cmp"
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
    $datetimePrefix = "${year}${month}${day}_${hour}${minute}${second}"

    $filename  = [System.IO.Path]::GetFileName($file)
    $ext       = [System.IO.Path]::GetExtension($filename).ToLower()
    $stem      = [System.IO.Path]::GetFileNameWithoutExtension($filename)
    $cleanStem = Get-SanitizedName $stem
    if (-not $cleanStem) { $cleanStem = 'file' }

    $targetName = "${datetimePrefix}_${cleanStem}${ext}"
    $resolved   = Resolve-NewName $file $targetName
    $finalName  = $resolved -replace '\|[^|]*$', ''
    $comparison = $resolved -replace '^.*\|', ''

    if ($comparison -eq 'already_named') {
        Write-Host "[SKIP] Already named: $filename"
        Add-Content -Path $logFile -Value "`"$filename`",`"$finalName`",`"$metaDate`",`"already_named`",`"$comparison`""
        return
    }

    if ($Mode -eq 'dry-run') {
        Write-Host "[DRY RUN] $filename"
        Write-Host "          -> $finalName"
        Write-Host "          comparison: $comparison"
        Add-Content -Path $logFile -Value "`"$filename`",`"$finalName`",`"$metaDate`",`"dry-run`",`"$comparison`""
        return
    }

    Rename-Item -LiteralPath $file -NewName $finalName
    Write-Host "[RENAMED] $filename -> $finalName [$comparison]"
    Add-Content -Path $logFile -Value "`"$filename`",`"$finalName`",`"$metaDate`",`"renamed`",`"$comparison`""
}

# --- Main ---

Test-ExifTool

$timestamp   = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile     = ".\rename_log_$timestamp.csv"
$skippedFile = ".\rename_skipped_$timestamp.csv"

Set-Content -Path $logFile     -Value "original_name,new_name,metadata_date,action,comparison"
Set-Content -Path $skippedFile -Value "original_name,reason"

Write-Host "Mode:     $Mode"
Write-Host "Folder:   $(Get-Location)"
Write-Host "Log:      $logFile"
Write-Host "Skipped:  $skippedFile"
Write-Host ""

$scriptName = Split-Path $PSCommandPath -Leaf
$mediaFiles = @(Get-ChildItem -Path . -File |
    Where-Object { $_.Name -ne $scriptName -and $allExts -contains $_.Extension.ToLower() })

$total = $mediaFiles.Count
Write-Host "Found $total media files in current folder."
Write-Host ""

for ($i = 0; $i -lt $total; $i++) {
    $file = $mediaFiles[$i]
    Write-Progress -Activity "Renaming photos" `
        -Status "$($i+1)/$total : $($file.Name)" `
        -PercentComplete ([int](($i / [Math]::Max($total,1)) * 100))
    Process-File $file.FullName $logFile $skippedFile
}
Write-Progress -Activity "Renaming photos" -Completed

Write-Host ""
Write-Host "Done."
Write-Host "Log:     $logFile"
Write-Host "Skipped: $skippedFile"
