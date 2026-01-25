# Quick Quarm VM Network Diagnostic
#Requires -RunAsAdministrator

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Quick Quarm Network Diagnostic" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$issues = @()
$vmIP = $null

# Check VM
Write-Host "[1/4] Checking VM..." -ForegroundColor Yellow
$vm = Get-VM -Name "QuickQuarm" -ErrorAction SilentlyContinue
if (-not $vm) {
    Write-Host "  [FAIL] VM 'QuickQuarm' not found" -ForegroundColor Red
    exit 1
}
if ($vm.State -ne "Running") {
    Write-Host "  [WARN] VM is $($vm.State). Starting..." -ForegroundColor Yellow
    Start-VM -Name "QuickQuarm"
    Start-Sleep -Seconds 30
}
Write-Host "  [PASS] VM is running" -ForegroundColor Green
Write-Host ""

# Get VM IP
Write-Host "[2/4] Detecting VM IP..." -ForegroundColor Yellow
$vmNetAdapter = Get-VMNetworkAdapter -VMName "QuickQuarm"
if ($vmNetAdapter.IPAddresses) {
    $vmIP = $vmNetAdapter.IPAddresses | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1
}

if ($vmIP) {
    Write-Host "  [INFO] Hyper-V reports: $vmIP (testing...)" -ForegroundColor Cyan
    $test = Test-NetConnection -ComputerName $vmIP -Port 22 -WarningAction SilentlyContinue -InformationLevel Quiet
    if ($test) {
        Write-Host "  [PASS] VM IP: $vmIP" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] IP not responding, scanning..." -ForegroundColor Yellow
        $vmIP = $null
    }
}

if (-not $vmIP) {
    Write-Host "  [INFO] Scanning networks..." -ForegroundColor Cyan
    
    # Get all Hyper-V network adapters to scan
    $networksToScan = @()
    
    # Add LAN networks (External switches)
    $lanNetworks = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object {
        $_.InterfaceAlias -like "vEthernet*" -and
        $_.InterfaceAlias -notlike "*Default Switch*" -and
        $_.IPAddress -notmatch '^(127\.|169\.254\.)'
    }
    foreach ($net in $lanNetworks) {
        $networksToScan += @{
            Name = $net.InterfaceAlias
            IP = $net.IPAddress
            Prefix = $net.PrefixLength
        }
    }
    
    # Add Default Switch
    $defaultSwitch = Get-NetIPAddress -InterfaceAlias "vEthernet (Default Switch)" -AddressFamily IPv4 -ErrorAction SilentlyContinue
    if ($defaultSwitch) {
        $networksToScan += @{
            Name = "Default Switch"
            IP = $defaultSwitch.IPAddress
            Prefix = $defaultSwitch.PrefixLength
        }
    }
    
    # Scan each network
    foreach ($network in $networksToScan) {
        Write-Host "  - Scanning $($network.Name) ($($network.IP)/$($network.Prefix))..." -ForegroundColor Gray
        
        $ipBytes = [System.Net.IPAddress]::Parse($network.IP).GetAddressBytes()
        $ipInt = [System.BitConverter]::ToUInt32($ipBytes[3..0], 0)
        $maskInt = [Convert]::ToUInt32(("1" * $network.Prefix).PadRight(32, "0"), 2)
        $networkInt = $ipInt -band $maskInt
        $broadcastInt = $networkInt -bor (-bnot $maskInt)
        
        for ($ip = $networkInt + 2; $ip -lt $broadcastInt; $ip++) {
            $bytes = [System.BitConverter]::GetBytes($ip)
            $testIP = [System.Net.IPAddress]::new($bytes[3..0]).ToString()
            if ($testIP -eq $network.IP) { continue }
            
            try {
                $tcpClient = New-Object System.Net.Sockets.TcpClient
                $connect = $tcpClient.BeginConnect($testIP, 22, $null, $null)
                if ($connect.AsyncWaitHandle.WaitOne(50, $false)) {
                    $tcpClient.EndConnect($connect)
                    $tcpClient.Close()
                    $vmIP = $testIP
                    Write-Host "  [PASS] Found VM: $vmIP" -ForegroundColor Green
                    break
                }
                $tcpClient.Close()
            } catch { }
        }
        
        if ($vmIP) { break }
    }
    
    if (-not $vmIP) {
        Write-Host "  [FAIL] Could not detect VM IP" -ForegroundColor Red
        $issues += "VM IP not detected - may still be booting"
    }
}
Write-Host ""

# Test SSH
Write-Host "[3/4] Testing SSH..." -ForegroundColor Yellow
if ($vmIP) {
    $sshKey = "$env:USERPROFILE\QuickQuarm-VM\id_rsa"
    if (Test-Path $sshKey) {
        $result = ssh -i $sshKey -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL root@$vmIP "echo OK" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [PASS] SSH connection successful" -ForegroundColor Green
            
            $qqStatus = ssh -i $sshKey -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL root@$vmIP "systemctl is-active quick-quarm.target 2>&1" 2>&1
            if ($qqStatus -match "^active$") {
                Write-Host "  [PASS] Quick Quarm is running" -ForegroundColor Green
            } elseif ($qqStatus -match "could not be found") {
                Write-Host "  [FAIL] Quick Quarm not installed" -ForegroundColor Red
                $issues += "Quick Quarm not installed on VM"
            } else {
                Write-Host "  [WARN] Quick Quarm is $qqStatus" -ForegroundColor Yellow
                $issues += "Quick Quarm not active"
            }
        } else {
            Write-Host "  [FAIL] SSH connection failed" -ForegroundColor Red
            $issues += "SSH not responding"
        }
    } else {
        Write-Host "  [FAIL] SSH key not found" -ForegroundColor Red
        $issues += "SSH key missing"
    }
} else {
    Write-Host "  [SKIP] No IP to test" -ForegroundColor Yellow
}
Write-Host ""

# Check port forwarding
Write-Host "[4/4] Checking port forwarding..." -ForegroundColor Yellow
$portProxy = netsh interface portproxy show v4tov4 2>&1 | Out-String
if ($portProxy -match "6000.*$vmIP") {
    Write-Host "  [PASS] Game ports forwarded" -ForegroundColor Green
} else {
    Write-Host "  [WARN] Game ports NOT forwarded" -ForegroundColor Yellow
    $issues += "Port forwarding not configured"
}
Write-Host ""

# Summary
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ($issues.Count -eq 0) {
    Write-Host "Status: All checks passed!" -ForegroundColor Green
    Write-Host ""
    if ($vmIP) {
        Write-Host "VM IP: $vmIP" -ForegroundColor Green
        $hostIP = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq "Up" }).IPv4Address.IPAddress | Select-Object -First 1
        if ($hostIP) {
            Write-Host "Client config: $hostIP:6000" -ForegroundColor Cyan
        }
    }
} else {
    Write-Host "Issues found:" -ForegroundColor Yellow
    foreach ($issue in $issues) {
        Write-Host "  - $issue" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "Recommended fix:" -ForegroundColor Cyan
    Write-Host "  .\Connection-HyperV.ps1 -Action Fix" -ForegroundColor White
}

Write-Host ""
