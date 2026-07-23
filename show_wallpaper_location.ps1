param([switch]$Help)

function Show-Help {
    Write-Host "Usage:"
    Write-Host "  .\show_wallpaper_location.ps1"
    Write-Host ""
    Write-Host "What it does:"
    Write-Host "  Finds the current Windows desktop wallpaper, reads its GPS and location"
    Write-Host "  metadata with exiftool, and prints a Google Maps link if coordinates exist."
    Write-Host "  Also shows title, description, artist, and copyright fields."
    Write-Host ""
    Write-Host "Parameters:"
    Write-Host "  -Help   Show this help and exit."
    Write-Host ""
    Write-Host "Requires exiftool. Install with: winget install OliverBetz.ExifTool"
}

if ($Help) {
    Show-Help
    exit 0
}

if (-not (Get-Command exiftool -ErrorAction SilentlyContinue)) {
    Write-Error "ExifTool is required but not found.`nInstall with: winget install OliverBetz.ExifTool"
    exit 1
}

# --- Find wallpaper ---

$wallpaperPath = (Get-ItemProperty 'HKCU:\Control Panel\Desktop' -ErrorAction SilentlyContinue).Wallpaper

if (-not $wallpaperPath -or -not (Test-Path -LiteralPath $wallpaperPath)) {
    # Windows sometimes transcodes the wallpaper (resize, Spotlight, etc.)
    $transcoded = "$env:APPDATA\Microsoft\Windows\Themes\TranscodedWallpaper"
    if (Test-Path -LiteralPath $transcoded) {
        $wallpaperPath = $transcoded
    } else {
        Write-Error "Could not locate the current wallpaper file."
        exit 1
    }
}

Write-Host "Wallpaper: $wallpaperPath"
Write-Host ""

# --- Show location / authorship metadata ---

$info = exiftool -s $wallpaperPath `
    -GPS:All `
    -XMP:Location -XMP:City -XMP:State -XMP:Country `
    -IPTC:Sub-location -IPTC:City -IPTC:Province-State -IPTC:Country-PrimaryLocationName `
    -Title -ImageDescription -Caption-Abstract -Description `
    -Artist -Creator -Credit -Copyright 2>$null

if ($info) {
    $info | ForEach-Object { Write-Host $_ }
} else {
    Write-Host "No location or authorship metadata found in this image."
}

Write-Host ""

# --- Build Google Maps link from GPS ---

$gpsJson = exiftool -json -n `
    -GPSLatitude -GPSLatitudeRef -GPSLongitude -GPSLongitudeRef `
    $wallpaperPath 2>$null

if ($gpsJson) {
    $gps = ($gpsJson | ConvertFrom-Json)[0]
    if ($null -ne $gps.GPSLatitude -and $null -ne $gps.GPSLongitude) {
        $lat = $gps.GPSLatitude
        $lng = $gps.GPSLongitude
        if ($gps.GPSLatitudeRef  -in @('S', 'South')) { $lat = -[Math]::Abs($lat) }
        if ($gps.GPSLongitudeRef -in @('W', 'West'))  { $lng = -[Math]::Abs($lng) }
        Write-Host "Google Maps: https://www.google.com/maps?q=$lat,$lng"
    } else {
        Write-Host "No GPS coordinates in this image."
    }
}
