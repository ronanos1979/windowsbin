<#
Find duplicate media files by content.

Two files are duplicates only if they share BOTH the same MD5 hash AND the
same file size. Same filename alone is NOT sufficient — there are many files
with the same name that are legitimately different.

Always writes two output files:
  1. A full inventory CSV  (every file: path, size, hash) — for manual review.
  2. A duplicates report CSV (keeper + dupe pairs) — for acting on.

Usage (no -File flag needed):
  powershell c:\tools\bin\find_duplicate_media.ps1 -Root F:\Photos
  powershell c:\tools\bin\find_duplicate_media.ps1 -Root F:\Photos -MoveTo F:\Dupes
  powershell c:\tools\bin\find_duplicate_media.ps1 -Root F:\Photos -Delete

Default (no -MoveTo or -Delete): scan and report only, nothing is moved or deleted.
#>

# No param() block: $args receives all arguments whether or not -File is used.
$Root      = '.'
$MoveTo    = ''
$Delete    = $false
$Help      = $false
$CacheFile = ''

$i = 0
while ($i -lt $args.Count) {
    $key = ($args[$i] -replace '^[-/]+', '').ToLower()
    switch ($key) {
        'root' {
            if ($i + 1 -ge $args.Count) { Write-Host "ERROR: -Root requires a value."; exit 1 }
            $i++; $Root = $args[$i]
        }
        'moveto' {
            if ($i + 1 -ge $args.Count) { Write-Host "ERROR: -MoveTo requires a value."; exit 1 }
            $i++; $MoveTo = $args[$i]
        }
        'cachefile' {
            if ($i + 1 -ge $args.Count) { Write-Host "ERROR: -CacheFile requires a value."; exit 1 }
            $i++; $CacheFile = $args[$i]
        }
        'delete'    { $Delete = $true }
        { $_ -in 'help','h','?' } { $Help = $true }
    }
    $i++
}

if ($Help -or $args.Count -eq 0) {
    Write-Host ""
    Write-Host "find_duplicate_media.ps1"
    Write-Host "------------------------"
    Write-Host "Scans a folder tree for duplicate media files."
    Write-Host ""
    Write-Host "Two files are considered duplicates only when they share BOTH:"
    Write-Host "  - the same MD5 hash  (identical content)"
    Write-Host "  - the same file size"
    Write-Host ""
    Write-Host "Files with the same name but different content are NOT duplicates."
    Write-Host ""
    Write-Host "Always writes two CSVs before taking any action:"
    Write-Host "  inventory_*.csv   - every scanned file with its name, path, size, and hash"
    Write-Host "  duplicates_*.csv  - keeper/dupe pairs for files confirmed as duplicates"
    Write-Host ""
    Write-Host "In each duplicate set the LARGEST file is kept. If sizes are equal"
    Write-Host "the oldest file (earliest creation time) is kept."
    Write-Host ""
    Write-Host "USAGE"
    Write-Host "  powershell c:\tools\bin\find_duplicate_media.ps1 -Root <path> [options]"
    Write-Host ""
    Write-Host "PARAMETERS"
    Write-Host "  -Root <path>        Folder to scan. Defaults to current directory."
    Write-Host "  -MoveTo <path>      Move duplicates here, preserving folder structure."
    Write-Host "                      The files you are KEEPING stay in -Root."
    Write-Host "  -Delete             Permanently delete all duplicates."
    Write-Host "  -CacheFile <path>   Path to hash cache file. Speeds up repeat scans by"
    Write-Host "                      reusing MD5 hashes for unchanged files. Defaults to"
    Write-Host "                      _media_hash_cache.json inside -Root."
    Write-Host "  -Help               Show this help message."
    Write-Host ""
    Write-Host "NOTES"
    Write-Host "  -MoveTo and -Delete cannot be used together."
    Write-Host "  Without -MoveTo or -Delete the script reports only - nothing is changed."
    Write-Host "  Recommended workflow: run report first, review both CSVs, then re-run"
    Write-Host "  with -MoveTo so you can verify before any permanent deletion."
    Write-Host "  Supported types: jpg jpeg png gif bmp tif webp heic raw dng cr2 nef arw"
    Write-Host "                   mov mp4 avi mkv wmv mpg 3gp mts mp3 m4a wav flac aiff"
    Write-Host ""
    Write-Host "INVENTORY CSV COLUMNS"
    Write-Host "  FileName    - file name only (no path)"
    Write-Host "  FullPath    - absolute path"
    Write-Host "  SizeBytes   - file size in bytes"
    Write-Host "  MD5Hash     - MD5 hash of file contents"
    Write-Host ""
    Write-Host "DUPLICATES CSV COLUMNS"
    Write-Host "  KeeperPath    - File that will be kept"
    Write-Host "  KeeperSizeKB  - Size of kept file in KB"
    Write-Host "  DupePath      - File that is a confirmed duplicate"
    Write-Host "  DupeSizeKB    - Size of duplicate file in KB"
    Write-Host "  MD5Hash       - Shared hash (proof of identical content)"
    Write-Host ""
    Write-Host "EXAMPLES"
    Write-Host "  # Report only - see what would be removed"
    Write-Host "  powershell c:\tools\bin\find_duplicate_media.ps1 -Root F:\Photos"
    Write-Host ""
    Write-Host "  # Move duplicates to a separate folder (safe - reversible)"
    Write-Host "  powershell c:\tools\bin\find_duplicate_media.ps1 -Root F:\Photos -MoveTo F:\Dupes"
    Write-Host ""
    Write-Host "  # Delete duplicates permanently"
    Write-Host "  powershell c:\tools\bin\find_duplicate_media.ps1 -Root F:\Photos -Delete"
    Write-Host ""
    exit 0
}

if ($Delete -and $MoveTo) {
    Write-Host "ERROR: -Delete and -MoveTo cannot be used together."
    exit 1
}

# Bug 3: validate -Root before doing anything
if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
    Write-Host "ERROR: -Root path does not exist or is not a directory: $Root"
    exit 1
}
$Root = (Resolve-Path -LiteralPath $Root).Path

# Bug 2: reject -MoveTo that is inside -Root (would re-scan moved files on future runs)
if ($MoveTo) {
    $MoveTo = [System.IO.Path]::GetFullPath($MoveTo)
    $rootWithSep = $Root.TrimEnd('\', '/') + '\'
    if ($MoveTo.Equals($Root.TrimEnd('\', '/'), [System.StringComparison]::OrdinalIgnoreCase) -or
        $MoveTo.StartsWith($rootWithSep, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Host "ERROR: -MoveTo cannot be inside -Root."
        Write-Host "       -Root:   $Root"
        Write-Host "       -MoveTo: $MoveTo"
        Write-Host "       Choose a destination outside of -Root so moved files are not re-scanned."
        exit 1
    }
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
Get-ChildItem -LiteralPath $Root -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.Length -gt 0 -and $mediaExts -contains $_.Extension.ToLower()) {
        $allFiles.Add($_)
        $found++
        if ($found % 10000 -eq 0) { Write-Host "  $found files collected..." }
    }
}
Write-Host "Total non-zero media files: $($allFiles.Count)"
Write-Host ""

# -----------------------------------------------------------------------
# 2. Hash every file (with cache for speed on repeat runs)
# -----------------------------------------------------------------------
Write-Host "Hashing all files (this may take a while for large collections)..."

$resolvedCacheFile = if ($CacheFile) { $CacheFile } else { Join-Path $Root '_media_hash_cache.json' }
$hashCache = @{}
if (Test-Path -LiteralPath $resolvedCacheFile) {
    try {
        $raw = Get-Content -LiteralPath $resolvedCacheFile -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($prop in $raw.PSObject.Properties) { $hashCache[$prop.Name] = $prop.Value }
        Write-Host "  Loaded $($hashCache.Count) cached hash(es) from: $resolvedCacheFile"
    } catch {
        Write-Host "  Warning: could not load hash cache: $_"
    }
}

# fileRecords holds the full inventory: file + its hash.
$fileRecords = [System.Collections.Generic.List[PSCustomObject]]::new()

$n = 0
$total = $allFiles.Count
$cacheHits = 0
foreach ($f in $allFiles) {
    $n++
    if ($n % 1000 -eq 0) { Write-Host "  Hashing $n / $total..." }
    try {
        $entry = $hashCache[$f.FullName]
        if ($entry -and [long]$entry.Size -eq $f.Length -and [long]$entry.Mtime -eq $f.LastWriteTime.Ticks) {
            $h = $entry.Hash
            $cacheHits++
        } else {
            $h = (Get-FileHash -LiteralPath $f.FullName -Algorithm MD5 -ErrorAction Stop).Hash
            $hashCache[$f.FullName] = [PSCustomObject]@{ Size = $f.Length; Mtime = $f.LastWriteTime.Ticks; Hash = $h }
        }
        $fileRecords.Add([PSCustomObject]@{
            FileInfo = $f
            Hash     = $h
        })
    } catch {
        Write-Host "  Cannot hash (skipping): $($f.FullName)"
    }
}
Write-Host "  Cache hits: $cacheHits / $total  ($($total - $cacheHits) hashed fresh)"
Write-Host "  Saving hash cache ($($hashCache.Count) entries) to: $resolvedCacheFile"
try {
    $hashCache | ConvertTo-Json -Compress | Set-Content -LiteralPath $resolvedCacheFile -Encoding UTF8
} catch {
    Write-Host "  Warning: could not save hash cache: $_"
}
Write-Host ""

# -----------------------------------------------------------------------
# 3. Write full inventory CSV  (every file: name, path, size, hash)
# -----------------------------------------------------------------------
$timestamp     = Get-Date -Format "yyyyMMdd_HHmmss"
$outDir        = (Get-Location).Path
$inventoryFile = Join-Path $outDir "inventory_$timestamp.csv"

$inventoryRows = $fileRecords | ForEach-Object {
    [PSCustomObject]@{
        FileName  = $_.FileInfo.Name
        FullPath  = $_.FileInfo.FullName
        SizeBytes = $_.FileInfo.Length
        MD5Hash   = $_.Hash
    }
}
$inventoryRows | Export-Csv -LiteralPath $inventoryFile -NoTypeInformation -Encoding UTF8
Write-Host "Full inventory written to: $inventoryFile  ($($fileRecords.Count) files)"
Write-Host ""

# -----------------------------------------------------------------------
# 4. Find duplicates: same MD5 hash AND same size
#    (Same name alone is NOT a criterion.)
# -----------------------------------------------------------------------
Write-Host "Finding duplicates (same hash + same size)..."

# Key = "HASH|SIZE"  so a hash collision between different-size files is not flagged.
$dupeMap = @{}
foreach ($rec in $fileRecords) {
    $key = "$($rec.Hash)|$($rec.FileInfo.Length)"
    if (-not $dupeMap.ContainsKey($key)) {
        $dupeMap[$key] = [System.Collections.Generic.List[PSCustomObject]]::new()
    }
    $dupeMap[$key].Add($rec)
}

$report = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($kvp in $dupeMap.GetEnumerator()) {
    $group = $kvp.Value
    if ($group.Count -lt 2) { continue }

    # Keep the largest file; ties broken by earliest CreationTime.
    $sorted = $group | Sort-Object -Property @{E={ $_.FileInfo.Length };D=$true},
                                             @{E={ $_.FileInfo.CreationTime };D=$false}
    $keeper = $sorted[0]
    for ($j = 1; $j -lt $sorted.Count; $j++) {
        $dup = $sorted[$j]
        $report.Add([PSCustomObject]@{
            KeeperPath   = $keeper.FileInfo.FullName
            KeeperSizeKB = [Math]::Round($keeper.FileInfo.Length / 1KB, 1)
            DupePath     = $dup.FileInfo.FullName
            DupeSizeKB   = [Math]::Round($dup.FileInfo.Length / 1KB, 1)
            MD5Hash      = $keeper.Hash
        })
    }
}

$dupeFile = Join-Path $outDir "duplicates_$timestamp.csv"
$report | Export-Csv -LiteralPath $dupeFile -NoTypeInformation -Encoding UTF8

Write-Host "Total confirmed duplicates: $($report.Count)"
Write-Host "Duplicates report saved to: $dupeFile"
Write-Host ""

if ($report.Count -eq 0) {
    Write-Host "No duplicates found."
    exit 0
}

if (-not $MoveTo -and -not $Delete) {
    Write-Host "Review $inventoryFile and $dupeFile"
    Write-Host "Then re-run with -MoveTo <path> or -Delete to act on the duplicates."
    exit 0
}

# -----------------------------------------------------------------------
# 5. Move or delete
# -----------------------------------------------------------------------
if ($MoveTo) {
    $absRoot = $Root.TrimEnd('\', '/')   # already resolved at startup
    $absDest = $MoveTo                   # already resolved at startup
    Write-Host "Moving $($report.Count) duplicate(s) to: $absDest"
    $moved = 0
    $failed = 0
    foreach ($item in $report) {
        $srcPath = $item.DupePath
        if (-not (Test-Path -LiteralPath $srcPath)) {
            Write-Host "  SKIP (already gone): $srcPath"
            continue
        }
        # Bug 5: guard against symlinks/junctions that resolve outside -Root
        if (-not $srcPath.StartsWith($absRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Host "  WARN: $srcPath is not under $absRoot (symlink or junction?), skipping"
            $failed++
            continue
        }
        $rel      = $srcPath.Substring($absRoot.Length).TrimStart('\', '/')
        $destPath = Join-Path $absDest $rel
        $destDir  = Split-Path $destPath -Parent
        if (Test-Path -LiteralPath $destPath) {
            Write-Host "  WARN: Destination already exists, skipping to avoid overwrite: $destPath"
            $failed++
            continue
        }
        try {
            if (-not (Test-Path -LiteralPath $destDir)) {
                New-Item -ItemType Directory -LiteralPath $destDir -Force | Out-Null
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
    if ($failed -gt 0) { exit 1 }
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
    if ($failed -gt 0) { exit 1 }
}
