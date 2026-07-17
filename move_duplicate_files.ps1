<#
Queries the database for files with the same MD5, size, and parent directory,
keeps the alphabetically first copy in place, and moves all others to -Dest
preserving the original folder structure.

Usage:
  powershell c:\tools\bin\move_duplicate_files.ps1 -Dest F:\moved_duplicates
  powershell c:\tools\bin\move_duplicate_files.ps1 -Dest F:\moved_duplicates -Root "F:\20220422_FINAL_NEW_SETUP"
#>

param(
    [Parameter(Mandatory)][string]$Dest,
    [string]$Root     = 'F:\20220422_FINAL_NEW_SETUP',
    [string]$Database = 'harddrives',
    [string]$User     = 'postgres',
    [switch]$Help
)

if ($Help) {
    Write-Host ""
    Write-Host "move_duplicate_files.ps1"
    Write-Host "------------------------"
    Write-Host "Finds files in the database that share the same MD5 hash, file size,"
    Write-Host "and parent directory. Keeps one copy in place (alphabetically first)"
    Write-Host "and moves the rest to -Dest, preserving the folder structure."
    Write-Host ""
    Write-Host "USAGE"
    Write-Host "  powershell c:\tools\bin\move_duplicate_files.ps1 -Dest <path> [options]"
    Write-Host ""
    Write-Host "PARAMETERS"
    Write-Host "  -Dest <path>       Folder to move duplicates into. Created if needed. Required."
    Write-Host "  -Root <path>       Folder to limit the search to. Defaults to F:\20220422_FINAL_NEW_SETUP"
    Write-Host "  -Database <name>   PostgreSQL database name. Defaults to: harddrives"
    Write-Host "  -User <name>       PostgreSQL user name.     Defaults to: postgres"
    Write-Host "  -Help              Show this help message."
    Write-Host ""
    Write-Host "EXAMPLES"
    Write-Host "  powershell c:\tools\bin\move_duplicate_files.ps1 -Dest F:\moved_duplicates"
    Write-Host "  powershell c:\tools\bin\move_duplicate_files.ps1 -Dest D:\quarantine -Root F:\20220422_FINAL_NEW_SETUP\Pictures"
    Write-Host ""
    exit 0
}

# Normalise root to single backslash then double for SQL ILIKE pattern
$rootNorm = $Root.Replace('\\', '\').TrimEnd('\')
$sqlRoot  = $rootNorm.Replace('\', '\\')

$sqlFile = [IO.Path]::GetTempFileName() + '.sql'

$sql = @"
SELECT full_path
FROM (
    SELECT
        full_path,
        ROW_NUMBER() OVER (
            PARTITION BY md5_hash, file_size_bytes, parent_directory
            ORDER BY full_path
        ) AS rn
    FROM file_inventory
    WHERE full_path ILIKE '$sqlRoot%'
      AND file_name NOT LIKE '._%'
      AND (md5_hash, file_size_bytes, parent_directory) IN (
          SELECT md5_hash, file_size_bytes, parent_directory
          FROM file_inventory
          WHERE full_path ILIKE '$sqlRoot%'
            AND file_name NOT LIKE '._%'
          GROUP BY md5_hash, file_size_bytes, parent_directory
          HAVING COUNT(*) > 1
      )
) sub
WHERE rn > 1
ORDER BY full_path;
"@

[IO.File]::WriteAllText($sqlFile, $sql, [Text.UTF8Encoding]::new($false))

Write-Host "Querying database for duplicates in: $rootNorm"
$paths = & psql -d $Database -U $User -f $sqlFile -t -A -q
Remove-Item $sqlFile -Force

$paths = $paths | Where-Object { $_.Trim() -ne '' }

if (-not $paths) {
    Write-Host "No duplicates found."
    exit 0
}

Write-Host "Found $($paths.Count) duplicate file(s) to move."
Write-Host ""

$moved   = 0
$skipped = 0
$failed  = 0

foreach ($p in $paths) {
    $src = $p.Trim().Replace('\\', '\')

    if (-not (Test-Path -LiteralPath $src)) {
        Write-Host "  SKIP (not on disk): $src"
        $skipped++
        continue
    }

    # Strip drive letter and rebuild under $Dest to preserve full folder structure
    $relative = $src.Substring(3)   # removes "F:\"
    $destPath = Join-Path $Dest $relative
    $destDir  = Split-Path $destPath -Parent

    if (-not (Test-Path -LiteralPath $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    try {
        Move-Item -LiteralPath $src -Destination $destPath -Force -ErrorAction Stop
        Write-Host "  MOVED: $src"
        Write-Host "     -> $destPath"
        $moved++
    } catch {
        Write-Host "  FAILED: $src - $_"
        $failed++
    }
}

Write-Host ""
Write-Host "Done. Moved: $moved  Skipped (not on disk): $skipped  Failed: $failed"
