# windowsbin
Some windows scripts I have as shortcuts

## home.bat
Just a shortcut into a folder

## tools.bat
Just a shortcut into the folder

## uptime.bat
Powershell for uptime

## triage.bat
Calls triage.ps1 which diagnoses for processes taking resources on windows

## triage-net.bat
Calls triage-net.ps1 which diagnoses network issues on the PC

## scan_drive_md5.ps1
Scans all files under a path, computes MD5 hashes, and writes a CSV for import
into PostgreSQL. Supports a hash cache so repeat scans are fast.

```
powershell c:\tools\bin\scan_drive_md5.ps1 -Root F:\ -Label "Seagate 4TB"
```

### Import CSV into PostgreSQL

```
psql -d <dbname> -U postgres -f c:\tools\bin\create_file_inventory.sql

psql -d <dbname> -U postgres -c "\COPY file_inventory
  (scan_label, scanned_at, full_path, file_name, file_extension,
   parent_directory, drive_or_volume, file_size_bytes, md5_hash,
   file_created_at, file_modified_at, is_hidden, is_readonly)
  FROM 'F:\scan.csv' WITH (FORMAT CSV, HEADER TRUE, ENCODING 'UTF8')"
```

### Find duplicate files after import

**Grouped summary** — one row per duplicate hash, all paths in an array,
ordered by wasted space (largest first).
To limit to one drive add `AND scan_label = 'F:'` in the WHERE clause.

```sql
SELECT
    md5_hash,
    file_size_bytes,
    COUNT(*)                                          AS copies,
    pg_size_pretty(file_size_bytes * (COUNT(*) - 1)) AS wasted_space,
    array_agg(full_path ORDER BY full_path)           AS paths
FROM file_inventory
WHERE file_size_bytes > 0
GROUP BY md5_hash, file_size_bytes
HAVING COUNT(*) > 1
ORDER BY file_size_bytes * (COUNT(*) - 1) DESC;
```

**Flat list** — one row per duplicate file, useful for scripting or deletion.
To limit to one drive add `AND scan_label = 'F:'` inside the subquery.

```sql
SELECT
    md5_hash,
    file_size_bytes,
    COUNT(*) OVER (PARTITION BY md5_hash) AS copy_count,
    full_path,
    file_name,
    file_modified_at,
    scan_label
FROM file_inventory
WHERE file_size_bytes > 0
  AND md5_hash IN (
      SELECT md5_hash FROM file_inventory
      WHERE file_size_bytes > 0
      GROUP BY md5_hash HAVING COUNT(*) > 1
  )
ORDER BY md5_hash, full_path;
```

### Find cross-tree duplicates: SortOutAll vs 20220422

Files in `F:\SortOutAll` that have an identical copy (same MD5 hash **and** same
file size) somewhere under `F:\20220422`. Files that only duplicate within one
tree are ignored. This is the query used by `move_sortoutall_dups.ps1`.

**Inspect** — shows what would be moved with a matching original for confirmation:

```sql
SELECT DISTINCT ON (s.full_path)
    s.full_path       AS file_to_move,
    s.file_size_bytes,
    s.md5_hash,
    o.full_path       AS original_kept
FROM file_inventory s
JOIN file_inventory o
    ON  o.md5_hash        = s.md5_hash
    AND o.file_size_bytes = s.file_size_bytes
    AND lower(o.full_path) LIKE 'f:\\20220422%'
WHERE lower(s.full_path) LIKE 'f:\\sortoutall%'
  AND s.file_size_bytes > 0
ORDER BY s.full_path, o.full_path;
```

**List only** — just the paths to move:

```sql
SELECT DISTINCT s.full_path
FROM file_inventory s
WHERE lower(s.full_path) LIKE 'f:\\sortoutall%'
  AND s.file_size_bytes > 0
  AND EXISTS (
      SELECT 1 FROM file_inventory o
      WHERE o.md5_hash        = s.md5_hash
        AND o.file_size_bytes = s.file_size_bytes
        AND lower(o.full_path) LIKE 'f:\\20220422%'
  )
ORDER BY s.full_path;
```

### Find within-SortOutAll duplicates

Files where both copies live entirely inside `F:\SortOutAll`. The
alphabetically-first path is the one to keep; everything else is a candidate
to move.

**Grouped summary** — one row per duplicate group showing which copy is kept:

```sql
SELECT
    md5_hash,
    file_size_bytes,
    COUNT(*)                                          AS copies,
    pg_size_pretty(file_size_bytes * (COUNT(*) - 1)) AS space_to_recover,
    MIN(full_path)                                    AS file_kept,
    array_agg(full_path ORDER BY full_path)           AS all_paths
FROM file_inventory
WHERE lower(full_path) LIKE 'f:\\sortoutall%'
  AND file_size_bytes > 0
GROUP BY md5_hash, file_size_bytes
HAVING COUNT(*) > 1
ORDER BY file_size_bytes * (COUNT(*) - 1) DESC;
```

**List of files to move** (all but the alphabetically-first copy per group):

```sql
SELECT full_path AS file_to_move
FROM (
    SELECT
        full_path,
        ROW_NUMBER() OVER (PARTITION BY md5_hash, file_size_bytes ORDER BY full_path) AS rn,
        COUNT(*)    OVER (PARTITION BY md5_hash, file_size_bytes)                     AS cnt
    FROM file_inventory
    WHERE lower(full_path) LIKE 'f:\\sortoutall%'
      AND file_size_bytes > 0
) x
WHERE cnt > 1 AND rn > 1
ORDER BY full_path;
```

### Find files named "identical" in F:\20220422 that have a non-identical original

Files in `F:\20220422` whose filename contains the word "identical" and that have
a duplicate (same MD5 + size) in `F:\20220422` whose name does NOT contain
"identical". The non-identical copy is the original to keep; the "identical" copy
is moved by `move_sortoutall_dups.ps1`.

**Inspect** — shows what would be moved with the original it duplicates:

```sql
SELECT DISTINCT ON (s.full_path)
    s.full_path    AS file_to_move,
    s.file_name,
    s.file_size_bytes,
    s.md5_hash,
    o.full_path    AS original_kept
FROM file_inventory s
JOIN file_inventory o
    ON  o.md5_hash        = s.md5_hash
    AND o.file_size_bytes = s.file_size_bytes
    AND lower(o.full_path) LIKE 'f:\\20220422%'
    AND lower(o.file_name) NOT LIKE '%identical%'
WHERE lower(s.full_path) LIKE 'f:\\20220422%'
  AND lower(s.file_name) LIKE '%identical%'
  AND s.file_size_bytes > 0
ORDER BY s.full_path, o.full_path;
```

**List only** — just the paths to move:

```sql
SELECT DISTINCT s.full_path AS file_to_move
FROM file_inventory s
WHERE lower(s.full_path) LIKE 'f:\\20220422%'
  AND lower(s.file_name) LIKE '%identical%'
  AND s.file_size_bytes > 0
  AND EXISTS (
      SELECT 1 FROM file_inventory o
      WHERE o.md5_hash        = s.md5_hash
        AND o.file_size_bytes = s.file_size_bytes
        AND lower(o.full_path) LIKE 'f:\\20220422%'
        AND lower(o.file_name) NOT LIKE '%identical%'
  )
ORDER BY s.full_path;
```

### Find date-folder duplicates that have an album-folder original

Files where one copy sits in a date-structured path (`\YYYY\MM-Month\YYYY-MM-DD\`)
and an identical copy (same MD5 + size) exists in a named-album path
(`\YYYY\AlbumName\`). The album copy is the original to keep; the date-folder
copy is moved by `move_sortoutall_dups.ps1`.

The regex `\\[0-9]{4}-[0-9]{2}-[0-9]{2}` matches any folder component that looks
like a `YYYY-MM-DD` date. Paths without such a component are treated as album paths.

**Inspect** — shows what would be moved with its album original:

```sql
SELECT DISTINCT ON (s.full_path)
    s.full_path    AS file_to_move,
    s.file_size_bytes,
    s.md5_hash,
    o.full_path    AS original_kept
FROM file_inventory s
JOIN file_inventory o
    ON  o.md5_hash        = s.md5_hash
    AND o.file_size_bytes = s.file_size_bytes
    AND o.full_path      != s.full_path
    AND o.parent_directory !~ '\\[0-9]{4}-[0-9]{2}-[0-9]{2}'
WHERE s.file_size_bytes > 0
  AND s.parent_directory ~ '\\[0-9]{4}-[0-9]{2}-[0-9]{2}'
ORDER BY s.full_path, o.full_path;
```

**List only** — just the paths to move:

```sql
SELECT DISTINCT s.full_path AS file_to_move
FROM file_inventory s
WHERE s.file_size_bytes > 0
  AND s.parent_directory ~ '\\[0-9]{4}-[0-9]{2}-[0-9]{2}'
  AND EXISTS (
      SELECT 1 FROM file_inventory o
      WHERE o.md5_hash        = s.md5_hash
        AND o.file_size_bytes = s.file_size_bytes
        AND o.full_path      != s.full_path
        AND o.parent_directory !~ '\\[0-9]{4}-[0-9]{2}-[0-9]{2}'
  )
ORDER BY s.full_path;
```

### Find Pictures/Videos cross-folder duplicates

Two rules govern which copy to move when a file exists in both a Pictures and a
Videos folder:

- **Pictures date path + Videos**: the Pictures copy is in a `YYYY-MM-DD` date
  folder (created by an automated script). Move it; keep the Videos copy.
- **Pictures album path + Videos**: the Pictures copy is in a named album (no
  `YYYY-MM-DD` component). Move the Videos copy; keep the Pictures copy.

**Case 6 — move Pictures date copy, keep Videos copy:**

```sql
SELECT DISTINCT ON (s.full_path)
    s.full_path    AS file_to_move,
    s.file_size_bytes,
    s.md5_hash,
    o.full_path    AS original_kept
FROM file_inventory s
JOIN file_inventory o
    ON  o.md5_hash        = s.md5_hash
    AND o.file_size_bytes = s.file_size_bytes
    AND o.full_path      != s.full_path
    AND lower(o.full_path) LIKE '%\\videos\\%'
WHERE s.file_size_bytes > 0
  AND lower(s.full_path) LIKE '%\\pictures\\%'
  AND s.parent_directory ~ '\\[0-9]{4}-[0-9]{2}-[0-9]{2}'
ORDER BY s.full_path, o.full_path;
```

**Case 7 — move Videos copy, keep Pictures album copy:**

```sql
SELECT DISTINCT ON (s.full_path)
    s.full_path    AS file_to_move,
    s.file_size_bytes,
    s.md5_hash,
    o.full_path    AS original_kept
FROM file_inventory s
JOIN file_inventory o
    ON  o.md5_hash        = s.md5_hash
    AND o.file_size_bytes = s.file_size_bytes
    AND o.full_path      != s.full_path
    AND lower(o.full_path) LIKE '%\\pictures\\%'
    AND o.parent_directory !~ '\\[0-9]{4}-[0-9]{2}-[0-9]{2}'
WHERE s.file_size_bytes > 0
  AND lower(s.full_path) LIKE '%\\videos\\%'
ORDER BY s.full_path, o.full_path;
```

## move_sortoutall_dups.ps1

Queries the `file_inventory` table and moves two classes of file from
`F:\SortOutAll` to `F:\movedoutwithdupsoutsidefinalnewsetup`, preserving the
full directory structure under `F:\`:

1. **Cross-tree duplicates** — files in `F:\SortOutAll` that have an identical
   copy (same MD5 + size) under `F:\20220422`.
2. **Within-SortOutAll duplicates** — files duplicated entirely inside
   `F:\SortOutAll`; the alphabetically-first path is kept, the rest are moved.

```
# Dry run — preview what would be moved
powershell c:\tools\bin\move_sortoutall_dups.ps1 -DbName filedb -WhatIf

# Move the files
powershell c:\tools\bin\move_sortoutall_dups.ps1 -DbName filedb
```
