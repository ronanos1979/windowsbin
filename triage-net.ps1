<#
.SYNOPSIS
Prints a quick network triage report.

.DESCRIPTION
Prints a quick network health snapshot covering:
  - All established TCP connections (remote address, port, owning process)
  - All locally listening TCP ports
  - Suspicious connections: established connections to non-LAN IP addresses
    (not 127.x, 192.168.x, 10.x, 172.16-31.x) made by processes that are not
    common browsers (Chrome, Firefox, Edge, Brave, Opera, IE)

Run directly or via the triage-net.bat wrapper (which sets ExecutionPolicy Bypass).

Related scripts:
  triage.ps1     — system triage: CPU, memory, disk health, remote access tools
  find-seagate.ps1 — scans the local subnet for a Seagate NAS or similar device

.PARAMETER None
This script does not accept command-line parameters.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File triage-net.ps1
#>

param([switch]$Help)

if ($Help) {
    Get-Help $PSCommandPath -Full
    exit 0
}

Write-Host "`n=== ACTIVE NETWORK CONNECTIONS ===" -ForegroundColor Cyan

$connections = Get-NetTCPConnection -State Established |
    Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort, OwningProcess

# Join with process names
$procs = Get-Process | Select-Object Id, Name
$result = $connections | ForEach-Object {
    $proc = $procs | Where-Object { $_.Id -eq $_.OwningProcess } | Select-Object -First 1
    # re-resolve since pipeline scope is different
    $pid_ = $_.OwningProcess
    $name = ($procs | Where-Object { $_.Id -eq $pid_ } | Select-Object -First 1).Name
    [PSCustomObject]@{
        Process       = if ($name) { $name } else { "PID $pid_" }
        PID           = $pid_
        LocalPort     = $_.LocalPort
        RemoteAddress = $_.RemoteAddress
        RemotePort    = $_.RemotePort
    }
}

$result |
    Where-Object { $_.RemoteAddress -notmatch '^(127\.|::1)' } |
    Sort-Object Process, RemoteAddress |
    Format-Table -AutoSize

Write-Host "`n=== LOCAL LISTENERS (ports open on this machine) ===" -ForegroundColor Cyan
Get-NetTCPConnection -State Listen |
    Select-Object LocalAddress, LocalPort, OwningProcess |
    Sort-Object LocalPort |
    ForEach-Object {
        $pid_ = $_.OwningProcess
        $name = (Get-Process -Id $pid_ -ErrorAction SilentlyContinue).Name
        [PSCustomObject]@{
            Process      = if ($name) { $name } else { "PID $pid_" }
            LocalAddress = $_.LocalAddress
            LocalPort    = $_.LocalPort
        }
    } |
    Format-Table -AutoSize

Write-Host "`n=== SUSPICIOUS: NON-BROWSER EXTERNAL CONNECTIONS ===" -ForegroundColor Cyan
$browsers = 'chrome|firefox|msedge|brave|opera|iexplore'
$result |
    Where-Object {
        $_.RemoteAddress -notmatch '^(127\.|192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[01])\.|::1)' -and
        $_.Process -notmatch $browsers
    } |
    Sort-Object Process |
    Format-Table -AutoSize
