# Quick Quarm Uninstallation Script for Hyper-V
# This script removes Quick Quarm Hyper-V VM and related components

#Requires -RunAsAdministrator

param(
    [switch]$Force
)

$VMName = "QuickQuarm"
$VMPath = "C:\Users\Laptop\QuickQuarm-VM"

# Result tracking
$script:UninstallResults = @()

# Function to add an uninstall result
function Add-UninstallResult {
    param(
        [string]$ComponentName,
        [string]$Status,  # "Found", "Removed", "Not Found", "Failed", "Skipped"
        [string]$Message = ""
    )
    
    $script:UninstallResults += @{
        Name = $ComponentName
        Status = $Status
        Message = $Message
    }
}

# Function to check if VM exists
function Test-QuickQuarmVM {
    try {
        $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
        return $null -ne $vm
    }
    catch {
        return $false
    }
}

# Function to check if VM files exist
function Test-QuickQuarmVMFiles {
    return Test-Path $VMPath
}

# Function to stop and remove VM
function Remove-QuickQuarmVM {
    param([bool]$ShouldRemove = $true)
    
    Write-Host "[STEP 1/4] Removing Quick Quarm VM..." -ForegroundColor Yellow
    
    if (-not $ShouldRemove) {
        Add-UninstallResult -ComponentName "Hyper-V VM" -Status "Skipped" -Message "VM removal not requested"
        Write-Host "  - Skipping VM removal" -ForegroundColor Gray
        return
    }
    
    if (-not (Test-QuickQuarmVM)) {
        Add-UninstallResult -ComponentName "Hyper-V VM" -Status "Not Found" -Message "VM '$VMName' not found"
        Write-Host "  [OK] VM '$VMName' not found" -ForegroundColor Green
        return
    }
    
    Write-Host "  - Stopping VM..." -ForegroundColor Gray
    try {
        $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
        if ($vm.State -eq "Running") {
            Stop-VM -Name $VMName -Force -ErrorAction Stop
            Start-Sleep -Seconds 2
        }
    }
    catch {
        # Continue even if stop fails
    }
    
    Write-Host "  - Removing VM..." -ForegroundColor Gray
    try {
        Remove-VM -Name $VMName -Force -ErrorAction Stop
        Start-Sleep -Seconds 1
        
        # Verify removal
        if (-not (Test-QuickQuarmVM)) {
            Add-UninstallResult -ComponentName "Hyper-V VM" -Status "Removed" -Message "Successfully removed VM '$VMName'"
            Write-Host "  [OK] VM removed successfully" -ForegroundColor Green
        }
        else {
            Add-UninstallResult -ComponentName "Hyper-V VM" -Status "Failed" -Message "VM still exists after removal attempt"
            Write-Host "  ! Failed to remove VM" -ForegroundColor Red
        }
    }
    catch {
        Add-UninstallResult -ComponentName "Hyper-V VM" -Status "Failed" -Message "Error: $($_.Exception.Message)"
        Write-Host "  ! Error removing VM: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Function to remove VM files
function Remove-QuickQuarmVMFiles {
    param([bool]$ShouldRemove = $true)
    
    Write-Host "[STEP 2/4] Removing VM files..." -ForegroundColor Yellow
    
    if (-not $ShouldRemove) {
        Add-UninstallResult -ComponentName "VM Files" -Status "Skipped" -Message "File removal not requested"
        Write-Host "  - Skipping file removal" -ForegroundColor Gray
        return
    }
    
    if (-not (Test-QuickQuarmVMFiles)) {
        Add-UninstallResult -ComponentName "VM Files" -Status "Not Found" -Message "VM directory not found"
        Write-Host "  [OK] VM files not found" -ForegroundColor Green
        return
    }
    
    Write-Host "  - Removing directory $VMPath..." -ForegroundColor Gray
    
    try {
        Remove-Item -Path $VMPath -Recurse -Force -ErrorAction Stop
        Start-Sleep -Seconds 1
        
        # Verify removal
        if (-not (Test-QuickQuarmVMFiles)) {
            Add-UninstallResult -ComponentName "VM Files" -Status "Removed" -Message "Successfully removed $VMPath"
            Write-Host "  [OK] VM files removed successfully" -ForegroundColor Green
        }
        else {
            Add-UninstallResult -ComponentName "VM Files" -Status "Failed" -Message "Directory still exists after removal attempt"
            Write-Host "  ! Failed to remove VM files" -ForegroundColor Red
        }
    }
    catch {
        Add-UninstallResult -ComponentName "VM Files" -Status "Failed" -Message "Error: $($_.Exception.Message)"
        Write-Host "  ! Error removing VM files: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Function to remove port forwarding
function Remove-PortForwarding {
    param([bool]$ShouldRemove = $true)
    
    Write-Host "[STEP 3/4] Removing port forwarding..." -ForegroundColor Yellow
    
    if (-not $ShouldRemove) {
        Add-UninstallResult -ComponentName "Port Forwarding" -Status "Skipped" -Message "Port forwarding removal not requested"
        Write-Host "  - Skipping port forwarding removal" -ForegroundColor Gray
        return
    }
    
    try {
        $portForwarding = netsh interface portproxy show all 2>&1 | Out-String
        $hasForwarding = $portForwarding -match "2222|6000|5998|9000"
        
        if (-not $hasForwarding) {
            Add-UninstallResult -ComponentName "Port Forwarding" -Status "Not Found" -Message "No port forwarding rules found"
            Write-Host "  [OK] No port forwarding rules found" -ForegroundColor Green
            return
        }
        
        $removedCount = 0
        $ports = @(2222, 6000, 5998, 9000)
        
        foreach ($port in $ports) {
            try {
                netsh interface portproxy delete v4tov4 listenport=$port listenaddress=0.0.0.0 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    $removedCount++
                }
            }
            catch {
                # Continue
            }
        }
        
        Add-UninstallResult -ComponentName "Port Forwarding" -Status "Removed" -Message "Removed $removedCount port forwarding rule(s)"
        Write-Host "  [OK] Removed $removedCount port forwarding rule(s)" -ForegroundColor Green
    }
    catch {
        Add-UninstallResult -ComponentName "Port Forwarding" -Status "Failed" -Message "Error: $($_.Exception.Message)"
        Write-Host "  ! Error removing port forwarding: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Function to remove firewall rules
function Remove-FirewallRules {
    param([bool]$ShouldRemove = $true)
    
    Write-Host "[STEP 4/4] Removing firewall rules..." -ForegroundColor Yellow
    
    if (-not $ShouldRemove) {
        Add-UninstallResult -ComponentName "Firewall Rules" -Status "Skipped" -Message "Firewall rules removal not requested"
        Write-Host "  - Skipping firewall rules removal" -ForegroundColor Gray
        return
    }
    
    try {
        $firewallRules = Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { 
            $_.DisplayName -match 'Quick Quarm' 
        }
        
        if (-not $firewallRules -or $firewallRules.Count -eq 0) {
            Add-UninstallResult -ComponentName "Firewall Rules" -Status "Not Found" -Message "No Quick Quarm firewall rules found"
            Write-Host "  [OK] No Quick Quarm firewall rules found" -ForegroundColor Green
            return
        }
        
        $removedCount = 0
        $failedRules = @()
        
        foreach ($rule in $firewallRules) {
            try {
                Remove-NetFirewallRule -DisplayName $rule.DisplayName -ErrorAction Stop
                $removedCount++
            }
            catch {
                $failedRules += $rule.DisplayName
            }
        }
        
        if ($failedRules.Count -gt 0) {
            Add-UninstallResult -ComponentName "Firewall Rules" -Status "Failed" -Message "Removed $removedCount/$($firewallRules.Count) rules. Failed: $($failedRules -join ', ')"
            Write-Host "  ! Removed $removedCount/$($firewallRules.Count) rules" -ForegroundColor Yellow
        }
        else {
            Add-UninstallResult -ComponentName "Firewall Rules" -Status "Removed" -Message "Successfully removed $removedCount rule(s)"
            Write-Host "  [OK] Successfully removed $removedCount rule(s)" -ForegroundColor Green
        }
    }
    catch {
        Add-UninstallResult -ComponentName "Firewall Rules" -Status "Failed" -Message "Error: $($_.Exception.Message)"
        Write-Host "  ! Error removing firewall rules: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Function to generate uninstall report
function Get-UninstallReport {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Uninstallation Report" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    $checkNumber = 1
    $totalChecks = $script:UninstallResults.Count
    
    foreach ($result in $script:UninstallResults) {
        $statusColor = switch ($result.Status) {
            "Removed" { "Green" }
            "Not Found" { "Gray" }
            "Skipped" { "Yellow" }
            "Failed" { "Red" }
            "Found" { "Cyan" }
            default { "White" }
        }
        
        $statusSymbol = switch ($result.Status) {
            "Removed" { "[REMOVED]" }
            "Not Found" { "[NOT FOUND]" }
            "Skipped" { "[SKIPPED]" }
            "Failed" { "[FAILED]" }
            "Found" { "[FOUND]" }
            default { "[UNKNOWN]" }
        }
        
        Write-Host "[$checkNumber/$totalChecks] $($result.Name): " -NoNewline
        Write-Host $statusSymbol -ForegroundColor $statusColor
        
        if ($result.Message) {
            Write-Host "  $($result.Message)" -ForegroundColor Gray
        }
        
        $checkNumber++
    }
    
    Write-Host ""
    
    # Summary
    $removedCount = ($script:UninstallResults | Where-Object { $_.Status -eq "Removed" }).Count
    $notFoundCount = ($script:UninstallResults | Where-Object { $_.Status -eq "Not Found" }).Count
    $skippedCount = ($script:UninstallResults | Where-Object { $_.Status -eq "Skipped" }).Count
    $failedCount = ($script:UninstallResults | Where-Object { $_.Status -eq "Failed" }).Count
    
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Summary" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    if ($removedCount -gt 0) {
        Write-Host "  Removed: $removedCount component(s)" -ForegroundColor Green
    }
    if ($notFoundCount -gt 0) {
        Write-Host "  Not Found: $notFoundCount component(s)" -ForegroundColor Gray
    }
    if ($skippedCount -gt 0) {
        Write-Host "  Skipped: $skippedCount component(s)" -ForegroundColor Yellow
    }
    if ($failedCount -gt 0) {
        Write-Host "  Failed: $failedCount component(s)" -ForegroundColor Red
    }
    
    Write-Host ""
    
    if ($failedCount -gt 0) {
        Write-Host "========================================" -ForegroundColor Red
        Write-Host "Uninstallation Complete with Errors" -ForegroundColor Red
        Write-Host "========================================" -ForegroundColor Red
        Write-Host ""
        Write-Host "Some components could not be removed." -ForegroundColor Yellow
        Write-Host ""
        return 1
    }
    elseif ($removedCount -gt 0 -or $notFoundCount -gt 0) {
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "Uninstallation Complete" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "Quick Quarm Hyper-V VM has been successfully uninstalled." -ForegroundColor Green
        Write-Host ""
        return 0
    }
    else {
        Write-Host "========================================" -ForegroundColor Yellow
        Write-Host "Nothing to Uninstall" -ForegroundColor Yellow
        Write-Host "========================================" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "No Quick Quarm components were found to remove." -ForegroundColor Yellow
        Write-Host ""
        return 0
    }
}

# Function to prompt user for uninstall options
function Get-UninstallOptions {
    param([bool]$Force = $false)
    
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Quick Quarm Uninstaller (Hyper-V)" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Scanning for Quick Quarm components..." -ForegroundColor Yellow
    Write-Host ""
    
    # Check what's installed
    $vmFound = Test-QuickQuarmVM
    $filesFound = Test-QuickQuarmVMFiles
    $portForwardingFound = $false
    $firewallRulesFound = $false
    
    try {
        $portForwarding = netsh interface portproxy show all 2>&1 | Out-String
        $portForwardingFound = $portForwarding -match "2222|6000|5998|9000"
    } catch {}
    
    try {
        $firewallRules = Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { 
            $_.DisplayName -match 'Quick Quarm' 
        }
        $firewallRulesFound = $null -ne $firewallRules -and $firewallRules.Count -gt 0
    } catch {}
    
    # Display what was found
    Write-Host "Components found:" -ForegroundColor Cyan
    if ($vmFound) {
        Write-Host "  [OK] Quick Quarm Hyper-V VM" -ForegroundColor Green
    }
    else {
        Write-Host "  [ ] Quick Quarm Hyper-V VM (not found)" -ForegroundColor Gray
    }
    
    if ($filesFound) {
        Write-Host "  [OK] VM files ($VMPath)" -ForegroundColor Green
    }
    else {
        Write-Host "  [ ] VM files (not found)" -ForegroundColor Gray
    }
    
    if ($portForwardingFound) {
        Write-Host "  [OK] Port forwarding rules" -ForegroundColor Green
    }
    else {
        Write-Host "  [ ] Port forwarding rules (not found)" -ForegroundColor Gray
    }
    
    if ($firewallRulesFound) {
        Write-Host "  [OK] Windows Firewall rules" -ForegroundColor Green
    }
    else {
        Write-Host "  [ ] Windows Firewall rules (not found)" -ForegroundColor Gray
    }
    
    Write-Host ""
    
    # Check if nothing was found
    if (-not $vmFound -and -not $filesFound -and -not $portForwardingFound -and -not $firewallRulesFound) {
        Write-Host "No Quick Quarm components were found." -ForegroundColor Yellow
        Write-Host ""
        return @{
            RemoveVM = $false
            RemoveFiles = $false
            RemovePortForwarding = $false
            RemoveFirewall = $false
        }
    }
    
    # Confirm removal
    Write-Host "This will remove all Quick Quarm Hyper-V VM components." -ForegroundColor Yellow
    Write-Host ""
    
    if (-not $Force) {
        $confirm = Read-Host "Do you want to proceed with uninstallation? (yes/no)"
        if ($confirm -ne "yes") {
            Write-Host ""
            Write-Host "Uninstallation cancelled." -ForegroundColor Yellow
            return $null
        }
        Write-Host ""
    }
    else {
        Write-Host "Force mode enabled - skipping confirmation." -ForegroundColor Yellow
        Write-Host ""
    }
    
    return @{
        RemoveVM = $vmFound
        RemoveFiles = $filesFound
        RemovePortForwarding = $portForwardingFound
        RemoveFirewall = $firewallRulesFound
    }
}

# Main uninstallation process
try {
    # Check if running as administrator
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "ERROR: This script must be run as Administrator" -ForegroundColor Red
        Write-Host "Right-click PowerShell and select Run as Administrator" -ForegroundColor Yellow
        exit 1
    }
    
    # Get user's uninstall options
    $uninstallOptions = Get-UninstallOptions -Force $Force
    
    # Check if user cancelled
    if ($null -eq $uninstallOptions) {
        exit 0
    }
    
    # Clear previous results
    $script:UninstallResults = @()
    
    # Run uninstallation steps
    Remove-QuickQuarmVM -ShouldRemove $uninstallOptions.RemoveVM
    Remove-QuickQuarmVMFiles -ShouldRemove $uninstallOptions.RemoveFiles
    Remove-PortForwarding -ShouldRemove $uninstallOptions.RemovePortForwarding
    Remove-FirewallRules -ShouldRemove $uninstallOptions.RemoveFirewall
    
    # Generate and display report
    $exitCode = Get-UninstallReport
    exit $exitCode
}
catch {
    Write-Host ""
    Write-Host "ERROR: Uninstallation failed" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "If you need help, please provide this error message." -ForegroundColor Yellow
    exit 1
}



