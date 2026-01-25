# Quick Quarm Installation Script for Windows (WSL2)
# This script sets up WSL2 with Ubuntu 22.04 and installs Quick Quarm

#Requires -RunAsAdministrator

param(
    [string]$InstallUser = "root",
    [string]$InstallPassword = "root",
    [string]$RepoUrl = "https://github.com/SecretsOTheP/EQMacEmu.git",
    [string]$DBHost = "localhost",
    [string]$DBName = "quarm",
    [string]$DBUser = "quarm",
    [string]$DBPassword = "quarm"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Quick Quarm Installation for Windows" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Function to check if WSL command is available
function Test-WSLCommand {
    try {
        $result = Get-Command wsl.exe -ErrorAction SilentlyContinue
        return $null -ne $result
    }
    catch {
        return $false
    }
}

# Function to check if WSL2 is properly installed and working
function Test-WSL2 {
    if (-not (Test-WSLCommand)) {
        return $false
    }
    
    try {
        $status = wsl --status 2>&1
        if ($status -match "not installed" -or $LASTEXITCODE -ne 0) {
            return $false
        }
        return $true
    }
    catch {
        return $false
    }
}

# Function to check if restart is needed
function Test-RestartNeeded {
    try {
        $featureStates = @()
        $featureStates += (Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux).State
        $featureStates += (Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform).State
        
        foreach ($state in $featureStates) {
            if ($state -eq "EnablePending") {
                return $true
            }
        }
        return $false
    }
    catch {
        return $false
    }
}

# Function to check if a specific Windows feature is enabled
function Test-WindowsFeature {
    param([string]$FeatureName)
    
    try {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName $FeatureName -ErrorAction SilentlyContinue
        return ($feature.State -eq "Enabled")
    }
    catch {
        return $false
    }
}

# Function to install WSL2
function Install-WSL2 {
    Write-Host "[STEP 1/7] Configuring WSL2..." -ForegroundColor Yellow
    
    $needsRestart = $false
    
    # Check and enable WSL feature
    if (-not (Test-WindowsFeature "Microsoft-Windows-Subsystem-Linux")) {
        Write-Host "  - Enabling WSL feature..." -ForegroundColor Gray
        Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart | Out-Null
        $needsRestart = $true
    }
    else {
        Write-Host "  ✓ WSL feature already enabled" -ForegroundColor Green
    }
    
    # Check and enable Virtual Machine Platform
    if (-not (Test-WindowsFeature "VirtualMachinePlatform")) {
        Write-Host "  - Enabling Virtual Machine Platform..." -ForegroundColor Gray
        Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart | Out-Null
        $needsRestart = $true
    }
    else {
        Write-Host "  ✓ Virtual Machine Platform already enabled" -ForegroundColor Green
    }
    
    # Check if restart is needed
    if ($needsRestart -or (Test-RestartNeeded)) {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Yellow
        Write-Host "RESTART REQUIRED" -ForegroundColor Yellow
        Write-Host "========================================" -ForegroundColor Yellow
        Write-Host "Windows features have been enabled but require a restart." -ForegroundColor Yellow
        Write-Host "After restarting, run this script again to continue." -ForegroundColor Yellow
        Write-Host ""
        $response = Read-Host "Would you like to restart now? (Y/n)"
        if ($response -eq '' -or $response -eq 'y' -or $response -eq 'Y') {
            Restart-Computer -Force
        }
        exit 0
    }
    
    # Install WSL kernel and set default version if not already done
    if (-not (Test-WSLCommand)) {
        Write-Host "  - Installing WSL kernel..." -ForegroundColor Gray
        wsl --install --no-distribution 2>&1 | Out-Null
    }
    else {
        Write-Host "  ✓ WSL kernel already installed" -ForegroundColor Green
    }
    
    # Set WSL2 as default version
    Write-Host "  - Setting WSL2 as default version..." -ForegroundColor Gray
    wsl --set-default-version 2 2>&1 | Out-Null
    
    Write-Host "  ✓ WSL2 configuration complete" -ForegroundColor Green
}

# Function to check if Ubuntu 22.04 is installed
function Test-Ubuntu2204 {
    # PRIMARY METHOD: Try to execute a command directly - if it works, Ubuntu is installed
    # This is the most reliable method and doesn't depend on parsing output
    try {
        $null = wsl -d Ubuntu-22.04 -e echo "test" 2>&1
        if ($LASTEXITCODE -eq 0) {
            return $true
        }
    }
    catch {
        # Continue to list check
    }
    
    try {
        # Get the distribution list - use raw output to avoid encoding issues
        $distrosRaw = wsl -l -v 2>&1
        $distros = if ($distrosRaw -is [string]) { $distrosRaw } else { $distrosRaw | Out-String }
        
        # Convert to string and make case-insensitive
        $distrosStr = $distros.ToString().ToLower()
        
        # Method 1: Remove ALL whitespace (handles spaced characters like "U b u n t u")
        $noSpaces = $distrosStr -replace '\s', ''
        if ($noSpaces.Contains("ubuntu-22.04")) {
            return $true
        }
        
        # Method 2: Check each line individually
        $lines = $distrosStr -split "`r?`n"
        foreach ($line in $lines) {
            $lineNoSpaces = $line -replace '\s', ''
            if ($lineNoSpaces.Contains("ubuntu-22.04")) {
                return $true
            }
        }
        
        # Method 3: Simple substring search (case-insensitive)
        if ($distrosStr.Contains("ubuntu-22.04") -or ($distrosStr.Contains("ubuntu") -and $distrosStr.Contains("22.04"))) {
            return $true
        }
        
        # Method 4: Regex match (case-insensitive)
        if ($distrosStr -match "ubuntu-22\.04" -or $distrosStr -match "ubuntu.*22\.04") {
            return $true
        }
        
        return $false
    }
    catch {
        return $false
    }
}

# Function to check if Ubuntu 22.04 is functional (can execute commands)
function Test-Ubuntu2204Functional {
    if (-not (Test-Ubuntu2204)) {
        return $false
    }
    
    try {
        $testResult = wsl -d Ubuntu-22.04 echo "test" 2>&1
        # Check if command succeeded (no error messages)
        if ($LASTEXITCODE -eq 0 -and $testResult -notmatch "error" -and $testResult -notmatch "not found" -and $testResult -notmatch "not registered") {
            return $true
        }
        return $false
    }
    catch {
        return $false
    }
}

# Function to create cloud-init configuration for automated Ubuntu setup
function Create-CloudInitConfig {
    param(
        [string]$Username,
        [string]$Password
    )
    
    Write-Host "  - Creating cloud-init configuration for automated setup..." -ForegroundColor Gray
    
    # Get user home directory
    $userHome = $env:USERPROFILE
    $cloudInitDir = Join-Path $userHome ".cloud-init"
    $userDataFile = Join-Path $cloudInitDir "Ubuntu-22.04.user-data"
    
    # Create .cloud-init directory if it doesn't exist
    if (-not (Test-Path $cloudInitDir)) {
        New-Item -ItemType Directory -Path $cloudInitDir -Force | Out-Null
    }
    
    # Create user-data file with cloud-init configuration
    $chpasswdLine = "${Username}:${Password}"
    $userDataContent = @"
#cloud-config
users:
  - name: $Username
    gecos: Quick Quarm User
    groups: [adm, dialout, cdrom, floppy, sudo, audio, dip, video, plugdev, netdev]
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
chpasswd:
  list: |
    $chpasswdLine
  expire: false
"@
    
    $userDataContent | Out-File -FilePath $userDataFile -Encoding UTF8 -Force
    
    Write-Host "  ✓ Cloud-init configuration created" -ForegroundColor Green
    return $userDataFile
}

# Function to cleanly uninstall Ubuntu 22.04
function Uninstall-Ubuntu2204 {
    Write-Host "  - Unregistering Ubuntu 22.04..." -ForegroundColor Gray
    
    # Stop any running WSL instances first
    try {
        wsl --shutdown 2>&1 | Out-Null
        Start-Sleep -Seconds 2
    }
    catch {
        # Ignore errors - WSL might not be running
    }
    
    # Unregister the distribution
    $unregisterResult = wsl --unregister Ubuntu-22.04 2>&1
    Start-Sleep -Seconds 3
    
    # Verify it was actually unregistered
    $maxRetries = 3
    $retryCount = 0
    while ($retryCount -lt $maxRetries -and (Test-Ubuntu2204)) {
        Start-Sleep -Seconds 2
        $retryCount++
        if ($retryCount -lt $maxRetries) {
            Write-Host "    Retrying unregister (attempt $($retryCount + 1)/$maxRetries)..." -ForegroundColor Gray
            wsl --unregister Ubuntu-22.04 2>&1 | Out-Null
            Start-Sleep -Seconds 2
        }
    }
    
    if (Test-Ubuntu2204) {
        Write-Host "  ! Failed to unregister Ubuntu 22.04 after $maxRetries attempts" -ForegroundColor Red
        Write-Host "    Please try manually: wsl --unregister Ubuntu-22.04" -ForegroundColor Yellow
        return $false
    }
    
    Write-Host "  ✓ Ubuntu 22.04 successfully unregistered" -ForegroundColor Green
    return $true
}

# Function to install Ubuntu 22.04
function Install-Ubuntu {
    param(
        [string]$Username,
        [string]$Password
    )
    
    Write-Host "[STEP 2/7] Configuring Ubuntu 22.04 LTS..." -ForegroundColor Yellow
    
    # First check if Ubuntu exists and is functional
    if (Test-Ubuntu2204Functional) {
        Write-Host "  ✓ Ubuntu 22.04 already installed and functional" -ForegroundColor Green
        return
    }
    
    # Check if Ubuntu exists but may not be functional (from previous failed install)
    # Use the Test-Ubuntu2204 function which handles normalization
    Write-Host "  - Checking if Ubuntu 22.04 is already installed..." -ForegroundColor Gray
    Start-Sleep -Seconds 1
    $ubuntuExists = Test-Ubuntu2204
    
    # Debug: Show what we found
    if ($ubuntuExists) {
        Write-Host "  ✓ Ubuntu 22.04 detected as installed" -ForegroundColor Green
    }
    else {
        Write-Host "  - Ubuntu 22.04 not found in installed distributions" -ForegroundColor Gray
    }
    
    if ($ubuntuExists) {
        Write-Host "  ✓ Ubuntu 22.04 is installed" -ForegroundColor Green
        Write-Host "  - Checking if it's functional..." -ForegroundColor Gray
        
        # Try to test if it's actually working
        Start-Sleep -Seconds 2
        if (Test-Ubuntu2204Functional) {
            Write-Host "  ✓ Ubuntu 22.04 is functional" -ForegroundColor Green
            return
        }
        
        # Ubuntu exists but not functional - might need cloud-init setup
        Write-Host "  ! Ubuntu 22.04 exists but is not functional" -ForegroundColor Yellow
        Write-Host "  - Will attempt to configure it with cloud-init..." -ForegroundColor Gray
        
        # Create cloud-init config
        Create-CloudInitConfig -Username $Username -Password $Password
        
        # Skip installation, go straight to cloud-init setup
        Write-Host "  - Skipping installation (Ubuntu already exists)" -ForegroundColor Gray
        Write-Host "  - Launching Ubuntu to trigger cloud-init setup..." -ForegroundColor Gray
        
        # Jump to cloud-init setup (skip the installation section)
        $skipToCloudInit = $true
    }
    else {
        # Create cloud-init configuration for automated setup
        Create-CloudInitConfig -Username $Username -Password $Password
        $skipToCloudInit = $false
    }
    
    # Skip installation if Ubuntu already exists
    if (-not $skipToCloudInit) {
        # Install Ubuntu 22.04 (note: --no-launch may not be supported, we'll handle setup after install)
    Write-Host "  - Installing Ubuntu 22.04 (this may take 5-10 minutes)..." -ForegroundColor Gray
    Write-Host "    Please wait, downloading and extracting..." -ForegroundColor Gray
    
    # Check available distributions first
    Write-Host "  - Checking available Ubuntu distributions..." -ForegroundColor Gray
    $availableDistros = wsl --list --online 2>&1 | Out-String
    # Normalize the string for matching (remove extra spaces)
    $normalizedDistros = $availableDistros -replace '\s+', ' '
    if ($normalizedDistros -match "Ubuntu-22\.04" -or $normalizedDistros -match "Ubuntu.*22\.04") {
        Write-Host "  ✓ Ubuntu 22.04 found in available distributions" -ForegroundColor Green
    }
    else {
        Write-Host "  ! Ubuntu 22.04 not found in available distributions" -ForegroundColor Yellow
        Write-Host "    Available distributions:" -ForegroundColor Gray
        Write-Host $availableDistros -ForegroundColor Gray
    }
    
    # Start the installation process (without --no-launch as it may not be supported)
    # We'll handle the setup after installation completes
    $job = Start-Job -ScriptBlock {
        wsl --install -d Ubuntu-22.04 2>&1
    }
    
    # Wait with progress indicator
    $timeout = 600 # 10 minutes
    $elapsed = 0
    $dots = 0
    
    while ($job.State -eq 'Running' -and $elapsed -lt $timeout) {
        Start-Sleep -Seconds 2
        $elapsed += 2
        $dots = ($dots + 1) % 4
        $progress = "." * $dots
        $output = ("    Progress: $progress").PadRight(25)
        Write-Host "`r$output" -NoNewline -ForegroundColor Gray
    }
    
    Write-Host "" # New line after progress
    
    # Check if job timed out
    if ($job.State -eq 'Running') {
        Stop-Job -Job $job
        Remove-Job -Job $job
        
        # Before showing error, check if Ubuntu was actually installed (maybe from a previous attempt)
        Start-Sleep -Seconds 3
        if (Test-Ubuntu2204Functional) {
            Write-Host "  ✓ Ubuntu 22.04 is now functional (installation may have completed)" -ForegroundColor Green
            return
        }
        
        Write-Host ""
        Write-Host "  ! Installation is taking longer than expected" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  This can happen due to:" -ForegroundColor Yellow
        Write-Host "    - Slow internet connection" -ForegroundColor Gray
        Write-Host "    - Network connectivity issues" -ForegroundColor Gray
        Write-Host "    - Windows Update conflicts" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  You can try installing manually from command line:" -ForegroundColor Cyan
        Write-Host "    wsl --install -d Ubuntu-22.04" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  After installation completes, run this script again to continue." -ForegroundColor Gray
        exit 1
    }
    
    # Get job results
    $result = Receive-Job -Job $job
    Remove-Job -Job $job
    
    # Show installation output for debugging
    Write-Host "  - Installation output:" -ForegroundColor Gray
    $resultString = $result | Out-String
    if ($resultString.Trim()) {
        Write-Host $resultString -ForegroundColor Yellow
    }
    else {
        Write-Host "    (No output from installation command)" -ForegroundColor Gray
    }
    
    # Check if Ubuntu was installed
    Write-Host "  - Verifying installation..." -ForegroundColor Gray
    Start-Sleep -Seconds 5
    
    # Check what distributions are actually installed
    Write-Host "  - Checking installed WSL distributions..." -ForegroundColor Gray
    $installedDistros = wsl -l -v 2>&1 | Out-String
    Write-Host $installedDistros -ForegroundColor Gray
    
    # Check if Ubuntu exists (even if not functional yet)
    # Use multiple detection methods - the most reliable is trying to execute a command
    Start-Sleep -Seconds 2
    
    # Method 1: Try to execute a command directly (MOST RELIABLE - if this works, Ubuntu is installed)
    $canExecute = $false
    try {
        $null = wsl -d Ubuntu-22.04 -e echo "test" 2>&1
        if ($LASTEXITCODE -eq 0) {
            $canExecute = $true
        }
    }
    catch {
        # Continue to other methods
    }
    
    # Method 2: Parse the output we just displayed (handle spaced characters)
    $noSpacesCheck = ($installedDistros.ToString() -replace '\s', '').ToLower()
    $directCheck = $noSpacesCheck.Contains("ubuntu-22.04")
    
    # Method 3: Use the detection function
    $functionCheck = Test-Ubuntu2204
    
    # If ANY method detects Ubuntu, it's installed (command execution is most reliable)
    $ubuntuInstalled = $canExecute -or $directCheck -or $functionCheck
    
    if ($ubuntuInstalled) {
        Write-Host "  ✓ Ubuntu 22.04 detected as installed" -ForegroundColor Green
        Write-Host "  - Proceeding to cloud-init setup..." -ForegroundColor Gray
        # Skip all alternative installation attempts and proceed to cloud-init
    }
    else {
        Write-Host "  ! Installation failed - Ubuntu 22.04 not found" -ForegroundColor Red
        
        # Try alternative distribution names
        Write-Host "  - Trying alternative installation method..." -ForegroundColor Yellow
        Write-Host "    Attempting: wsl --install Ubuntu" -ForegroundColor Gray
        
        # Try installing just "Ubuntu" which might install the latest version
        $altJob = Start-Job -ScriptBlock {
            wsl --install -d Ubuntu --no-launch 2>&1
        }
        
        $altTimeout = 600
        $altElapsed = 0
        while ($altJob.State -eq 'Running' -and $altElapsed -lt $altTimeout) {
            Start-Sleep -Seconds 2
            $altElapsed += 2
        }
        
        if ($altJob.State -eq 'Running') {
            Stop-Job -Job $altJob
            Remove-Job -Job $altJob
        }
        else {
            $altResult = Receive-Job -Job $altJob
            Remove-Job -Job $altJob
            Write-Host "  - Alternative installation output:" -ForegroundColor Gray
            $altResultString = $altResult | Out-String
            if ($altResultString.Trim()) {
                Write-Host $altResultString -ForegroundColor Yellow
            }
        }
        
        Start-Sleep -Seconds 5
        
        # Check again after alternative install
        $installedDistros2 = wsl -l -v 2>&1 | Out-String
        Write-Host "  - Installed distributions after alternative attempt:" -ForegroundColor Gray
        Write-Host $installedDistros2 -ForegroundColor Gray
        
        # Check if any Ubuntu version was installed
        if ($installedDistros2 -match "Ubuntu") {
            Write-Host "  ! Ubuntu was installed but with a different name" -ForegroundColor Yellow
            Write-Host "    Please check the distribution name and update the script" -ForegroundColor Yellow
            exit 1
        }
        
        # Final retry with original name
        Write-Host "  - Retrying with original method..." -ForegroundColor Yellow
        $retryJob = Start-Job -ScriptBlock {
            wsl --install -d Ubuntu-22.04 --no-launch 2>&1
        }
        
        $retryTimeout = 600
        $retryElapsed = 0
        while ($retryJob.State -eq 'Running' -and $retryElapsed -lt $retryTimeout) {
            Start-Sleep -Seconds 2
            $retryElapsed += 2
        }
        
        if ($retryJob.State -eq 'Running') {
            Stop-Job -Job $retryJob
            Remove-Job -Job $retryJob
        }
        else {
            $retryResult = Receive-Job -Job $retryJob
            Remove-Job -Job $retryJob
            Write-Host "  - Retry installation output:" -ForegroundColor Gray
            $retryResultString = $retryResult | Out-String
            if ($retryResultString.Trim()) {
                Write-Host $retryResultString -ForegroundColor Yellow
            }
        }
        
        Start-Sleep -Seconds 5
        
        # Final check - verify Ubuntu was installed
        if (Test-Ubuntu2204) {
            Write-Host "  ✓ Ubuntu 22.04 detected after installation attempts" -ForegroundColor Green
            Write-Host "  - Proceeding to cloud-init setup..." -ForegroundColor Gray
        }
        elseif (-not (Test-Ubuntu2204)) {
            Write-Host "  ! All installation attempts failed" -ForegroundColor Red
            Write-Host "    Please try manually: wsl --install -d Ubuntu-22.04" -ForegroundColor Yellow
            Write-Host "    Or check available distributions: wsl --list --online" -ForegroundColor Yellow
            exit 1
        }
    }
    }  # End of if (-not $skipToCloudInit) block
    
    # Ubuntu is installed (or already existed), now launch it to trigger cloud-init
    Write-Host "  - Launching Ubuntu to trigger cloud-init setup..." -ForegroundColor Gray
    Write-Host "    (This will automatically configure the user account)" -ForegroundColor Gray
    
    # Launch Ubuntu in background to trigger cloud-init
    # First, try to run a command as root to trigger cloud-init
    $launchJob = Start-Job -ScriptBlock {
        wsl -d Ubuntu-22.04 -u root -- bash -c "echo 'Cloud-init setup starting...'" 2>&1
    }
    
    # Wait for cloud-init to complete (can take 30-60 seconds)
    Write-Host "  - Waiting for cloud-init to complete (this may take up to 60 seconds)..." -ForegroundColor Gray
    $cloudInitTimeout = 90
    $cloudInitElapsed = 0
    $cloudInitComplete = $false
    
    while ($cloudInitElapsed -lt $cloudInitTimeout -and -not $cloudInitComplete) {
        Start-Sleep -Seconds 3
        $cloudInitElapsed += 3
        
        # Check if Ubuntu is functional (cloud-init has completed)
        if (Test-Ubuntu2204Functional) {
            $cloudInitComplete = $true
            break
        }
        
        # Try to check cloud-init status
        try {
            $cloudStatus = wsl -d Ubuntu-22.04 -u root -- cloud-init status 2>&1
            if ($cloudStatus -match "status: done" -or $cloudStatus -match "status: complete") {
                Start-Sleep -Seconds 2
                if (Test-Ubuntu2204Functional) {
                    $cloudInitComplete = $true
                    break
                }
            }
        }
        catch {
            # Continue waiting
        }
    }
    
    # Clean up launch job
    if ($launchJob.State -eq 'Running') {
        Stop-Job -Job $launchJob
        Remove-Job -Job $launchJob
    }
    else {
        Remove-Job -Job $launchJob
    }
    
    # Final verification
    Start-Sleep -Seconds 2
    if (Test-Ubuntu2204Functional) {
        Write-Host "  ✓ Ubuntu 22.04 is functional (cloud-init completed)" -ForegroundColor Green
        return
    }
    
    # If still not functional, try one more launch attempt
    Write-Host "  - Cloud-init may still be running, waiting a bit longer..." -ForegroundColor Yellow
    Start-Sleep -Seconds 10
    
    # Try to launch and verify
    try {
        $testLaunch = wsl -d Ubuntu-22.04 -u $Username -- whoami 2>&1
        if ($LASTEXITCODE -eq 0 -and $testLaunch -eq $Username) {
            Write-Host "  ✓ Ubuntu 22.04 is functional" -ForegroundColor Green
            return
        }
    }
    catch {
        # Continue to error handling
    }
    
    # Final check
    if (Test-Ubuntu2204Functional) {
        Write-Host "  ✓ Ubuntu 22.04 is functional" -ForegroundColor Green
        return
    }
    
    # If we get here, something went wrong
    Write-Host "  ! Ubuntu installation completed but cloud-init setup may have failed" -ForegroundColor Yellow
    Write-Host "    Ubuntu exists but is not fully functional" -ForegroundColor Yellow
    Write-Host "    Attempting automatic recovery..." -ForegroundColor Gray
    
    # Try to manually complete setup by running a command as root
    try {
        $chpasswdCmd = "${Username}:${Password}"
        $setupResult = wsl -d Ubuntu-22.04 -u root -- bash -c "useradd -m -s /bin/bash $Username 2>/dev/null || true; echo '$chpasswdCmd' | chpasswd 2>/dev/null || true; usermod -aG sudo $Username 2>/dev/null || true" 2>&1
        Start-Sleep -Seconds 2
        
        if (Test-Ubuntu2204Functional) {
            Write-Host "  ✓ Ubuntu 22.04 is now functional (manual setup completed)" -ForegroundColor Green
            return
        }
    }
    catch {
        # Continue to final error
    }
    
    Write-Host "  ! Failed to complete Ubuntu setup automatically" -ForegroundColor Red
    Write-Host "    Ubuntu 22.04 is installed but needs manual configuration" -ForegroundColor Yellow
    Write-Host "    Please run: wsl -d Ubuntu-22.04" -ForegroundColor Cyan
    Write-Host "    Then create a user manually and run this script again" -ForegroundColor Yellow
    exit 1
}

# Function to check if Quick Quarm is already installed in WSL
function Test-QuickQuarmInstalled {
    try {
        $result = wsl -d Ubuntu-22.04 -u root -- test -d /root/quick-quarm 2>&1
        return $LASTEXITCODE -eq 0
    }
    catch {
        return $false
    }
}

# Function to check if Quick Quarm service is installed
function Test-QuickQuarmService {
    try {
        $result = wsl -d Ubuntu-22.04 -u root -- systemctl list-unit-files quick-quarm.target 2>&1 | Out-String
        return $result -match "quick-quarm.target"
    }
    catch {
        return $false
    }
}

# Function to get the Windows host IP for WSL
function Get-HostIP {
    Write-Host "[STEP 3/7] Detecting network configuration..." -ForegroundColor Yellow
    
    # Get physical network adapters (exclude virtual adapters)
    $adapters = Get-NetAdapter | Where-Object { 
        $_.Status -eq 'Up' -and 
        $_.InterfaceDescription -notmatch 'Hyper-V|VirtualBox|VMware|WSL|Loopback|Teredo|isatap' 
    }
    
    $hostIP = $null
    
    # First pass: Find adapter with default route
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
                Write-Host "  ✓ Detected primary adapter IP: $hostIP" -ForegroundColor Green
                break
            }
        }
    }
    
    # Second pass: Find any private IP on physical adapter
    if (-not $hostIP) {
        foreach ($adapter in $adapters) {
            $ipConfig = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | 
                        Where-Object { 
                            $_.IPAddress -notmatch '^(127\.|169\.254\.)' -and
                            ($_.IPAddress -match '^192\.168\.|^10\.|^172\.(1[6-9]|2[0-9]|3[0-1])\.')
                        } | Select-Object -First 1
            
            if ($ipConfig) {
                $hostIP = $ipConfig.IPAddress
                Write-Host "  ✓ Detected adapter IP: $hostIP" -ForegroundColor Green
                break
            }
        }
    }
    
    # Fallback: Any non-loopback IP
    if (-not $hostIP) {
        $hostIP = (Get-NetIPAddress -AddressFamily IPv4 | 
                   Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' } | 
                   Select-Object -First 1).IPAddress
        
        if ($hostIP) {
            Write-Host "  ! Using detected IP: $hostIP (may be virtual adapter)" -ForegroundColor Yellow
        }
    }
    
    # Final fallback
    if (-not $hostIP) {
        $hostIP = "192.168.1.100"
        Write-Host "  ! Could not detect IP, using default: $hostIP" -ForegroundColor Yellow
        Write-Host "    You may need to manually update the login server configuration" -ForegroundColor Yellow
    }
    
    return $hostIP
}

# Function to execute installation directly in WSL (no file copying)
function Invoke-QuickQuarmInstall {
    param(
        [string]$HostIP,
        [string]$InstallUser,
        [string]$RepoUrl,
        [string]$DBHost,
        [string]$DBName,
        [string]$DBUser,
        [string]$DBPassword
    )
    
    Write-Host "[STEP 4/7] Preparing installation..." -ForegroundColor Yellow
    
    # Build answers file content (already working approach)
    $answersArray = @(
        $InstallUser
        $RepoUrl
        $DBHost
        $DBName
        $DBUser
        $DBPassword
        $HostIP
        "N"
    )
    
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $answersContent = ($answersArray -join "`n") + "`n"
    $answersFile = [System.IO.Path]::GetTempFileName() + ".txt"
    [System.IO.File]::WriteAllText($answersFile, $answersContent, $utf8NoBom)
    
    # Copy answers file to WSL - use persistent location instead of /tmp
    # /tmp gets cleared on WSL restart, so use quick-quarm's etc directory
    Write-Host "[STEP 5/7] Copying configuration to WSL..." -ForegroundColor Yellow
    wsl -d Ubuntu-22.04 -u root -- mkdir -p /root/quick-quarm/etc 2>&1 | Out-Null
    
    if ($answersFile -match '^([A-Z]):\\(.+)$') {
        $driveLetter = $matches[1].ToLower()
        $pathPart = $matches[2] -replace '\\', '/'
        $wslAnswersPath = "/mnt/$driveLetter/$pathPart"
        wsl -d Ubuntu-22.04 -u root -- cp "$wslAnswersPath" /root/quick-quarm/etc/qq_answers.txt 2>&1 | Out-Null
        Remove-Item $answersFile -Force -ErrorAction SilentlyContinue
    }
    
    # Escape variables for bash
    $safeHostIP = $HostIP -replace '\\', '\\' -replace '\$', '\$' -replace '`', '\`' -replace '"', '\"'
    $safeDBName = $DBName -replace '\\', '\\' -replace '\$', '\$' -replace '`', '\`' -replace '"', '\"'
    $safeDBUser = $DBUser -replace '\\', '\\' -replace '\$', '\$' -replace '`', '\`' -replace '"', '\"'
    
    Write-Host "[STEP 6/7] Running installation in WSL..." -ForegroundColor Yellow
    Write-Host "  (This will take 10-20 minutes - please be patient)" -ForegroundColor Gray
    Write-Host ""
    
    # Execute commands directly instead of using a script file
    # This avoids all multiline string and pipe issues
    
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host "Quick Quarm Setup in WSL2" -ForegroundColor Cyan
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Step 1: Check and install git
    wsl -d Ubuntu-22.04 -u root -- bash -c 'if ! command -v git &> /dev/null; then echo ''[1/6] Installing git...''; echo ''  (Updating package lists...)''; export DEBIAN_FRONTEND=noninteractive; apt-get update -qq; echo ''  (Installing git package...)''; apt-get install -y git 2>&1 | grep -vE ''^(Reading|Building|The following|Unpacking|Setting up)'' || true; echo ''  ✓ Git installed''; else echo ''[1/6] Git already installed ✓''; fi'
    
    # Step 2: Clone or update repository
    wsl -d Ubuntu-22.04 -u root -- bash -c 'if [ -d "/root/quick-quarm" ]; then echo ''[2/6] Quick Quarm repository already exists ✓''; echo ''  Checking for updates...''; cd /root/quick-quarm; git pull -q 2>&1 | head -5; else echo ''[2/6] Cloning Quick Quarm repository...''; echo ''  (This may take 1-2 minutes...)''; git clone -q --progress https://github.com/ryhoneyman/quick-quarm.git /root/quick-quarm 2>&1 | grep -E ''(Receiving|Resolving)'' || true; echo ''  ✓ Repository cloned''; fi'
    
    # Step 3: Check if already installed (check for COMPLETE installation, not just config file)
    # A complete installation has: .env file + services ENABLED + binaries exist
    Write-Host "[3/6] Checking installation status..." -ForegroundColor Yellow
    
    # Check if critical services are enabled (best indicator of completed setup)
    $servicesEnabled = wsl -d Ubuntu-22.04 -u root -- bash -c "systemctl is-enabled eqemu-world.service 2>&1"
    
    if ($servicesEnabled -match "enabled") {
        Write-Host "  ✓ Quick Quarm services are enabled (setup completed previously)" -ForegroundColor Green
        Write-Host "  - Verifying binaries exist..." -ForegroundColor Gray
        
        $binariesExist = wsl -d Ubuntu-22.04 -u root -- bash -c "test -f /root/quick-quarm/bin/world && echo yes || echo no"
        
        if ($binariesExist -match "yes") {
            Write-Host "  ✓ Installation complete - skipping setup" -ForegroundColor Green
            $runSetup = $false
        } else {
            Write-Host "  ! Binaries missing - will run setup" -ForegroundColor Yellow
            $runSetup = $true
        }
    } else {
        Write-Host "  ! Quick Quarm services not enabled (setup incomplete or never ran)" -ForegroundColor Yellow
        Write-Host "  - Will run full setup process" -ForegroundColor Gray
        $runSetup = $true
    }
    
    if ($runSetup) {
        # Step 4: Update system packages and ensure required tools are installed
        Write-Host "[4/6] Updating system packages..." -ForegroundColor Yellow
        Write-Host "  (This may take 3-5 minutes depending on your connection...)" -ForegroundColor Gray
        Write-Host "  - Updating package lists..." -ForegroundColor Gray
        wsl -d Ubuntu-22.04 -u root -- bash -c 'export DEBIAN_FRONTEND=noninteractive; apt-get update -qq 2>&1 | tail -n 1'
        Write-Host "  - Upgrading packages (please be patient)..." -ForegroundColor Gray
        wsl -d Ubuntu-22.04 -u root -- bash -c 'export DEBIAN_FRONTEND=noninteractive; apt-get upgrade -y 2>&1 | grep -E ''(upgraded|installed|removed|not upgraded)'' | head -1 || echo ''  Packages up to date'''
        Write-Host "  - Ensuring gettext (envsubst) is installed..." -ForegroundColor Gray
        wsl -d Ubuntu-22.04 -u root -- bash -c 'export DEBIAN_FRONTEND=noninteractive; apt-get install -y gettext 2>&1 | grep -E ''(already|installed|Setting up)'' | head -1 || echo ''  ✓ gettext ready'''
        Write-Host "  ✓ System packages updated" -ForegroundColor Green
        
        # Step 5: Ensure systemd is enabled in WSL (Ubuntu 22.04+)
        Write-Host "[5/6] Verifying systemd configuration..." -ForegroundColor Yellow
        Write-Host "  - Checking systemd status..." -ForegroundColor Gray
        $systemdCheck = wsl -d Ubuntu-22.04 -u root -- bash -c 'if systemctl is-system-running &> /dev/null; then echo "enabled"; else echo "disabled"; fi' 2>&1
        $needsWslRestart = $false

        if ($systemdCheck -match "disabled" -or $systemdCheck -match "error") {
            Write-Host "  ! Systemd is not running properly" -ForegroundColor Yellow
            Write-Host "  - Configuring systemd in /etc/wsl.conf..." -ForegroundColor Gray
            
            # Always write the config (don't just check if file exists)
            # Use a here-document to avoid any quoting/escaping issues
            wsl -d Ubuntu-22.04 -u root -- bash -c 'mkdir -p /etc && cat > /etc/wsl.conf << "EOF"
[boot]
systemd=true
EOF' 2>&1 | Out-Null
            $needsWslRestart = $true
        } else {
            # Double-check that wsl.conf has systemd enabled
            $wslConfCheck = wsl -d Ubuntu-22.04 -u root -- bash -c 'grep -q "systemd=true" /etc/wsl.conf 2>/dev/null && echo "yes" || echo "no"' 2>&1
            if ($wslConfCheck -match "no") {
                Write-Host "  ! Systemd config missing from /etc/wsl.conf" -ForegroundColor Yellow
                Write-Host "  - Adding systemd configuration..." -ForegroundColor Gray
                # Use a here-document to avoid any quoting/escaping issues
                wsl -d Ubuntu-22.04 -u root -- bash -c 'mkdir -p /etc && cat > /etc/wsl.conf << "EOF"
[boot]
systemd=true
EOF' 2>&1 | Out-Null
                $needsWslRestart = $true
            } else {
                Write-Host "  ✓ Systemd is properly configured" -ForegroundColor Green
            }
        }

        # If we modified wsl.conf, we MUST restart WSL for it to take effect
        if ($needsWslRestart) {
            Write-Host "  ! WSL restart required for systemd changes" -ForegroundColor Yellow
            Write-Host "  - Shutting down WSL..." -ForegroundColor Gray
            wsl --shutdown
            Write-Host "  - Waiting for WSL to fully terminate (8 seconds)..." -ForegroundColor Gray
            Start-Sleep -Seconds 8
            Write-Host "  - Restarting WSL with systemd enabled..." -ForegroundColor Gray
            
            # Start WSL again and verify systemd is now working
            $systemdVerify = wsl -d Ubuntu-22.04 -u root -- systemctl is-system-running 2>&1
            if ($systemdVerify -match "running" -or $systemdVerify -match "degraded") {
                Write-Host "  ✓ Systemd is now running" -ForegroundColor Green
            } else {
                Write-Host "  ! Warning: Systemd may not have started properly" -ForegroundColor Yellow
                Write-Host "    Status: $systemdVerify" -ForegroundColor Gray
                Write-Host "    Continuing anyway - you may need to restart WSL manually" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  ✓ Systemd is enabled" -ForegroundColor Green
        }
        
        # Step 6: Configuration (answers file already copied)
        Write-Host "  ✓ Configuration ready" -ForegroundColor Green
        
        # Step 6.5: Ensure MariaDB is running (CRITICAL for setup to succeed)
        Write-Host "  - Ensuring MariaDB is running before setup..." -ForegroundColor Gray
        $mariadbPreCheck = wsl -d Ubuntu-22.04 -u root -- systemctl is-active mariadb.service 2>&1
        if ($mariadbPreCheck -notmatch "active") {
            Write-Host "    MariaDB not running - starting it now..." -ForegroundColor Yellow
            wsl -d Ubuntu-22.04 -u root -- systemctl start mariadb.service 2>&1 | Out-Null
            Start-Sleep -Seconds 3
            $mariadbPreCheck = wsl -d Ubuntu-22.04 -u root -- systemctl is-active mariadb.service 2>&1
            if ($mariadbPreCheck -match "active") {
                Write-Host "  ✓ MariaDB is now running" -ForegroundColor Green
            } else {
                Write-Host "  ! Failed to start MariaDB - setup will likely fail" -ForegroundColor Red
                Write-Host "    Trying to continue anyway..." -ForegroundColor Yellow
            }
        } else {
            Write-Host "  ✓ MariaDB is already running" -ForegroundColor Green
        }
        
        # Step 7: Run setup
        Write-Host "[6/6] Running Quick Quarm setup..." -ForegroundColor Yellow
        Write-Host "  ======================================" -ForegroundColor Gray
        Write-Host "  This is the longest step (10-20 minutes)" -ForegroundColor Gray
        Write-Host "  Progress will be shown below:" -ForegroundColor Gray
        Write-Host "  ======================================" -ForegroundColor Gray
        Write-Host ""
        
        # Run setup and capture output AND exit code (use persistent location for answers)
        $setupOutput = wsl -d Ubuntu-22.04 -u root -- bash -c 'cd /root/quick-quarm; cat /root/quick-quarm/etc/qq_answers.txt | ./scripts/setup 2>&1; echo "EXIT_CODE:$?"'
        
        # Show important lines and errors (don't hide problems)
        $exitCode = "0"
        $setupOutput | ForEach-Object {
            if ($_ -match '\[(INSTALL|SOURCE|DATABASE|BUILD|CONFIG|SYSTEMD)\]|===== DONE|Starting build|Generating make|threads|Installing Quick Quarm service|Enabling Quick Quarm service') {
                Write-Host $_ -ForegroundColor Cyan
            } elseif ($_ -match '(ERROR|Error|error|FAIL|Failed|failed|E:.*apt|Could not|Cannot|Unable to)') {
                Write-Host $_ -ForegroundColor Red
            } elseif ($_ -match 'EXIT_CODE:') {
                # Extract exit code and trim whitespace
                $exitCode = ($_ -replace 'EXIT_CODE:', '').Trim()
            }
        }
        
        # Check if setup failed
        if ($exitCode -and $exitCode -ne "0") {
            Write-Host ""
            Write-Host "  ! Setup script failed with exit code: $exitCode" -ForegroundColor Red
            Write-Host "    Last 20 lines of output:" -ForegroundColor Yellow
            $setupOutput | Select-Object -Last 21 | Select-Object -SkipLast 1 | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
            
            Write-Host ""
            Write-Host "    Checking for missing dependencies..." -ForegroundColor Yellow
            
            # Check specifically for MariaDB
            $mariadbCheck = wsl -d Ubuntu-22.04 -u root -- bash -c 'dpkg -l | grep mariadb-server | wc -l' 2>&1
            if ($mariadbCheck -eq "0") {
                Write-Host "    ! MariaDB not installed - attempting to install now..." -ForegroundColor Yellow
                $mariadbInstall = wsl -d Ubuntu-22.04 -u root -- bash -c 'export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y mariadb-server mariadb-client 2>&1'
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "    ✓ MariaDB installed successfully" -ForegroundColor Green
                    wsl -d Ubuntu-22.04 -u root -- bash -c 'systemctl start mariadb.service && systemctl enable mariadb.service 2>&1' | Out-Null
                } else {
                    Write-Host "    ! MariaDB installation failed" -ForegroundColor Red
                    $mariadbInstall | Select-Object -Last 10 | ForEach-Object { Write-Host "      $_" -ForegroundColor Yellow }
                    Write-Host ""
                    Write-Host "  Setup failed - please check the errors above and try again" -ForegroundColor Red
                    exit 1
                }
            }
        }
        
        # Check if setup completed successfully
        $setupComplete = $setupOutput | Select-String -Pattern '===== DONE' -Quiet
        
        if (-not $setupComplete) {
            Write-Host ""
            Write-Host "  ! Setup did not complete successfully" -ForegroundColor Red
            Write-Host "    Last 20 lines of output:" -ForegroundColor Yellow
            $setupOutput | Select-Object -Last 21 | Select-Object -SkipLast 1 | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
            Write-Host ""
            Write-Host "  Please review the errors above and try running the installer again" -ForegroundColor Yellow
            exit 1
        }
        
        # MANDATORY: Verify MariaDB installation and status
        Write-Host ""
        Write-Host "  - Verifying MariaDB installation..." -ForegroundColor Gray
        $mariadbInstalled = wsl -d Ubuntu-22.04 -u root -- bash -c 'dpkg -l | grep mariadb-server | wc -l' 2>&1
        if ($mariadbInstalled -eq "0") {
            Write-Host "  ! MariaDB was not installed by setup - installing now..." -ForegroundColor Yellow
            $mariadbInstallResult = wsl -d Ubuntu-22.04 -u root -- bash -c 'export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y mariadb-server mariadb-client 2>&1'
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  ✓ MariaDB installed successfully" -ForegroundColor Green
            } else {
                Write-Host "  ! MariaDB installation failed" -ForegroundColor Red
                $mariadbInstallResult | Select-Object -Last 10 | ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow }
                Write-Host ""
                Write-Host "  Installation cannot continue without MariaDB" -ForegroundColor Red
                exit 1
            }
        } else {
            Write-Host "  ✓ MariaDB is installed" -ForegroundColor Green
        }
        
        # Start MariaDB service
        Write-Host "  - Starting MariaDB service..." -ForegroundColor Gray
        $mariadbStatus = wsl -d Ubuntu-22.04 -u root -- bash -c 'systemctl is-active mariadb.service 2>&1'
        if ($mariadbStatus -notmatch "active") {
            $startResult = wsl -d Ubuntu-22.04 -u root -- bash -c 'systemctl start mariadb.service 2>&1'
            if ($LASTEXITCODE -ne 0) {
                Write-Host "  ! Failed to start MariaDB" -ForegroundColor Red
                Write-Host "    Error details:" -ForegroundColor Yellow
                Write-Host $startResult -ForegroundColor Gray
                Write-Host "    Checking logs..." -ForegroundColor Yellow
                wsl -d Ubuntu-22.04 -u root -- bash -c 'journalctl -u mariadb.service -n 20' 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
                Write-Host ""
                Write-Host "  Installation cannot continue - MariaDB failed to start" -ForegroundColor Red
                exit 1
            }
            Start-Sleep -Seconds 3
        }
        
        # Enable MariaDB to start on boot
        $mariadbEnabled = wsl -d Ubuntu-22.04 -u root -- bash -c 'systemctl is-enabled mariadb.service 2>&1'
        if ($mariadbEnabled -notmatch "enabled") {
            Write-Host "  - Enabling MariaDB to start on boot..." -ForegroundColor Gray
            wsl -d Ubuntu-22.04 -u root -- bash -c 'systemctl enable mariadb.service 2>&1' | Out-Null
        }
        
        # Final verification - MariaDB MUST be running
        $mariadbFinalStatus = wsl -d Ubuntu-22.04 -u root -- bash -c 'systemctl is-active mariadb.service 2>&1'
        if ($mariadbFinalStatus -match "active") {
            Write-Host "  ✓ MariaDB is running and enabled" -ForegroundColor Green
        } else {
            Write-Host "  ! MariaDB is not running" -ForegroundColor Red
            Write-Host "    Status: $mariadbFinalStatus" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  Installation cannot continue - MariaDB must be running" -ForegroundColor Red
            Write-Host "  Please check system logs: journalctl -u mariadb.service" -ForegroundColor Yellow
            exit 1
        }
        
        # Verify install-systemd ran successfully
        Write-Host ""
        Write-Host "  - Verifying systemd installation..." -ForegroundColor Gray
        $systemdInstalled = wsl -d Ubuntu-22.04 -u root -- bash -c 'if systemctl list-unit-files quick-quarm.target &> /dev/null; then echo "yes"; else echo "no"; fi' 2>&1
        if ($systemdInstalled -match "yes") {
            Write-Host "  ✓ Quick Quarm systemd service installed successfully" -ForegroundColor Green
            
            # Test if services can start (check dependencies)
            Write-Host "  - Checking service dependencies..." -ForegroundColor Gray
            $depCheck = wsl -d Ubuntu-22.04 -u root -- bash -c 'systemctl start quick-quarm.target 2>&1'
            if ($LASTEXITCODE -ne 0) {
                Write-Host "  ! Service dependency issue detected" -ForegroundColor Yellow
                Write-Host "    Error: $depCheck" -ForegroundColor Gray
                Write-Host "    Note: This may be normal if dependencies aren't fully configured yet" -ForegroundColor Gray
            } else {
                Write-Host "  ✓ Service dependencies satisfied" -ForegroundColor Green
                # Stop the service since we just started it for testing
                wsl -d Ubuntu-22.04 -u root -- bash -c 'systemctl stop quick-quarm.target 2>&1' | Out-Null
            }
        } else {
            Write-Host "  ! Systemd service installation may have failed" -ForegroundColor Yellow
            Write-Host "  - Attempting to run install-systemd directly..." -ForegroundColor Gray
            $systemdOutput = wsl -d Ubuntu-22.04 -u root -- bash -c 'cd /root/quick-quarm; . ./scripts/install-systemd 2>&1'
            $systemdOutput | Select-String -Pattern 'SYSTEMD|Installing|Enabling|error|Error|failed|Failed' | ForEach-Object { Write-Host "    $($_.Line)" -ForegroundColor Yellow }
            
            # Check again
            $systemdInstalled2 = wsl -d Ubuntu-22.04 -u root -- bash -c 'if systemctl list-unit-files quick-quarm.target &> /dev/null; then echo "yes"; else echo "no"; fi' 2>&1
            if ($systemdInstalled2 -match "yes") {
                Write-Host "  ✓ Quick Quarm systemd service installed successfully" -ForegroundColor Green
            } else {
                Write-Host "  ! Systemd service installation failed" -ForegroundColor Red
                Write-Host "    You may need to run manually: cd /root/quick-quarm && ./scripts/install-systemd" -ForegroundColor Yellow
            }
        }
        
        wsl -d Ubuntu-22.04 -u root -- bash -c 'rm -f /root/quick-quarm/etc/qq_answers.txt'
        Write-Host ""
        Write-Host "  ✓ Quick Quarm setup complete!" -ForegroundColor Green
        } else {
        Write-Host "[4/6] Skipped - using existing installation" -ForegroundColor Gray
        Write-Host "[5/6] Skipped - using existing installation" -ForegroundColor Gray
        Write-Host "[6/6] Skipped - using existing installation" -ForegroundColor Gray
    }
    
    # Final output
    Write-Host ""
    Write-Host "=========================================" -ForegroundColor Green
    Write-Host "Installation Complete!" -ForegroundColor Green
    Write-Host "=========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Quick Quarm server details:" -ForegroundColor Cyan
    $serverAddr = "$safeHostIP" + ":6000"
    Write-Host "  Server IP: $serverAddr" -ForegroundColor White
    Write-Host "  Database: $safeDBName" -ForegroundColor White
    Write-Host "  DB User: $safeDBUser" -ForegroundColor White
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "1. Download TAKP v2.2 Client from PQ Discord #server-files" -ForegroundColor White
    Write-Host "2. Edit eqhost.txt and change server to: $serverAddr" -ForegroundColor White
    Write-Host "3. Run the client and login with any username/password" -ForegroundColor White
    Write-Host "4. Select your Quick Quarm server and create a character" -ForegroundColor White
    Write-Host "5. To grant GM powers: cd ~/quick-quarm && ./scripts/eq/makegm -l LOGINACCOUNT" -ForegroundColor White
    Write-Host ""
    Write-Host "Server management commands:" -ForegroundColor Cyan
    Write-Host "  Start:   sudo systemctl start quick-quarm.target" -ForegroundColor White
    Write-Host "  Stop:    sudo systemctl stop quick-quarm.target" -ForegroundColor White
    Write-Host "  Restart: sudo systemctl restart quick-quarm.target" -ForegroundColor White
    Write-Host "  Status:  sudo systemctl status quick-quarm.target" -ForegroundColor White
    Write-Host ""
    Write-Host "To update Quick Quarm in the future:" -ForegroundColor Cyan
    Write-Host "  cd ~/quick-quarm && ./scripts/update" -ForegroundColor White
    Write-Host ""
}

# Main installation process
try {
    # Check if running as administrator
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "ERROR: This script must be run as Administrator" -ForegroundColor Red
        Write-Host "Right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
        exit 1
    }
    
    # Check and install WSL2
    if (-not (Test-WSL2)) {
        Write-Host "  WSL2 is not installed or not properly configured" -ForegroundColor Yellow
        Install-WSL2
        # If we get here and still need restart, exit was already handled in Install-WSL2
    }
    else {
        Write-Host "[STEP 1/7] WSL2 already installed ✓" -ForegroundColor Green
    }
    
    # Install Ubuntu with automated cloud-init setup
    Install-Ubuntu -Username $InstallUser -Password $InstallPassword
    
    # Get host IP
    $hostIP = Get-HostIP
    
    # Check if Quick Quarm is already installed
    if (Test-QuickQuarmService) {
        Write-Host ""
        Write-Host "  ! Quick Quarm appears to be already installed" -ForegroundColor Yellow
        Write-Host "  - Continuing with installation anyway..." -ForegroundColor Gray
    }
    
    # Execute installation directly in WSL (no script file needed)
    Invoke-QuickQuarmInstall -HostIP $hostIP -InstallUser $InstallUser -RepoUrl $RepoUrl -DBHost $DBHost -DBName $DBName -DBUser $DBUser -DBPassword $DBPassword
    
    # POST-INSTALLATION VERIFICATION
    Write-Host ""
    Write-Host "[STEP 7/7] Verifying installation..." -ForegroundColor Yellow
    Write-Host "  - Ensuring WSL systemd is properly configured..." -ForegroundColor Gray
    wsl --shutdown
    Start-Sleep -Seconds 8
    $systemdStatus = wsl -d Ubuntu-22.04 -u root -- systemctl is-system-running 2>&1
    if ($systemdStatus -notmatch "running" -and $systemdStatus -notmatch "degraded") {
        Write-Host "  ! Warning: Systemd may not be working properly" -ForegroundColor Yellow
    }

    Write-Host "  - Verifying MariaDB service..." -ForegroundColor Gray
    $mariadbActive = wsl -d Ubuntu-22.04 -u root -- systemctl is-active mariadb.service 2>&1
    if ($mariadbActive -notmatch "active") {
        Write-Host "  ! MariaDB not running, attempting to start..." -ForegroundColor Yellow
        wsl -d Ubuntu-22.04 -u root -- systemctl start mariadb.service 2>&1 | Out-Null
        Start-Sleep -Seconds 3
        $mariadbActive = wsl -d Ubuntu-22.04 -u root -- systemctl is-active mariadb.service 2>&1
    }

    if ($mariadbActive -match "active") {
        Write-Host "  ✓ MariaDB is running" -ForegroundColor Green
    } else {
        Write-Host "  ! CRITICAL: MariaDB is not running" -ForegroundColor Red
        Write-Host "    Status: $mariadbActive" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Please run this command to diagnose:" -ForegroundColor Yellow
        Write-Host "    wsl -d Ubuntu-22.04 -u root -- journalctl -u mariadb.service -n 50" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  After fixing MariaDB, restart the server with:" -ForegroundColor Yellow
        Write-Host "    wsl -d Ubuntu-22.04 -u root -- systemctl start quick-quarm.target" -ForegroundColor Gray
        Write-Host ""
        exit 1
    }

    Write-Host "  ✓ Verification complete" -ForegroundColor Green
    
    # Start the server automatically (following Quick Quarm best practices)
    Write-Host ""
    Write-Host "  - Starting Quick Quarm server..." -ForegroundColor Gray
    $serverStart = wsl -d Ubuntu-22.04 -u root -- systemctl start quick-quarm.target 2>&1
    if ($LASTEXITCODE -eq 0) {
        Start-Sleep -Seconds 3
        $serverStatus = wsl -d Ubuntu-22.04 -u root -- systemctl is-active quick-quarm.target 2>&1
        if ($serverStatus -match "active") {
            Write-Host "  ✓ Quick Quarm server is now running" -ForegroundColor Green
        } else {
            Write-Host "  ! Server may be starting (check status in a moment)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  ! Failed to start server automatically" -ForegroundColor Yellow
        Write-Host "    You can start it manually: wsl -d Ubuntu-22.04 sudo systemctl start quick-quarm.target" -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "Installation Complete!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Your Quick Quarm server is now running in WSL2!" -ForegroundColor Cyan
    $serverAddress = "$hostIP" + ":6000"
    Write-Host "Server IP: $serverAddress" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor White
    Write-Host "  1. Download TAKP v2.2 Client from PQ Discord #server-files" -ForegroundColor Gray
    Write-Host "  2. Edit eqhost.txt and change server to: $serverAddress" -ForegroundColor Gray
    Write-Host "  3. Run the client and login with any username/password" -ForegroundColor Gray
    Write-Host "  4. Select your Quick Quarm server and create a character" -ForegroundColor Gray
    Write-Host "  5. To grant GM powers: wsl -d Ubuntu-22.04" -ForegroundColor Gray
    Write-Host "     Then: cd ~/quick-quarm && ./scripts/eq/makegm -l LOGINACCOUNT" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Server management commands:" -ForegroundColor White
    Write-Host "  Check Status: wsl -d Ubuntu-22.04 sudo systemctl status quick-quarm.target" -ForegroundColor Gray
    Write-Host "  Stop Server:  wsl -d Ubuntu-22.04 sudo systemctl stop quick-quarm.target" -ForegroundColor Gray
    Write-Host "  Restart:      wsl -d Ubuntu-22.04 sudo systemctl restart quick-quarm.target" -ForegroundColor Gray
    Write-Host ""
}
catch {
    Write-Host ""
    Write-Host "ERROR: Installation failed" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "If you need help, please provide this error message." -ForegroundColor Yellow
    exit 1
}