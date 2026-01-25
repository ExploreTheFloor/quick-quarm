# Check-ShutdownCause.ps1
# Diagnose why the Quick Quarm VM is shutting down

#Requires -RunAsAdministrator

param(
    [string]$VMName = "QuickQuarm",
    [string]$SSHKeyPath = "$env:USERPROFILE\QuickQuarm-VM\id_rsa",
    [string]$VMUser = "root"
)

Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "Quick Quarm Shutdown Diagnostic Tool" -ForegroundColor Cyan
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host ""

# Check if VM exists
$vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if (-not $vm) {
    Write-Host "ERROR: VM '$VMName' not found" -ForegroundColor Red
    exit 1
}

Write-Host "[1/6] VM Status" -ForegroundColor Yellow
Write-Host "  State: $($vm.State)" -ForegroundColor White
Write-Host "  Uptime: $($vm.Uptime)" -ForegroundColor White
Write-Host "  CPU Usage: $($vm.CPUUsage)%" -ForegroundColor White
Write-Host "  Memory: $([math]::Round($vm.MemoryAssigned/1GB, 2))GB / $([math]::Round($vm.MemoryStartup/1GB, 2))GB" -ForegroundColor White
Write-Host ""

Write-Host "[2/6] Hyper-V Configuration" -ForegroundColor Yellow
Write-Host "  Automatic Stop Action: $($vm.AutomaticStopAction)" -ForegroundColor White
Write-Host "  Automatic Start Action: $($vm.AutomaticStartAction)" -ForegroundColor White
Write-Host "  Automatic Critical Error Action: $($vm.AutomaticCriticalErrorAction)" -ForegroundColor White

if ($vm.AutomaticStopAction -ne "Save") {
    Write-Host "  ! WARNING: VM will shut down (not save) when host stops" -ForegroundColor Yellow
    Write-Host "    Recommendation: Set-VM -Name $VMName -AutomaticStopAction Save" -ForegroundColor Gray
}
Write-Host ""

Write-Host "[3/6] Network Configuration" -ForegroundColor Yellow
$netAdapter = Get-VMNetworkAdapter -VMName $VMName
Write-Host "  Switch: $($netAdapter.SwitchName)" -ForegroundColor White
Write-Host "  Status: $($netAdapter.Status)" -ForegroundColor White

# Try to get IP address
$vmIP = $null
if ($vm.State -eq "Running") {
    $netAdapter = Get-VMNetworkAdapter -VMName $VMName
    if ($netAdapter.IPAddresses -and $netAdapter.IPAddresses.Count -gt 0) {
        $vmIP = $netAdapter.IPAddresses | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1
        Write-Host "  IP Address: $vmIP" -ForegroundColor White
    } else {
        Write-Host "  IP Address: Not detected yet" -ForegroundColor Yellow
        
        # Try to get from port forwarding
        $portProxy = netsh interface portproxy show v4tov4 | Select-String "2222"
        if ($portProxy -and $portProxy -match '(\d+\.\d+\.\d+\.\d+)') {
            $vmIP = $matches[1]
            Write-Host "  IP Address (from port forward): $vmIP" -ForegroundColor White
        }
    }
}
Write-Host ""

# If VM is running and we have SSH access, check inside the VM
if ($vm.State -eq "Running" -and (Test-Path $SSHKeyPath)) {
    Write-Host "[4/6] Connecting to VM for internal checks..." -ForegroundColor Yellow
    
    # Determine SSH connection string
    $sshHost = "localhost"
    $sshPort = 2222
    
    # Test SSH connection
    $sshTest = Test-NetConnection -ComputerName $sshHost -Port $sshPort -InformationLevel Quiet -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
    
    if ($sshTest) {
        Write-Host "  SSH connection: OK" -ForegroundColor Green
        Write-Host ""
        
        # Check system uptime
        Write-Host "[5/6] System Information" -ForegroundColor Yellow
        ssh -i $SSHKeyPath -p $sshPort -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL -o ConnectTimeout=5 "${VMUser}@${sshHost}" "uptime" 2>$null
        
        # Check power management settings
        Write-Host ""
        Write-Host "[6/6] Power Management & Services" -ForegroundColor Yellow
        
        $script = @'
echo "  === Suspend/Hibernate Status ==="
systemctl status sleep.target 2>/dev/null | grep -i "active\|loaded" || echo "  sleep.target: N/A"
systemctl status suspend.target 2>/dev/null | grep -i "active\|loaded" || echo "  suspend.target: N/A"
systemctl status hibernate.target 2>/dev/null | grep -i "active\|loaded" || echo "  hibernate.target: N/A"

echo ""
echo "  === Quick Quarm Services ==="
systemctl is-active quick-quarm.target 2>/dev/null || echo "  quick-quarm.target: inactive"
systemctl list-units 'eqemu-*.service' --no-pager --no-legend | awk '{print "  "$1": "$3}' 2>/dev/null

echo ""
echo "  === Recent Shutdowns/Reboots (last 10) ==="
last -x shutdown reboot -n 10 2>/dev/null | head -10 | sed 's/^/  /' || echo "  No shutdown history found"

echo ""
echo "  === Recent Service Failures ==="
journalctl -u quick-quarm.target --no-pager -n 20 --since "24 hours ago" 2>/dev/null | grep -i "failed\|error\|stopped" | tail -5 | sed 's/^/  /' || echo "  No recent failures"

echo ""
echo "  === Memory Usage ==="
free -h | sed 's/^/  /'

echo ""
echo "  === Disk Usage ==="
df -h / | sed 's/^/  /'
'@
        
        ssh -i $SSHKeyPath -p $sshPort -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL -o ConnectTimeout=5 "${VMUser}@${sshHost}" "$script" 2>$null
        
    } else {
        Write-Host "  SSH connection: Failed (port $sshPort not responding)" -ForegroundColor Red
        Write-Host "  ! Cannot check internal VM status" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "[5/6] System Information - SKIPPED (no SSH)" -ForegroundColor Gray
        Write-Host "[6/6] Power Management & Services - SKIPPED (no SSH)" -ForegroundColor Gray
    }
} else {
    if ($vm.State -ne "Running") {
        Write-Host "[4/6] VM is not running - cannot check internal status" -ForegroundColor Gray
        Write-Host "[5/6] System Information - SKIPPED (VM not running)" -ForegroundColor Gray
        Write-Host "[6/6] Power Management & Services - SKIPPED (VM not running)" -ForegroundColor Gray
    } else {
        Write-Host "[4/6] SSH key not found at: $SSHKeyPath" -ForegroundColor Yellow
        Write-Host "[5/6] System Information - SKIPPED (no SSH key)" -ForegroundColor Gray
        Write-Host "[6/6] Power Management & Services - SKIPPED (no SSH key)" -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "Recommendations" -ForegroundColor Cyan
Write-Host "=======================================" -ForegroundColor Cyan

$hasIssues = $false

if ($vm.AutomaticStopAction -ne "Save") {
    Write-Host "1. Fix Hyper-V auto-stop action:" -ForegroundColor Yellow
    Write-Host "   Set-VM -Name $VMName -AutomaticStopAction Save" -ForegroundColor White
    $hasIssues = $true
}

if ($vm.State -eq "Running") {
    Write-Host "2. Check/fix power management inside VM:" -ForegroundColor Yellow
    Write-Host "   .\Fix-AutoShutdown.ps1" -ForegroundColor White
    $hasIssues = $true
}

if (-not $vmIP -or $vmIP -match '^172\.16\.') {
    Write-Host "3. Consider using static IP to prevent DHCP lease expiration:" -ForegroundColor Yellow
    Write-Host "   .\QuarmUninstaller-HyperV.ps1" -ForegroundColor White
    Write-Host "   .\QuarmInstaller-HyperV.ps1 -UseStaticIP" -ForegroundColor White
    $hasIssues = $true
}

if (-not $hasIssues) {
    Write-Host "No obvious issues detected!" -ForegroundColor Green
    Write-Host "VM appears to be configured correctly." -ForegroundColor Green
}

Write-Host ""
