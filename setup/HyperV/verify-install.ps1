param(
    [string]$VMIP,
    [string]$SSHKeyPath,
    [string]$Username,
    [string]$DBUser,
    [string]$DBPassword
)

Write-Host ""
Write-Host "Verifying installation..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

$verifyFailed = $false

# Test SSH connectivity
Write-Host "  - Testing SSH to VM ($VMIP)..." -ForegroundColor Gray
$sshTest = Test-NetConnection -ComputerName $VMIP -Port 22 -WarningAction SilentlyContinue -InformationLevel Quiet
if ($sshTest) {
    Write-Host "    [PASS] SSH accessible" -ForegroundColor Green
} else {
    Write-Host "    [FAIL] SSH not accessible" -ForegroundColor Red
    $verifyFailed = $true
}

# Test Quick Quarm services
Write-Host "  - Testing Quick Quarm services..." -ForegroundColor Gray
$qqStatus = ssh -i $SSHKeyPath -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL "$Username@$VMIP" "systemctl is-active quick-quarm.target" 2>&1
if ($qqStatus -match "active") {
    Write-Host "    [PASS] Quick Quarm services running" -ForegroundColor Green
} else {
    Write-Host "    [FAIL] Quick Quarm services: $qqStatus" -ForegroundColor Red
    $verifyFailed = $true
}

# Test database
Write-Host "  - Testing database..." -ForegroundColor Gray
$dbTest = ssh -i $SSHKeyPath -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL "$Username@$VMIP" "mysql -u$DBUser -p$DBPassword -e 'SELECT 1' 2>/dev/null" 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "    [PASS] Database accessible" -ForegroundColor Green
} else {
    Write-Host "    [WARN] Could not verify database" -ForegroundColor Yellow
}

# Test server processes
Write-Host "  - Testing server processes..." -ForegroundColor Gray
$processTest = ssh -i $SSHKeyPath -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL "$Username@$VMIP" "pgrep -f 'world|zone' | wc -l" 2>&1
# Extract just the numeric value (handle array output from SSH)
$processCount = ($processTest | Where-Object { $_ -match '^\s*\d+\s*$' } | Select-Object -First 1)
if ($processCount) {
    $processCount = $processCount.Trim()
}
if ($processCount -and [int]$processCount -gt 0) {
    Write-Host "    [PASS] Server processes running ($processCount processes)" -ForegroundColor Green
} else {
    Write-Host "    [WARN] Could not verify server processes" -ForegroundColor Yellow
}

# Display verification results
Write-Host ""
if ($verifyFailed) {
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "Installation Verification FAILED" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "The installation completed but verification failed." -ForegroundColor Yellow
    Write-Host "Check the VM logs for errors:" -ForegroundColor Yellow
    $logCmd = "ssh -i `"$SSHKeyPath`" $Username@$VMIP 'sudo journalctl -xe'"
    Write-Host "  $logCmd" -ForegroundColor Gray
    Write-Host ""
} else {
    Write-Host "  [PASS] All verification tests PASSED" -ForegroundColor Green
    Write-Host ""
}

return -not $verifyFailed
