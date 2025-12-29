# Quick Quarm Update Script for Windows (WSL2)
# This script runs the update script which stops the server, updates code/database, and restarts

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Quick Quarm Update" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This will:" -ForegroundColor Yellow
Write-Host "  1. Stop the Quick Quarm server" -ForegroundColor Yellow
Write-Host "  2. Update source code (if using default repo)" -ForegroundColor Yellow
Write-Host "  3. Update database" -ForegroundColor Yellow
Write-Host "  4. Build and install binaries" -ForegroundColor Yellow
Write-Host "  5. Restart the server" -ForegroundColor Yellow
Write-Host ""

# Check if WSL is available
try {
    $wslCheck = wsl --status 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: WSL is not available or not properly configured." -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-Host "Error: WSL command not found. Please ensure WSL2 is installed." -ForegroundColor Red
    exit 1
}

Write-Host "Running update script..." -ForegroundColor Green
Write-Host ""

# Run the update script through WSL
wsl -d Ubuntu-22.04 bash -c "cd /root/quick-quarm && sudo ./scripts/update"

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "Update completed successfully!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
}
else {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "Update failed with exit code: $LASTEXITCODE" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    exit $LASTEXITCODE
}

