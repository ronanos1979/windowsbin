<#
.SYNOPSIS
    Tests the effective speed of a USB cable by benchmarking an external drive.

.DESCRIPTION
    Writes and reads a temporary file on the target drive using direct I/O, then
    reports write and read speeds in MB/s. The result indicates whether the cable
    is operating at USB 2.0 or USB 3.x speed.

    The temporary file is always deleted when the script exits, even on error.

    Run PowerShell as Administrator if access is denied.

.PARAMETER DriveLetter
    The drive letter of the external drive to test (e.g. E or E:).

.PARAMETER TestSizeMB
    Size of the temporary test file in megabytes. Must be between 512 and 8192.
    Defaults to 2048 (2 GB). Larger values give more accurate results.

.EXAMPLE
    .\Test-UsbCable.ps1 -DriveLetter E

    Tests the USB cable connected to drive E: using a 2 GB test file.

.EXAMPLE
    .\Test-UsbCable.ps1 -DriveLetter F -TestSizeMB 512

    Tests drive F: with a smaller 512 MB file for a quicker result.

.NOTES
    For consistent cable comparisons:
    - Use the same external drive for every cable tested.
    - Use the same known USB 3.x port for every test.
    - Close all programs that are using the drive before running.
#>

[CmdletBinding(DefaultParameterSetName = 'Run')]
param(
    [Parameter(ParameterSetName = 'Help')]
    [Alias('h', '?')]
    [switch]$Help,

    [Parameter(Mandatory = $true, ParameterSetName = 'Run')]
    [ValidatePattern('^[A-Za-z]:?$')]
    [string]$DriveLetter,

    [Parameter(ParameterSetName = 'Run')]
    [ValidateRange(512, 8192)]
    [int]$TestSizeMB = 2048
)

if ($Help) {
    Get-Help $MyInvocation.MyCommand.Path -Detailed
    exit
}

$ErrorActionPreference = "Stop"

# Normalize E or E: to E:
$DriveLetter = $DriveLetter.TrimEnd(':').ToUpper() + ":"
$TestFile = Join-Path $DriveLetter "USB_CABLE_SPEED_TEST.tmp"

if (-not (Test-Path "$DriveLetter\")) {
    throw "Drive $DriveLetter was not found."
}

$drive = Get-CimInstance Win32_LogicalDisk |
    Where-Object DeviceID -eq $DriveLetter

if (-not $drive) {
    throw "Unable to obtain information for drive $DriveLetter."
}

$requiredBytes = ($TestSizeMB + 500) * 1MB

if ($drive.FreeSpace -lt $requiredBytes) {
    throw "The drive needs at least $([math]::Round($requiredBytes / 1GB, 2)) GB of free space."
}

if (Test-Path $TestFile) {
    Remove-Item $TestFile -Force
}

$bufferSize = 8MB
$buffer = New-Object byte[] $bufferSize

# Fill the buffer with non-zero data.
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$rng.GetBytes($buffer)
$rng.Dispose()

$totalBytes = [int64]$TestSizeMB * 1MB

Write-Host ""
Write-Host "USB cable/connection speed test"
Write-Host "Drive:       $DriveLetter"
Write-Host "Volume:      $($drive.VolumeName)"
Write-Host "Test size:   $TestSizeMB MB"
Write-Host ""
Write-Host "Do not disconnect the drive during the test."
Write-Host ""

try {
    # WRITE TEST
    Write-Host "Running write test..."

    $writeStream = [System.IO.FileStream]::new(
        $TestFile,
        [System.IO.FileMode]::Create,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::None,
        $bufferSize,
        [System.IO.FileOptions]::WriteThrough
    )

    $writeWatch = [System.Diagnostics.Stopwatch]::StartNew()
    $written = [int64]0

    while ($written -lt $totalBytes) {
        $remaining = $totalBytes - $written
        $bytesToWrite = [int][math]::Min([int64]$buffer.Length, $remaining)

        $writeStream.Write($buffer, 0, $bytesToWrite)
        $written += $bytesToWrite

        $percent = [math]::Floor(($written / $totalBytes) * 100)
        Write-Progress -Activity "Writing test file" -Status "$percent%" -PercentComplete $percent
    }

    $writeStream.Flush($true)
    $writeWatch.Stop()
    $writeStream.Dispose()
    Write-Progress -Activity "Writing test file" -Completed

    $writeMBps = ($totalBytes / 1MB) / $writeWatch.Elapsed.TotalSeconds

    # READ TEST
    Write-Host "Running read test..."

    $readStream = [System.IO.FileStream]::new(
        $TestFile,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::Read,
        $bufferSize,
        [System.IO.FileOptions]::SequentialScan
    )

    $readWatch = [System.Diagnostics.Stopwatch]::StartNew()
    $readTotal = [int64]0

    while (($bytesRead = $readStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
        $readTotal += $bytesRead

        $percent = [math]::Floor(($readTotal / $totalBytes) * 100)
        Write-Progress -Activity "Reading test file" -Status "$percent%" -PercentComplete $percent
    }

    $readWatch.Stop()
    $readStream.Dispose()
    Write-Progress -Activity "Reading test file" -Completed

    $readMBps = ($readTotal / 1MB) / $readWatch.Elapsed.TotalSeconds

    $bestSpeed = [math]::Max($writeMBps, $readMBps)

    Write-Host ""
    Write-Host "========== RESULTS =========="
    Write-Host ("Write speed: {0:N1} MB/s" -f $writeMBps)
    Write-Host ("Read speed:  {0:N1} MB/s" -f $readMBps)
    Write-Host ""

    if ($bestSpeed -ge 80) {
        Write-Host "Result: The connection is operating at USB 3.x speed." -ForegroundColor Green
        Write-Host "This cable is very likely USB 3-capable."
    }
    elseif ($bestSpeed -ge 50) {
        Write-Host "Result: Probably USB 3.x, but not conclusive." -ForegroundColor Yellow
        Write-Host "The drive itself may be limiting the speed."
    }
    elseif ($bestSpeed -ge 25) {
        Write-Host "Result: USB 2.0 speed or a slow drive." -ForegroundColor Yellow
        Write-Host "Retest using a fast external SSD for a definitive result."
    }
    else {
        Write-Host "Result: Very slow connection." -ForegroundColor Red
        Write-Host "Possible USB 2 cable, USB 2 port, slow device, hub, or drive problem."
    }

    Write-Host ""
    Write-Host "Typical real-world speeds:"
    Write-Host "  USB 2.0:          approximately 25-45 MB/s"
    Write-Host "  USB 3.x hard disk: approximately 80-180 MB/s"
    Write-Host "  USB 3.x SSD:       approximately 300-550+ MB/s"
}
finally {
    if ($writeStream) {
        $writeStream.Dispose()
    }

    if ($readStream) {
        $readStream.Dispose()
    }

    if (Test-Path $TestFile) {
        Remove-Item $TestFile -Force
        Write-Host ""
        Write-Host "Temporary test file deleted."
    }
}