# Quick Quarm Hyper-V VM Management Script
# Provides easy commands to manage the Quick Quarm VM

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Start", "Stop", "Restart", "Status", "SSH", "Logs")]
    [string]$Action
)

$VMName = "QuickQuarm"
$SSHKeyPath = "C:\Users\Laptop\QuickQuarm-VM\id_rsa"

# Check if VM exists
$vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if (-not $vm -and $Action -ne "Status") {
    Write-Host "ERROR: VM '$VMName' not found" -ForegroundColor Red
    Write-Host "Please run the installer first: .\QuarmInstaller-HyperV.ps1" -ForegroundColor Yellow
    exit 1
}

switch ($Action) {
    "Start" {
        Write-Host "Starting Quick Quarm VM..." -ForegroundColor Cyan
        
        if ($vm.State -eq "Running") {
            Write-Host "VM is already running" -ForegroundColor Yellow
            exit 0
        }
        
        try {
            Start-VM -Name $VMName -ErrorAction Stop
            Write-Host "VM started successfully" -ForegroundColor Green
            
            Write-Host "Waiting for VM to be ready..." -ForegroundColor Gray
            Start-Sleep -Seconds 10
            
            # Get VM IP
            $vmNetAdapter = Get-VMNetworkAdapter -VMName $VMName -ErrorAction SilentlyContinue
            if ($vmNetAdapter -and $vmNetAdapter.IPAddresses) {
                $vmIP = $vmNetAdapter.IPAddresses | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1
                if ($vmIP) {
                    Write-Host "VM IP Address: $vmIP" -ForegroundColor Cyan
                }
            }
        } catch {
            Write-Host "ERROR: Failed to start VM: $($_.Exception.Message)" -ForegroundColor Red
            exit 1
        }
    }
    
    "Stop" {
        Write-Host "Stopping Quick Quarm VM..." -ForegroundColor Cyan
        
        if ($vm.State -ne "Running") {
            Write-Host "VM is not running" -ForegroundColor Yellow
            exit 0
        }
        
        try {
            Stop-VM -Name $VMName -Force -ErrorAction Stop
            Write-Host "VM stopped successfully" -ForegroundColor Green
        } catch {
            Write-Host "ERROR: Failed to stop VM: $($_.Exception.Message)" -ForegroundColor Red
            exit 1
        }
    }
    
    "Restart" {
        Write-Host "Restarting Quick Quarm VM..." -ForegroundColor Cyan
        
        if ($vm.State -eq "Running") {
            try {
                Stop-VM -Name $VMName -Force -ErrorAction Stop
                Write-Host "VM stopped" -ForegroundColor Gray
                Start-Sleep -Seconds 3
            } catch {
                Write-Host "ERROR: Failed to stop VM: $($_.Exception.Message)" -ForegroundColor Red
                exit 1
            }
        }
        
        try {
            Start-VM -Name $VMName -ErrorAction Stop
            Write-Host "VM restarted successfully" -ForegroundColor Green
            
            Write-Host "Waiting for VM to be ready..." -ForegroundColor Gray
            Start-Sleep -Seconds 10
            
            # Get VM IP
            $vmNetAdapter = Get-VMNetworkAdapter -VMName $VMName -ErrorAction SilentlyContinue
            if ($vmNetAdapter -and $vmNetAdapter.IPAddresses) {
                $vmIP = $vmNetAdapter.IPAddresses | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1
                if ($vmIP) {
                    Write-Host "VM IP Address: $vmIP" -ForegroundColor Cyan
                }
            }
        } catch {
            Write-Host "ERROR: Failed to restart VM: $($_.Exception.Message)" -ForegroundColor Red
            exit 1
        }
    }
    
    "Status" {
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Quick Quarm VM Status" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        
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
        if ($vmNetAdapter) {
            Write-Host "Network Adapter:" -ForegroundColor Cyan
            Write-Host "  Switch: $($vmNetAdapter.SwitchName)" -ForegroundColor White
            Write-Host "  MAC Address: $($vmNetAdapter.MacAddress)" -ForegroundColor White
            
            if ($vmNetAdapter.IPAddresses) {
                $vmIP = $vmNetAdapter.IPAddresses | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1
                if ($vmIP) {
                    Write-Host "  IP Address: $vmIP" -ForegroundColor White
                } else {
                    Write-Host "  IP Address: Not assigned" -ForegroundColor Yellow
                }
            } else {
                Write-Host "  IP Address: Not available" -ForegroundColor Yellow
            }
        }
        Write-Host ""
        
        # Get VM resources
        Write-Host "VM Resources:" -ForegroundColor Cyan
        Write-Host "  Memory: $($vm.MemoryAssigned / 1GB) GB assigned / $($vm.MemoryStartup / 1GB) GB startup" -ForegroundColor White
        Write-Host "  Processors: $($vm.ProcessorCount)" -ForegroundColor White
        Write-Host ""
        
        # Check Quick Quarm service status if VM is running
        if ($vm.State -eq "Running" -and (Test-Path $SSHKeyPath) -and $vmIP) {
            Write-Host "Quick Quarm Services:" -ForegroundColor Cyan
            try {
                $serviceStatus = ssh -i $SSHKeyPath -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL root@$vmIP "systemctl is-active quick-quarm.target" 2>&1
                if ($serviceStatus -match "active") {
                    Write-Host "  Status: RUNNING" -ForegroundColor Green
                } else {
                    Write-Host "  Status: NOT RUNNING" -ForegroundColor Yellow
                }
            } catch {
                Write-Host "  Status: UNKNOWN (could not connect via SSH)" -ForegroundColor Yellow
            }
        } else {
            if ($vm.State -ne "Running") {
                Write-Host "Quick Quarm Services: VM not running" -ForegroundColor Gray
            }
        }
        Write-Host ""
        
        # Port forwarding status
        Write-Host "Port Forwarding:" -ForegroundColor Cyan
        $portForwarding = netsh interface portproxy show all 2>&1 | Out-String
        if ($portForwarding -match "6000|5998|9000") {
            $lines = $portForwarding -split "`r?`n" | Where-Object { $_ -match "6000|5998|9000" }
            foreach ($line in $lines) {
                Write-Host "  $line" -ForegroundColor White
            }
        } else {
            Write-Host "  No port forwarding configured" -ForegroundColor Yellow
            Write-Host "  Run: .\Connection-HyperV.ps1 -Action Fix" -ForegroundColor Cyan
        }
        Write-Host ""
    }
    
    "SSH" {
        Write-Host "Connecting to VM via SSH..." -ForegroundColor Cyan
        
        if ($vm.State -ne "Running") {
            Write-Host "ERROR: VM is not running" -ForegroundColor Red
            Write-Host "Start the VM first: .\Manage-QuarmVM.ps1 -Action Start" -ForegroundColor Yellow
            exit 1
        }
        
        if (-not (Test-Path $SSHKeyPath)) {
            Write-Host "ERROR: SSH key not found at $SSHKeyPath" -ForegroundColor Red
            exit 1
        }
        
        # Get VM IP
        $vmNetAdapter = Get-VMNetworkAdapter -VMName $VMName -ErrorAction SilentlyContinue
        $vmIP = $null
        if ($vmNetAdapter -and $vmNetAdapter.IPAddresses) {
            $vmIP = $vmNetAdapter.IPAddresses | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1
        }
        
        if (-not $vmIP) {
            Write-Host "ERROR: Could not get VM IP address" -ForegroundColor Red
            Write-Host "VM may not have network connectivity" -ForegroundColor Yellow
            exit 1
        }
        
        Write-Host "Connecting to root@$vmIP..." -ForegroundColor Gray
        Write-Host ""
        
        & ssh -i $SSHKeyPath -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL root@$vmIP
    }
    
    "Logs" {
        Write-Host "Fetching Quick Quarm logs from VM..." -ForegroundColor Cyan
        
        if ($vm.State -ne "Running") {
            Write-Host "ERROR: VM is not running" -ForegroundColor Red
            Write-Host "Start the VM first: .\Manage-QuarmVM.ps1 -Action Start" -ForegroundColor Yellow
            exit 1
        }
        
        if (-not (Test-Path $SSHKeyPath)) {
            Write-Host "ERROR: SSH key not found at $SSHKeyPath" -ForegroundColor Red
            exit 1
        }
        
        # Get VM IP
        $vmNetAdapter = Get-VMNetworkAdapter -VMName $VMName -ErrorAction SilentlyContinue
        $vmIP = $null
        if ($vmNetAdapter -and $vmNetAdapter.IPAddresses) {
            $vmIP = $vmNetAdapter.IPAddresses | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1
        }
        
        if (-not $vmIP) {
            Write-Host "ERROR: Could not get VM IP address" -ForegroundColor Red
            exit 1
        }
        
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Quick Quarm Service Logs" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        
        try {
            $logs = ssh -i $SSHKeyPath -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL root@$vmIP "journalctl -u quick-quarm.target -n 50 --no-pager" 2>&1
            Write-Host $logs
        } catch {
            Write-Host "ERROR: Failed to fetch logs: $($_.Exception.Message)" -ForegroundColor Red
            exit 1
        }
    }
}




