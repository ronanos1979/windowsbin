# System triage — quick snapshot of CPU, RAM, disk, and top processes
# Usage: powershell -ExecutionPolicy Bypass -File triage.ps1

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
