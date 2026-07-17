<#
Lists all subfolders under a path, flagging any whose name matches a list of
keywords (temp files, OS junk, device sync folders, etc).

Usage:
  powershell c:\tools\bin\list_folders.ps1 -Root "F:\20220422_FINAL_NEW_SETUP"
#>

param(
    [Parameter(Mandatory)][string]$Root,
    [switch]$Help
)

if ($Help) {
    Write-Host ""
    Write-Host "list_folders.ps1"
    Write-Host "----------------"
    Write-Host "Lists all subfolders under -Root, flagging names that match known"
    Write-Host "junk/device keywords so you can review them before taking action."
    Write-Host ""
    Write-Host "USAGE"
    Write-Host "  powershell c:\tools\bin\list_folders.ps1 -Root <path>"
    Write-Host ""
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
