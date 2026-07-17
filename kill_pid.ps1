#Requires -RunAsAdministrator
<#
.SYNOPSIS
Kills a process by PID.

.DESCRIPTION
Attempts a graceful close via CloseMainWindow, waits 500 ms, then force-kills
with taskkill if the process is still running. Requires administrator privileges.

.PARAMETER ProcessId
The numeric PID of the process to kill. Required.

.EXAMPLE
.\kill_pid.ps1 -ProcessId 1234

.NOTES
If the process is a protected system process it may survive even a forced kill.
Try running as SYSTEM or disabling Tamper Protection in that case.
#>

param(
    [switch]$Help,

    [Parameter(Mandatory=$false)]
    [int]$ProcessId
)

if ($Help) {
    Get-Help $PSCommandPath -Full
    exit 0
}

if (-not $ProcessId) {
    Write-Error "-ProcessId is required. Use -Help for usage information."
    exit 1
}

$proc = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
if (-not $proc) {
    Write-Host "No process found with PID $ProcessId"
    exit 0
}

Write-Host "Killing: $($proc.Name) (PID $ProcessId)"

# Try graceful first, then force
try {
    $proc.CloseMainWindow() | Out-Null
    Start-Sleep -Milliseconds 500
}
catch {}

if (-not (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) {
    Write-Host "Process exited gracefully."
    exit 0
}

# Force kill via taskkill (handles protected processes better than Stop-Process)
$result = & taskkill /F /PID $ProcessId 2>&1
Write-Host $result

if (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue) {
    Write-Host "Process still alive - may be a protected system process. Try running as SYSTEM or disable Tamper Protection first."
    exit 1
} else {
    Write-Host "Process killed successfully."
    exit 0
}
