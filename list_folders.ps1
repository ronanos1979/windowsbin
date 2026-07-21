<#
Lists all subfolders under a path, flagging any whose name matches a list of
keywords (temp files, OS junk, Apple/Android device sync folders, backup and
duplicate folder names, thumbnail folders, and OS recycle bins).

Usage:
  powershell c:\tools\bin\list_folders.ps1 -Root "F:\20220422_FINAL_NEW_SETUP"
  powershell c:\tools\bin\list_folders.ps1 -Root "F:\" -Help

Related: move_sortoutall_dups.ps1, delete_mac_junk.ps1
#>

param(
    [Parameter(Mandatory)][string]$Root,
    [switch]$Help
)

if ($Help) {
    Write-Host @'

list_folders.ps1
----------------
Lists every subfolder under -Root, flagging names that match known junk/device
keywords so you can review them before deleting or moving.

Flagged keyword categories: temp/cache/trash, Apple/iPhone/iCloud, Android/Samsung,
backup/archive/copy, duplicate/identical, thumbnail folders, and OS recycle bins.

USAGE
  powershell c:\tools\bin\list_folders.ps1 -Root <path>

PARAMETERS
  -Root <path>   The root folder to scan. All subfolders are listed recursively.
  -Help          Show this help message.

EXAMPLES
  # List and flag folders under the final photo archive
  powershell c:\tools\bin\list_folders.ps1 -Root "F:\20220422_FINAL_NEW_SETUP"

  # Review a drive before running move_sortoutall_dups.ps1
  powershell c:\tools\bin\list_folders.ps1 -Root "F:\"

OUTPUT
  Two sections are printed:
    FLAGGED FOLDERS  — subfolders whose name matches a keyword (keyword shown in brackets)
    ALL OTHER FOLDERS — remaining subfolders

RELATED SCRIPTS
  move_sortoutall_dups.ps1   — moves duplicate files out of flagged/duplicate trees
  delete_mac_junk.ps1        — deletes ._* and .DS_Store Mac junk files

'@
    exit 0
}

if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
    Write-Host "ERROR: Path does not exist: $Root"
    exit 1
}

$keywords = @(
    'temp', 'tmp', 'cache', 'trash', 'recycle', 'garbage',
    'apple', 'iphone', 'ipad', 'ipod', 'itunes', 'iphoto', 'macos', 'mac os',
    'android', 'samsung', 'google',
    'backup', 'old', 'archive', 'archived', 'copy', 'copies',
    'duplicate', 'dupe', 'identical',
    'thumbnails', 'thumb', '.thumbnails',
    'appdata', 'system volume', 'recycler', '$recycle',
    'lost+found', 'found.000'
)

$all     = [System.Collections.Generic.List[string]]::new()
$flagged = [System.Collections.Generic.List[string]]::new()

Get-ChildItem -LiteralPath $Root -Recurse -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
    $relative = $_.FullName.Substring($Root.Length).TrimStart('\')
    $name     = $_.Name.ToLower()
    $match    = $keywords | Where-Object { $name -like "*$_*" } | Select-Object -First 1

    if ($match) {
        $flagged.Add("  [FLAGGED: $match] $relative")
    } else {
        $all.Add("  $relative")
    }
}

Write-Host ""
Write-Host "===== FLAGGED FOLDERS ($($flagged.Count)) ====="
if ($flagged.Count -eq 0) {
    Write-Host "  None."
} else {
    $flagged | ForEach-Object { Write-Host $_ }
}

Write-Host ""
Write-Host "===== ALL OTHER FOLDERS ($($all.Count)) ====="
$all | ForEach-Object { Write-Host $_ }

Write-Host ""
Write-Host "Total: $($flagged.Count + $all.Count) folders  ($($flagged.Count) flagged)"
