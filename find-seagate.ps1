<#
.SYNOPSIS
Looks for a Seagate Personal Cloud or similar NAS on the local network.

.DESCRIPTION
Checks a known IP address, tries common Seagate hostnames, prints local network
configuration, scans the local subnet for live devices, highlights likely NAS
hostnames, and shows current SMB mappings.

.PARAMETER None
This script does not accept command-line parameters. The known IP and hostname
list are defined inside the script.

.EXAMPLE
.\find-seagate.ps1
#>

Write-Host "===== FIND SEAGATE / NETWORK DRIVE =====" -ForegroundColor Cyan

Write-Host "`n===== 1. CHECK KNOWN SEAGATE IP FROM BEFORE =====" -ForegroundColor Yellow
$knownIp = "192.168.86.111"

if (Test-Connection $knownIp -Count 2 -Quiet) {
    Write-Host "FOUND: $knownIp is responding" -ForegroundColor Green
    Write-Host "Try opening:"
    Write-Host "  http://$knownIp"
    Write-Host "  \\$knownIp"
} else {
    Write-Host "$knownIp did not respond."
}

Write-Host "`n===== 2. CHECK KNOWN NETWORK NAME =====" -ForegroundColor Yellow
$names = @("personalcloud", "seagate", "seagate-personalcloud")

foreach ($name in $names) {
    Write-Host "Checking $name ..."
    try {
        $result = Resolve-DnsName $name -ErrorAction Stop
        $result | Format-Table Name,IPAddress,Type -AutoSize
        Write-Host "Try: \\$name" -ForegroundColor Green
    } catch {
        Write-Host "Could not resolve $name"
    }
}

Write-Host "`n===== 3. SHOW CURRENT NETWORK INFO =====" -ForegroundColor Yellow
Get-NetIPConfiguration |
    Where-Object { $_.IPv4Address -ne $null } |
    Select-Object InterfaceAlias, IPv4Address, IPv4DefaultGateway |
    Format-List

Write-Host "`n===== 4. SCAN LOCAL SUBNET FOR LIVE DEVICES =====" -ForegroundColor Yellow

$ipInfo = Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object {
        $_.IPAddress -like "192.168.*" -or
        $_.IPAddress -like "10.*" -or
        $_.IPAddress -like "172.*"
    } |
    Select-Object -First 1

if ($null -eq $ipInfo) {
    Write-Host "Could not determine local subnet."
} else {
    $parts = $ipInfo.IPAddress.Split(".")
    $subnet = "$($parts[0]).$($parts[1]).$($parts[2])"

    Write-Host "Scanning $subnet.1 to $subnet.254 ..."
    Write-Host "This may take a minute."

    $liveDevices = foreach ($i in 1..254) {
        $ip = "$subnet.$i"
        if (Test-Connection $ip -Count 1 -Quiet -ErrorAction SilentlyContinue) {
            try {
                $name = [System.Net.Dns]::GetHostEntry($ip).HostName
            } catch {
                $name = ""
            }

            [PSCustomObject]@{
                IPAddress = $ip
                HostName  = $name
            }
        }
    }

    $liveDevices | Sort-Object IPAddress | Format-Table -AutoSize

    Write-Host "`nPossible Seagate/NAS matches:" -ForegroundColor Yellow
    $liveDevices |
        Where-Object {
            $_.HostName -match "seagate|personal|cloud|nas|storage"
        } |
        Format-Table -AutoSize
}

Write-Host "`n===== 5. CHECK WINDOWS NETWORK / SMB SHARES =====" -ForegroundColor Yellow

Write-Host "`nKnown shares currently mapped:"
Get-SmbMapping | Format-Table LocalPath, RemotePath, Status -AutoSize

Write-Host "`nTry browsing these manually in File Explorer:"
Write-Host "  \\personalcloud"
Write-Host "  \\192.168.86.111"

Write-Host "`n===== DONE =====" -ForegroundColor Cyan
