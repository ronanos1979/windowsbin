<#
Reads the file_inventory PostgreSQL table (populated by scan_drive_md5.ps1) and
moves files from F:\SortOutAll into F:\movedoutwithdupsoutsidefinalnewsetup,
preserving the full directory structure under F:\.

Four classes of file are moved:
  1. Cross-tree duplicates: files in F:\SortOutAll that have an identical copy
     (same MD5 hash AND same file size) anywhere under F:\20220422.
  2. Within-SortOutAll duplicates: where multiple copies of the same file exist
     entirely inside F:\SortOutAll. The alphabetically-first path is kept; all
     others are moved.
  3. Files named "*identical*" inside F:\20220422 that have a duplicate with a
     normal name in the same tree. The non-identical copy is kept.
  4. Same-directory duplicates anywhere on the drive: within each folder, files
     with identical content keep the alphabetically-first name; all others move.

Usage:
  powershell c:\tools\bin\move_sortoutall_dups.ps1 -DbName mydb
  powershell c:\tools\bin\move_sortoutall_dups.ps1 -DbName mydb -WhatIf
  powershell c:\tools\bin\move_sortoutall_dups.ps1 -DbName mydb -DbUser myuser -PsqlPath "C:\Program Files\PostgreSQL\17\bin\psql.exe"
#>

$DbName   = ''
$DbUser   = 'postgres'
$PsqlPath = 'psql'
$WhatIf   = $false
$Help     = $false

$i = 0
while ($i -lt $args.Count) {
    $key = ($args[$i] -replace '^[-/]+', '').ToLower()
    switch ($key) {
        'dbname'   { if ($i + 1 -lt $args.Count) { $i++; $DbName   = $args[$i] } }
        'dbuser'   { if ($i + 1 -lt $args.Count) { $i++; $DbUser   = $args[$i] } }
        'psqlpath' { if ($i + 1 -lt $args.Count) { $i++; $PsqlPath = $args[$i] } }
        'whatif'   { $WhatIf = $true }
        { $_ -in 'help','h','?' } { $Help = $true }
    }
    $i++
}

if ($Help -or -not $DbName) {
    Write-Host @'

move_sortoutall_dups.ps1
------------------------
Moves files from F:\SortOutAll to F:\movedoutwithdupsoutsidefinalnewsetup,
preserving the full directory structure under F:\.

Four classes of file are moved:
  1. Cross-tree: files in F:\SortOutAll that have an identical copy (same MD5
     + size) anywhere under F:\20220422.
  2. Within-SortOutAll: files duplicated entirely inside F:\SortOutAll. The
     alphabetically-first copy is kept; all others are moved.
  3. Named "*identical*" inside F:\20220422: moved when a non-identical copy
     with the same MD5 + size exists in the same tree.
  4. Same-directory duplicates anywhere on the drive: alphabetically-first
     filename is kept, all others are moved.
  5. Date-folder copies when an album-folder original exists: the copy in a
     YYYY-MM-DD date folder is moved; the copy in a named album is kept.
  6. Pictures date-folder copy + Videos copy: move the Pictures copy.
  7. Videos copy + Pictures named album copy: move the Videos copy.
  5. Date-folder copies that have an album-folder original: if the same file
     exists under a named album (e.g. Pictures\2017\Christmas) AND under a
     date folder (e.g. Pictures\2017\06-June\2017-06-15), the date-folder
     copy is moved and the album copy is kept.
  6. Pictures date-folder copy that also exists in a Videos folder: move the
     Pictures copy, keep the Videos copy.
  7. Videos copy that also exists in a Pictures named album: move the Videos
     copy, keep the Pictures album copy.

USAGE
  powershell c:\tools\bin\move_sortoutall_dups.ps1 -DbName <name> [options]

PARAMETERS
  -DbName <name>     PostgreSQL database name. Required.
  -DbUser <name>     PostgreSQL user. Default: postgres
  -PsqlPath <path>   Path to psql.exe if not in PATH. Default: psql
  -WhatIf            Preview what would be moved without moving anything.
  -Help              Show this help message.

EXAMPLES
  # Dry run
  powershell c:\tools\bin\move_sortoutall_dups.ps1 -DbName filedb -WhatIf

  # Move the files
  powershell c:\tools\bin\move_sortoutall_dups.ps1 -DbName filedb

'@
    if (-not $DbName -and -not $Help) { Write-Host 'ERROR: -DbName is required.' }
    exit $(if ($Help) { 0 } else { 1 })
}

$SourcePrefix = 'F:\SortOutAll'
$OrigPrefix   = 'F:\20220422'
$DestRoot     = 'F:\movedoutwithdupsoutsidefinalnewsetup'

function Get-LongPath($p) {
    if ($p.Length -ge 260 -and $p -match '^[A-Za-z]:\\') { '\\?\' + $p } else { $p }
}

# Write the SQL to a temp file to avoid command-line quoting issues
$tempSql = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), '.sql')
$sourceLower = $SourcePrefix.ToLower() -replace '\\', '\\'
$origLower   = $OrigPrefix.ToLower()   -replace '\\', '\\'
$driveLower  = ($DestRoot[0].ToString().ToLower()) + ':\\'
$sql = @"
-- Case 1: cross-tree duplicates (copy in F:\20220422 is the original)
SELECT DISTINCT s.full_path
FROM file_inventory s
WHERE lower(s.full_path) LIKE '$sourceLower%'
  AND s.file_size_bytes > 0
  AND EXISTS (
      SELECT 1 FROM file_inventory o
      WHERE o.md5_hash        = s.md5_hash
        AND o.file_size_bytes = s.file_size_bytes
        AND lower(o.full_path) LIKE '$origLower%'
  )

UNION

-- Case 2: within-SortOutAll duplicates (keep alphabetically-first, move rest)
SELECT full_path
FROM (
    SELECT
        full_path,
        ROW_NUMBER() OVER (PARTITION BY md5_hash, file_size_bytes ORDER BY full_path) AS rn,
        COUNT(*)    OVER (PARTITION BY md5_hash, file_size_bytes)                     AS cnt
    FROM file_inventory
    WHERE lower(full_path) LIKE '$sourceLower%'
      AND file_size_bytes > 0
) x
WHERE cnt > 1 AND rn > 1

UNION

-- Case 3: files named "*identical*" in F:\20220422 whose content matches a
--         non-identical copy in the same tree (original is kept, this moves)
SELECT DISTINCT s.full_path
FROM file_inventory s
WHERE lower(s.full_path) LIKE '$origLower%'
  AND lower(s.file_name) LIKE '%identical%'
  AND s.file_size_bytes > 0
  AND EXISTS (
      SELECT 1 FROM file_inventory o
      WHERE o.md5_hash        = s.md5_hash
        AND o.file_size_bytes = s.file_size_bytes
        AND lower(o.full_path) LIKE '$origLower%'
        AND lower(o.file_name) NOT LIKE '%identical%'
  )

UNION

-- Case 4: same-directory duplicates anywhere on the drive.
-- Within each directory, files with identical content (same MD5 + size) are
-- grouped; the alphabetically-first filename is kept, all others are moved.
SELECT full_path
FROM (
    SELECT
        full_path,
        ROW_NUMBER() OVER (PARTITION BY parent_directory, md5_hash, file_size_bytes ORDER BY file_name) AS rn,
        COUNT(*)    OVER (PARTITION BY parent_directory, md5_hash, file_size_bytes)                     AS cnt
    FROM file_inventory
    WHERE lower(full_path) LIKE '$driveLower%'
      AND file_size_bytes > 0
) x
WHERE cnt > 1 AND rn > 1

UNION

-- Case 5: date-folder copy when an album-folder original exists on the same drive.
-- Date path:  parent_directory contains a YYYY-MM-DD folder component.
-- Album path: parent_directory has no such component (named album, e.g. Christmas).
-- Keep the album copy; move the date-folder copy.
SELECT DISTINCT s.full_path
FROM file_inventory s
WHERE lower(s.full_path) LIKE '$driveLower%'
  AND s.file_size_bytes > 0
  AND s.parent_directory ~ '\\[0-9]{4}-[0-9]{2}-[0-9]{2}'
  AND EXISTS (
      SELECT 1 FROM file_inventory o
      WHERE o.md5_hash        = s.md5_hash
        AND o.file_size_bytes = s.file_size_bytes
        AND o.full_path      != s.full_path
        AND lower(o.full_path) LIKE '$driveLower%'
        AND o.parent_directory !~ '\\[0-9]{4}-[0-9]{2}-[0-9]{2}'
  )

UNION

-- Case 6: file in Pictures date folder also exists in Videos folder.
-- The Pictures copy is script-generated (date path); keep the Videos copy.
SELECT DISTINCT s.full_path
FROM file_inventory s
WHERE lower(s.full_path) LIKE '$driveLower%'
  AND s.file_size_bytes > 0
  AND lower(s.full_path) LIKE '%\\pictures\\%'
  AND s.parent_directory ~ '\\[0-9]{4}-[0-9]{2}-[0-9]{2}'
  AND EXISTS (
      SELECT 1 FROM file_inventory o
      WHERE o.md5_hash        = s.md5_hash
        AND o.file_size_bytes = s.file_size_bytes
        AND o.full_path      != s.full_path
        AND lower(o.full_path) LIKE '$driveLower%'
        AND lower(o.full_path) LIKE '%\\videos\\%'
  )

UNION

-- Case 7: file in Videos folder also exists in a Pictures named album.
-- The album copy is the curated original; move the Videos copy.
SELECT DISTINCT s.full_path
FROM file_inventory s
WHERE lower(s.full_path) LIKE '$driveLower%'
  AND s.file_size_bytes > 0
  AND lower(s.full_path) LIKE '%\\videos\\%'
  AND EXISTS (
      SELECT 1 FROM file_inventory o
      WHERE o.md5_hash        = s.md5_hash
        AND o.file_size_bytes = s.file_size_bytes
        AND o.full_path      != s.full_path
        AND lower(o.full_path) LIKE '$driveLower%'
        AND lower(o.full_path) LIKE '%\\pictures\\%'
        AND o.parent_directory !~ '\\[0-9]{4}-[0-9]{2}-[0-9]{2}'
  )

ORDER BY full_path;
"@
[System.IO.File]::WriteAllText($tempSql, $sql, [System.Text.UTF8Encoding]::new($false))

Write-Host "Source tree:  $SourcePrefix"
Write-Host "Original in:  $OrigPrefix"
Write-Host "Destination:  $DestRoot"
Write-Host ""
Write-Host "SQL:"
Write-Host $sql
Write-Host ""
Write-Host "Querying database '$DbName'..."

# Force UTF-8 so that paths with curly apostrophes, accented characters, etc.
# are not mangled when PowerShell decodes psql's output (default is CP1252).
$savedEncoding = [Console]::OutputEncoding
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$env:PGCLIENTENCODING = 'UTF8'
$rawOutput = & $PsqlPath -d $DbName -U $DbUser -t -A -f $tempSql 2>&1
[Console]::OutputEncoding = $savedEncoding
Remove-Item $tempSql -ErrorAction SilentlyContinue

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: psql failed. Check -DbName, -DbUser, and -PsqlPath."
    $rawOutput | ForEach-Object { Write-Host $_ }
    exit 1
}

# -t -A output is one path per line; filter out blank lines and psql messages
$filePaths = @($rawOutput | Where-Object { $_ -match '^[A-Za-z]:\\' })

Write-Host "Files to move: $($filePaths.Count)"
if ($WhatIf) { Write-Host '(WhatIf - no files will be moved)' }
Write-Host ""

$moved   = 0
$missing = 0
$skipped = 0
$errors  = 0

foreach ($src in $filePaths) {
    # Strip drive prefix (3 chars: letter + colon + backslash) to get relative path
    $relative = $src.Substring(3)
    $dest     = Join-Path $DestRoot $relative

    $srcLong  = Get-LongPath $src
    $destLong = Get-LongPath $dest

    if (-not [System.IO.File]::Exists($srcLong)) {
        Write-Host "  MISSING : $src"
        $missing++
        continue
    }

    if ([System.IO.File]::Exists($destLong)) {
        Write-Host "  EXISTS  : $dest  (skipping)"
        $skipped++
        continue
    }

    Write-Host "  MOVE: $src"
    Write-Host "    ->  $dest"

    if (-not $WhatIf) {
        try {
            $destDir = [System.IO.Path]::GetDirectoryName($dest)
            [System.IO.Directory]::CreateDirectory((Get-LongPath $destDir)) | Out-Null
            [System.IO.File]::Move($srcLong, $destLong)
            $moved++
        } catch {
            Write-Host "  ERROR   : $_"
            $errors++
        }
    } else {
        $moved++
    }
}

Write-Host ""
Write-Host "Done."
Write-Host "  Moved:             $moved"
Write-Host "  Skipped (dest exists): $skipped"
Write-Host "  Missing on disk:   $missing"
Write-Host "  Errors:            $errors"
