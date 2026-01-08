# Quick script to add port 9000 forwarding for Quick Quarm
# Must be run as Administrator

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Quick Quarm Port Forwarding Fix" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "ERROR: This script must be run as Administrator!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please:" -ForegroundColor Yellow
    Write-Host "  1. Right-click on PowerShell" -ForegroundColor White
    Write-Host "  2. Select 'Run as Administrator'" -ForegroundColor White
    Write-Host "  3. Navigate to this directory and run:" -ForegroundColor White
    Write-Host "     .\setup\fix-port-forwarding.ps1" -ForegroundColor Cyan
    Write-Host ""
    exit 1
}

# Get WSL2 IP
Write-Host "Getting WSL2 IP address..." -ForegroundColor Yellow
try {
    $wslIPOutput = wsl -d Ubuntu-22.04 -e hostname -I 2>&1
    $wslIP = ($wslIPOutput -split '\s+' | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1).Trim()
    
    if (-not $wslIP) {
        Write-Host "ERROR: Could not get WSL2 IP address" -ForegroundColor Red
        Write-Host "Make sure WSL2 is running: wsl -d Ubuntu-22.04" -ForegroundColor Yellow
        exit 1
    }
    
    Write-Host "  WSL2 IP: $wslIP" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to get WSL2 IP: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Setting up port forwarding for port 9000..." -ForegroundColor Yellow

# Remove existing port 9000 forwarding if any
netsh interface portproxy delete v4tov4 listenport=9000 listenaddress=0.0.0.0 2>&1 | Out-Null

# Add port 9000 forwarding
$result = netsh interface portproxy add v4tov4 listenport=9000 listenaddress=0.0.0.0 connectport=9000 connectaddress=$wslIP 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "  SUCCESS: Port 9000 forwarding configured" -ForegroundColor Green
    Write-Host "  Forwarding: 0.0.0.0:9000 -> $wslIP:9000" -ForegroundColor Gray
} else {
    Write-Host "  ERROR: Failed to configure port 9000 forwarding" -ForegroundColor Red
    Write-Host "  Output: $result" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "Verifying port forwarding..." -ForegroundColor Yellow
netsh interface portproxy show all | Select-String -Pattern "9000"

Write-Host ""
Write-Host "Testing connectivity..." -ForegroundColor Yellow
$test = Test-NetConnection -ComputerName 192.168.0.159 -Port 9000 -WarningAction SilentlyContinue
if ($test.TcpTestSucceeded) {
    Write-Host "  SUCCESS: Port 9000 is now accessible!" -ForegroundColor Green
} else {
    Write-Host "  WARNING: Port 9000 test failed, but forwarding is configured" -ForegroundColor Yellow
    Write-Host "  The world server may need to be restarted" -ForegroundColor Gray
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "Port Forwarding Configuration Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Your EQ client should now be able to connect using:" -ForegroundColor Cyan
Write-Host "  LoginServer=192.168.0.159:6000" -ForegroundColor White
Write-Host ""





