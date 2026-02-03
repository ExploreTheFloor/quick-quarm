# HyperV-QuarmCommon.psm1
# Shared module for Quick Quarm Hyper-V management scripts
# Provides common functions for Installer, Fixer, and Uninstaller

# ============================================================================
# VALIDATION FUNCTIONS
# ============================================================================

function Test-Administrator {
    <#
    .SYNOPSIS
    Checks if the current session is running with Administrator privileges.
    #>
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-SSHKeyExists {
    <#
    .SYNOPSIS
    Checks if SSH key exists at the specified path.
    #>
    param(
        [string]$SSHKeyPath
    )
    return (Test-Path $SSHKeyPath)
}

function Test-VMExists {
    <#
    .SYNOPSIS
    Checks if a VM with the specified name exists.
    #>
    param(
        [string]$VMName = "QuickQuarm"
    )
    try {
        $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
        return ($null -ne $vm)
    }
    catch {
        return $false
    }
}

function Get-VMState {
    <#
    .SYNOPSIS
    Gets the state of a VM safely.
    #>
    param(
        [string]$VMName = "QuickQuarm"
    )
    try {
        $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
        if ($vm) {
            return $vm.State
        }
        return $null
    }
    catch {
        return $null
    }
}

# ============================================================================
# NETWORK DETECTION FUNCTIONS
# ============================================================================

function Get-WindowsHostIPv4 {
    <#
    .SYNOPSIS
    Gets the Windows host LAN IP address (not Default Switch).
    #>
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

function Get-DefaultSwitchNetworkConfig {
    <#
    .SYNOPSIS
    Detects Default Switch subnet and calculates a predictable static IP.
    #>
    param(
        [int]$PreferredHostID = 100
    )
    
    Write-Host "  - Detecting Default Switch network configuration..." -ForegroundColor Gray
    
    # Get Default Switch IP configuration
    $defaultSwitchIP = Get-NetIPAddress -InterfaceAlias "vEthernet (Default Switch)" -AddressFamily IPv4 -ErrorAction SilentlyContinue
    if (-not $defaultSwitchIP) {
        Write-Host "  ! Could not detect Default Switch" -ForegroundColor Yellow
        return $null
    }
    
    $gatewayIP = $defaultSwitchIP.IPAddress
    $prefixLength = $defaultSwitchIP.PrefixLength
    
    # Calculate network address
    $ipBytes = [System.Net.IPAddress]::Parse($gatewayIP).GetAddressBytes()
    $ipInt = [System.BitConverter]::ToUInt32($ipBytes[3..0], 0)
    $maskInt = [Convert]::ToUInt32(("1" * $prefixLength).PadRight(32, "0"), 2)
    $networkInt = $ipInt -band $maskInt
    
    # Calculate the predictable static IP (network + PreferredHostID)
    $staticIPInt = $networkInt + $PreferredHostID
    $broadcastInt = $networkInt -bor (-bnot $maskInt)
    
    # If preferred IP would be broadcast or out of range, use network + 2
    if ($staticIPInt -ge $broadcastInt -or $staticIPInt -eq $networkInt) {
        $staticIPInt = $networkInt + 2
        $PreferredHostID = 2
    }
    
    # Convert back to IP address
    $staticIPBytes = [System.BitConverter]::GetBytes($staticIPInt)
    $staticIP = [System.Net.IPAddress]::new($staticIPBytes[3..0]).ToString()
    
    # Convert prefix length to netmask if needed
    $netmask = $prefixLength.ToString()
    
    Write-Host "  + Default Switch: $gatewayIP/$prefixLength" -ForegroundColor Green
    Write-Host "  + Calculated static IP: $staticIP/$prefixLength" -ForegroundColor Green
    
    return @{
        StaticIP = $staticIP
        Gateway = $gatewayIP
        Netmask = $netmask
        PrefixLength = $prefixLength
        Network = [System.Net.IPAddress]::new([System.BitConverter]::GetBytes($networkInt)[3..0]).ToString()
    }
}

function Get-VMIPAddress {
    <#
    .SYNOPSIS
    Detects VM IP address by scanning network or using Hyper-V integration services.
    #>
    param(
        [string]$VMName = "QuickQuarm",
        [int]$TimeoutSeconds = 120,
        [string]$StaticIP = ""
    )
    
    # If static IP is provided, test it first
    if (-not [string]::IsNullOrEmpty($StaticIP)) {
        Write-Host "  - Testing configured static IP: $StaticIP..." -ForegroundColor Gray
        try {
            $tcpClient = New-Object System.Net.Sockets.TcpClient
            $connect = $tcpClient.BeginConnect($StaticIP, 22, $null, $null)
            $wait = $connect.AsyncWaitHandle.WaitOne(2000, $false)
            
            if ($wait) {
                try {
                    $tcpClient.EndConnect($connect)
                    $tcpClient.Close()
                    Write-Host "  + VM is accessible at static IP: $StaticIP" -ForegroundColor Green
                    return $StaticIP
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
            # Static IP not responding, will fall back to other methods
        }
        Write-Host "  - Static IP not responding yet, trying other detection methods..." -ForegroundColor Yellow
    }
    
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
    
    # Method 2: Scan networks for VM
    # Try LAN networks first (External switches)
    $lanNetworks = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object {
        $_.InterfaceAlias -like "vEthernet*" -and
        $_.InterfaceAlias -notlike "*Default Switch*" -and
        $_.IPAddress -notmatch '^(127\.|169\.254\.)'
    }
    
    foreach ($net in $lanNetworks) {
        $networkIP = $net.IPAddress
        $prefixLength = $net.PrefixLength
        
        $ipBytes = [System.Net.IPAddress]::Parse($networkIP).GetAddressBytes()
        $ipInt = [System.BitConverter]::ToUInt32($ipBytes[3..0], 0)
        $maskInt = [Convert]::ToUInt32(("1" * $prefixLength).PadRight(32, "0"), 2)
        $networkInt = $ipInt -band $maskInt
        $broadcastInt = $networkInt -bor (-bnot $maskInt)
        
        Write-Host "  - Scanning $($net.InterfaceAlias) ($networkIP/$prefixLength)..." -ForegroundColor Gray
        
        for ($ipToTest = $networkInt + 2; $ipToTest -lt $broadcastInt; $ipToTest++) {
            $bytes = [System.BitConverter]::GetBytes($ipToTest)
            $testIP = [System.Net.IPAddress]::new($bytes[3..0]).ToString()
            if ($testIP -eq $networkIP) { continue }
            
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
    }
    
    # Method 3: Scan Default Switch subnet for VM
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

# ============================================================================
# VM OPERATIONS
# ============================================================================

function Start-QuarmVM {
    <#
    .SYNOPSIS
    Starts the Quick Quarm VM and optionally waits for it to be ready.
    #>
    param(
        [string]$VMName = "QuickQuarm",
        [switch]$WaitForReady,
        [int]$WaitSeconds = 10
    )
    
    $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
    if (-not $vm) {
        Write-Host "ERROR: VM '$VMName' not found" -ForegroundColor Red
        return $false
    }
    
    if ($vm.State -eq "Running") {
        Write-Host "VM is already running" -ForegroundColor Yellow
        return $true
    }
    
    try {
        Start-VM -Name $VMName -ErrorAction Stop
        Write-Host "VM started successfully" -ForegroundColor Green
        
        if ($WaitForReady) {
            Write-Host "Waiting for VM to be ready..." -ForegroundColor Gray
            Start-Sleep -Seconds $WaitSeconds
        }
        
        return $true
    }
    catch {
        Write-Host "ERROR: Failed to start VM: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Stop-QuarmVM {
    <#
    .SYNOPSIS
    Stops the Quick Quarm VM.
    #>
    param(
        [string]$VMName = "QuickQuarm",
        [switch]$Force
    )
    
    $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
    if (-not $vm) {
        Write-Host "VM '$VMName' not found" -ForegroundColor Yellow
        return $false
    }
    
    if ($vm.State -ne "Running") {
        Write-Host "VM is not running" -ForegroundColor Yellow
        return $true
    }
    
    try {
        if ($Force) {
            Stop-VM -Name $VMName -Force -ErrorAction Stop
        } else {
            Stop-VM -Name $VMName -ErrorAction Stop
        }
        Write-Host "VM stopped successfully" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "ERROR: Failed to stop VM: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Set-VMAutoStart {
    <#
    .SYNOPSIS
    Configures VM auto-start and auto-stop actions.
    #>
    param(
        [string]$VMName = "QuickQuarm",
        [string]$AutomaticStartAction = "Start",
        [int]$AutomaticStartDelay = 0,
        [string]$AutomaticStopAction = "Save"
    )
    
    try {
        Set-VM -VMName $VMName -AutomaticStartAction $AutomaticStartAction -AutomaticStartDelay $AutomaticStartDelay -ErrorAction Stop
        Set-VM -VMName $VMName -AutomaticStopAction $AutomaticStopAction -ErrorAction Stop
        Write-Host "  + VM auto-start configured" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "  ! Error configuring VM auto-start: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# ============================================================================
# SSH OPERATIONS
# ============================================================================

function Test-SSHConnection {
    <#
    .SYNOPSIS
    Tests SSH connectivity to a host.
    #>
    param(
        [string]$Hostname,
        [int]$Port = 22,
        [int]$TimeoutSeconds = 5
    )
    
    try {
        $test = Test-NetConnection -ComputerName $Hostname -Port $Port -InformationLevel Quiet -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        return $test
    }
    catch {
        return $false
    }
}

function Invoke-SSHCommand {
    <#
    .SYNOPSIS
    Executes an SSH command with common options.
    #>
    param(
        [string]$SSHKeyPath,
        [string]$Hostname,
        [int]$Port = 22,
        [string]$User = "root",
        [string]$Command,
        [int]$TimeoutSeconds = 30
    )
    
    $sshOptions = @(
        "-i", $SSHKeyPath,
        "-p", $Port.ToString(),
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=NUL",
        "-o", "PasswordAuthentication=no",
        "-o", "ConnectTimeout=$TimeoutSeconds"
    )
    
    $sshArgs = $sshOptions + @("${User}@${Hostname}", $Command)
    
    try {
        $result = & ssh $sshArgs 2>&1
        return @{
            Success = ($LASTEXITCODE -eq 0)
            Output = $result
            ExitCode = $LASTEXITCODE
        }
    }
    catch {
        return @{
            Success = $false
            Output = $_.Exception.Message
            ExitCode = -1
        }
    }
}

function Copy-ToVM {
    <#
    .SYNOPSIS
    Copies a file to the VM via SCP.
    #>
    param(
        [string]$SSHKeyPath,
        [string]$Hostname,
        [int]$Port = 22,
        [string]$User = "root",
        [string]$SourcePath,
        [string]$DestPath
    )
    
    $scpOptions = @(
        "-i", $SSHKeyPath,
        "-P", $Port.ToString(),
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=NUL",
        "-o", "PasswordAuthentication=no"
    )
    
    $scpArgs = $scpOptions + @("$SourcePath", "${User}@${Hostname}:$DestPath")
    
    try {
        & scp $scpArgs 2>&1 | Out-Null
        return ($LASTEXITCODE -eq 0)
    }
    catch {
        return $false
    }
}

# ============================================================================
# PORT FORWARDING OPERATIONS
# ============================================================================

function Set-PortForwarding {
    <#
    .SYNOPSIS
    Sets up port forwarding for Quick Quarm game ports.
    #>
    param(
        [string]$VMIP,
        [int[]]$Ports = @(6000, 5998, 9000),
        [switch]$VerifyConnectivity
    )
    
    # Verify IP Helper service is running (required for port forwarding)
    Write-Host "  - Checking IP Helper service..." -ForegroundColor Gray
    $ipHelperService = Get-Service -Name "iphlpsvc" -ErrorAction SilentlyContinue
    if ($ipHelperService) {
        if ($ipHelperService.Status -ne "Running") {
            Write-Host "  ! IP Helper service is not running, attempting to start..." -ForegroundColor Yellow
            try {
                Start-Service -Name "iphlpsvc" -ErrorAction Stop
                Write-Host "  + IP Helper service started" -ForegroundColor Green
            }
            catch {
                Write-Host "  ! ERROR: Could not start IP Helper service: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host "    Port forwarding requires IP Helper service to be running" -ForegroundColor Yellow
                return 0
            }
        } else {
            Write-Host "  + IP Helper service is running" -ForegroundColor Green
        }
    } else {
        Write-Host "  ! WARNING: Could not check IP Helper service status" -ForegroundColor Yellow
    }
    
    $successCount = 0
    
    foreach ($port in $Ports) {
        try {
            # Remove existing rule
            netsh interface portproxy delete v4tov4 listenport=$port listenaddress=0.0.0.0 2>&1 | Out-Null
            
            # Add new rule
            $addResult = netsh interface portproxy add v4tov4 listenport=$port listenaddress=0.0.0.0 connectport=$port connectaddress=$VMIP 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  [PASS] Port $port forwarding configured" -ForegroundColor Green
                $successCount++
                
                # Verify connectivity if requested
                if ($VerifyConnectivity) {
                    Start-Sleep -Milliseconds 500
                    $test = Test-NetConnection -ComputerName localhost -Port $port -InformationLevel Quiet -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                    if ($test) {
                        Write-Host "  [PASS] Port $port is accessible and forwarding correctly" -ForegroundColor Green
                    } else {
                        Write-Host "  [WARN] Port $port forwarding configured but not responding (service may not be running yet)" -ForegroundColor Yellow
                    }
                }
            } else {
                Write-Host "  [WARN] Failed to configure port $port forwarding" -ForegroundColor Yellow
                Write-Host "    netsh output: $addResult" -ForegroundColor Gray
            }
        }
        catch {
            Write-Host "  [WARN] Error configuring port ${port}: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    
    # Show final port forwarding configuration
    if ($successCount -gt 0) {
        Write-Host "  - Port forwarding summary:" -ForegroundColor Gray
        $portProxyList = netsh interface portproxy show all 2>&1 | Out-String
        if ($portProxyList -match "Listen on ipv4") {
            $portProxyList -split "`n" | Where-Object { $_ -match "^\s*\d+\.\d+\.\d+\.\d+" -or $_ -match "Listen on ipv4" } | ForEach-Object {
                Write-Host "    $_" -ForegroundColor Gray
            }
        }
    }
    
    return $successCount
}

function Remove-PortForwarding {
    <#
    .SYNOPSIS
    Removes port forwarding rules.
    #>
    param(
        [int[]]$Ports = @(2222, 6000, 5998, 9000)
    )
    
    $removedCount = 0
    
    foreach ($port in $Ports) {
        try {
            netsh interface portproxy delete v4tov4 listenport=$port listenaddress=0.0.0.0 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  [PASS] Port $port forwarding removed" -ForegroundColor Green
                $removedCount++
            }
        }
        catch {
            # Continue
        }
    }
    
    return $removedCount
}

function Get-PortForwarding {
    <#
    .SYNOPSIS
    Gets current port forwarding configuration.
    #>
    try {
        $portForwarding = netsh interface portproxy show all 2>&1 | Out-String
        return $portForwarding
    }
    catch {
        return $null
    }
}

# ============================================================================
# FIREWALL OPERATIONS
# ============================================================================

function Set-FirewallRules {
    <#
    .SYNOPSIS
    Creates Windows Firewall rules for Quick Quarm ports.
    #>
    $rules = @(
        @{ Name = "Quick Quarm Login Server (6000)"; Port = 6000; Protocol = "Any" },
        @{ Name = "Quick Quarm Login Server TCP (5998)"; Port = 5998; Protocol = "TCP" },
        @{ Name = "Quick Quarm World Server (9000)"; Port = 9000; Protocol = "TCP" }
    )
    
    $successCount = 0
    
    foreach ($rule in $rules) {
        try {
            # Remove existing rule
            Remove-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue
            
            # Add new rule
            New-NetFirewallRule -DisplayName $rule.Name `
                -Direction Inbound `
                -LocalPort $rule.Port `
                -Protocol $rule.Protocol `
                -Action Allow `
                -Enabled True `
                -ErrorAction Stop | Out-Null
            
            Write-Host "  [PASS] Firewall rule added for port $($rule.Port)" -ForegroundColor Green
            $successCount++
        }
        catch {
            Write-Host "  [WARN] Error configuring firewall rule for port $($rule.Port): $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    
    return $successCount
}

function Remove-FirewallRules {
    <#
    .SYNOPSIS
    Removes Windows Firewall rules for Quick Quarm.
    #>
    try {
        $firewallRules = Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { 
            $_.DisplayName -match 'Quick Quarm' 
        }
        
        if (-not $firewallRules -or $firewallRules.Count -eq 0) {
            Write-Host "  [SKIP] No Quick Quarm firewall rules found" -ForegroundColor Yellow
            return 0
        }
        
        $removedCount = 0
        $failedRules = @()
        
        foreach ($rule in $firewallRules) {
            try {
                Remove-NetFirewallRule -DisplayName $rule.DisplayName -ErrorAction Stop
                Write-Host "  [PASS] Removed firewall rule: $($rule.DisplayName)" -ForegroundColor Green
                $removedCount++
            }
            catch {
                $failedRules += $rule.DisplayName
            }
        }
        
        if ($failedRules.Count -gt 0) {
            Write-Host "  [WARN] Failed to remove some rules: $($failedRules -join ', ')" -ForegroundColor Yellow
        }
        
        return $removedCount
    }
    catch {
        Write-Host "  [WARN] Error removing firewall rules: $($_.Exception.Message)" -ForegroundColor Yellow
        return 0
    }
}

# ============================================================================
# CONFIGURATION HELPERS
# ============================================================================

function Get-VMConfigPath {
    <#
    .SYNOPSIS
    Gets the standard VM configuration file path.
    #>
    return Join-Path $env:USERPROFILE "QuickQuarm-VM\vm-config.json"
}

function Get-VMConfig {
    <#
    .SYNOPSIS
    Gets VM configuration from config file.
    #>
    $configFile = Get-VMConfigPath
    if (Test-Path $configFile) {
        try {
            $config = Get-Content $configFile | ConvertFrom-Json
            return $config
        }
        catch {
            return $null
        }
    }
    return $null
}

function Save-VMConfig {
    <#
    .SYNOPSIS
    Saves VM configuration to config file.
    #>
    param(
        [hashtable]$Config
    )
    
    $configFile = Get-VMConfigPath
    $configDir = Split-Path $configFile -Parent
    
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }
    
    try {
        $Config | ConvertTo-Json | Out-File -FilePath $configFile -Encoding UTF8
        return $true
    }
    catch {
        return $false
    }
}

# Export all functions
Export-ModuleMember -Function @(
    'Test-Administrator',
    'Test-SSHKeyExists',
    'Test-VMExists',
    'Get-VMState',
    'Get-WindowsHostIPv4',
    'Get-DefaultSwitchNetworkConfig',
    'Get-VMIPAddress',
    'Start-QuarmVM',
    'Stop-QuarmVM',
    'Set-VMAutoStart',
    'Test-SSHConnection',
    'Invoke-SSHCommand',
    'Copy-ToVM',
    'Set-PortForwarding',
    'Remove-PortForwarding',
    'Get-PortForwarding',
    'Set-FirewallRules',
    'Remove-FirewallRules',
    'Get-VMConfigPath',
    'Get-VMConfig',
    'Save-VMConfig'
)
