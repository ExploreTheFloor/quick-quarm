# Quick Quarm Connection Management Script for Hyper-V
# Unified script for Diagnose/Fix/Undo connection operations

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Diagnose", "Fix", "Undo")]
    [string]$Action
)

# Prefer the Windows host LAN IP (not Default Switch).
function Get-WindowsHostIPv4 {
    # Try method 1: Get adapter with default gateway (most reliable)
    try {
        $cfg = Get-NetIPConfiguration | Where-Object {
            $_.IPv4DefaultGateway -and
            $_.NetAdapter -and
            $_.NetAdapter.Status -eq "Up" -and
            $_.InterfaceAlias -notlike "*Default Switch*"
        } | Select-Object -First 1

        if ($cfg -and $cfg.IPv4Address -and $cfg.IPv4Address.IPAddress) {
            return $cfg.IPv4Address.IPAddress
        }
    } catch { }

    # Try method 2: Get first valid private IP (not loopback, not APIPA, not Default Switch)
    try {
        $ip = Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
            $_.IPAddress -notmatch '^(127\.|169\.254\.)' -and
            ($_.IPAddress -match '^192\.168\.|^10\.|^172\.(1[6-9]|2[0-9]|3[0-1])\.') -and
            $_.InterfaceAlias -notlike "*Default Switch*" -and
            $_.IPAddress -notmatch '^172\.18\.'
        } | Select-Object -First 1

        if ($ip -and $ip.IPAddress) {
            return $ip.IPAddress
        }
    } catch { }

    return $null
}

# Function to detect VM IP by scanning Default Switch subnet
function Get-VMIPAddress {
    param(
        [string]$VMName,
        [int]$TimeoutSeconds = 120
    )
    
    Write-Host "  - Detecting VM IP address (this may take 1-2 minutes)..." -ForegroundColor Gray
    
    # Method 1: Try to get IP from Hyper-V integration services
    $vmNetAdapter = Get-VMNetworkAdapter -VMName $VMName -ErrorAction SilentlyContinue
    if ($vmNetAdapter -and $vmNetAdapter.IPAddresses) {
        $reportedIP = $vmNetAdapter.IPAddresses | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1
        
        if ($reportedIP) {
            Write-Host "  - Hyper-V reports IP: $reportedIP (verifying SSH access...)" -ForegroundColor Gray
            
            # Verify SSH is actually accessible
            try {
                $tcpClient = New-Object System.Net.Sockets.TcpClient
                $connect = $tcpClient.BeginConnect($reportedIP, 22, $null, $null)
                $wait = $connect.AsyncWaitHandle.WaitOne(2000, $false)
                
                if ($wait) {
                    try {
                        $tcpClient.EndConnect($connect)
                        $tcpClient.Close()
                        Write-Host "  + Found VM at reported IP: $reportedIP" -ForegroundColor Green
                        return $reportedIP
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
                # SSH not responding on reported IP
            }
            
            Write-Host "  - Reported IP not responding to SSH, scanning subnet..." -ForegroundColor Yellow
        }
    }
    
    # Method 2: Scan Default Switch subnet for VM
    $defaultSwitchIP = Get-NetIPAddress -InterfaceAlias "vEthernet (Default Switch)" -AddressFamily IPv4 -ErrorAction SilentlyContinue
    if (-not $defaultSwitchIP) {
        Write-Host "  ! Could not detect Default Switch IP" -ForegroundColor Red
        return $null
    }
    
    $hostIP = $defaultSwitchIP.IPAddress
    $prefixLength = $defaultSwitchIP.PrefixLength
    
    # Calculate subnet range based on prefix length
    $ipBytes = [System.Net.IPAddress]::Parse($hostIP).GetAddressBytes()
    $ipInt = [System.BitConverter]::ToUInt32($ipBytes[3..0], 0)
    
    $maskInt = [Convert]::ToUInt32(("1" * $prefixLength).PadRight(32, "0"), 2)
    $networkInt = $ipInt -band $maskInt
    $broadcastInt = $networkInt -bor (-bnot $maskInt)
    
    Write-Host "  - Scanning /$prefixLength subnet for VM..." -ForegroundColor Gray
    
    $elapsed = 0
    $scanInterval = 15
    $scansPerformed = 0
    
    while ($elapsed -lt $TimeoutSeconds) {
        $scansPerformed++
        
        # Scan IP range from network+2 to broadcast-1 (skip network and broadcast addresses)
        for ($ipToTest = $networkInt + 2; $ipToTest -lt $broadcastInt; $ipToTest++) {
            # Convert back to IP address
            $bytes = [System.BitConverter]::GetBytes($ipToTest)
            $testIP = [System.Net.IPAddress]::new($bytes[3..0]).ToString()
            
            # Skip the host IP itself
            if ($testIP -eq $hostIP) { continue }
            
            # Quick TCP connect test to port 22
            try {
                $tcpClient = New-Object System.Net.Sockets.TcpClient
                $connect = $tcpClient.BeginConnect($testIP, 22, $null, $null)
                $wait = $connect.AsyncWaitHandle.WaitOne(50, $false)
                
                if ($wait) {
                    try {
                        $tcpClient.EndConnect($connect)
                        $tcpClient.Close()
                        Write-Host "  + Found VM at IP: $testIP" -ForegroundColor Green
                        return $testIP
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
                # Ignore connection errors
            }
        }
        
        if ($scansPerformed -eq 1) {
            Write-Host "  - First scan complete, no VM found. VM may still be booting..." -ForegroundColor Yellow
            Write-Host "  - Waiting and rescanning... ($scanInterval seconds)" -ForegroundColor Gray
        } else {
            Write-Host "  - Rescanning subnet... (elapsed: $elapsed/${TimeoutSeconds}s)" -ForegroundColor Gray
        }
        
        Start-Sleep -Seconds $scanInterval
        $elapsed += $scanInterval
    }
    
    Write-Host "  ! Could not detect VM IP address after ${TimeoutSeconds}s" -ForegroundColor Red
    return $null
}

# Check if running as Administrator (required for Fix and Undo)
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (($Action -eq "Fix" -or $Action -eq "Undo") -and -not $isAdmin) {
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
    Write-Host "     .\Connection-HyperV.ps1 -Action $Action" -ForegroundColor Cyan
    Write-Host ""
    exit 1
}

# Execute the requested action
switch ($Action) {
    "Diagnose" {
        # ========================================
        # DIAGNOSE CONNECTION
        # ========================================
        
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Quick Quarm Connection Diagnostic (Hyper-V)" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""

        $issues = @()
        $warnings = @()

        # 1. Check if Hyper-V VM exists and is running
        Write-Host "[1/8] Checking Hyper-V VM..." -ForegroundColor Yellow
        try {
            $vm = Get-VM -Name "QuickQuarm" -ErrorAction SilentlyContinue
            if ($vm) {
                if ($vm.State -eq "Running") {
                    Write-Host "  [PASS] VM 'QuickQuarm' is running" -ForegroundColor Green
                } else {
                    $issues += "VM 'QuickQuarm' exists but is not running (State: $($vm.State))"
                    Write-Host "  [FAIL] VM is not running (State: $($vm.State))" -ForegroundColor Red
                }
            } else {
                $issues += "VM 'QuickQuarm' not found"
                Write-Host "  [FAIL] VM 'QuickQuarm' not found" -ForegroundColor Red
            }
        } catch {
            $issues += "Error checking VM: $($_.Exception.Message)"
            Write-Host "  [FAIL] Error checking VM" -ForegroundColor Red
        }

        # 2. Get VM IP address
        Write-Host "[2/8] Getting VM IP address..." -ForegroundColor Yellow
        $vmIP = $null
        try {
            if ($vm -and $vm.State -eq "Running") {
                # Try quick check first (no scanning)
                $vmNetAdapter = Get-VMNetworkAdapter -VMName "QuickQuarm" -ErrorAction SilentlyContinue
                if ($vmNetAdapter -and $vmNetAdapter.IPAddresses) {
                    $vmIP = $vmNetAdapter.IPAddresses | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1
                }
                
                if ($vmIP) {
                    Write-Host "  [INFO] Hyper-V reports IP: $vmIP" -ForegroundColor Cyan
                    
                    # Verify it's actually accessible
                    try {
                        $testConnection = Test-NetConnection -ComputerName $vmIP -Port 22 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -InformationLevel Quiet
                        if ($testConnection) {
                            Write-Host "  [PASS] VM IP verified: $vmIP" -ForegroundColor Green
                        } else {
                            Write-Host "  [WARN] VM IP reported but not accessible: $vmIP" -ForegroundColor Yellow
                            $warnings += "VM IP $vmIP is not responding to connections"
                        }
                    } catch {
                        Write-Host "  [WARN] Could not verify VM IP: $vmIP" -ForegroundColor Yellow
                    }
                } else {
                    Write-Host "  [INFO] Hyper-V has not reported an IP yet" -ForegroundColor Cyan
                    Write-Host "  [INFO] Attempting network scan..." -ForegroundColor Cyan
                    
                    # Try network scanning (with short timeout for diagnostics)
                    $vmIP = Get-VMIPAddress -VMName "QuickQuarm" -TimeoutSeconds 30
                    
                    if ($vmIP) {
                        Write-Host "  [PASS] VM IP found via scan: $vmIP" -ForegroundColor Green
                    } else {
                        $issues += "VM has no IPv4 address or is not responding to network probes"
                        Write-Host "  [FAIL] Could not detect VM IP" -ForegroundColor Red
                    }
                }
            } else {
                Write-Host "  [SKIP] VM is not running" -ForegroundColor Yellow
            }
        } catch {
            $issues += "Error getting VM IP: $($_.Exception.Message)"
            Write-Host "  [FAIL] Error getting VM IP" -ForegroundColor Red
        }

        # 3. Get Windows host IP address
        Write-Host "[3/8] Getting Windows host IP address..." -ForegroundColor Yellow
        try {
            $hostIP = Get-WindowsHostIPv4
            
            if ($hostIP) {
                Write-Host "  [PASS] Windows host IP: $hostIP" -ForegroundColor Green
            } else {
                $warnings += "Could not determine Windows host IP"
                Write-Host "  [WARN] Could not detect host IP" -ForegroundColor Yellow
            }
        } catch {
            $warnings += "Failed to get Windows host IP: $($_.Exception.Message)"
            Write-Host "  [WARN] Error getting host IP" -ForegroundColor Yellow
        }

        # 4. Check if SSH is accessible
        Write-Host "[4/8] Checking SSH accessibility..." -ForegroundColor Yellow
        if ($vmIP) {
            try {
                $sshTest = Test-NetConnection -ComputerName $vmIP -Port 22 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                if ($sshTest.TcpTestSucceeded) {
                    Write-Host "  [PASS] SSH port 22 is accessible on VM" -ForegroundColor Green
                } else {
                    $issues += "SSH port 22 is not accessible on VM IP $vmIP"
                    Write-Host "  [FAIL] SSH port 22 not accessible" -ForegroundColor Red
                }
            } catch {
                $issues += "Error testing SSH connectivity"
                Write-Host "  [FAIL] Error testing SSH" -ForegroundColor Red
            }
        } else {
            Write-Host "  [SKIP] No VM IP address to test" -ForegroundColor Yellow
        }

        # 5. Check port forwarding configuration
        Write-Host "[5/8] Checking port forwarding configuration..." -ForegroundColor Yellow
        $forwarding6000 = $false
        $forwarding5998 = $false
        $forwarding9000 = $false

        if ($vmIP) {
            try {
                $portForwarding = netsh interface portproxy show all 2>&1 | Out-String
                
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
            } catch {
                Write-Host "  [FAIL] Error checking port forwarding" -ForegroundColor Red
            }
        } else {
            Write-Host "  [SKIP] Cannot check port forwarding (VM IP unknown)" -ForegroundColor Yellow
        }

        # 6. Check Windows Firewall rules
        Write-Host "[6/8] Checking Windows Firewall rules..." -ForegroundColor Yellow
        try {
            $firewallRules = Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { 
                $_.DisplayName -match 'Quick Quarm|6000|5998|9000' 
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

        # 7. Check if Quick Quarm services are running inside VM
        Write-Host "[7/8] Checking Quick Quarm services in VM..." -ForegroundColor Yellow
        if ($vmIP) {
            try {
                # Check if SSH key exists
                $sshKeyPath = "C:\Users\Laptop\QuickQuarm-VM\id_rsa"
                if (Test-Path $sshKeyPath) {
                    $serviceStatus = ssh -i $sshKeyPath -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL root@$vmIP "systemctl is-active quick-quarm.target" 2>&1
                    if ($serviceStatus -match "active") {
                        Write-Host "  [PASS] Quick Quarm services are running" -ForegroundColor Green
                    } else {
                        $issues += "Quick Quarm services are not running inside VM"
                        Write-Host "  [FAIL] Quick Quarm services not active" -ForegroundColor Red
                    }
                } else {
                    Write-Host "  [SKIP] SSH key not found, cannot check services" -ForegroundColor Yellow
                }
            } catch {
                $warnings += "Could not check service status: $($_.Exception.Message)"
                Write-Host "  [WARN] Could not check service status" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  [SKIP] No VM IP address" -ForegroundColor Yellow
        }

        # 8. Test connectivity to login server
        Write-Host "[8/8] Testing connectivity to login server..." -ForegroundColor Yellow
        if ($vmIP) {
            try {
                $loginTest = Test-NetConnection -ComputerName $vmIP -Port 6000 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                if ($loginTest.TcpTestSucceeded) {
                    Write-Host "  [INFO] Port 6000 (TCP) is accessible" -ForegroundColor Cyan
                } else {
                    Write-Host "  [INFO] Port 6000 (UDP) cannot be tested directly" -ForegroundColor Cyan
                }
            } catch {
                Write-Host "  [WARN] Could not test connectivity" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  [SKIP] No VM IP address to test" -ForegroundColor Yellow
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
            Write-Host "Client Configuration:" -ForegroundColor Cyan
            Write-Host "  Use IP: $hostIP:6000" -ForegroundColor White
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
            
            Write-Host "RECOMMENDED FIX:" -ForegroundColor Cyan
            Write-Host "  Run: .\Connection-HyperV.ps1 -Action Fix" -ForegroundColor White
        }

        Write-Host ""
        if ($vmIP) {
            Write-Host "VM IP: $vmIP" -ForegroundColor Cyan
            Write-Host "Client should connect to: $hostIP:6000" -ForegroundColor Cyan
        }
        Write-Host ""
    }
    
    "Fix" {
        # ========================================
        # FIX CONNECTION
        # ========================================
        
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Quick Quarm Connection Fix (Hyper-V)" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""

        # Get VM IP address
        Write-Host "[1/3] Getting VM IP address..." -ForegroundColor Yellow
        try {
            $vm = Get-VM -Name "QuickQuarm" -ErrorAction SilentlyContinue
            if (-not $vm) {
                Write-Host "  [FAIL] VM 'QuickQuarm' not found" -ForegroundColor Red
                Write-Host "  Please run the installer first: .\QuarmInstaller-HyperV.ps1" -ForegroundColor Yellow
                exit 1
            }

            if ($vm.State -ne "Running") {
                Write-Host "  [INFO] Starting VM..." -ForegroundColor Cyan
                Start-VM -Name "QuickQuarm"
                Write-Host "  [INFO] Waiting for VM to boot (this takes 1-2 minutes)..." -ForegroundColor Cyan
                Start-Sleep -Seconds 30
            } else {
                Write-Host "  [INFO] VM is already running" -ForegroundColor Cyan
            }

            # Use robust IP detection with network scanning
            $vmIP = Get-VMIPAddress -VMName "QuickQuarm" -TimeoutSeconds 120
            
            if (-not $vmIP) {
                Write-Host ""
                Write-Host "  [FAIL] Could not detect VM IP address" -ForegroundColor Red
                Write-Host "" -ForegroundColor Yellow
                Write-Host "  Possible causes:" -ForegroundColor Yellow
                Write-Host "    - VM is still booting (cloud-init takes 3-5 minutes on first boot)" -ForegroundColor Yellow
                Write-Host "    - SSH service hasn't started yet" -ForegroundColor Yellow
                Write-Host "    - Network configuration failed" -ForegroundColor Yellow
                Write-Host ""
                Write-Host "  Troubleshooting:" -ForegroundColor Cyan
                Write-Host "    1. Wait 5 more minutes and try again" -ForegroundColor White
                Write-Host "    2. Check VM console in Hyper-V Manager:" -ForegroundColor White
                Write-Host "       - Open Hyper-V Manager" -ForegroundColor Gray
                Write-Host "       - Right-click 'QuickQuarm' -> Connect" -ForegroundColor Gray
                Write-Host "       - Check if VM is at login prompt or showing errors" -ForegroundColor Gray
                Write-Host "    3. Run diagnostic: .\Diagnose-VMNetwork.ps1" -ForegroundColor White
                Write-Host ""
                exit 1
            }
            
            Write-Host "  [PASS] VM IP: $vmIP" -ForegroundColor Green
        } catch {
            Write-Host "  [FAIL] Error getting VM IP: $($_.Exception.Message)" -ForegroundColor Red
            exit 1
        }

        # Set up port forwarding
        Write-Host ""
        Write-Host "[2/3] Setting up port forwarding..." -ForegroundColor Yellow
        try {
            # Remove existing rules
            netsh interface portproxy delete v4tov4 listenport=6000 listenaddress=0.0.0.0 2>&1 | Out-Null
            netsh interface portproxy delete v4tov4 listenport=5998 listenaddress=0.0.0.0 2>&1 | Out-Null
            netsh interface portproxy delete v4tov4 listenport=9000 listenaddress=0.0.0.0 2>&1 | Out-Null

            # Add new rules
            netsh interface portproxy add v4tov4 listenport=6000 listenaddress=0.0.0.0 connectport=6000 connectaddress=$vmIP 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  [PASS] Port 6000 forwarding configured" -ForegroundColor Green
            } else {
                Write-Host "  [WARN] Failed to configure port 6000 forwarding" -ForegroundColor Yellow
            }

            netsh interface portproxy add v4tov4 listenport=5998 listenaddress=0.0.0.0 connectport=5998 connectaddress=$vmIP 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  [PASS] Port 5998 forwarding configured" -ForegroundColor Green
            } else {
                Write-Host "  [WARN] Failed to configure port 5998 forwarding" -ForegroundColor Yellow
            }

            netsh interface portproxy add v4tov4 listenport=9000 listenaddress=0.0.0.0 connectport=9000 connectaddress=$vmIP 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  [PASS] Port 9000 forwarding configured" -ForegroundColor Green
            } else {
                Write-Host "  [WARN] Failed to configure port 9000 forwarding" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "  [WARN] Error setting up port forwarding: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        # Configure Windows Firewall
        Write-Host ""
        Write-Host "[3/3] Configuring Windows Firewall..." -ForegroundColor Yellow
        try {
            Remove-NetFirewallRule -DisplayName "Quick Quarm Login Server (6000)" -ErrorAction SilentlyContinue
            Remove-NetFirewallRule -DisplayName "Quick Quarm Login Server TCP (5998)" -ErrorAction SilentlyContinue
            Remove-NetFirewallRule -DisplayName "Quick Quarm World Server (9000)" -ErrorAction SilentlyContinue
            
            New-NetFirewallRule -DisplayName "Quick Quarm Login Server (6000)" `
                -Direction Inbound `
                -LocalPort 6000 `
                -Protocol Any `
                -Action Allow `
                -Enabled True `
                -ErrorAction Stop | Out-Null
            Write-Host "  [PASS] Firewall rule added for port 6000" -ForegroundColor Green

            New-NetFirewallRule -DisplayName "Quick Quarm Login Server TCP (5998)" `
                -Direction Inbound `
                -LocalPort 5998 `
                -Protocol TCP `
                -Action Allow `
                -Enabled True `
                -ErrorAction Stop | Out-Null
            Write-Host "  [PASS] Firewall rule added for port 5998" -ForegroundColor Green

            New-NetFirewallRule -DisplayName "Quick Quarm World Server (9000)" `
                -Direction Inbound `
                -LocalPort 9000 `
                -Protocol TCP `
                -Action Allow `
                -Enabled True `
                -ErrorAction Stop | Out-Null
            Write-Host "  [PASS] Firewall rule added for port 9000" -ForegroundColor Green
        } catch {
            Write-Host "  [WARN] Error configuring firewall: $($_.Exception.Message)" -ForegroundColor Yellow
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

        Write-Host "Important Notes:" -ForegroundColor Cyan
        Write-Host "  - Port forwarding will be lost if VM gets a new IP address" -ForegroundColor Yellow
        Write-Host "  - You may need to run this script again after VM restarts" -ForegroundColor Yellow
        Write-Host "  - To undo these changes, run: .\Connection-HyperV.ps1 -Action Undo" -ForegroundColor Cyan
        Write-Host ""
    }
    
    "Undo" {
        # ========================================
        # UNDO CONNECTION FIX
        # ========================================
        
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Quick Quarm Connection Undo (Hyper-V)" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "This will undo all changes made by the Fix operation" -ForegroundColor Yellow
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
        try {
            netsh interface portproxy delete v4tov4 listenport=6000 listenaddress=0.0.0.0 2>&1 | Out-Null
            Write-Host "  [PASS] Port 6000 forwarding removed" -ForegroundColor Green

            netsh interface portproxy delete v4tov4 listenport=5998 listenaddress=0.0.0.0 2>&1 | Out-Null
            Write-Host "  [PASS] Port 5998 forwarding removed" -ForegroundColor Green

            netsh interface portproxy delete v4tov4 listenport=9000 listenaddress=0.0.0.0 2>&1 | Out-Null
            Write-Host "  [PASS] Port 9000 forwarding removed" -ForegroundColor Green
        } catch {
            Write-Host "  [WARN] Error removing port forwarding: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        # Remove Windows Firewall rules
        Write-Host ""
        Write-Host "[2/2] Removing Windows Firewall rules..." -ForegroundColor Yellow
        try {
            $rulesRemoved = 0
            
            if (Get-NetFirewallRule -DisplayName "Quick Quarm Login Server (6000)" -ErrorAction SilentlyContinue) {
                Remove-NetFirewallRule -DisplayName "Quick Quarm Login Server (6000)" -ErrorAction SilentlyContinue
                Write-Host "  [PASS] Removed firewall rule: Quick Quarm Login Server (6000)" -ForegroundColor Green
                $rulesRemoved++
            }
            
            if (Get-NetFirewallRule -DisplayName "Quick Quarm Login Server TCP (5998)" -ErrorAction SilentlyContinue) {
                Remove-NetFirewallRule -DisplayName "Quick Quarm Login Server TCP (5998)" -ErrorAction SilentlyContinue
                Write-Host "  [PASS] Removed firewall rule: Quick Quarm Login Server TCP (5998)" -ForegroundColor Green
                $rulesRemoved++
            }
            
            if (Get-NetFirewallRule -DisplayName "Quick Quarm World Server (9000)" -ErrorAction SilentlyContinue) {
                Remove-NetFirewallRule -DisplayName "Quick Quarm World Server (9000)" -ErrorAction SilentlyContinue
                Write-Host "  [PASS] Removed firewall rule: Quick Quarm World Server (9000)" -ForegroundColor Green
                $rulesRemoved++
            }
            
            if ($rulesRemoved -eq 0) {
                Write-Host "  [SKIP] No Quick Quarm firewall rules found" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "  [WARN] Error removing firewall rules: $($_.Exception.Message)" -ForegroundColor Yellow
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
}




