<#
Scan all files under a path and write a CSV with MD5 hashes and file metadata,
suitable for importing into a PostgreSQL database for duplicate detection.

Usage:
  powershell c:\tools\bin\scan_drive_md5.ps1 -Root F:\
  powershell c:\tools\bin\scan_drive_md5.ps1 -Root F:\ -Out F:\scan.csv -Label "Seagate 4TB"
  powershell c:\tools\bin\scan_drive_md5.ps1 -Root F:\ -CacheFile F:\hash_cache.json
#>

$Root      = ''
$Out       = ''
$Label     = ''
$CacheFile = ''
$Help      = $false

$i = 0
while ($i -lt $args.Count) {
    $key = ($args[$i] -replace '^[-/]+', '').ToLower()
    switch ($key) {
        'root' {
            if ($i + 1 -ge $args.Count) { Write-Host "ERROR: -Root requires a value."; exit 1 }
            $i++; $Root = $args[$i]
        }
        'out' {
            if ($i + 1 -ge $args.Count) { Write-Host "ERROR: -Out requires a value."; exit 1 }
            $i++; $Out = $args[$i]
        }
        'label' {
            if ($i + 1 -ge $args.Count) { Write-Host "ERROR: -Label requires a value."; exit 1 }
            $i++; $Label = $args[$i]
        }
        'cachefile' {
            if ($i + 1 -ge $args.Count) { Write-Host "ERROR: -CacheFile requires a value."; exit 1 }
            $i++; $CacheFile = $args[$i]
        }
        { $_ -in 'help','h','?' } { $Help = $true }
    }
    $i++
}

if ($Help -or $args.Count -eq 0) {
    Write-Host ""
    Write-Host "scan_drive_md5.ps1"
    Write-Host "------------------"
    Write-Host "Scans all files under a path and writes a CSV with MD5 hashes and"
    Write-Host "file metadata for import into a PostgreSQL database."
    Write-Host ""
    Write-Host "USAGE"
    Write-Host "  powershell c:\tools\bin\scan_drive_md5.ps1 -Root <path> [options]"
    Write-Host ""
    Write-Host "PARAMETERS"
    Write-Host "  -Root <path>        Path to scan (drive or folder). Required."
    Write-Host "  -Out <path>         Output CSV file path."
    Write-Host "                      Defaults to scan_<label>_<timestamp>.csv in current dir."
    Write-Host "  -Label <text>       Human-readable label stored in every row (e.g. 'Seagate 4TB')."
    Write-Host "                      Defaults to the drive letter or root folder name."
    Write-Host "  -CacheFile <path>   Path to hash cache file. Speeds up repeat scans by"
    Write-Host "                      reusing MD5 hashes for unchanged files."
    Write-Host "                      Defaults to _md5_cache.json inside -Root."
    Write-Host "  -Help               Show this help message."
    Write-Host ""
    Write-Host "OUTPUT CSV COLUMNS"
    Write-Host "  ScanLabel         - label you supplied (or default) to identify the scan"
    Write-Host "  ScannedAt         - ISO 8601 timestamp when this scan was run"
    Write-Host "  FullPath          - absolute path to the file"
    Write-Host "  FileName          - file name with extension"
    Write-Host "  FileExtension     - lower-cased extension including dot (e.g. .jpg)"
    Write-Host "  ParentDirectory   - folder containing the file"
    Write-Host "  DriveOrVolume     - drive letter or UNC server name"
    Write-Host "  FileSizeBytes     - file size in bytes"
    Write-Host "  MD5Hash           - MD5 hex digest of file contents"
    Write-Host "  FileCreatedAt     - file creation timestamp (local time)"
    Write-Host "  FileModifiedAt    - last-write timestamp (local time)"
    Write-Host "  IsHidden          - true/false"
    Write-Host "  IsReadOnly        - true/false"
    Write-Host ""
    Write-Host "IMPORT INTO POSTGRESQL"
    Write-Host "  Run create_file_inventory.sql to create the table, then:"
    Write-Host "  \COPY file_inventory FROM 'scan.csv' WITH (FORMAT CSV, HEADER TRUE, ENCODING 'UTF8');"
    Write-Host ""
    Write-Host "EXAMPLES"
    Write-Host "  # Scan an entire drive"
    Write-Host "  powershell c:\tools\bin\scan_drive_md5.ps1 -Root F:\"
    Write-Host ""
    Write-Host "  # Scan with a friendly label and fixed output path"
    Write-Host "  powershell c:\tools\bin\scan_drive_md5.ps1 -Root F:\ -Label ""Seagate 4TB"" -Out F:\scan.csv"
    Write-Host ""
    Write-Host "  # Re-scan quickly using cached hashes from last run"
    Write-Host "  powershell c:\tools\bin\scan_drive_md5.ps1 -Root F:\ -CacheFile F:\hash_cache.json"
    Write-Host ""
    exit 0
}

if (-not $Root) {
    Write-Host "ERROR: -Root is required. Run with -Help for usage."
    exit 1
}

if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
    Write-Host "ERROR: -Root path does not exist or is not a directory: $Root"
    exit 1
}
$Root = (Resolve-Path -LiteralPath $Root).Path

# Default label = drive letter (e.g. "F:") or last folder name
if (-not $Label) {
    $driveRoot = [System.IO.Path]::GetPathRoot($Root)
    if ($driveRoot -and $driveRoot.TrimEnd('\') -eq $Root.TrimEnd('\')) {
        $Label = $driveRoot.TrimEnd('\')
    } else {
        $Label = Split-Path $Root -Leaf
    }
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$scannedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

if (-not $Out) {
    $safeName = $Label -replace '[\\/:*?"<>|]', '_'
    $Out = Join-Path (Get-Location).Path "scan_${safeName}_${timestamp}.csv"
}

$resolvedCacheFile = if ($CacheFile) { $CacheFile } else { Join-Path $Root '_md5_cache.json' }

# Derive drive/volume from root
$driveOrVolume = [System.IO.Path]::GetPathRoot($Root).TrimEnd('\')
if ($driveOrVolume -match '^\\\\([^\\]+)') { $driveOrVolume = $Matches[1] }  # UNC: extract server name

Write-Host "Scanning:     $Root"
Write-Host "Scan label:   $Label"
Write-Host "Drive/volume: $driveOrVolume"
Write-Host "Output CSV:   $Out"
Write-Host "Cache file:   $resolvedCacheFile"
Write-Host ""

# -----------------------------------------------------------------------
# 1. Load hash cache
# -----------------------------------------------------------------------
$hashCache = @{}
if (Test-Path -LiteralPath $resolvedCacheFile) {
    try {
        $raw = Get-Content -LiteralPath $resolvedCacheFile -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($prop in $raw.PSObject.Properties) { $hashCache[$prop.Name] = $prop.Value }
        Write-Host "Loaded $($hashCache.Count) cached hash(es) from: $resolvedCacheFile"
    } catch {
        Write-Host "Warning: could not load hash cache: $_"
    }
}

# -----------------------------------------------------------------------
# 2. Collect and hash all files
# -----------------------------------------------------------------------
Write-Host "Collecting files..."

$allFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
$found = 0
Get-ChildItem -LiteralPath $Root -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
    $allFiles.Add($_)
    $found++
    if ($found % 10000 -eq 0) { Write-Host "  $found files found..." }
}
Write-Host "Total files: $($allFiles.Count)"
Write-Host ""
Write-Host "Hashing files (this may take a while for large drives)..."

$rows       = [System.Collections.Generic.List[PSCustomObject]]::new()
$n          = 0
$total      = $allFiles.Count
$cacheHits  = 0
$skipped    = 0

foreach ($f in $allFiles) {
    $n++
    if ($n % 1000 -eq 0) { Write-Host "  $n / $total  (cache hits: $cacheHits  skipped: $skipped)..." }

    # Zero-byte files: hash is always the MD5 of empty input (d41d8cd98f00b204e9800998ecf8427e).
    # We record them but skip actual hashing.
    if ($f.Length -eq 0) {
        $h = 'd41d8cd98f00b204e9800998ecf8427e'
    } else {
        try {
            $entry = $hashCache[$f.FullName]
            if ($entry -and [long]$entry.Size -eq $f.Length -and [long]$entry.Mtime -eq $f.LastWriteTime.Ticks) {
                $h = $entry.Hash
                $cacheHits++
            } else {
                $h = (Get-FileHash -LiteralPath $f.FullName -Algorithm MD5 -ErrorAction Stop).Hash.ToLower()
                $hashCache[$f.FullName] = [PSCustomObject]@{
                    Size  = $f.Length
                    Mtime = $f.LastWriteTime.Ticks
                    Hash  = $h
                }
            }
        } catch {
            Write-Host "  WARN: cannot hash (skipping): $($f.FullName)"
            $skipped++
            continue
        }
    }

    $hidden   = ($f.Attributes -band [System.IO.FileAttributes]::Hidden)   -gt 0
    $readOnly = ($f.Attributes -band [System.IO.FileAttributes]::ReadOnly) -gt 0

    $rows.Add([PSCustomObject]@{
        ScanLabel       = $Label
        ScannedAt       = $scannedAt
        FullPath        = $f.FullName
        FileName        = $f.Name
        FileExtension   = $f.Extension.ToLower()
        ParentDirectory = $f.DirectoryName
        DriveOrVolume   = $driveOrVolume
        FileSizeBytes   = $f.Length
        MD5Hash         = $h
        FileCreatedAt   = $f.CreationTime.ToString("yyyy-MM-dd HH:mm:ss")
        FileModifiedAt  = $f.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
        IsHidden        = $hidden.ToString().ToLower()
        IsReadOnly      = $readOnly.ToString().ToLower()
    })
}

Write-Host "  Hashing complete. Cache hits: $cacheHits  Fresh hashes: $($n - $cacheHits - $skipped)  Skipped: $skipped"
Write-Host ""

# -----------------------------------------------------------------------
# 3. Save hash cache
# -----------------------------------------------------------------------
Write-Host "Saving hash cache ($($hashCache.Count) entries) to: $resolvedCacheFile"
try {
    $hashCache | ConvertTo-Json -Compress | Set-Content -LiteralPath $resolvedCacheFile -Encoding UTF8
} catch {
    Write-Host "Warning: could not save hash cache: $_"
}

# -----------------------------------------------------------------------
# 4. Write CSV
# -----------------------------------------------------------------------
Write-Host "Writing CSV ($($rows.Count) rows) to: $Out"
$rows | Export-Csv -LiteralPath $Out -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host "Done."
Write-Host "  Files scanned:  $($rows.Count)"
Write-Host "  Files skipped:  $skipped"
Write-Host "  Output:         $Out"
Write-Host ""
Write-Host "To import into PostgreSQL:"
Write-Host "  psql -d <dbname> -c ""\COPY file_inventory FROM '$Out' WITH (FORMAT CSV, HEADER TRUE, ENCODING 'UTF8')"""
