<#
Import a scan_drive_md5.ps1 CSV into PostgreSQL.
Strips BOM automatically and uses the correct column list.

Usage:
  powershell c:\tools\bin\import_scan_csv.ps1 -Csv F:\scan.csv
  powershell c:\tools\bin\import_scan_csv.ps1 -Csv F:\scan.csv -Database harddrives -User postgres

Run this once per CSV. Multiple CSVs can be loaded into the same table — rows are appended.
Do NOT re-run create_file_inventory.sql between imports or you will lose existing data.
#>

param(
    [Parameter(Mandatory)][string]$Csv,
    [string]$Database = 'harddrives',
    [string]$User     = 'postgres',
    [switch]$Help
)

if ($Help) {
    Write-Host ""
    Write-Host "import_scan_csv.ps1"
    Write-Host "-------------------"
    Write-Host "Imports a CSV produced by scan_drive_md5.ps1 into PostgreSQL."
    Write-Host "Strips the UTF-8 BOM automatically so PostgreSQL can read it."
    Write-Host ""
    Write-Host "USAGE"
    Write-Host "  powershell c:\tools\bin\import_scan_csv.ps1 -Csv <path> [options]"
    Write-Host ""
    Write-Host "PARAMETERS"
    Write-Host "  -Csv <path>        Path to the CSV file produced by scan_drive_md5.ps1. Required."
    Write-Host "  -Database <name>   PostgreSQL database name. Defaults to: harddrives"
    Write-Host "  -User <name>       PostgreSQL user name.     Defaults to: postgres"
    Write-Host "  -Help              Show this help message."
    Write-Host ""
    Write-Host "FIRST-TIME SETUP"
    Write-Host "  Create the table before importing for the first time:"
    Write-Host "    psql -d harddrives -U postgres -f c:\tools\bin\create_file_inventory.sql"
    Write-Host ""
    Write-Host "EXAMPLES"
    Write-Host "  # Import a scan from F:\"
    Write-Host "  powershell c:\tools\bin\import_scan_csv.ps1 -Csv F:\scan.csv"
    Write-Host ""
    Write-Host "  # Import a second drive into the same table (rows are appended)"
    Write-Host "  powershell c:\tools\bin\import_scan_csv.ps1 -Csv G:\scan.csv"
    Write-Host ""
    Write-Host "  # Different database or user"
    Write-Host "  powershell c:\tools\bin\import_scan_csv.ps1 -Csv F:\scan.csv -Database mydb -User myuser"
    Write-Host ""
    exit 0
}

if (-not (Test-Path -LiteralPath $Csv)) {
    Write-Host "ERROR: File not found: $Csv"
    exit 1
}

# Strip BOM — write a clean copy next to the original
$dir   = [IO.Path]::GetDirectoryName((Resolve-Path $Csv).Path)
$base  = [IO.Path]::GetFileNameWithoutExtension($Csv)
$nobom = [IO.Path]::Combine($dir, $base + '_nobom.csv')

Write-Host "Stripping BOM: $Csv"
$text = [IO.File]::ReadAllText($Csv, [Text.Encoding]::UTF8)
[IO.File]::WriteAllText($nobom, $text, [Text.UTF8Encoding]::new($false))
Write-Host "Clean file:    $nobom"
Write-Host ""

# psql handles forward slashes fine on Windows and avoids backslash interpretation issues
$sqlpath = $nobom -replace '\\', '/'

$cols = 'scan_label, scanned_at, full_path, file_name, file_extension, parent_directory, ' +
        'drive_or_volume, file_size_bytes, md5_hash, file_created_at, file_modified_at, ' +
        'is_hidden, is_readonly'

$sql = "\COPY file_inventory ($cols) FROM '$sqlpath' WITH (FORMAT CSV, HEADER TRUE, ENCODING 'UTF8')"

Write-Host "Importing into database '$Database' as user '$User'..."
Write-Host "(You will be prompted for the PostgreSQL password.)"
Write-Host ""
& psql -d $Database -U $User -c $sql

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "Import complete."
} else {
    Write-Host ""
    Write-Host "ERROR: psql exited with code $LASTEXITCODE. Check the error above."
    exit 1
}
