<#
.SYNOPSIS
    Displays hardware and USB connection details for an external drive.

.DESCRIPTION
    Identifies the physical disk behind a drive letter, walks the Windows
    PnP device tree to locate the USB device and host hub, and reports
    the drive model, capacity, serial number, USB Vendor ID / Product ID,
    and whether the connection is USB 2.0 or USB 3.x.

.PARAMETER DriveLetter
    Drive letter of the external USB drive (e.g. E or E:).

.EXAMPLE
    .\Get-UsbDriveInfo.ps1 -DriveLetter E
#>

[CmdletBinding(DefaultParameterSetName = 'Run')]
param(
    [Parameter(ParameterSetName = 'Help')]
    [Alias('h', '?')]
    [switch]$Help,

    [Parameter(Mandatory, ParameterSetName = 'Run')]
    [ValidatePattern('^[A-Za-z]:?$')]
    [string]$DriveLetter
)

if ($Help) {
    Get-Help $MyInvocation.MyCommand.Path -Detailed
    exit
}

$ErrorActionPreference = 'Stop'
$DriveLetter = $DriveLetter.TrimEnd(':').ToUpper() + ':'

# Map drive letter -> partition -> physical disk
try {
    $diskNumber = (Get-Partition -DriveLetter $DriveLetter.TrimEnd(':') -ErrorAction Stop).DiskNumber
} catch {
    throw "No partition found for drive $DriveLetter. Is the drive connected and formatted?"
}

$disk      = Get-Disk -Number $diskNumber
$diskDrive = Get-CimInstance Win32_DiskDrive | Where-Object Index -eq $diskNumber

if (-not $diskDrive) {
    throw "Could not retrieve disk information for drive $DriveLetter."
}

# Walk the PnP device tree to find the USB device (VID/PID) and host hub
function Get-PnpParentId ([string]$InstanceId) {
    (Get-PnpDeviceProperty -InstanceId $InstanceId `
        -KeyName 'DEVPKEY_Device_Parent' `
        -ErrorAction SilentlyContinue).Data
}

$vid            = $null
$pidStr         = $null
$usbDeviceName  = $null
$hubName        = $null
$connectionType = 'Unknown (device may not be USB)'

$currentId = $diskDrive.PNPDeviceID

for ($depth = 0; $depth -lt 10; $depth++) {
    $parentId = Get-PnpParentId $currentId
    if (-not $parentId) { break }

    # USB device node — VID and PID live here
    if (-not $vid -and $parentId -match 'USB\\VID_([0-9A-F]{4})&PID_([0-9A-F]{4})') {
        $vid    = $Matches[1]
        $pidStr = $Matches[2]
        $usbDev = Get-PnpDevice -InstanceId $parentId -ErrorAction SilentlyContinue
        $usbDeviceName = $usbDev.FriendlyName
    }

    # Hub node — USB 2.0 vs 3.x is determined here
    if ($parentId -match 'USB\\(ROOT_HUB|HUB)') {
        $hub     = Get-PnpDevice -InstanceId $parentId -ErrorAction SilentlyContinue
        $hubName = $hub.FriendlyName

        $connectionType = if ($parentId -match 'HUB30' -or $hubName -match 'USB 3') {
            'USB 3.x   (SuperSpeed, 5-20 Gbps theoretical)'
        } elseif ($parentId -match 'HUB20' -or $hubName -match 'USB 2') {
            'USB 2.0   (480 Mbps theoretical, ~45 MB/s real-world max)'
        } else {
            $hubName
        }
        break
    }

    $currentId = $parentId
}

# Format capacity
$capacityGB  = $disk.Size / 1GB
$capacityStr = if ($capacityGB -ge 900) {
    '{0:N2} TB' -f ($capacityGB / 1024)
} else {
    '{0:N0} GB' -f $capacityGB
}

Write-Host ''
Write-Host '====== DRIVE ======'
Write-Host "Letter:      $DriveLetter"
Write-Host "Model:       $($diskDrive.Model.Trim())"
Write-Host "Capacity:    $capacityStr"
Write-Host "Serial:      $($diskDrive.SerialNumber.Trim())"
Write-Host ''
Write-Host '====== USB CONNECTION ======'
if ($vid) {
    Write-Host "Vendor ID:   $vid"
    Write-Host "Product ID:  $pidStr"
    Write-Host "Device:      $usbDeviceName"
}
Write-Host "Host hub:    $hubName"
Write-Host "Connection:  $connectionType"
if ($vid) {
    Write-Host ''
    Write-Host "Spec lookup: https://devicehunt.com/view/type/usb/vendor/$vid/device/$pidStr"
}
Write-Host ''
