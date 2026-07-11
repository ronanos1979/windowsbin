<#
Find duplicate media files. Two detection strategies:
  1. Exact duplicates  - same MD5 hash (content identical, any size)
  2. Same-name copies  - same filename in multiple locations but different sizes;
                         the largest version is kept, smaller copies are removed.

For every duplicate set the LARGEST file is kept. If sizes are equal the
oldest file (earliest CreationTime) is kept.

Usage (no -File flag needed):
  powershell c:\tools\bin\find_duplicate_media.ps1 -Root F:\Photos
  powershell c:\tools\bin\find_duplicate_media.ps1 -Root F:\Photos -MoveTo F:\Dupes
  powershell c:\tools\bin\find_duplicate_media.ps1 -Root F:\Photos -Delete

Default (no -MoveTo or -Delete): scan and report only, nothing is moved or deleted.
#>

# No param() block: $args receives all arguments whether or not -File is used.
$Root   = '.'
$MoveTo = ''
$Delete = $false

$i = 0
while ($i -lt $args.Count) {
    $key = ($args[$i] -replace '^[-/]+', '').ToLower()
    switch ($key) {
        'root'   { $i++; $Root   = $args[$i] }
        'moveto' { $i++; $MoveTo = $args[$i] }
        'delete' { $Delete = $true }
    }
    $i++
}

if ($Delete -and $MoveTo) {
    Write-Host "ERROR: -Delete and -MoveTo cannot be used together."
    exit 1
}

$mediaExts = @(
    '.jpg', '.jpeg', '.jpe', '.png', '.gif', '.bmp',
    '.tif', '.tiff', '.webp', '.heic', '.heif',
    '.raw', '.dng', '.cr2', '.nef', '.arw', '.orf', '.rw2',
    '.mov', '.mp4', '.m4v', '.avi', '.mkv', '.wmv',
    '.mpg', '.mpeg', '.3gp', '.mts', '.m2ts',
    '.mp3', '.m4a', '.aac', '.wav', '.flac', '.aiff', '.aif'
)

Write-Host "Scanning: $Root"
if ($MoveTo) { Write-Host "Move duplicates to: $MoveTo" }
if ($Delete) { Write-Host "Action: DELETE duplicates" }
if (-not $MoveTo -and -not $Delete) { Write-Host "Mode: REPORT ONLY (pass -MoveTo or -Delete to act)" }
Write-Host ""

# -----------------------------------------------------------------------
# 1. Collect all non-zero media files
# -----------------------------------------------------------------------
Write-Host "Collecting files..."
$allFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
$found = 0
Get-ChildItem -Path $Root -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.Length -gt 0 -and $mediaExts -contains $_.Extension.ToLower()) {
        $allFiles.Add($_)
        $found++
        if ($found % 10000 -eq 0) { Write-Host "  $found files collected..." }
    }
}
Write-Host "Total non-zero media files: $($allFiles.Count)"
Write-Host ""

# Tracks which paths are already marked for removal so we don't double-report.
$markedForRemoval = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase)

# Final list of (keeper, remove, reason) records.
$report = [System.Collections.Generic.List[PSCustomObject]]::new()

# -----------------------------------------------------------------------
# Helper: given a group of FileInfo objects, keep the largest (ties broken
# by earliest CreationTime), add the rest to $report.
# -----------------------------------------------------------------------
function Add-Duplicates {
    param(
        [System.IO.FileInfo[]]$Group,
        [string]$Reason
    )
    $sorted = $Group | Sort-Object -Property @{E='Length';D=$true}, @{E='CreationTime';D=$false}
    $keeper = $sorted[0]
    for ($j = 1; $j -lt $sorted.Count; $j++) {
        $dup = $sorted[$j]
        if ($script:markedForRemoval.Contains($dup.FullName)) { continue }
        $script:markedForRemoval.Add($dup.FullName) | Out-Null
        $script:report.Add([PSCustomObject]@{
            Reason        = $Reason
            KeeperPath    = $keeper.FullName
            KeeperSizeKB  = [Math]::Round($keeper.Length / 1KB, 1)
            DupePath      = $dup.FullName
            DupeSizeKB    = [Math]::Round($dup.Length / 1KB, 1)
        })
    }
}

# -----------------------------------------------------------------------
# 2. Strategy A - Exact hash duplicates
#    Pre-filter: only hash files whose size is shared by at least one other
#    file. Files with a unique size cannot be exact duplicates.
# -----------------------------------------------------------------------
Write-Host "Step 1: Finding exact duplicates (hash-based)..."
$sizeGroups = $allFiles | Group-Object -Property Length | Where-Object { $_.Count -gt 1 }
$hashCandidates = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
foreach ($sg in $sizeGroups) { foreach ($f in $sg.Group) { $hashCandidates.Add($f) } }
Write-Host "  $($hashCandidates.Count) files share a size with at least one other file."

$hashMap = @{}
$n = 0
$total = $hashCandidates.Count
foreach ($f in $hashCandidates) {
    $n++
    if ($n % 1000 -eq 0) { Write-Host "  Hashing $n / $total..." }
    try {
        $h = (Get-FileHash -LiteralPath $f.FullName -Algorithm MD5 -ErrorAction Stop).Hash
        if (-not $hashMap.ContainsKey($h)) {
            $hashMap[$h] = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
        }
        $hashMap[$h].Add($f)
    } catch {
        Write-Host "  Cannot hash (skipping): $($f.FullName)"
    }
}

$exactDupeGroups = 0
foreach ($kvp in $hashMap.GetEnumerator()) {
    if ($kvp.Value.Count -lt 2) { continue }
    $exactDupeGroups++
    Add-Duplicates -Group $kvp.Value.ToArray() -Reason 'ExactDuplicate'
}
Write-Host "  Exact duplicate groups: $exactDupeGroups  (files to remove: $($report.Count))"
Write-Host ""

# -----------------------------------------------------------------------
# 3. Strategy B - Same filename, different size
#    Groups all files by case-insensitive name. Within each group, keeps
#    the largest; smaller copies are duplicates.
# -----------------------------------------------------------------------
Write-Host "Step 2: Finding same-name files with different sizes..."
$nameMap = @{}
foreach ($f in $allFiles) {
    $key = $f.Name.ToLower()
    if (-not $nameMap.ContainsKey($key)) {
        $nameMap[$key] = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    }
    $nameMap[$key].Add($f)
}

$countBefore = $report.Count
foreach ($kvp in $nameMap.GetEnumerator()) {
    $group = $kvp.Value
    if ($group.Count -lt 2) { continue }
    Add-Duplicates -Group $group.ToArray() -Reason 'SameNameSmallerCopy'
}
$nameDupes = $report.Count - $countBefore
Write-Host "  Same-name smaller copies: $nameDupes"
Write-Host ""

# -----------------------------------------------------------------------
# 4. Write report
# -----------------------------------------------------------------------
$timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$reportFile = "duplicate_media_$timestamp.csv"
$report | Export-Csv -Path $reportFile -NoTypeInformation -Encoding UTF8

Write-Host "Total duplicates found: $($report.Count)"
Write-Host "Report saved to: $reportFile"
Write-Host ""

if ($report.Count -eq 0) {
    Write-Host "No duplicates found."
    exit 0
}

if (-not $MoveTo -and -not $Delete) {
    Write-Host "Review $reportFile then re-run with -MoveTo <path> or -Delete to act."
    exit 0
}

# -----------------------------------------------------------------------
# 5. Move or delete
# -----------------------------------------------------------------------
if ($MoveTo) {
    $absRoot = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\', '/')
    $absDest = [System.IO.Path]::GetFullPath($MoveTo)
    Write-Host "Moving $($report.Count) duplicate(s) to: $absDest"
    $moved = 0
    $failed = 0
    foreach ($item in $report) {
        $srcPath = $item.DupePath
        if (-not (Test-Path -LiteralPath $srcPath)) {
            Write-Host "  SKIP (already gone): $srcPath"
            continue
        }
        $rel      = $srcPath.Substring($absRoot.Length).TrimStart('\', '/')
        $destPath = Join-Path $absDest $rel
        $destDir  = Split-Path $destPath -Parent
        try {
            if (-not (Test-Path $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }
            Move-Item -LiteralPath $srcPath -Destination $destPath -Force
            $moved++
            if ($moved % 1000 -eq 0) { Write-Host "  Moved $moved..." }
        } catch {
            Write-Host "  WARN: Could not move $srcPath : $_"
            $failed++
        }
    }
    Write-Host "Done. Moved: $moved  Failed: $failed"
}

if ($Delete) {
    Write-Host "Deleting $($report.Count) duplicate(s)..."
    $deleted = 0
    $failed  = 0
    foreach ($item in $report) {
        $srcPath = $item.DupePath
        if (-not (Test-Path -LiteralPath $srcPath)) {
            Write-Host "  SKIP (already gone): $srcPath"
            continue
        }
        try {
            Remove-Item -LiteralPath $srcPath -Force
            $deleted++
            if ($deleted % 1000 -eq 0) { Write-Host "  Deleted $deleted..." }
        } catch {
            Write-Host "  WARN: Could not delete $srcPath : $_"
            $failed++
        }
    }
    Write-Host "Done. Deleted: $deleted  Failed: $failed"
}
