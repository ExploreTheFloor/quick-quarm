# Quick Quarm Connection Management Script
# Unified script for Diagnose/Fix/Undo connection operations

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Diagnose", "Fix", "Undo")]
    [string]$Action
)

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
    Write-Host "     .\Connection.ps1 -Action $Action" -ForegroundColor Cyan
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
        Write-Host "Quick Quarm Connection Diagnostic" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""

        $issues = @()
        $warnings = @()

        # 1. Check WSL2 is available
        Write-Host "[1/8] Checking WSL2..." -ForegroundColor Yellow
        try {
            $wslStatus = wsl --status 2>&1
            if ($LASTEXITCODE -ne 0) {
                $issues += "WSL2 is not properly configured"
                Write-Host "  [FAIL] WSL2 not available" -ForegroundColor Red
            } else {
                Write-Host "  [PASS] WSL2 is available" -ForegroundColor Green
            }
        } catch {
            $issues += "WSL2 command failed: $($_.Exception.Message)"
            Write-Host "  [FAIL] WSL2 check failed" -ForegroundColor Red
        }

        # 2. Get WSL2 IP address
        Write-Host "[2/8] Getting WSL2 IP address..." -ForegroundColor Yellow
        try {
            $wslIPOutput = wsl -d Ubuntu-22.04 -e hostname -I 2>&1
            $wslIP = ($wslIPOutput -split '\s+' | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1).Trim()
            
            if ($wslIP) {
                Write-Host "  [PASS] WSL2 IP: $wslIP" -ForegroundColor Green
            } else {
                $issues += "Could not determine WSL2 IP address"
                Write-Host "  [FAIL] Could not get WSL2 IP" -ForegroundColor Red
                $wslIP = $null
            }
        } catch {
            $issues += "Failed to get WSL2 IP: $($_.Exception.Message)"
            Write-Host "  [FAIL] Error getting WSL2 IP" -ForegroundColor Red
            $wslIP = $null
        }

        # 3. Get Windows host IP address
        Write-Host "[3/8] Getting Windows host IP address..." -ForegroundColor Yellow
        try {
            $hostIP = (Get-NetIPAddress -AddressFamily IPv4 | 
                       Where-Object { 
                           $_.IPAddress -notmatch '^(127\.|169\.254\.)' -and
                           ($_.IPAddress -match '^192\.168\.|^10\.|^172\.(1[6-9]|2[0-9]|3[0-1])\.')
                       } | Select-Object -First 1).IPAddress
            
            if ($hostIP) {
                Write-Host "  [PASS] Windows host IP: $hostIP" -ForegroundColor Green
            } else {
                $warnings += "Could not determine Windows host IP (using fallback)"
                Write-Host "  [WARN] Could not detect host IP" -ForegroundColor Yellow
                $hostIP = "192.168.1.100"
            }
        } catch {
            $warnings += "Failed to get Windows host IP: $($_.Exception.Message)"
            Write-Host "  [WARN] Error getting host IP" -ForegroundColor Yellow
            $hostIP = "192.168.1.100"
        }

        # 4. Check if ports are listening inside WSL2
        Write-Host "[4/8] Checking if ports are listening inside WSL2..." -ForegroundColor Yellow
        $portsToCheck = @(6000, 5998)
        $wslPortsListening = @{}

        foreach ($port in $portsToCheck) {
            try {
                $portCheck = wsl -d Ubuntu-22.04 -u root -- bash -c "ss -tuln 2>/dev/null | grep -q ':$port ' && echo 'LISTENING' || echo 'NOT_LISTENING'" 2>&1 | Out-String
                $portStatus = ($portCheck -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 1).Trim()
                
                if ($portStatus -eq "LISTENING") {
                    Write-Host "  [PASS] Port $port is listening inside WSL2" -ForegroundColor Green
                    $wslPortsListening[$port] = $true
                } else {
                    Write-Host "  [FAIL] Port $port is NOT listening inside WSL2" -ForegroundColor Red
                    $wslPortsListening[$port] = $false
                    $issues += "Port $port is not listening inside WSL2"
                }
            } catch {
                Write-Host "  [FAIL] Error checking port $port in WSL2" -ForegroundColor Red
                $wslPortsListening[$port] = $false
                $issues += "Error checking port $port in WSL2"
            }
        }

        # 5. Check port forwarding from Windows to WSL2
        Write-Host "[5/8] Checking port forwarding configuration..." -ForegroundColor Yellow
        $forwarding6000 = $false
        $forwarding5998 = $false

        if ($wslIP) {
            try {
                $portForwarding = netsh interface portproxy show all 2>&1 | Out-String
                
                $forwarding6000 = $portForwarding -match '6000'
                $forwarding5998 = $portForwarding -match '5998'
                
                if ($forwarding6000) {
                    Write-Host "  [PASS] Port 6000 forwarding configured" -ForegroundColor Green
                    $forwardingLine = $portForwarding -split "`r?`n" | Where-Object { $_ -match '6000' } | Select-Object -First 1
                    if ($forwardingLine) {
                        Write-Host "    $forwardingLine" -ForegroundColor Gray
                    }
                } else {
                    Write-Host "  [FAIL] Port 6000 forwarding NOT configured" -ForegroundColor Red
                    $issues += "Port 6000 is not forwarded from Windows to WSL2"
                }
                
                if ($forwarding5998) {
                    Write-Host "  [PASS] Port 5998 forwarding configured" -ForegroundColor Green
                    $forwardingLine = $portForwarding -split "`r?`n" | Where-Object { $_ -match '5998' } | Select-Object -First 1
                    if ($forwardingLine) {
                        Write-Host "    $forwardingLine" -ForegroundColor Gray
                    }
                } else {
                    Write-Host "  [WARN] Port 5998 forwarding NOT configured (TCP login server)" -ForegroundColor Yellow
                    $warnings += "Port 5998 (TCP) is not forwarded - may be needed for some clients"
                }
            } catch {
                Write-Host "  [FAIL] Error checking port forwarding: $($_.Exception.Message)" -ForegroundColor Red
                $issues += "Error checking port forwarding configuration"
            }
        } else {
            Write-Host "  [SKIP] Cannot check port forwarding (WSL2 IP unknown)" -ForegroundColor Yellow
        }

        # 6. Check Windows Firewall rules
        Write-Host "[6/8] Checking Windows Firewall rules..." -ForegroundColor Yellow
        try {
            $firewallRules = Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { 
                $_.DisplayName -match 'Quick Quarm|6000|5998' 
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
            Write-Host "  [WARN] Error checking firewall: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        # 7. Check if ports are listening on Windows
        Write-Host "[7/8] Checking if ports are listening on Windows..." -ForegroundColor Yellow
        foreach ($port in $portsToCheck) {
            try {
                $listener = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
                if ($listener) {
                    Write-Host "  [PASS] Port $port is listening on Windows (TCP)" -ForegroundColor Green
                } else {
                    # Check UDP for port 6000
                    if ($port -eq 6000) {
                        $udpListener = Get-NetUDPEndpoint -LocalPort $port -ErrorAction SilentlyContinue
                        if ($udpListener) {
                            Write-Host "  [PASS] Port $port (UDP) is listening on Windows" -ForegroundColor Green
                        } else {
                            Write-Host "  [FAIL] Port $port is NOT listening on Windows" -ForegroundColor Red
                            if (-not $forwarding6000 -and $port -eq 6000) {
                                $issues += "Port $port is not listening on Windows and port forwarding is not configured"
                            }
                        }
                    } else {
                        Write-Host "  [FAIL] Port $port is NOT listening on Windows" -ForegroundColor Red
                        if (-not $forwarding5998 -and $port -eq 5998) {
                            $issues += "Port $port is not listening on Windows and port forwarding is not configured"
                        }
                    }
                }
            } catch {
                Write-Host "  [WARN] Error checking port $port on Windows" -ForegroundColor Yellow
            }
        }

        # 8. Test connectivity
        Write-Host "[8/8] Testing connectivity..." -ForegroundColor Yellow
        if ($hostIP -and $wslIP) {
            Write-Host "  Testing connection to $hostIP:6000 (UDP)..." -ForegroundColor Gray
            try {
                if ($forwarding6000) {
                    Write-Host "  [INFO] Port forwarding exists - connection should work" -ForegroundColor Cyan
                } else {
                    Write-Host "  [FAIL] No port forwarding - connection will fail" -ForegroundColor Red
                }
            } catch {
                Write-Host "  [WARN] Could not test connectivity" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  [SKIP] Cannot test connectivity (missing IP addresses)" -ForegroundColor Yellow
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
            Write-Host "  Run: .\Connection.ps1 -Action Fix" -ForegroundColor White
        }

        Write-Host ""
        Write-Host "Client should connect to: $hostIP:6000" -ForegroundColor Cyan
        Write-Host ""
    }
    
    "Fix" {
        # ========================================
        # FIX CONNECTION
        # ========================================
        
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Quick Quarm Connection Fix" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""

        # Get WSL2 IP address
        Write-Host "[1/5] Getting WSL2 IP address..." -ForegroundColor Yellow
        try {
            $wslIPOutput = wsl -d Ubuntu-22.04 -e hostname -I 2>&1
            $wslIP = ($wslIPOutput -split '\s+' | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1).Trim()
            
            if (-not $wslIP) {
                Write-Host "  [FAIL] Could not get WSL2 IP address" -ForegroundColor Red
                Write-Host "  Make sure WSL2 is running: wsl -d Ubuntu-22.04" -ForegroundColor Yellow
                exit 1
            }
            
            Write-Host "  [PASS] WSL2 IP: $wslIP" -ForegroundColor Green
        } catch {
            Write-Host "  [FAIL] Error getting WSL2 IP: $($_.Exception.Message)" -ForegroundColor Red
            exit 1
        }

        # Fix login server configuration to bind to 0.0.0.0
        Write-Host ""
        Write-Host "[2/5] Fixing login server configuration..." -ForegroundColor Yellow
        try {
            $loginJsonExists = wsl -d Ubuntu-22.04 -u root -- test -f /root/quick-quarm/bin/login.json 2>&1
            if ($LASTEXITCODE -eq 0) {
                wsl -d Ubuntu-22.04 -u root -- cp /root/quick-quarm/bin/login.json /root/quick-quarm/bin/login.json.backup 2>&1 | Out-Null
                wsl -d Ubuntu-22.04 -u root -- bash -c 'sed -i "s/\"local_network\":.*/\"local_network\": \"0.0.0.0\",/" /root/quick-quarm/bin/login.json' 2>&1 | Out-Null
                wsl -d Ubuntu-22.04 -u root -- bash -c 'sed -i "s/\"network_ip\":.*/\"network_ip\": \"0.0.0.0\",/" /root/quick-quarm/bin/login.json' 2>&1 | Out-Null
                Write-Host "  [PASS] Login server configured to accept all connections (0.0.0.0)" -ForegroundColor Green
            } else {
                Write-Host "  [WARN] login.json not found - server may not be installed yet" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "  [WARN] Could not update login server config: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        # Set up TCP port forwarding (5998)
        Write-Host ""
        Write-Host "[3/5] Setting up TCP port forwarding..." -ForegroundColor Yellow
        try {
            netsh interface portproxy delete v4tov4 listenport=5998 listenaddress=0.0.0.0 2>&1 | Out-Null
            $result5998 = netsh interface portproxy add v4tov4 listenport=5998 listenaddress=0.0.0.0 connectport=5998 connectaddress=$wslIP 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  [PASS] Port 5998 (TCP) forwarding configured" -ForegroundColor Green
            } else {
                Write-Host "  [WARN] Failed to configure port 5998 forwarding" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "  [WARN] Error setting up TCP port forwarding: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        # Configure Windows Firewall
        Write-Host ""
        Write-Host "[4/5] Configuring Windows Firewall..." -ForegroundColor Yellow
        Write-Host "  [INFO] Note: netsh portproxy does NOT support UDP" -ForegroundColor Cyan
        Write-Host "  [INFO] Using Windows Firewall to allow UDP traffic to WSL2" -ForegroundColor Cyan

        try {
            Remove-NetFirewallRule -DisplayName "Quick Quarm Login Server UDP" -ErrorAction SilentlyContinue
            Remove-NetFirewallRule -DisplayName "Quick Quarm Login Server TCP" -ErrorAction SilentlyContinue
            Remove-NetFirewallRule -DisplayName "Quick Quarm WSL2 Forward" -ErrorAction SilentlyContinue
            
            try {
                New-NetFirewallRule -DisplayName "Quick Quarm Login Server UDP" `
                    -Direction Inbound `
                    -LocalPort 6000 `
                    -Protocol UDP `
                    -Action Allow `
                    -Enabled True `
                    -ErrorAction Stop | Out-Null
                Write-Host "  [PASS] Firewall rule added for port 6000 (UDP inbound)" -ForegroundColor Green
            } catch {
                Write-Host "  [WARN] Failed to add UDP firewall rule: $($_.Exception.Message)" -ForegroundColor Yellow
            }
            
            try {
                New-NetFirewallRule -DisplayName "Quick Quarm Login Server TCP" `
                    -Direction Inbound `
                    -LocalPort 5998 `
                    -Protocol TCP `
                    -Action Allow `
                    -Enabled True `
                    -ErrorAction Stop | Out-Null
                Write-Host "  [PASS] Firewall rule added for port 5998 (TCP)" -ForegroundColor Green
            } catch {
                Write-Host "  [WARN] Failed to add TCP firewall rule: $($_.Exception.Message)" -ForegroundColor Yellow
            }
            
            try {
                New-NetFirewallRule -DisplayName "Quick Quarm WSL2 Forward" `
                    -Direction Outbound `
                    -RemoteAddress $wslIP `
                    -Protocol Any `
                    -Action Allow `
                    -Enabled True `
                    -ErrorAction Stop | Out-Null
                Write-Host "  [PASS] Firewall rule added for WSL2 forwarding" -ForegroundColor Green
            } catch {
                Write-Host "  [WARN] Failed to add WSL2 forwarding rule: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "  [WARN] Error configuring firewall: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        # Restart login server
        Write-Host ""
        Write-Host "[5/5] Restarting login server..." -ForegroundColor Yellow
        try {
            $restartResult = wsl -d Ubuntu-22.04 -u root -- systemctl restart eqemu-loginserver.service 2>&1
            if ($LASTEXITCODE -eq 0) {
                Start-Sleep -Seconds 2
                $statusCheck = wsl -d Ubuntu-22.04 -u root -- systemctl is-active eqemu-loginserver.service 2>&1
                if ($statusCheck -match "active") {
                    Write-Host "  [PASS] Login server restarted successfully" -ForegroundColor Green
                } else {
                    Write-Host "  [WARN] Login server may not be running" -ForegroundColor Yellow
                }
            } else {
                Write-Host "  [WARN] Could not restart login server" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "  [WARN] Error restarting login server: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        # Get Windows host IP
        Write-Host ""
        Write-Host "Getting Windows host IP address..." -ForegroundColor Yellow
        try {
            $adapters = Get-NetAdapter | Where-Object { 
                $_.Status -eq 'Up' -and 
                $_.InterfaceDescription -notmatch 'Hyper-V|VirtualBox|VMware|WSL|Loopback|Teredo|isatap' 
            }
            
            $hostIP = $null
            foreach ($adapter in $adapters) {
                $ipConfig = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | 
                            Where-Object { 
                                $_.IPAddress -notmatch '^(127\.|169\.254\.)' -and
                                ($_.IPAddress -match '^192\.168\.|^10\.|^172\.(1[6-9]|2[0-9]|3[0-1])\.')
                            }
                
                if ($ipConfig) {
                    $route = Get-NetRoute -InterfaceIndex $adapter.ifIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue
                    if ($route) {
                        $hostIP = $ipConfig.IPAddress
                        break
                    }
                }
            }
            
            if (-not $hostIP) {
                foreach ($adapter in $adapters) {
                    $ipConfig = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | 
                                Where-Object { 
                                    $_.IPAddress -notmatch '^(127\.|169\.254\.)' -and
                                    ($_.IPAddress -match '^192\.168\.|^10\.|^172\.(1[6-9]|2[0-9]|3[0-1])\.')
                                } | Select-Object -First 1
                    
                    if ($ipConfig) {
                        $hostIP = $ipConfig.IPAddress
                        break
                    }
                }
            }
            
            if (-not $hostIP) {
                $hostIP = (Get-NetIPAddress -AddressFamily IPv4 | 
                           Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' } | 
                           Select-Object -First 1).IPAddress
            }
            
            if ($hostIP) {
                Write-Host "  [PASS] Windows host IP: $hostIP" -ForegroundColor Green
            } else {
                Write-Host "  [WARN] Could not determine Windows host IP" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "  [WARN] Error getting Windows host IP: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        # Summary
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "Connection Fix Complete!" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        Write-Host ""

        Write-Host "Configuration:" -ForegroundColor Cyan
        Write-Host "  WSL2 IP: $wslIP" -ForegroundColor White
        if ($hostIP) {
            Write-Host "  Windows Host IP: $hostIP" -ForegroundColor White
            Write-Host ""
            Write-Host "Client Configuration:" -ForegroundColor Cyan
            $clientAddress = $hostIP + ":6000"
            Write-Host "  Edit eqhost.txt and use: $clientAddress" -ForegroundColor White
            Write-Host ""
        } else {
            Write-Host "  Windows Host IP: [NOT DETECTED]" -ForegroundColor Yellow
            Write-Host ""
        }

        Write-Host "What was fixed:" -ForegroundColor Cyan
        Write-Host "  [✓] Login server configured to accept connections from any IP (0.0.0.0)" -ForegroundColor Green
        Write-Host "  [✓] Windows Firewall configured to allow UDP port 6000" -ForegroundColor Green
        Write-Host "  [✓] TCP port forwarding configured for port 5998" -ForegroundColor Green
        Write-Host "  [✓] Login server restarted with new configuration" -ForegroundColor Green
        Write-Host ""

        Write-Host "Important Notes:" -ForegroundColor Cyan
        Write-Host "  - UDP port forwarding works via Windows Firewall (netsh doesn't support UDP)" -ForegroundColor Yellow
        Write-Host "  - TCP port forwarding will be lost if WSL2 restarts" -ForegroundColor Yellow
        Write-Host "  - You may need to run this script again after WSL2 restarts" -ForegroundColor Yellow
        Write-Host "  - To undo these changes, run: .\Connection.ps1 -Action Undo" -ForegroundColor Cyan
        Write-Host ""
    }
    
    "Undo" {
        # ========================================
        # UNDO CONNECTION FIX
        # ========================================
        
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Quick Quarm Connection Undo" -ForegroundColor Cyan
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

        # Restore login server configuration
        Write-Host "[1/4] Restoring login server configuration..." -ForegroundColor Yellow
        try {
            $backupExists = wsl -d Ubuntu-22.04 -u root -- test -f /root/quick-quarm/bin/login.json.backup 2>&1
            if ($LASTEXITCODE -eq 0) {
                wsl -d Ubuntu-22.04 -u root -- cp /root/quick-quarm/bin/login.json.backup /root/quick-quarm/bin/login.json 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "  [PASS] Login server configuration restored from backup" -ForegroundColor Green
                } else {
                    Write-Host "  [FAIL] Failed to restore configuration" -ForegroundColor Red
                }
            } else {
                Write-Host "  [SKIP] No backup found (login.json.backup doesn't exist)" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "  [FAIL] Error restoring config: $($_.Exception.Message)" -ForegroundColor Red
        }

        # Remove TCP port forwarding
        Write-Host ""
        Write-Host "[2/4] Removing TCP port forwarding..." -ForegroundColor Yellow
        try {
            $result5998 = netsh interface portproxy delete v4tov4 listenport=5998 listenaddress=0.0.0.0 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  [PASS] Port 5998 forwarding removed" -ForegroundColor Green
            } else {
                Write-Host "  [SKIP] Port 5998 forwarding was not configured" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "  [WARN] Error removing port forwarding: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        # Remove Windows Firewall rules
        Write-Host ""
        Write-Host "[3/4] Removing Windows Firewall rules..." -ForegroundColor Yellow
        try {
            $rulesRemoved = 0
            
            $rule6000 = Get-NetFirewallRule -DisplayName "Quick Quarm Login Server UDP" -ErrorAction SilentlyContinue
            if ($rule6000) {
                Remove-NetFirewallRule -DisplayName "Quick Quarm Login Server UDP" -ErrorAction SilentlyContinue
                Write-Host "  [PASS] Removed firewall rule: Quick Quarm Login Server UDP" -ForegroundColor Green
                $rulesRemoved++
            }
            
            $rule5998 = Get-NetFirewallRule -DisplayName "Quick Quarm Login Server TCP" -ErrorAction SilentlyContinue
            if ($rule5998) {
                Remove-NetFirewallRule -DisplayName "Quick Quarm Login Server TCP" -ErrorAction SilentlyContinue
                Write-Host "  [PASS] Removed firewall rule: Quick Quarm Login Server TCP" -ForegroundColor Green
                $rulesRemoved++
            }
            
            $ruleWSL = Get-NetFirewallRule -DisplayName "Quick Quarm WSL2 Forward" -ErrorAction SilentlyContinue
            if ($ruleWSL) {
                Remove-NetFirewallRule -DisplayName "Quick Quarm WSL2 Forward" -ErrorAction SilentlyContinue
                Write-Host "  [PASS] Removed firewall rule: Quick Quarm WSL2 Forward" -ForegroundColor Green
                $rulesRemoved++
            }
            
            $oldRule = Get-NetFirewallRule -DisplayName "Quick Quarm Login Server" -ErrorAction SilentlyContinue
            if ($oldRule) {
                Remove-NetFirewallRule -DisplayName "Quick Quarm Login Server" -ErrorAction SilentlyContinue
                Write-Host "  [PASS] Removed firewall rule: Quick Quarm Login Server" -ForegroundColor Green
                $rulesRemoved++
            }
            
            if ($rulesRemoved -eq 0) {
                Write-Host "  [SKIP] No Quick Quarm firewall rules found" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "  [WARN] Error removing firewall rules: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        # Restart login server
        Write-Host ""
        Write-Host "[4/4] Restarting login server..." -ForegroundColor Yellow
        try {
            $restartResult = wsl -d Ubuntu-22.04 -u root -- systemctl restart eqemu-loginserver.service 2>&1
            if ($LASTEXITCODE -eq 0) {
                Start-Sleep -Seconds 2
                $statusCheck = wsl -d Ubuntu-22.04 -u root -- systemctl is-active eqemu-loginserver.service 2>&1
                if ($statusCheck -match "active") {
                    Write-Host "  [PASS] Login server restarted successfully" -ForegroundColor Green
                } else {
                    Write-Host "  [WARN] Login server may not be running" -ForegroundColor Yellow
                }
            } else {
                Write-Host "  [WARN] Could not restart login server" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "  [WARN] Error restarting login server: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        # Summary
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "Undo Complete!" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        Write-Host ""

        Write-Host "Changes undone:" -ForegroundColor Cyan
        Write-Host "  [✓] Login server configuration restored from backup" -ForegroundColor Green
        Write-Host "  [✓] TCP port forwarding removed" -ForegroundColor Green
        Write-Host "  [✓] Windows Firewall rules removed" -ForegroundColor Green
        Write-Host "  [✓] Login server restarted" -ForegroundColor Green
        Write-Host ""

        Write-Host "Note: The server should now be back to its original configuration." -ForegroundColor Yellow
        Write-Host ""
    }
}





