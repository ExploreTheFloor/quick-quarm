# Quick Quarm Hyper-V Fixer Script
# Consolidated script for fixing, diagnosing, and managing Quick Quarm VM
#Requires -RunAsAdministrator

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet(
        "Diagnose",           # Full diagnostic (network, services, config, shutdown causes)
        "FixConnection",      # Fix port forwarding + firewall
        "UndoConnection",     # Undo connection fix (remove port forwarding + firewall)
        "FixAutoStart",       # Configure VM auto-start
        "FixAutoShutdown",    # Fix VM auto-shutdown issues
        "FixStaticIP",        # Configure static IP
        "Verify",             # Verify installation (SSH, services, database, processes)
        "Start",              # Start VM
        "Stop",               # Stop VM
        "Restart",            # Restart VM
        "Status",             # Show VM status
        "SSH",                # Connect via SSH
        "Logs"                # View service logs
    )]
    [string]$Action,
    [string]$VMName = "QuickQuarm",
    [string]$SSHKeyPath = "$env:USERPROFILE\QuickQuarm-VM\id_rsa",
    [string]$VMUser = "root",
    [string]$StaticIP = "",
    [string]$Gateway = "",
    [string]$Netmask = "",
    [string]$DNS = "8.8.8.8,8.8.4.4",
    [int]$PreferredHostID = 100,
    [string]$DBUser = "quarm",
    [string]$DBPassword = "quarm"
)

# Import shared module
$modulePath = Join-Path $PSScriptRoot "HyperV-QuarmCommon.psm1"
if (Test-Path $modulePath) {
    Import-Module $modulePath -Force
} else {
    Write-Host "ERROR: Shared module not found at: $modulePath" -ForegroundColor Red
    exit 1
}

# Check administrator for actions that require it
$adminActions = @("Diagnose", "FixConnection", "UndoConnection", "FixAutoStart", "FixAutoShutdown", "FixStaticIP", "Start", "Stop", "Restart")
if ($adminActions -contains $Action -and -not (Test-Administrator)) {
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "Administrator Rights Required" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "This operation requires Administrator privileges." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Please:" -ForegroundColor White
    Write-Host "  1. Right-click on PowerShell" -ForegroundColor Gray
    Write-Host "  2. Select 'Run as Administrator'" -ForegroundColor Gray
    Write-Host "  3. Navigate to this directory and run:" -ForegroundColor Gray
    Write-Host "     .\QuarmFixer-HyperV.ps1 -Action $Action" -ForegroundColor Cyan
    Write-Host ""
    exit 1
}

# ============================================================================
# LOGGING SETUP
# ============================================================================

# Create logs directory
$LogDir = Join-Path $PSScriptRoot "logs"
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

# Start transcript with timestamp (include action name)
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$LogFile = Join-Path $LogDir "QuarmFixer-$Action-$Timestamp.log"
Start-Transcript -Path $LogFile -Append

Write-Host "Logging to: $LogFile" -ForegroundColor Gray
Write-Host ""

# ============================================================================

try {

# Helper function to get VM IP with config support
function Get-VMIPWithConfig {
    param([string]$VMName)
    
    $config = Get-VMConfig
    $staticIP = if ($config) { $config.StaticIP } else { $null }
    
    # Try to get from Hyper-V first
    $vmNetAdapter = Get-VMNetworkAdapter -VMName $VMName -ErrorAction SilentlyContinue
    if ($vmNetAdapter -and $vmNetAdapter.IPAddresses) {
        $reportedIP = $vmNetAdapter.IPAddresses | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1
        if ($reportedIP -and (Test-SSHConnection -Hostname $reportedIP)) {
            return $reportedIP
        }
    }
    
    # Fall back to scanning
    return (Get-VMIPAddress -VMName $VMName -TimeoutSeconds 30 -StaticIP $staticIP)
}

switch ($Action) {
    "Diagnose" {
        # ========================================
        # FULL DIAGNOSTIC
        # ========================================
        
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Quick Quarm Full Diagnostic (Hyper-V)" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""

        $issues = @()
        $warnings = @()

        # 1. Check VM
        Write-Host "[1/8] Checking Hyper-V VM..." -ForegroundColor Yellow
        $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
        if ($vm) {
            if ($vm.State -eq "Running") {
                Write-Host "  [PASS] VM '$VMName' is running" -ForegroundColor Green
            } else {
                $issues += "VM '$VMName' exists but is not running (State: $($vm.State))"
                Write-Host "  [FAIL] VM is not running (State: $($vm.State))" -ForegroundColor Red
            }
        } else {
            $issues += "VM '$VMName' not found"
            Write-Host "  [FAIL] VM '$VMName' not found" -ForegroundColor Red
        }

        # 2. Get VM IP
        Write-Host "[2/8] Getting VM IP address..." -ForegroundColor Yellow
        $vmIP = $null
        if ($vm -and $vm.State -eq "Running") {
            $vmIP = Get-VMIPWithConfig -VMName $VMName
            if ($vmIP) {
                Write-Host "  [PASS] VM IP: $vmIP" -ForegroundColor Green
            } else {
                $issues += "VM has no IPv4 address or is not responding to network probes"
                Write-Host "  [FAIL] Could not detect VM IP" -ForegroundColor Red
            }
        } else {
            Write-Host "  [SKIP] VM is not running" -ForegroundColor Yellow
        }

        # 3. Get Windows host IP
        Write-Host "[3/8] Getting Windows host IP address..." -ForegroundColor Yellow
        $hostIP = Get-WindowsHostIPv4
        if ($hostIP) {
            Write-Host "  [PASS] Windows host IP: $hostIP" -ForegroundColor Green
        } else {
            $warnings += "Could not determine Windows host IP"
            Write-Host "  [WARN] Could not detect host IP" -ForegroundColor Yellow
        }

        # 4. Check SSH
        Write-Host "[4/8] Checking SSH accessibility..." -ForegroundColor Yellow
        if ($vmIP) {
            if (Test-SSHConnection -Hostname $vmIP) {
                Write-Host "  [PASS] SSH port 22 is accessible on VM" -ForegroundColor Green
            } else {
                $issues += "SSH port 22 is not accessible on VM IP $vmIP"
                Write-Host "  [FAIL] SSH port 22 not accessible" -ForegroundColor Red
            }
        } else {
            Write-Host "  [SKIP] No VM IP address to test" -ForegroundColor Yellow
        }

        # 5. Check port forwarding
        Write-Host "[5/8] Checking port forwarding configuration..." -ForegroundColor Yellow
        if ($vmIP) {
            $portForwarding = Get-PortForwarding
            $forwarding6000 = $portForwarding -match "6000.*$vmIP"
            $forwarding5998 = $portForwarding -match "5998.*$vmIP"
            $forwarding9000 = $portForwarding -match "9000.*$vmIP"
            
            if ($forwarding6000) {
                Write-Host "  [PASS] Port 6000 forwarding configured" -ForegroundColor Green
            } else {
                Write-Host "  [WARN] Port 6000 forwarding NOT configured" -ForegroundColor Yellow
                $warnings += "Port 6000 (login server) is not forwarded"
            }
            
            if ($forwarding5998) {
                Write-Host "  [PASS] Port 5998 forwarding configured" -ForegroundColor Green
            } else {
                Write-Host "  [WARN] Port 5998 forwarding NOT configured" -ForegroundColor Yellow
                $warnings += "Port 5998 (TCP login server) is not forwarded"
            }

            if ($forwarding9000) {
                Write-Host "  [PASS] Port 9000 forwarding configured" -ForegroundColor Green
            } else {
                Write-Host "  [WARN] Port 9000 forwarding NOT configured" -ForegroundColor Yellow
                $warnings += "Port 9000 (world server) is not forwarded"
            }
        } else {
            Write-Host "  [SKIP] Cannot check port forwarding (VM IP unknown)" -ForegroundColor Yellow
        }

        # 6. Check firewall
        Write-Host "[6/8] Checking Windows Firewall rules..." -ForegroundColor Yellow
        try {
            $firewallRules = Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { 
                $_.DisplayName -match 'Quick Quarm' 
            }
            
            if ($firewallRules) {
                Write-Host "  [PASS] Found firewall rules:" -ForegroundColor Green
                foreach ($rule in $firewallRules) {
                    Write-Host "    - $($rule.DisplayName) ($($rule.Direction), $($rule.Action))" -ForegroundColor Gray
                }
            } else {
                Write-Host "  [WARN] No Quick Quarm firewall rules found" -ForegroundColor Yellow
                $warnings += "Windows Firewall may be blocking connections"
            }
        } catch {
            Write-Host "  [WARN] Error checking firewall" -ForegroundColor Yellow
        }

        # 7. Check Quick Quarm services
        Write-Host "[7/8] Checking Quick Quarm services in VM..." -ForegroundColor Yellow
        if ($vmIP -and (Test-SSHKeyExists -SSHKeyPath $SSHKeyPath)) {
            $result = Invoke-SSHCommand -SSHKeyPath $SSHKeyPath -Hostname $vmIP -User $VMUser -Command "systemctl is-active quick-quarm.target"
            if ($result.Success -and $result.Output -match "active") {
                Write-Host "  [PASS] Quick Quarm services are running" -ForegroundColor Green
            } else {
                $issues += "Quick Quarm services are not running inside VM"
                Write-Host "  [FAIL] Quick Quarm services not active" -ForegroundColor Red
                
                # Check if services are enabled
                $enabledResult = Invoke-SSHCommand -SSHKeyPath $SSHKeyPath -Hostname $vmIP -User $VMUser -Command "systemctl is-enabled quick-quarm.target 2>&1"
                if ($enabledResult.Success) {
                    if ($enabledResult.Output -match "enabled") {
                        Write-Host "    Services are enabled for auto-start" -ForegroundColor Gray
                    } else {
                        Write-Host "    Services are NOT enabled for auto-start" -ForegroundColor Yellow
                        $warnings += "Services are not enabled to start on boot"
                    }
                }
                
                # Get service status for more details
                $statusResult = Invoke-SSHCommand -SSHKeyPath $SSHKeyPath -Hostname $vmIP -User $VMUser -Command "systemctl status quick-quarm.target --no-pager -l | head -20"
                if ($statusResult.Success -and $statusResult.Output) {
                    Write-Host "    Service status:" -ForegroundColor Gray
                    $statusLines = $statusResult.Output -split "`n" | Where-Object { $_ -match "Active:|Loaded:|Main PID:|Tasks:" }
                    foreach ($line in $statusLines) {
                        Write-Host "      $line" -ForegroundColor Gray
                    }
                }
                
                # Get recent error logs
                $logResult = Invoke-SSHCommand -SSHKeyPath $SSHKeyPath -Hostname $vmIP -User $VMUser -Command "journalctl -u quick-quarm.target -n 10 --no-pager | grep -i 'error\|failed\|stopped' | tail -5"
                if ($logResult.Success -and $logResult.Output) {
                    Write-Host "    Recent errors:" -ForegroundColor Yellow
                    $logLines = $logResult.Output -split "`n" | Where-Object { $_.Trim() -ne "" }
                    foreach ($line in $logLines) {
                        Write-Host "      $line" -ForegroundColor Yellow
                    }
                }
            }
        } else {
            Write-Host "  [SKIP] Cannot check services (no SSH key or VM IP)" -ForegroundColor Yellow
        }

        # 8. Check VM auto-stop action
        Write-Host "[8/8] Checking VM auto-stop configuration..." -ForegroundColor Yellow
        if ($vm) {
            if ($vm.AutomaticStopAction -eq "Save") {
                Write-Host "  [PASS] VM auto-stop action is configured correctly" -ForegroundColor Green
            } else {
                Write-Host "  [WARN] VM auto-stop action: $($vm.AutomaticStopAction)" -ForegroundColor Yellow
                $warnings += "VM will shut down (not save) when host stops"
            }
        }

        # Summary
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Diagnostic Summary" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""

        if ($issues.Count -eq 0 -and $warnings.Count -eq 0) {
            Write-Host "All checks passed! Connection should work." -ForegroundColor Green
            Write-Host ""
            if ($hostIP) {
                Write-Host "Client Configuration:" -ForegroundColor Cyan
                Write-Host "  Use IP: ${hostIP}:6000" -ForegroundColor White
            }
        } else {
            if ($issues.Count -gt 0) {
                Write-Host "CRITICAL ISSUES (must fix):" -ForegroundColor Red
                foreach ($issue in $issues) {
                    Write-Host "  - $issue" -ForegroundColor Red
                }
                Write-Host ""
            }
            
            if ($warnings.Count -gt 0) {
                Write-Host "WARNINGS:" -ForegroundColor Yellow
                foreach ($warning in $warnings) {
                    Write-Host "  - $warning" -ForegroundColor Yellow
                }
                Write-Host ""
            }
            
            if ($issues -match "Quick Quarm services") {
                Write-Host "RECOMMENDED FIX FOR SERVICES:" -ForegroundColor Cyan
                Write-Host "  1. Try starting services: .\QuarmFixer-HyperV.ps1 -Action Start" -ForegroundColor White
                Write-Host "  2. Check service logs: .\QuarmFixer-HyperV.ps1 -Action Logs" -ForegroundColor White
                Write-Host "  3. Or connect via SSH and check: systemctl status quick-quarm.target" -ForegroundColor White
                Write-Host ""
            }
            if ($issues -match "port forwarding|firewall|SSH" -or ($issues.Count -gt 0 -and -not ($issues -match "Quick Quarm services"))) {
                Write-Host "RECOMMENDED FIX FOR CONNECTION:" -ForegroundColor Cyan
                Write-Host "  Run: .\QuarmFixer-HyperV.ps1 -Action FixConnection" -ForegroundColor White
            }
        }

        Write-Host ""
        if ($vmIP) {
            Write-Host "VM IP: $vmIP" -ForegroundColor Cyan
            if ($hostIP) {
                Write-Host "Client should connect to: ${hostIP}:6000" -ForegroundColor Cyan
            }
        }
        Write-Host ""
    }
    
    "FixConnection" {
        # ========================================
        # FIX CONNECTION (Port Forwarding + Firewall)
        # ========================================
        
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Quick Quarm Connection Fix (Hyper-V)" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""

        # Get VM IP
        Write-Host "[1/3] Getting VM IP address..." -ForegroundColor Yellow
        $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
        if (-not $vm) {
            Write-Host "  [FAIL] VM '$VMName' not found" -ForegroundColor Red
            Write-Host "  Please run the installer first: .\QuarmInstaller-HyperV.ps1" -ForegroundColor Yellow
            exit 1
        }

        if ($vm.State -ne "Running") {
            Write-Host "  [INFO] Starting VM..." -ForegroundColor Cyan
            Start-QuarmVM -VMName $VMName -WaitForReady -WaitSeconds 30
        }

        $config = Get-VMConfig
        $staticIP = if ($config) { $config.StaticIP } else { $null }
        $vmIP = Get-VMIPAddress -VMName $VMName -TimeoutSeconds 120 -StaticIP $staticIP
        
        if (-not $vmIP) {
            Write-Host "  [FAIL] Could not detect VM IP address" -ForegroundColor Red
            Write-Host "  Run diagnostic: .\QuarmFixer-HyperV.ps1 -Action Diagnose" -ForegroundColor Yellow
            exit 1
        }
        
        Write-Host "  [PASS] VM IP: $vmIP" -ForegroundColor Green

        # Set up port forwarding
        Write-Host ""
        Write-Host "[2/3] Setting up port forwarding..." -ForegroundColor Yellow
        $portCount = Set-PortForwarding -VMIP $vmIP
        if ($portCount -eq 0) {
            Write-Host "  [WARN] No port forwarding rules were configured" -ForegroundColor Yellow
        }

        # Configure firewall
        Write-Host ""
        Write-Host "[3/3] Configuring Windows Firewall..." -ForegroundColor Yellow
        $firewallCount = Set-FirewallRules
        if ($firewallCount -eq 0) {
            Write-Host "  [WARN] No firewall rules were configured" -ForegroundColor Yellow
        }

        # Get Windows host IP
        Write-Host ""
        Write-Host "Getting Windows host IP address..." -ForegroundColor Yellow
        $hostIP = Get-WindowsHostIPv4

        # Summary
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "Connection Fix Complete!" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        Write-Host ""

        Write-Host "Configuration:" -ForegroundColor Cyan
        Write-Host "  VM IP: $vmIP" -ForegroundColor White
        if ($hostIP) {
            Write-Host "  Windows Host IP: $hostIP" -ForegroundColor White
            Write-Host ""
            Write-Host "Client Configuration:" -ForegroundColor Cyan
            Write-Host "  Edit eqhost.txt and use: $($hostIP):6000" -ForegroundColor White
        }
        Write-Host ""

        Write-Host "What was fixed:" -ForegroundColor Cyan
        Write-Host "  [✓] Port forwarding configured for ports 6000, 5998, 9000" -ForegroundColor Green
        Write-Host "  [✓] Windows Firewall configured to allow connections" -ForegroundColor Green
        Write-Host ""
    }
    
    "UndoConnection" {
        # ========================================
        # UNDO CONNECTION FIX
        # ========================================
        
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Quick Quarm Connection Undo (Hyper-V)" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "This will undo all changes made by the FixConnection operation" -ForegroundColor Yellow
        Write-Host ""

        # Confirm with user
        $confirmation = Read-Host "Are you sure you want to undo the connection fix? (yes/no)"
        if ($confirmation -ne "yes") {
            Write-Host "Undo cancelled." -ForegroundColor Yellow
            exit 0
        }

        Write-Host ""

        # Remove port forwarding
        Write-Host "[1/2] Removing port forwarding..." -ForegroundColor Yellow
        $removedPorts = Remove-PortForwarding -Ports @(6000, 5998, 9000)
        if ($removedPorts -eq 0) {
            Write-Host "  [SKIP] No port forwarding rules found" -ForegroundColor Yellow
        }

        # Remove Windows Firewall rules
        Write-Host ""
        Write-Host "[2/2] Removing Windows Firewall rules..." -ForegroundColor Yellow
        $removedFirewall = Remove-FirewallRules
        if ($removedFirewall -eq 0) {
            Write-Host "  [SKIP] No Quick Quarm firewall rules found" -ForegroundColor Yellow
        }

        # Summary
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "Undo Complete!" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        Write-Host ""

        Write-Host "Changes undone:" -ForegroundColor Cyan
        Write-Host "  [✓] Port forwarding removed" -ForegroundColor Green
        Write-Host "  [✓] Windows Firewall rules removed" -ForegroundColor Green
        Write-Host ""
    }
    
    "FixAutoStart" {
        # ========================================
        # FIX AUTO-START
        # ========================================
        
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Quick Quarm VM Auto-Start Configuration" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""

        if (-not (Test-VMExists -VMName $VMName)) {
            Write-Host "ERROR: VM '$VMName' not found" -ForegroundColor Red
            exit 1
        }

        Write-Host "Configuring VM: $VMName" -ForegroundColor Cyan
        Write-Host ""

        $vm = Get-VM -Name $VMName
        Write-Host "Current settings:" -ForegroundColor Yellow
        Write-Host "  Start Action: $($vm.AutomaticStartAction)" -ForegroundColor Gray
        Write-Host "  Start Delay: $($vm.AutomaticStartDelay) seconds" -ForegroundColor Gray
        Write-Host "  Stop Action: $($vm.AutomaticStopAction)" -ForegroundColor Gray
        Write-Host ""

        Write-Host "Configuring auto-start settings..." -ForegroundColor Yellow
        if (Set-VMAutoStart -VMName $VMName) {
            Write-Host ""
            Write-Host "========================================" -ForegroundColor Green
            Write-Host "Auto-start configuration complete!" -ForegroundColor Green
            Write-Host "========================================" -ForegroundColor Green
            Write-Host ""
            Write-Host "The VM will now:" -ForegroundColor Cyan
            Write-Host "  - Start automatically when Windows boots" -ForegroundColor White
            Write-Host "  - Start automatically when Windows resumes from sleep" -ForegroundColor White
            Write-Host "  - Save state when Windows shuts down (for faster startup)" -ForegroundColor White
            Write-Host ""
        } else {
            Write-Host ""
            Write-Host "ERROR: Failed to configure auto-start settings" -ForegroundColor Red
            exit 1
        }
    }
    
    "FixAutoShutdown" {
        # ========================================
        # FIX AUTO-SHUTDOWN
        # ========================================
        
        Write-Host "=======================================" -ForegroundColor Cyan
        Write-Host "Quick Quarm Auto-Shutdown Fix Tool" -ForegroundColor Cyan
        Write-Host "=======================================" -ForegroundColor Cyan
        Write-Host ""

        if (-not (Test-VMExists -VMName $VMName)) {
            Write-Host "ERROR: VM '$VMName' not found" -ForegroundColor Red
            exit 1
        }

        $vm = Get-VM -Name $VMName
        if ($vm.State -ne "Running") {
            Write-Host "ERROR: VM is not running (State: $($vm.State))" -ForegroundColor Red
            Write-Host "Start the VM first: .\QuarmFixer-HyperV.ps1 -Action Start" -ForegroundColor Yellow
            exit 1
        }

        if (-not (Test-SSHKeyExists -SSHKeyPath $SSHKeyPath)) {
            Write-Host "ERROR: SSH key not found at: $SSHKeyPath" -ForegroundColor Red
            exit 1
        }

        Write-Host "[1/4] Fixing Hyper-V auto-stop action..." -ForegroundColor Yellow
        if ($vm.AutomaticStopAction -ne "Save") {
            Set-VM -Name $VMName -AutomaticStopAction Save
            Write-Host "  + Set VM to save state (not shutdown) when host stops" -ForegroundColor Green
        } else {
            Write-Host "  + Already configured correctly" -ForegroundColor Green
        }
        Write-Host ""

        Write-Host "[2/4] Testing SSH connection..." -ForegroundColor Yellow
        $vmIP = Get-VMIPWithConfig -VMName $VMName
        if (-not $vmIP) {
            Write-Host "  ! Could not get VM IP address" -ForegroundColor Red
            exit 1
        }

        if (-not (Test-SSHConnection -Hostname $vmIP)) {
            Write-Host "  ! SSH not responding on VM IP" -ForegroundColor Red
            Write-Host "  Try running: .\QuarmFixer-HyperV.ps1 -Action FixConnection" -ForegroundColor Yellow
            exit 1
        }
        Write-Host "  + SSH connection successful" -ForegroundColor Green
        Write-Host ""

        Write-Host "[3/4] Disabling power management inside VM..." -ForegroundColor Yellow

        $fixScript = @'
#!/bin/bash
set -e

echo "  [3.1] Masking sleep/suspend/hibernate targets..."
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target 2>/dev/null || true

echo "  [3.2] Disabling systemd idle timeout..."
mkdir -p /etc/systemd/logind.conf.d/
cat > /etc/systemd/logind.conf.d/no-suspend.conf << 'EOF'
[Login]
IdleAction=ignore
IdleActionSec=0
HandleSuspendKey=ignore
HandleHibernateKey=ignore
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandlePowerKey=ignore
EOF

echo "  [3.3] Reloading systemd configuration..."
systemctl daemon-reload 2>/dev/null || true
systemctl restart systemd-logind 2>/dev/null || true

echo "  [3.4] Disabling ACPI power button events..."
if [ -f /etc/acpi/events/powerbtn ]; then
    mv /etc/acpi/events/powerbtn /etc/acpi/events/powerbtn.disabled 2>/dev/null || true
fi
systemctl stop acpid 2>/dev/null || true
systemctl disable acpid 2>/dev/null || true

echo "  [3.5] Configuring services to restart on failure..."
mkdir -p /etc/systemd/system/eqemu-world.service.d/
cat > /etc/systemd/system/eqemu-world.service.d/restart.conf << 'EOF'
[Service]
Restart=always
RestartSec=10
EOF

mkdir -p /etc/systemd/system/eqemu-loginserver.service.d/
cat > /etc/systemd/system/eqemu-loginserver.service.d/restart.conf << 'EOF'
[Service]
Restart=always
RestartSec=10
EOF

for service in zone ucs queryserv shared-memory boats; do
    mkdir -p /etc/systemd/system/eqemu-${service}.service.d/
    cat > /etc/systemd/system/eqemu-${service}.service.d/restart.conf << 'EOF'
[Service]
Restart=always
RestartSec=10
EOF
done

echo "  [3.6] Reloading service configurations..."
systemctl daemon-reload

echo "  [3.7] Disabling unattended upgrades that might restart services..."
systemctl stop unattended-upgrades 2>/dev/null || true
systemctl disable unattended-upgrades 2>/dev/null || true

echo "  + Power management disabled successfully"
'@

        $tempScript = [System.IO.Path]::GetTempFileName() + ".sh"
        $fixScript = $fixScript -replace "`r`n", "`n" -replace "`r", "`n"
        [System.IO.File]::WriteAllText($tempScript, $fixScript, [System.Text.UTF8Encoding]::new($false))

        # Copy and execute script
        if (Copy-ToVM -SSHKeyPath $SSHKeyPath -Hostname $vmIP -User $VMUser -SourcePath $tempScript -DestPath "/tmp/fix_shutdown.sh") {
            $result = Invoke-SSHCommand -SSHKeyPath $SSHKeyPath -Hostname $vmIP -User $VMUser -Command "chmod +x /tmp/fix_shutdown.sh && sudo /tmp/fix_shutdown.sh && rm /tmp/fix_shutdown.sh"
            if (-not $result.Success) {
                Write-Host "  ! Warning: Script execution had issues" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  ! Failed to copy script to VM" -ForegroundColor Red
        }

        Remove-Item $tempScript -Force -ErrorAction SilentlyContinue

        Write-Host ""
        Write-Host "[4/4] Verifying fixes..." -ForegroundColor Yellow

        $verifyScript = @'
echo -n "  Sleep/Suspend targets: "
systemctl status sleep.target 2>&1 | grep -q "masked" && echo "MASKED ✓" || echo "NOT MASKED ✗"

echo -n "  Systemd logind config: "
[ -f /etc/systemd/logind.conf.d/no-suspend.conf ] && echo "CONFIGURED ✓" || echo "NOT CONFIGURED ✗"

echo -n "  Service auto-restart: "
grep -q "Restart=always" /etc/systemd/system/eqemu-world.service.d/restart.conf 2>/dev/null && echo "ENABLED ✓" || echo "NOT ENABLED ✗"

echo -n "  Quick Quarm status: "
systemctl is-active quick-quarm.target 2>/dev/null || echo "inactive"
'@

        $result = Invoke-SSHCommand -SSHKeyPath $SSHKeyPath -Hostname $vmIP -User $VMUser -Command $verifyScript
        if ($result.Success) {
            Write-Host $result.Output
        }

        Write-Host ""
        Write-Host "=======================================" -ForegroundColor Green
        Write-Host "Fix Applied Successfully!" -ForegroundColor Green
        Write-Host "=======================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "The following changes were made:" -ForegroundColor Cyan
        Write-Host "  ✓ Hyper-V VM set to save state (not shutdown)" -ForegroundColor White
        Write-Host "  ✓ Sleep/suspend/hibernate disabled in VM" -ForegroundColor White
        Write-Host "  ✓ Systemd idle timeout disabled" -ForegroundColor White
        Write-Host "  ✓ ACPI power button events disabled" -ForegroundColor White
        Write-Host "  ✓ Services configured to auto-restart on failure" -ForegroundColor White
        Write-Host "  ✓ Unattended upgrades disabled" -ForegroundColor White
        Write-Host ""
    }
    
    "Verify" {
        # ========================================
        # VERIFY INSTALLATION
        # ========================================
        
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Quick Quarm Installation Verification" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Verifying installation..." -ForegroundColor Yellow
        Start-Sleep -Seconds 5
        
        $verifyFailed = $false
        
        # Load credentials from config FIRST (before any operations)
        $config = Get-VMConfig
        if ($config) {
            # Always prefer config SSH key path if it exists
            if ($config.SSHKeyPath -and (Test-Path $config.SSHKeyPath)) {
                $SSHKeyPath = $config.SSHKeyPath
                Write-Host "  [INFO] Using SSH key from config: $SSHKeyPath" -ForegroundColor Cyan
            }
            if (-not $VMUser -or $VMUser -eq "root") { 
                if ($config.InstallUser) { $VMUser = $config.InstallUser }
            }
            if (-not $DBUser) { $DBUser = $config.DBUser }
            if (-not $DBPassword) { $DBPassword = $config.DBPassword }
        }
        
        # Validate SSH key exists before proceeding
        if (-not (Test-SSHKeyExists -SSHKeyPath $SSHKeyPath)) {
            Write-Host "  [FAIL] SSH key not found at: $SSHKeyPath" -ForegroundColor Red
            Write-Host "  [ERROR] Cannot verify installation without SSH key" -ForegroundColor Red
            Write-Host "  Please ensure the SSH key exists or run the installer again." -ForegroundColor Yellow
            exit 1
        }
        
        Write-Host "  [INFO] Using SSH key: $SSHKeyPath" -ForegroundColor Cyan
        Write-Host "  [INFO] SSH user: $VMUser" -ForegroundColor Cyan
        
        # Get VM IP
        $vmIP = Get-VMIPWithConfig -VMName $VMName
        if (-not $vmIP) {
            Write-Host "  [FAIL] Could not detect VM IP address" -ForegroundColor Red
            Write-Host "  VM may not be running or network is not configured" -ForegroundColor Yellow
            exit 1
        }
        
        # Test SSH key authentication BEFORE attempting any commands
        Write-Host "  - Testing SSH key authentication..." -ForegroundColor Gray
        $testResult = Invoke-SSHCommand -SSHKeyPath $SSHKeyPath -Hostname $vmIP -User $VMUser -Command "echo 'SSH key authentication successful'"
        if (-not $testResult.Success) {
            Write-Host "  [FAIL] SSH key authentication failed" -ForegroundColor Red
            Write-Host "  [ERROR] Output: $($testResult.Output)" -ForegroundColor Red
            Write-Host "  [INFO] This usually means:" -ForegroundColor Yellow
            Write-Host "    - The SSH key was not properly added to the VM during installation" -ForegroundColor Yellow
            Write-Host "    - The SSH key path is incorrect" -ForegroundColor Yellow
            Write-Host "    - The VM's SSH server is not accepting key authentication" -ForegroundColor Yellow
            Write-Host "  [INFO] You can try connecting manually to verify:" -ForegroundColor Cyan
            Write-Host "    ssh -i `"$SSHKeyPath`" $VMUser@$vmIP" -ForegroundColor Gray
            exit 1
        }
        Write-Host "    [PASS] SSH key authentication successful" -ForegroundColor Green
        
        # Test SSH connectivity
        Write-Host "  - Testing SSH to VM ($vmIP)..." -ForegroundColor Gray
        if (Test-SSHConnection -Hostname $vmIP) {
            Write-Host "    [PASS] SSH accessible" -ForegroundColor Green
        } else {
            Write-Host "    [FAIL] SSH not accessible" -ForegroundColor Red
            $verifyFailed = $true
        }
        
        # Test Quick Quarm services
        Write-Host "  - Testing Quick Quarm services..." -ForegroundColor Gray
        $result = Invoke-SSHCommand -SSHKeyPath $SSHKeyPath -Hostname $vmIP -User $VMUser -Command "systemctl is-active quick-quarm.target"
        if ($result.Success -and $result.Output -match "active") {
            Write-Host "    [PASS] Quick Quarm services running" -ForegroundColor Green
        } else {
            Write-Host "    [FAIL] Quick Quarm services: $($result.Output)" -ForegroundColor Red
            $verifyFailed = $true
        }
        
        # Test database
        Write-Host "  - Testing database..." -ForegroundColor Gray
        if ($DBUser -and $DBPassword) {
            $result = Invoke-SSHCommand -SSHKeyPath $SSHKeyPath -Hostname $vmIP -User $VMUser -Command "mysql -u'$DBUser' -p'$DBPassword' -e 'SELECT 1' 2>/dev/null"
            if ($result.Success) {
                Write-Host "    [PASS] Database accessible" -ForegroundColor Green
            } else {
                Write-Host "    [WARN] Could not verify database" -ForegroundColor Yellow
            }
        } else {
            Write-Host "    [SKIP] Database credentials not provided" -ForegroundColor Yellow
        }
        
        # Test server processes
        Write-Host "  - Testing server processes..." -ForegroundColor Gray
        $result = Invoke-SSHCommand -SSHKeyPath $SSHKeyPath -Hostname $vmIP -User $VMUser -Command "pgrep -f 'world|zone' | wc -l"
        if ($result.Success) {
            # Extract just the numeric value (handle array output from SSH)
            $processCount = ($result.Output | Where-Object { $_ -match '^\s*\d+\s*$' } | Select-Object -First 1)
            if ($processCount) {
                $processCount = $processCount.Trim()
            }
            if ($processCount -and [int]$processCount -gt 0) {
                Write-Host "    [PASS] Server processes running ($processCount processes)" -ForegroundColor Green
            } else {
                Write-Host "    [WARN] Could not verify server processes" -ForegroundColor Yellow
            }
        } else {
            Write-Host "    [WARN] Could not check server processes" -ForegroundColor Yellow
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
            Write-Host "  .\QuarmFixer-HyperV.ps1 -Action Logs" -ForegroundColor Gray
            Write-Host ""
            exit 1
        } else {
            Write-Host "  [PASS] All verification tests PASSED" -ForegroundColor Green
            Write-Host ""
        }
    }
    
    "FixStaticIP" {
        # ========================================
        # FIX STATIC IP
        # ========================================
        
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Quick Quarm VM Static IP Configuration" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""

        if (-not (Test-SSHKeyExists -SSHKeyPath $SSHKeyPath)) {
            Write-Host "ERROR: SSH key not found at: $SSHKeyPath" -ForegroundColor Red
            exit 1
        }

        # Auto-detect network configuration if not provided
        if ([string]::IsNullOrEmpty($StaticIP) -or [string]::IsNullOrEmpty($Gateway) -or [string]::IsNullOrEmpty($Netmask)) {
            Write-Host "Auto-detecting network configuration..." -ForegroundColor Yellow
            $networkConfig = Get-DefaultSwitchNetworkConfig -PreferredHostID $PreferredHostID
            
            if ($networkConfig) {
                if ([string]::IsNullOrEmpty($StaticIP)) { $StaticIP = $networkConfig.StaticIP }
                if ([string]::IsNullOrEmpty($Gateway)) { $Gateway = $networkConfig.Gateway }
                if ([string]::IsNullOrEmpty($Netmask)) { $Netmask = $networkConfig.Netmask }
                Write-Host ""
            } else {
                Write-Host "ERROR: Could not auto-detect network configuration" -ForegroundColor Red
                Write-Host "Please provide -StaticIP, -Gateway, and -Netmask parameters manually." -ForegroundColor Yellow
                exit 1
            }
        }

        # Validate required parameters
        if ([string]::IsNullOrEmpty($StaticIP) -or [string]::IsNullOrEmpty($Gateway) -or [string]::IsNullOrEmpty($Netmask)) {
            Write-Host "ERROR: StaticIP, Gateway, and Netmask are required" -ForegroundColor Red
            exit 1
        }

        # Detect VM IP if not provided
        $vmIP = Get-VMIPWithConfig -VMName $VMName
        if (-not $vmIP) {
            Write-Host "ERROR: Could not detect VM IP address" -ForegroundColor Red
            exit 1
        }

        # Parse connection string
        $sshHost = $vmIP
        $sshPort = 22

        # Convert netmask to prefix length if needed
        $prefixLength = $Netmask
        if ($Netmask -match '^\d+\.\d+\.\d+\.\d+$') {
            $octets = $Netmask.Split('.')
            $binary = ""
            foreach ($octet in $octets) {
                $binary += [Convert]::ToString([int]$octet, 2).PadLeft(8, '0')
            }
            $prefixLength = ($binary -replace '0+$', '').Length
        }

        # Parse DNS servers
        $dnsServers = $DNS -split ',' | ForEach-Object { $_.Trim() }

        Write-Host "Configuration:" -ForegroundColor Cyan
        Write-Host "  Static IP: $StaticIP/$prefixLength" -ForegroundColor White
        Write-Host "  Gateway: $Gateway" -ForegroundColor White
        Write-Host "  DNS: $($dnsServers -join ', ')" -ForegroundColor White
        Write-Host "  SSH: ${VMUser}@${sshHost}:${sshPort}" -ForegroundColor White
        Write-Host ""

        # Create netplan configuration script
        $netplanScript = @"
#!/bin/bash
set -e

echo 'Configuring static IP address...'

# Find the network interface
INTERFACE=`$(ip -o -4 route show to default | awk '{print `$5}' | head -1)
if [ -z "`$INTERFACE" ]; then
    INTERFACE=`$(ls /sys/class/net | grep -E '^(eth|en)' | head -1)
fi

if [ -z "`$INTERFACE" ]; then
    echo "ERROR: Could not detect network interface"
    exit 1
fi

echo "Detected interface: `$INTERFACE"

# Backup existing netplan config
if [ -f /etc/netplan/50-cloud-init.yaml ]; then
    sudo cp /etc/netplan/50-cloud-init.yaml /etc/netplan/50-cloud-init.yaml.backup
    echo "Backed up existing netplan config"
fi

# Create new netplan configuration
sudo tee /etc/netplan/50-quickquarm-static.yaml > /dev/null <<NETPLAN_EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    `$INTERFACE:
      addresses:
        - $StaticIP/$prefixLength
      routes:
        - to: default
          via: $Gateway
      nameservers:
        addresses: [$($dnsServers -join ', ')]
NETPLAN_EOF

echo "Netplan configuration created"

# Apply the configuration
echo "Applying netplan configuration..."
sudo netplan apply

echo ""
echo "Static IP configuration complete!"
echo "New IP address: $StaticIP/$prefixLength"
"@

        # Test SSH connection
        Write-Host "Testing SSH connection..." -ForegroundColor Yellow
        if (-not (Test-SSHConnection -Hostname $vmIP)) {
            Write-Host "  ! SSH connection failed" -ForegroundColor Red
            exit 1
        }
        Write-Host "  + SSH connection successful" -ForegroundColor Green
        Write-Host ""

        # Save script to temp file
        $scriptPath = [System.IO.Path]::GetTempFileName() + ".sh"
        $netplanScript = $netplanScript -replace "`r`n", "`n" -replace "`r", "`n"
        [System.IO.File]::WriteAllText($scriptPath, $netplanScript, [System.Text.UTF8Encoding]::new($false))

        # Copy script to VM
        Write-Host "Copying configuration script to VM..." -ForegroundColor Yellow
        if (-not (Copy-ToVM -SSHKeyPath $SSHKeyPath -Hostname $vmIP -Port $sshPort -User $VMUser -SourcePath $scriptPath -DestPath "/tmp/configure_static_ip.sh")) {
            Write-Host "  ! Failed to copy script to VM" -ForegroundColor Red
            Remove-Item $scriptPath -Force -ErrorAction SilentlyContinue
            exit 1
        }

        # Execute script on VM
        Write-Host "Executing configuration on VM..." -ForegroundColor Yellow
        Write-Host ""
        $result = Invoke-SSHCommand -SSHKeyPath $SSHKeyPath -Hostname $vmIP -Port $sshPort -User $VMUser -Command "chmod +x /tmp/configure_static_ip.sh && /tmp/configure_static_ip.sh"

        if ($result.Success) {
            Write-Host ""
            Write-Host "========================================" -ForegroundColor Green
            Write-Host "Static IP configuration complete!" -ForegroundColor Green
            Write-Host "========================================" -ForegroundColor Green
            Write-Host ""
            Write-Host "VM is now configured with static IP: $StaticIP/$prefixLength" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "Note: If you lost SSH connection, reconnect using:" -ForegroundColor Yellow
            Write-Host "  ssh -i `"$SSHKeyPath`" ${VMUser}@${StaticIP}" -ForegroundColor White
        } else {
            Write-Host ""
            Write-Host "ERROR: Configuration failed" -ForegroundColor Red
        }

        # Cleanup
        Remove-Item $scriptPath -Force -ErrorAction SilentlyContinue
    }
    
    "Start" {
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Starting Quick Quarm VM and Services" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        
        # Start the VM
        Write-Host "[1/3] Starting Hyper-V VM..." -ForegroundColor Yellow
        if (-not (Start-QuarmVM -VMName $VMName -WaitForReady -WaitSeconds 30)) {
            Write-Host "  [FAIL] Failed to start VM" -ForegroundColor Red
            exit 1
        }
        Write-Host "  [PASS] VM started successfully" -ForegroundColor Green
        Write-Host ""
        
        # Get VM IP address
        Write-Host "[2/3] Getting VM IP address..." -ForegroundColor Yellow
        $config = Get-VMConfig
        $staticIP = if ($config) { $config.StaticIP } else { $null }
        $vmIP = Get-VMIPAddress -VMName $VMName -TimeoutSeconds 120 -StaticIP $staticIP
        
        if (-not $vmIP) {
            Write-Host "  [FAIL] Could not detect VM IP address" -ForegroundColor Red
            Write-Host "  VM may still be booting. Services will not be started." -ForegroundColor Yellow
            Write-Host "  You can start services manually via SSH:" -ForegroundColor Yellow
            Write-Host "    ssh -i `"$SSHKeyPath`" $VMUser@<VM_IP> 'systemctl start quick-quarm.target'" -ForegroundColor Gray
            exit 1
        }
        Write-Host "  [PASS] VM IP Address: $vmIP" -ForegroundColor Green
        Write-Host ""
        
        # Start quarm services
        Write-Host "[3/3] Starting Quick Quarm services..." -ForegroundColor Yellow
        if (-not (Test-SSHKeyExists -SSHKeyPath $SSHKeyPath)) {
            Write-Host "  [WARN] SSH key not found at: $SSHKeyPath" -ForegroundColor Yellow
            Write-Host "  Cannot start services automatically." -ForegroundColor Yellow
            Write-Host "  Start services manually via SSH:" -ForegroundColor Yellow
            Write-Host "    ssh -i `"$SSHKeyPath`" $VMUser@$vmIP 'systemctl start quick-quarm.target'" -ForegroundColor Gray
            exit 1
        }
        
        # Wait a bit more for SSH to be fully ready
        Write-Host "  - Waiting for SSH to be ready..." -ForegroundColor Gray
        $sshReady = $false
        for ($i = 0; $i -lt 10; $i++) {
            if (Test-SSHConnection -Hostname $vmIP) {
                $sshReady = $true
                break
            }
            Start-Sleep -Seconds 2
        }
        
        if (-not $sshReady) {
            Write-Host "  [WARN] SSH not responding yet" -ForegroundColor Yellow
            Write-Host "  Services will not be started automatically." -ForegroundColor Yellow
            Write-Host "  Start services manually via SSH:" -ForegroundColor Yellow
            Write-Host "    ssh -i `"$SSHKeyPath`" $VMUser@$vmIP 'systemctl start quick-quarm.target'" -ForegroundColor Gray
            exit 1
        }
        
        # Check if services are enabled, enable if not
        Write-Host "  - Checking if services are enabled..." -ForegroundColor Gray
        $enabledResult = Invoke-SSHCommand -SSHKeyPath $SSHKeyPath -Hostname $vmIP -User $VMUser -Command "systemctl is-enabled quick-quarm.target 2>&1"
        if ($enabledResult.Success -and $enabledResult.Output -notmatch "enabled") {
            Write-Host "  - Enabling services to start on boot..." -ForegroundColor Gray
            $enableResult = Invoke-SSHCommand -SSHKeyPath $SSHKeyPath -Hostname $vmIP -User $VMUser -Command "systemctl enable quick-quarm.target"
            if ($enableResult.Success) {
                Write-Host "    + Services enabled" -ForegroundColor Green
            } else {
                Write-Host "    ! Warning: Failed to enable services" -ForegroundColor Yellow
            }
        } else {
            Write-Host "    + Services already enabled" -ForegroundColor Green
        }
        
        # Start the services
        Write-Host "  - Starting Quick Quarm services..." -ForegroundColor Gray
        $result = Invoke-SSHCommand -SSHKeyPath $SSHKeyPath -Hostname $vmIP -User $VMUser -Command "systemctl start quick-quarm.target"
        if ($result.Success) {
            # Wait a moment and verify services are actually running
            Start-Sleep -Seconds 3
            $statusResult = Invoke-SSHCommand -SSHKeyPath $SSHKeyPath -Hostname $vmIP -User $VMUser -Command "systemctl is-active quick-quarm.target"
            if ($statusResult.Success -and $statusResult.Output -match "active") {
                Write-Host "  [PASS] Quick Quarm services started successfully" -ForegroundColor Green
            } else {
                Write-Host "  [WARN] Services may not have started properly" -ForegroundColor Yellow
                Write-Host "  Checking service status..." -ForegroundColor Gray
                $statusResult = Invoke-SSHCommand -SSHKeyPath $SSHKeyPath -Hostname $vmIP -User $VMUser -Command "systemctl status quick-quarm.target --no-pager -l | head -15"
                if ($statusResult.Success) {
                    Write-Host $statusResult.Output -ForegroundColor Yellow
                }
                Write-Host "  Run diagnostic for more details: .\QuarmFixer-HyperV.ps1 -Action Diagnose" -ForegroundColor Cyan
            }
        } else {
            Write-Host "  [FAIL] Failed to start services" -ForegroundColor Red
            Write-Host "  Output: $($result.Output)" -ForegroundColor Gray
            Write-Host "  Check logs: .\QuarmFixer-HyperV.ps1 -Action Logs" -ForegroundColor Cyan
        }
        
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "Start Complete!" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "VM IP: $vmIP" -ForegroundColor Cyan
        Write-Host "Services: Running" -ForegroundColor Green
        Write-Host ""
    }
    
    "Stop" {
        Write-Host "Stopping Quick Quarm VM..." -ForegroundColor Cyan
        Stop-QuarmVM -VMName $VMName -Force
    }
    
    "Restart" {
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Restarting Quick Quarm VM and Services" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        
        # Stop the VM if running
        Write-Host "[1/4] Stopping VM (if running)..." -ForegroundColor Yellow
        $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
        if ($vm -and $vm.State -eq "Running") {
            Stop-QuarmVM -VMName $VMName -Force
            Start-Sleep -Seconds 3
            Write-Host "  [PASS] VM stopped" -ForegroundColor Green
        } else {
            Write-Host "  [SKIP] VM was not running" -ForegroundColor Yellow
        }
        Write-Host ""
        
        # Start the VM
        Write-Host "[2/4] Starting Hyper-V VM..." -ForegroundColor Yellow
        if (-not (Start-QuarmVM -VMName $VMName -WaitForReady -WaitSeconds 30)) {
            Write-Host "  [FAIL] Failed to start VM" -ForegroundColor Red
            exit 1
        }
        Write-Host "  [PASS] VM started successfully" -ForegroundColor Green
        Write-Host ""
        
        # Get VM IP address
        Write-Host "[3/4] Getting VM IP address..." -ForegroundColor Yellow
        $config = Get-VMConfig
        $staticIP = if ($config) { $config.StaticIP } else { $null }
        $vmIP = Get-VMIPAddress -VMName $VMName -TimeoutSeconds 120 -StaticIP $staticIP
        
        if (-not $vmIP) {
            Write-Host "  [FAIL] Could not detect VM IP address" -ForegroundColor Red
            Write-Host "  VM may still be booting. Services will not be started." -ForegroundColor Yellow
            Write-Host "  You can start services manually via SSH:" -ForegroundColor Yellow
            Write-Host "    ssh -i `"$SSHKeyPath`" $VMUser@<VM_IP> 'systemctl start quick-quarm.target'" -ForegroundColor Gray
            exit 1
        }
        Write-Host "  [PASS] VM IP Address: $vmIP" -ForegroundColor Green
        Write-Host ""
        
        # Start quarm services
        Write-Host "[4/4] Starting Quick Quarm services..." -ForegroundColor Yellow
        if (-not (Test-SSHKeyExists -SSHKeyPath $SSHKeyPath)) {
            Write-Host "  [WARN] SSH key not found at: $SSHKeyPath" -ForegroundColor Yellow
            Write-Host "  Cannot start services automatically." -ForegroundColor Yellow
            Write-Host "  Start services manually via SSH:" -ForegroundColor Yellow
            Write-Host "    ssh -i `"$SSHKeyPath`" $VMUser@$vmIP 'systemctl start quick-quarm.target'" -ForegroundColor Gray
            exit 1
        }
        
        # Wait a bit more for SSH to be fully ready
        Write-Host "  - Waiting for SSH to be ready..." -ForegroundColor Gray
        $sshReady = $false
        for ($i = 0; $i -lt 10; $i++) {
            if (Test-SSHConnection -Hostname $vmIP) {
                $sshReady = $true
                break
            }
            Start-Sleep -Seconds 2
        }
        
        if (-not $sshReady) {
            Write-Host "  [WARN] SSH not responding yet" -ForegroundColor Yellow
            Write-Host "  Services will not be started automatically." -ForegroundColor Yellow
            Write-Host "  Start services manually via SSH:" -ForegroundColor Yellow
            Write-Host "    ssh -i `"$SSHKeyPath`" $VMUser@$vmIP 'systemctl start quick-quarm.target'" -ForegroundColor Gray
            exit 1
        }
        
        # Check if services are enabled, enable if not
        Write-Host "  - Checking if services are enabled..." -ForegroundColor Gray
        $enabledResult = Invoke-SSHCommand -SSHKeyPath $SSHKeyPath -Hostname $vmIP -User $VMUser -Command "systemctl is-enabled quick-quarm.target 2>&1"
        if ($enabledResult.Success -and $enabledResult.Output -notmatch "enabled") {
            Write-Host "  - Enabling services to start on boot..." -ForegroundColor Gray
            $enableResult = Invoke-SSHCommand -SSHKeyPath $SSHKeyPath -Hostname $vmIP -User $VMUser -Command "systemctl enable quick-quarm.target"
            if ($enableResult.Success) {
                Write-Host "    + Services enabled" -ForegroundColor Green
            } else {
                Write-Host "    ! Warning: Failed to enable services" -ForegroundColor Yellow
            }
        } else {
            Write-Host "    + Services already enabled" -ForegroundColor Green
        }
        
        # Start the services
        Write-Host "  - Starting Quick Quarm services..." -ForegroundColor Gray
        $result = Invoke-SSHCommand -SSHKeyPath $SSHKeyPath -Hostname $vmIP -User $VMUser -Command "systemctl start quick-quarm.target"
        if ($result.Success) {
            # Wait a moment and verify services are actually running
            Start-Sleep -Seconds 3
            $statusResult = Invoke-SSHCommand -SSHKeyPath $SSHKeyPath -Hostname $vmIP -User $VMUser -Command "systemctl is-active quick-quarm.target"
            if ($statusResult.Success -and $statusResult.Output -match "active") {
                Write-Host "  [PASS] Quick Quarm services started successfully" -ForegroundColor Green
            } else {
                Write-Host "  [WARN] Services may not have started properly" -ForegroundColor Yellow
                Write-Host "  Checking service status..." -ForegroundColor Gray
                $statusResult = Invoke-SSHCommand -SSHKeyPath $SSHKeyPath -Hostname $vmIP -User $VMUser -Command "systemctl status quick-quarm.target --no-pager -l | head -15"
                if ($statusResult.Success) {
                    Write-Host $statusResult.Output -ForegroundColor Yellow
                }
                Write-Host "  Run diagnostic for more details: .\QuarmFixer-HyperV.ps1 -Action Diagnose" -ForegroundColor Cyan
            }
        } else {
            Write-Host "  [FAIL] Failed to start services" -ForegroundColor Red
            Write-Host "  Output: $($result.Output)" -ForegroundColor Gray
            Write-Host "  Check logs: .\QuarmFixer-HyperV.ps1 -Action Logs" -ForegroundColor Cyan
        }
        
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "Restart Complete!" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "VM IP: $vmIP" -ForegroundColor Cyan
        Write-Host "Services: Running" -ForegroundColor Green
        Write-Host ""
    }
    
    "Status" {
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Quick Quarm VM Status" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        
        $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
        if (-not $vm) {
            Write-Host "VM Status: NOT INSTALLED" -ForegroundColor Red
            Write-Host ""
            Write-Host "To install, run: .\QuarmInstaller-HyperV.ps1" -ForegroundColor Yellow
            exit 0
        }
        
        Write-Host "VM Name: $VMName" -ForegroundColor White
        Write-Host "VM State: $($vm.State)" -ForegroundColor $(if ($vm.State -eq "Running") { "Green" } else { "Yellow" })
        Write-Host "Uptime: $($vm.Uptime)" -ForegroundColor White
        Write-Host ""
        
        # Get network info
        $vmNetAdapter = Get-VMNetworkAdapter -VMName $VMName -ErrorAction SilentlyContinue
        $detectedVMIP = $null
        
        if ($vmNetAdapter) {
            Write-Host "Network Adapter:" -ForegroundColor Cyan
            Write-Host "  Switch: $($vmNetAdapter.SwitchName)" -ForegroundColor White
            Write-Host "  MAC Address: $($vmNetAdapter.MacAddress)" -ForegroundColor White
            
            # Try to get IP from Hyper-V integration services first
            if ($vmNetAdapter.IPAddresses) {
                $reportedIP = $vmNetAdapter.IPAddresses | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1
                if ($reportedIP) {
                    Write-Host "  IP Address: $reportedIP" -ForegroundColor White
                    $detectedVMIP = $reportedIP
                } else {
                    Write-Host "  IP Address: Not assigned (via integration services)" -ForegroundColor Yellow
                }
            } else {
                Write-Host "  IP Address: Not available (via integration services)" -ForegroundColor Yellow
            }
            
            # If VM is running and we don't have an IP from integration services, try to detect it
            if ($vm.State -eq "Running" -and -not $detectedVMIP) {
                Write-Host "  - Detecting VM IP address..." -ForegroundColor Gray
                $config = Get-VMConfig
                $staticIP = if ($config) { $config.StaticIP } else { $null }
                
                # Test static IP if configured
                if ($staticIP -and $staticIP.Trim() -ne "") {
                    Write-Host "  - Testing configured static IP: $staticIP..." -ForegroundColor Gray
                    try {
                        $tcpClient = New-Object System.Net.Sockets.TcpClient
                        $connect = $tcpClient.BeginConnect($staticIP, 22, $null, $null)
                        $wait = $connect.AsyncWaitHandle.WaitOne(2000, $false)
                        
                        if ($wait) {
                            try {
                                $tcpClient.EndConnect($connect)
                                $tcpClient.Close()
                                Write-Host "  + VM is accessible at static IP: $staticIP" -ForegroundColor Green
                                $detectedVMIP = $staticIP
                            }
                            catch {
                                $tcpClient.Close()
                            }
                        }
                        else {
                            $tcpClient.Close()
                        }
                    }
                    catch {
                        # Static IP not responding, will fall back to scanning
                    }
                }
                
                # If static IP didn't work, try full detection
                if (-not $detectedVMIP) {
                    $detectedVMIP = Get-VMIPWithConfig -VMName $VMName
                    if ($detectedVMIP) {
                        Write-Host "  IP Address: $detectedVMIP (detected)" -ForegroundColor Green
                    } else {
                        Write-Host "  IP Address: Could not detect" -ForegroundColor Red
                    }
                }
            }
        }
        Write-Host ""

        $hostIP = Get-WindowsHostIPv4
        if ($hostIP -and $hostIP.Trim() -ne "") {
            Write-Host "Windows Host IP: $hostIP" -ForegroundColor Cyan
            Write-Host "Client should connect to: $hostIP:6000" -ForegroundColor Cyan
        } else {
            Write-Host "Windows Host IP: (could not detect)" -ForegroundColor Yellow
            Write-Host "Client should connect to: (host IP unknown)" -ForegroundColor Yellow
        }
        Write-Host ""
        
        # Get VM resources
        Write-Host "VM Resources:" -ForegroundColor Cyan
        Write-Host "  Memory: $($vm.MemoryAssigned / 1GB) GB assigned / $($vm.MemoryStartup / 1GB) GB startup" -ForegroundColor White
        Write-Host "  Processors: $($vm.ProcessorCount)" -ForegroundColor White
        Write-Host ""
        
        # Check Quick Quarm service status if VM is running
        if ($vm.State -eq "Running") {
            # Use the detected VM IP if we have it, otherwise try to get it again
            $vmIP = if ($detectedVMIP) { $detectedVMIP } else { Get-VMIPWithConfig -VMName $VMName }
            if ($vmIP -and (Test-SSHKeyExists -SSHKeyPath $SSHKeyPath)) {
                Write-Host "Quick Quarm Services:" -ForegroundColor Cyan
                $result = Invoke-SSHCommand -SSHKeyPath $SSHKeyPath -Hostname $vmIP -User $VMUser -Command "systemctl is-active quick-quarm.target"
                if ($result.Success -and $result.Output -match "active") {
                    Write-Host "  Status: RUNNING" -ForegroundColor Green
                } else {
                    Write-Host "  Status: NOT RUNNING" -ForegroundColor Yellow
                }
            }
        }
        Write-Host ""
        
        # Port forwarding status
        Write-Host "Port Forwarding:" -ForegroundColor Cyan
        $portForwarding = Get-PortForwarding
        if ($portForwarding -match "6000|5998|9000") {
            $lines = $portForwarding -split "`r?`n" | Where-Object { $_ -match "6000|5998|9000" }
            foreach ($line in $lines) {
                Write-Host "  $line" -ForegroundColor White
            }
        } else {
            Write-Host "  No port forwarding configured" -ForegroundColor Yellow
            Write-Host "  Run: .\QuarmFixer-HyperV.ps1 -Action FixConnection" -ForegroundColor Cyan
        }
        Write-Host ""
    }
    
    "SSH" {
        Write-Host "Connecting to VM via SSH..." -ForegroundColor Cyan
        
        $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
        if (-not $vm -or $vm.State -ne "Running") {
            Write-Host "ERROR: VM is not running" -ForegroundColor Red
            Write-Host "Start the VM first: .\QuarmFixer-HyperV.ps1 -Action Start" -ForegroundColor Yellow
            exit 1
        }
        
        if (-not (Test-SSHKeyExists -SSHKeyPath $SSHKeyPath)) {
            Write-Host "ERROR: SSH key not found at $SSHKeyPath" -ForegroundColor Red
            exit 1
        }
        
        $vmIP = Get-VMIPWithConfig -VMName $VMName
        if (-not $vmIP) {
            Write-Host "ERROR: Could not get VM IP address" -ForegroundColor Red
            exit 1
        }
        
        Write-Host "Connecting to root@$vmIP..." -ForegroundColor Gray
        Write-Host ""
        
        & ssh -i $SSHKeyPath -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL root@$vmIP
    }
    
    "Logs" {
        Write-Host "Fetching Quick Quarm logs from VM..." -ForegroundColor Cyan
        
        $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
        if (-not $vm -or $vm.State -ne "Running") {
            Write-Host "ERROR: VM is not running" -ForegroundColor Red
            Write-Host "Start the VM first: .\QuarmFixer-HyperV.ps1 -Action Start" -ForegroundColor Yellow
            exit 1
        }
        
        if (-not (Test-SSHKeyExists -SSHKeyPath $SSHKeyPath)) {
            Write-Host "ERROR: SSH key not found at $SSHKeyPath" -ForegroundColor Red
            exit 1
        }
        
        $vmIP = Get-VMIPWithConfig -VMName $VMName
        if (-not $vmIP) {
            Write-Host "ERROR: Could not get VM IP address" -ForegroundColor Red
            exit 1
        }
        
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Quick Quarm Service Logs" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        
        $result = Invoke-SSHCommand -SSHKeyPath $SSHKeyPath -Hostname $vmIP -User $VMUser -Command "journalctl -u quick-quarm.target -n 50 --no-pager"
        if ($result.Success) {
            Write-Host $result.Output
        } else {
            Write-Host "ERROR: Failed to fetch logs" -ForegroundColor Red
            exit 1
        }
    }
    
    default {
        Write-Host "ERROR: Unknown action: $Action" -ForegroundColor Red
        exit 1
    }
}

} finally {
    # Stop transcript logging
    Stop-Transcript
}
