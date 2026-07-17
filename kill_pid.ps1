#Requires -RunAsAdministrator
param(
    [Parameter(Mandatory)][int]$ProcessId
)

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
