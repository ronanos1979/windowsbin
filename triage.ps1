<#
.SYNOPSIS
Prints a quick Windows system triage report.

.DESCRIPTION
Prints a quick Windows health snapshot covering:
  - Top 20 processes by CPU usage
  - Total / used / free RAM
  - Current CPU load percentage
  - Disk drive model and SMART status
  - Running remote access tools (VNC, TeamViewer, AnyDesk, Ammyy, LogMeIn,
    ScreenConnect, RustDesk, Parsec, Supremo, Splashtop, UltraViewer)
  - All registered startup commands (via Win32_StartupCommand)

Run directly or via the triage.bat wrapper (which sets ExecutionPolicy Bypass).

Related scripts:
  triage-net.ps1   — network triage: active TCP connections and suspicious external traffic
  kill_pid.ps1     — gracefully close or force-kill a process by PID

.PARAMETER None
This script does not accept command-line parameters.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File triage.ps1
#>

param([switch]$Help)

if ($Help) {
    Get-Help $PSCommandPath -Full
    exit 0
}

Write-Host "`n=== TOP PROCESSES BY CPU ===" -ForegroundColor Cyan
Get-Process |
    Sort-Object CPU -Descending |
    Select-Object -First 20 Name, CPU,
        @{N='RAM_MB'; E={[math]::Round($_.WorkingSet64 / 1MB, 1)}}, Id |
    Format-Table -AutoSize

Write-Host "`n=== MEMORY ===" -ForegroundColor Cyan
$os = Get-WmiObject Win32_OperatingSystem
$totalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
$freeGB  = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
$usedGB  = [math]::Round($totalGB - $freeGB, 1)
Write-Host "Total: ${totalGB} GB   Used: ${usedGB} GB   Free: ${freeGB} GB"

Write-Host "`n=== CPU LOAD ===" -ForegroundColor Cyan
$cpuLoad = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
Write-Host "Overall CPU load: ${cpuLoad}%"

Write-Host "`n=== DISK HEALTH ===" -ForegroundColor Cyan
Get-WmiObject Win32_DiskDrive |
    Select-Object Model, Status, Size |
    Format-Table -AutoSize

Write-Host "`n=== REMOTE ACCESS SOFTWARE (if any) ===" -ForegroundColor Cyan
$remoteProcs = Get-Process | Where-Object {
    $_.Name -match 'vnc|teamviewer|anydesk|ammyy|logmein|screenconnect|rustdesk|parsec|supremo|splashtop|ultraviewer'
}
if ($remoteProcs) {
    $remoteProcs | Select-Object Name, Id, CPU | Format-Table -AutoSize
} else {
    Write-Host "None found." -ForegroundColor Green
}

Write-Host "`n=== STARTUP IMPACT (high-impact programs) ===" -ForegroundColor Cyan
Get-CimInstance Win32_StartupCommand |
    Select-Object Name, Command, Location |
    Format-Table -AutoSize
