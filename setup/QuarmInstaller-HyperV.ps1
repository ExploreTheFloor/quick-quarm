# Quick Quarm Installation Script for Windows (Hyper-V VM)
# This script creates a Hyper-V VM with Ubuntu 22.04 and installs Quick Quarm

#Requires -RunAsAdministrator

param(
    [string]$VMName = "QuickQuarm",
    [string]$VMMemory = 4GB,
    [int]$VMProcessors = 2,
    [string]$VMDiskSize = 60GB,
    [string]$InstallUser = "root",
    [string]$InstallPassword = "root",
    [string]$RepoUrl = "https://github.com/SecretsOTheP/EQMacEmu.git",
    [string]$DBHost = "localhost",
    [string]$DBName = "quarm",
    [string]$DBUser = "quarm",
    [string]$DBPassword = "quarm"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Quick Quarm VM Installation for Windows" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Function to check if Hyper-V is enabled
function Test-HyperV {
    $hyperv = Get-WindowsOptionalFeature -FeatureName Microsoft-Hyper-V-All -Online -ErrorAction SilentlyContinue
    return ($null -ne $hyperv -and $hyperv.State -eq "Enabled")
}

# Function to enable Hyper-V
function Enable-HyperV {
    Write-Host '[STEP 1/8] Enabling Hyper-V...' -ForegroundColor Yellow
    
    $hyperv = Get-WindowsOptionalFeature -FeatureName Microsoft-Hyper-V-All -Online -ErrorAction SilentlyContinue
    
    if ($hyperv.State -ne "Enabled") {
        Write-Host "  - Enabling Hyper-V features..." -ForegroundColor Gray
        Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -NoRestart
        
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Yellow
        Write-Host "RESTART REQUIRED" -ForegroundColor Yellow
        Write-Host "========================================" -ForegroundColor Yellow
        Write-Host "Hyper-V has been enabled but requires a restart." -ForegroundColor Yellow
        Write-Host "After restarting, run this script again to continue." -ForegroundColor Yellow
        Write-Host ""
        $response = Read-Host "Would you like to restart now? (Y/n)"
        if ($response -eq '' -or $response -eq 'y' -or $response -eq 'Y') {
            Restart-Computer -Force
        }
        exit 0
    }
    else {
        Write-Host "  + Hyper-V already enabled" -ForegroundColor Green
    }
}

# Function to install Chocolatey
function Install-Chocolatey {
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Host "  - Installing Chocolatey package manager..." -ForegroundColor Gray
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        
        # Reload PATH
        $machinePath = [System.Environment]::GetEnvironmentVariable("Path","Machine")
        $userPath = [System.Environment]::GetEnvironmentVariable("Path","User")
        $env:Path = "$machinePath;$userPath"
        Write-Host "  - Chocolatey installed" -ForegroundColor Green
    }
    else {
        Write-Host "  - Chocolatey already installed" -ForegroundColor Green
    }
}

# Function to install required tools
function Install-RequiredTools {
    Write-Host '[STEP 2/8] Installing required tools...' -ForegroundColor Yellow
    
    Install-Chocolatey
    
    # Install qemu-img for disk image conversion
    if (-not (Get-Command qemu-img -ErrorAction SilentlyContinue)) {
        Write-Host "  - Installing qemu-img..." -ForegroundColor Gray
        choco install qemu-img -y --no-progress
        $machinePath = [System.Environment]::GetEnvironmentVariable("Path","Machine")
        $userPath = [System.Environment]::GetEnvironmentVariable("Path","User")
        $env:Path = "$machinePath;$userPath"
        Write-Host "  + qemu-img installed" -ForegroundColor Green
    }
    else {
        Write-Host "  + qemu-img already installed" -ForegroundColor Green
    }
    
    # Install git
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Host "  - Installing git..." -ForegroundColor Gray
        choco install git -y --no-progress
        $machinePath = [System.Environment]::GetEnvironmentVariable("Path","Machine")
        $userPath = [System.Environment]::GetEnvironmentVariable("Path","User")
        $env:Path = "$machinePath;$userPath"
        Write-Host "  + git installed" -ForegroundColor Green
    }
    else {
        Write-Host "  + git already installed" -ForegroundColor Green
    }
}

# Function to generate SSH key pair
function New-SSHKeyPair {
    param([string]$KeyPath)
    
    Write-Host '[STEP 3/8] Setting up SSH authentication...' -ForegroundColor Yellow
    
    if (Test-Path $KeyPath) {
        Write-Host "  + SSH key already exists" -ForegroundColor Green
        return
    }
    
    Write-Host "  - Generating SSH key pair..." -ForegroundColor Gray
    $keyDir = Split-Path $KeyPath -Parent
    if (-not (Test-Path $keyDir)) {
        New-Item -ItemType Directory -Path $keyDir -Force | Out-Null
    }
    
    ssh-keygen -t rsa -b 4096 -f $KeyPath -N '""' -C "quickquarm@hyperv"
    Write-Host "  + SSH key pair generated" -ForegroundColor Green
}

# Function to download Ubuntu cloud image
function Get-UbuntuImage {
    param([string]$ImagePath)
    
    Write-Host '[STEP 4/8] Downloading Ubuntu 22.04 cloud image...' -ForegroundColor Yellow
    
    if (Test-Path $ImagePath) {
        Write-Host "  + Ubuntu image already downloaded" -ForegroundColor Green
        return
    }
    
    $imageDir = Split-Path $ImagePath -Parent
    if (-not (Test-Path $imageDir)) {
        New-Item -ItemType Directory -Path $imageDir -Force | Out-Null
    }
    
    $ubuntuUrl = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
    Write-Host "  - Downloading from Ubuntu (~700MB, this may take 5-10 minutes)..." -ForegroundColor Gray
    Write-Host "    Source: $ubuntuUrl" -ForegroundColor Gray
    
    try {
        # Try using BITS transfer first (shows progress)
        try {
            Import-Module BitsTransfer -ErrorAction Stop
            Start-BitsTransfer -Source $ubuntuUrl -Destination $ImagePath -DisplayName "Ubuntu Cloud Image" -Description "Downloading Ubuntu 22.04 Server Cloud Image"
            Write-Host "  + Ubuntu image downloaded" -ForegroundColor Green
        }
        catch {
            # Fall back to Invoke-WebRequest with progress
            Write-Host "    BITS transfer not available, using alternative method..." -ForegroundColor Gray
            $ProgressPreference = 'SilentlyContinue'  # Speeds up download significantly
            Invoke-WebRequest -Uri $ubuntuUrl -OutFile $ImagePath -UseBasicParsing -TimeoutSec 600
            $ProgressPreference = 'Continue'
            Write-Host "  + Ubuntu image downloaded" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "  ! Failed to download Ubuntu image" -ForegroundColor Red
        Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "    " -ForegroundColor Yellow
        Write-Host "    You can manually download the image from:" -ForegroundColor Yellow
        Write-Host "    $ubuntuUrl" -ForegroundColor Cyan
        Write-Host "    And save it as: $ImagePath" -ForegroundColor Cyan
        exit 1
    }
}

# Function to convert qcow2 to vhdx
function Convert-ImageToVHDX {
    param(
        [string]$SourceImage,
        [string]$DestVHDX
    )
    
    Write-Host '[STEP 5/8] Converting image to VHDX format...' -ForegroundColor Yellow
    
    if (Test-Path $DestVHDX) {
        Write-Host "  + VHDX already exists" -ForegroundColor Green
        return
    }
    
    Write-Host "  - Converting qcow2 to vhdx using qemu-img..." -ForegroundColor Gray
    
    # Use Start-Process to properly handle qemu-img execution
    $qemuArgs = @(
        "convert",
        "-f", "qcow2",
        "-O", "vhdx",
        "-o", "subformat=dynamic",
        $SourceImage,
        $DestVHDX
    )
    
    $processInfo = Start-Process -FilePath "qemu-img" -ArgumentList $qemuArgs -Wait -PassThru -NoNewWindow
    
    if ($processInfo.ExitCode -ne 0) {
        Write-Host "  ! qemu-img conversion failed with exit code $($processInfo.ExitCode)" -ForegroundColor Red
        exit 1
    }
    
    if (-not (Test-Path $DestVHDX)) {
        Write-Host "  ! Conversion failed - VHDX file not created" -ForegroundColor Red
        exit 1
    }
    
    # Remove sparse attribute to make it Hyper-V compatible
    Write-Host "  - Removing sparse attribute for Hyper-V compatibility..." -ForegroundColor Gray
    try {
        # Use fsutil to remove the sparse attribute
        $fsutilResult = & fsutil sparse setflag "$DestVHDX" 0 2>&1
        
        # Check if file has compression/encryption attributes and remove them
        $fileAttribs = Get-Item "$DestVHDX" -Force
        if ($fileAttribs.Attributes -band [System.IO.FileAttributes]::Compressed) {
            Write-Host "    Removing compression attribute..." -ForegroundColor Gray
            & compact /U "$DestVHDX" | Out-Null
        }
        if ($fileAttribs.Attributes -band [System.IO.FileAttributes]::Encrypted) {
            Write-Host "    Removing encryption attribute..." -ForegroundColor Gray
            & cipher /D "$DestVHDX" | Out-Null
        }
        
        # Resize VHDX to 20GB for Quick Quarm installation (2.2GB is too small)
        Write-Host "  - Resizing VHDX to 20GB for Quick Quarm..." -ForegroundColor Gray
        try {
            Resize-VHD -Path "$DestVHDX" -SizeBytes 20GB -ErrorAction Stop
            Write-Host "  + VHDX resized to 20GB" -ForegroundColor Green
        }
        catch {
            Write-Host "  ! Warning: Failed to resize VHDX: $($_.Exception.Message)" -ForegroundColor Yellow
        }
        
        Write-Host "  + Image converted successfully" -ForegroundColor Green
    }
    catch {
        Write-Host "  ! Warning: Could not optimize VHDX" -ForegroundColor Yellow
        Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor Gray
        Write-Host "    Continuing anyway..." -ForegroundColor Gray
    }
}

# Function to create cloud-init ISO
function New-CloudInitISO {
    param(
        [string]$ISOPath,
        [string]$PublicKeyPath,
        [string]$Username,
        [string]$Password
    )
    
    Write-Host '[STEP 6/8] Creating cloud-init configuration...' -ForegroundColor Yellow
    
    $isoDir = Split-Path $ISOPath -Parent
    $tempDir = Join-Path $isoDir "cloud-init-temp"
    
    if (-not (Test-Path $tempDir)) {
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    }
    
    # Read SSH public key
    $publicKey = Get-Content $PublicKeyPath -Raw
    $publicKey = $publicKey.Trim()
    
    # Create meta-data file
    $metaData = @"
instance-id: quickquarm-001
local-hostname: quickquarm
"@
    
    # Create user-data file with SSH key injection
    $userData = @'
#cloud-config
# Automatically grow root partition to fill disk
growpart:
  mode: auto
  devices: ['/']
  ignore_growroot_disabled: false
users:
  - name: {USERNAME}
    gecos: Quick Quarm User
    groups: [adm, audio, cdrom, dialout, dip, floppy, netdev, plugdev, sudo, video]
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    ssh_authorized_keys:
      - {PUBLICKEY}
chpasswd:
  list: |
    {USERNAME}:{PASSWORD}
  expire: false
ssh_pwauth: true
package_update: true
package_upgrade: false
packages:
  - openssh-server
  - linux-cloud-tools-generic
  - linux-tools-generic
  - linux-generic
bootcmd:
  - modprobe hv_balloon
  - modprobe hv_utils
  - modprobe hv_vmbus
  - modprobe hv_sock
  - modprobe hv_storvsc
  - modprobe hv_netvsc
  - sh -c 'echo "hv_balloon\nhv_utils\nhv_vmbus\nhv_sock\nhv_storvsc\nhv_netvsc" >>/etc/initramfs-tools/modules' && update-initramfs -k all -u
runcmd:
  - systemctl enable ssh
  - systemctl start ssh
'@
    
    # Replace placeholders with actual values
    $userData = $userData -replace '\{USERNAME\}', $Username
    $userData = $userData -replace '\{PASSWORD\}', $Password
    $userData = $userData -replace '\{PUBLICKEY\}', $publicKey
    
    $metaData | Out-File -FilePath (Join-Path $tempDir "meta-data") -Encoding ASCII -NoNewline
    $userData | Out-File -FilePath (Join-Path $tempDir "user-data") -Encoding ASCII -NoNewline
    
    # Create network-config file with DHCP for all interfaces
    # This works with External switches (physical network DHCP)
    # For Default Switch/Internal switches, DHCP may not work but VM will still boot
    $networkConfig = @"
version: 2
ethernets:
  id0:
    match:
      name: "eth*"
    dhcp4: true
    dhcp6: false
  id1:
    match:
      name: "en*"
    dhcp4: true
    dhcp6: false
"@
    
    $networkConfig | Out-File -FilePath (Join-Path $tempDir "network-config") -Encoding ASCII -NoNewline
    
    # Create ISO using oscdimg (part of Windows ADK)
    Write-Host "  - Creating cloud-init ISO..." -ForegroundColor Gray
    
    # Check for oscdimg.exe from Windows ADK
    $oscdimgPath = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
    
    if (-not (Test-Path $oscdimgPath)) {
        Write-Host "  - oscdimg.exe not found, installing Windows ADK Deployment Tools..." -ForegroundColor Gray
        Write-Host "    This will take 5-10 minutes on first run..." -ForegroundColor Gray
        
        choco install windows-adk-deploy -y --no-progress
        
        # Refresh PATH
        $machinePath = [System.Environment]::GetEnvironmentVariable("Path","Machine")
        $userPath = [System.Environment]::GetEnvironmentVariable("Path","User")
        $env:Path = "$machinePath;$userPath"
        
        # Verify installation
        if (-not (Test-Path $oscdimgPath)) {
            Write-Host "  ! Failed to install Windows ADK Deployment Tools" -ForegroundColor Red
            Write-Host "    oscdimg.exe not found at: $oscdimgPath" -ForegroundColor Yellow
            exit 1
        }
        
        Write-Host "  + Windows ADK Deployment Tools installed" -ForegroundColor Green
    }
    
    # Create ISO using oscdimg
    & $oscdimgPath -n -m -d -l"CIDATA" $tempDir $ISOPath 2>&1 | Out-Null
    
    # Cleanup temp directory
    Remove-Item -Path $tempDir -Recurse -Force
    
    if (Test-Path $ISOPath) {
        Write-Host "  + Cloud-init ISO created" -ForegroundColor Green
    }
    else {
        Write-Host "  ! Failed to create cloud-init ISO" -ForegroundColor Red
        exit 1
    }
}

# Function to create Hyper-V VM
function New-QuickQuarmVM {
    param(
        [string]$Name,
        [string]$VHDPath,
        [string]$CloudInitISO,
        [uint64]$Memory,
        [int]$ProcessorCount
    )
    
    Write-Host '[STEP 7/8] Creating Hyper-V VM...' -ForegroundColor Yellow
    
    # Check if VM already exists
    $existingVM = Get-VM -Name $Name -ErrorAction SilentlyContinue
    if ($existingVM) {
        Write-Host "  ! VM '$Name' already exists" -ForegroundColor Yellow
        $response = Read-Host "  Would you like to remove it and create a new one? (y/N)"
        if ($response -eq 'y' -or $response -eq 'Y') {
            if ($existingVM.State -ne "Off") {
                Stop-VM -Name $Name -Force
            }
            Remove-VM -Name $Name -Force
            Write-Host "  - Old VM removed" -ForegroundColor Gray
        }
        else {
            Write-Host "  - Using existing VM" -ForegroundColor Gray
            return $existingVM
        }
    }
    
    # Get default VM path
    $vmPath = (Get-VMHost).VirtualMachinePath
    $vmConfigPath = Join-Path $vmPath $Name
    
    # Create VM
    Write-Host "  - Creating VM '$Name'..." -ForegroundColor Gray
    $vm = New-VM -Name $Name -MemoryStartupBytes $Memory -Generation 2 -Path $vmPath -VHDPath $VHDPath
    
    # Configure VM
    Write-Host "  - Configuring VM..." -ForegroundColor Gray
    Set-VMProcessor -VMName $Name -Count $ProcessorCount
    Set-VMMemory -VMName $Name -DynamicMemoryEnabled $false
    
    # Add DVD drive for cloud-init
    Add-VMDvdDrive -VMName $Name -Path $CloudInitISO
    
    # Select network switch - prefer Default Switch for Wi-Fi compatibility
    $switch = $null
    
    # Option 1: Try Default Switch (BEST for Wi-Fi - works with port forwarding)
    $defaultSwitch = Get-VMSwitch -Name "Default Switch" -ErrorAction SilentlyContinue
    if ($defaultSwitch) {
        $switch = $defaultSwitch
        Write-Host "  - Using Default Switch (with port forwarding for SSH access)" -ForegroundColor Gray
    }
    
    # Option 2: Try existing external switch (for wired connections)
    if (-not $switch) {
        $externalSwitches = Get-VMSwitch -SwitchType External -ErrorAction SilentlyContinue
        if ($externalSwitches) {
            $switch = $externalSwitches[0]
            Write-Host "  - Using existing external switch: $($switch.Name)" -ForegroundColor Gray
        }
    }
    
    # Option 3: Try to create external switch (for wired connections)
    if (-not $switch) {
        Write-Host "  - Attempting to create external switch..." -ForegroundColor Gray
        $netAdapter = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and -not $_.Virtual } | Select-Object -First 1
        
        if ($netAdapter) {
            try {
                $switch = New-VMSwitch -Name "QuickQuarm-External" -NetAdapterName $netAdapter.Name -AllowManagementOS $true -ErrorAction Stop
                Write-Host "  + External switch created on adapter: $($netAdapter.Name)" -ForegroundColor Green
            }
            catch {
                Write-Host "  ! Could not create external switch, trying Default Switch" -ForegroundColor Yellow
                $defaultSwitch = Get-VMSwitch -Name "Default Switch" -ErrorAction SilentlyContinue
                if ($defaultSwitch) {
                    $switch = $defaultSwitch
                    Write-Host "  - Using Default Switch as fallback" -ForegroundColor Gray
                }
            }
        }
    }
    
    # Option 4: Fall back to internal switch (last resort - no network)
    if (-not $switch) {
        Write-Host "  ! No network switches available, creating internal switch" -ForegroundColor Yellow
        Write-Host "    Warning: VM will have no network connectivity" -ForegroundColor Yellow
        
        $existingInternal = Get-VMSwitch -Name "QuickQuarm-Internal" -SwitchType Internal -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($existingInternal) {
            $switch = $existingInternal
            Write-Host "  - Using existing internal switch" -ForegroundColor Gray
        }
        else {
            $switch = New-VMSwitch -Name "QuickQuarm-Internal" -SwitchType Internal
            Write-Host "  + Internal switch created" -ForegroundColor Green
        }
    }
    
    # Connect VM to switch
    Connect-VMNetworkAdapter -VMName $Name -SwitchName $switch.Name
    
    # Disable Secure Boot for Ubuntu compatibility
    Set-VMFirmware -VMName $Name -EnableSecureBoot Off
    
    Write-Host "  + VM created successfully" -ForegroundColor Green
    
    return $vm
}

# Function to detect VM IP by scanning Default Switch subnet
function Get-VMIPAddress {
    param(
        [string]$VMName,
        [int]$TimeoutSeconds = 180
    )
    
    Write-Host "  - Detecting VM IP address..." -ForegroundColor Gray
    
    # Get Default Switch subnet
    $defaultSwitchIP = Get-NetIPAddress -InterfaceAlias "vEthernet (Default Switch)" -AddressFamily IPv4 -ErrorAction SilentlyContinue
    if (-not $defaultSwitchIP) {
        Write-Host "  ! Could not detect Default Switch IP" -ForegroundColor Yellow
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
    
    Write-Host "  - Scanning /$prefixLength subnet for VM (this may take a moment)..." -ForegroundColor Gray
    
    $elapsed = 0
    $scanInterval = 15
    
    while ($elapsed -lt $TimeoutSeconds) {
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
            
            # Show progress every 256 IPs
            if ($ipToTest % 256 -eq 0) {
                $progress = [Math]::Round((($ipToTest - $networkInt) / ($broadcastInt - $networkInt)) * 100)
                Write-Host "  - Scanning... $progress% complete" -ForegroundColor Gray
            }
        }
        
        Start-Sleep -Seconds $scanInterval
        $elapsed += $scanInterval
        Write-Host "  - Rescanning subnet... ($elapsed/$TimeoutSeconds seconds)" -ForegroundColor Gray
    }
    
    Write-Host "  ! Could not detect VM IP address" -ForegroundColor Red
    return $null
}

# Function to set up port forwarding for SSH access
function Set-VMPortForward {
    param(
        [string]$VMIPAddress,
        [int]$HostPort = 2222,
        [int]$VMPort = 22
    )
    
    Write-Host "  - Setting up port forwarding (localhost:${HostPort} -> ${VMIPAddress}:${VMPort})..." -ForegroundColor Gray
    
    # Remove any existing port forward
    $existing = netsh interface portproxy show v4tov4 | Select-String "0.0.0.0\s+$HostPort"
    if ($existing) {
        netsh interface portproxy delete v4tov4 listenaddress=0.0.0.0 listenport=$HostPort | Out-Null
    }
    
    # Add new port forward
    $result = netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=$HostPort connectaddress=$VMIPAddress connectport=$VMPort
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  + Port forwarding configured" -ForegroundColor Green
        return $true
    }
    else {
        Write-Host "  ! Failed to configure port forwarding" -ForegroundColor Red
        return $false
    }
}

# Function to start VM and wait for SSH
function Start-VMAndWaitForSSH {
    param(
        [string]$VMName,
        [int]$TimeoutSeconds = 300,
        [int]$SSHPort = 22
    )
    
    Write-Host "  - Starting VM..." -ForegroundColor Gray
    Start-VM -Name $VMName
    
    Write-Host "  - Waiting for VM to boot (2 minutes)..." -ForegroundColor Gray
    Start-Sleep -Seconds 120
    
    # Detect VM IP address by scanning
    $vmIP = Get-VMIPAddress -VMName $VMName -TimeoutSeconds 120
    
    if (-not $vmIP) {
        Write-Host "  ! Could not detect VM IP address" -ForegroundColor Red
        return $null
    }
    
    # Set up port forwarding for SSH access
    $portForward = Set-VMPortForward -VMIPAddress $vmIP -HostPort 2222 -VMPort 22
    
    if (-not $portForward) {
        Write-Host "  ! Could not set up port forwarding" -ForegroundColor Red
        return $null
    }
    
    # Test SSH connection via port forward
    Write-Host "  - Testing SSH connection via localhost:2222..." -ForegroundColor Gray
    Start-Sleep -Seconds 5
    
    $sshTest = Test-NetConnection -ComputerName "localhost" -Port 2222 -InformationLevel Quiet -WarningAction SilentlyContinue
    
    if ($sshTest) {
        Write-Host "  + SSH is available via port forward" -ForegroundColor Green
        return @{
            ConnectionString = "localhost:2222"
            ActualIP = $vmIP
        }
    }
    else {
        Write-Host "  ! SSH not responding via port forward" -ForegroundColor Red
        return $null
    }
}

# Function to install Quick Quarm via SSH
function Install-QuickQuarmViaSSH {
    param(
        [string]$VMIPAddress,  # Can be "IP" or "localhost:port"
        [string]$ActualVMIP,   # The real VM IP for configuration
        [string]$Username,
        [string]$PrivateKeyPath,
        [string]$RepoUrl,
        [string]$DBHost,
        [string]$DBName,
        [string]$DBUser,
        [string]$DBPassword
    )
    
    Write-Host '[STEP 8/8] Installing Quick Quarm on VM...' -ForegroundColor Yellow
    Write-Host "  (This will take 15-25 minutes - please be patient)" -ForegroundColor Gray
    Write-Host ""
    
    # Parse connection string (localhost:2222 or IP)
    $sshHost = $VMIPAddress
    $sshPort = 22
    if ($VMIPAddress -match '^(.+):(\d+)$') {
        $sshHost = $matches[1]
        $sshPort = $matches[2]
    }
    
    # Create installation script
    $installScript = @'
#!/bin/bash
set -e

echo '[1/6] Updating system...'
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -qq
sudo apt-get upgrade -y -qq

echo '[2/6] Installing git...'
sudo apt-get install -y -qq git

echo '[3/6] Cloning Quick Quarm repository...'
cd ~
if [ -d quick-quarm ]; then
    cd quick-quarm && git pull -q
else
    git clone -q https://github.com/ryhoneyman/quick-quarm.git
    cd quick-quarm
fi

echo '[4/6] Creating configuration file...'
cat > /tmp/qq_answers.txt << 'ANSWERS_EOF'
{USERNAME}
{REPOURL}
{DBHOST}
{DBNAME}
{DBUSER}
{DBPASSWORD}
{VMIPADDRESS}
N
ANSWERS_EOF

echo '[5/6] Running Quick Quarm setup...'
echo '  (This is the longest step - 15-20 minutes)'
sudo bash -c 'cat /tmp/qq_answers.txt | ./scripts/setup'
rm -f /tmp/qq_answers.txt

echo '[6/6] Starting Quick Quarm services...'
sudo systemctl start quick-quarm.target

echo ''
echo '===== INSTALLATION COMPLETE ====='
echo ''
echo 'Quick Quarm is now running!'
echo "Server IP: {VMIPADDRESS}:6000"
'@
    
    # Replace placeholders with actual values (use ActualVMIP for server configuration)
    $installScript = $installScript -replace '\{USERNAME\}', $Username
    $installScript = $installScript -replace '\{REPOURL\}', $RepoUrl
    $installScript = $installScript -replace '\{DBHOST\}', $DBHost
    $installScript = $installScript -replace '\{DBNAME\}', $DBName
    $installScript = $installScript -replace '\{DBUSER\}', $DBUser
    $installScript = $installScript -replace '\{DBPASSWORD\}', $DBPassword
    $installScript = $installScript -replace '\{VMIPADDRESS\}', $ActualVMIP
    
    # Save script to temp file
    $scriptPath = [System.IO.Path]::GetTempFileName() + ".sh"
    $installScript | Out-File -FilePath $scriptPath -Encoding ASCII -NoNewline
    
    # Copy script to VM (using port if specified)
    Write-Host "  - Copying installation script to VM..." -ForegroundColor Gray
    if ($sshPort -ne 22) {
        scp -i $PrivateKeyPath -P $sshPort -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL $scriptPath "${Username}@${sshHost}:/tmp/install_qq.sh"
    }
    else {
        scp -i $PrivateKeyPath -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL $scriptPath "${Username}@${sshHost}:/tmp/install_qq.sh"
    }
    
    # Make script executable and run it
    Write-Host "  - Executing installation on VM..." -ForegroundColor Gray
    Write-Host ""
    
    if ($sshPort -ne 22) {
        ssh -i $PrivateKeyPath -p $sshPort -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL "${Username}@${sshHost}" "chmod +x /tmp/install_qq.sh && /tmp/install_qq.sh"
    }
    else {
        ssh -i $PrivateKeyPath -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL "${Username}@${sshHost}" "chmod +x /tmp/install_qq.sh && /tmp/install_qq.sh"
    }
    
    # Cleanup
    Remove-Item $scriptPath -Force
    
    Write-Host ""
    Write-Host "  + Quick Quarm installation complete" -ForegroundColor Green
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
    
    # Enable Hyper-V if needed
    if (-not (Test-HyperV)) {
        Enable-HyperV
        # If we get here and Hyper-V is still not enabled, we need a restart
        exit 0
    }
    else {
        Write-Host '[STEP 1/8] Hyper-V already enabled +' -ForegroundColor Green
    }
    
    # Install required tools
    Install-RequiredTools
    
    # Setup paths
    $workDir = Join-Path $env:USERPROFILE "QuickQuarm-VM"
    if (-not (Test-Path $workDir)) {
        New-Item -ItemType Directory -Path $workDir -Force | Out-Null
    }
    
    $sshKeyPath = Join-Path $workDir "id_rsa"
    $ubuntuImage = Join-Path $workDir "ubuntu-22.04-server.img"
    $vhdxPath = Join-Path $workDir "$VMName.vhdx"
    $cloudInitISO = Join-Path $workDir "cloud-init.iso"
    
    # Generate SSH key pair
    New-SSHKeyPair -KeyPath $sshKeyPath
    
    # Download Ubuntu image
    Get-UbuntuImage -ImagePath $ubuntuImage
    
    # Convert to VHDX
    Convert-ImageToVHDX -SourceImage $ubuntuImage -DestVHDX $vhdxPath
    
    # Create cloud-init ISO with SSH key
    New-CloudInitISO -ISOPath $cloudInitISO -PublicKeyPath "$sshKeyPath.pub" -Username $InstallUser -Password $InstallPassword
    
    # Create VM
    $vm = New-QuickQuarmVM -Name $VMName -VHDPath $vhdxPath -CloudInitISO $cloudInitISO -Memory $VMMemory -ProcessorCount $VMProcessors
    
    # Start VM and wait for SSH
    $vmConnection = Start-VMAndWaitForSSH -VMName $VMName -TimeoutSeconds 300
    
    if (-not $vmConnection) {
        Write-Host ""
        Write-Host "Failed to get VM IP address or SSH is not responding" -ForegroundColor Red
        Write-Host "You can try to connect manually later using:" -ForegroundColor Yellow
        Write-Host "  ssh -i `"$sshKeyPath`" ${InstallUser}@<VM_IP>" -ForegroundColor Gray
        exit 1
    }
    
    $sshConnection = $vmConnection.ConnectionString
    $vmActualIP = $vmConnection.ActualIP
    
    # Install Quick Quarm via SSH
    Install-QuickQuarmViaSSH -VMIPAddress $sshConnection -ActualVMIP $vmActualIP -Username $InstallUser -PrivateKeyPath $sshKeyPath -RepoUrl $RepoUrl -DBHost $DBHost -DBName $DBName -DBUser $DBUser -DBPassword $DBPassword
    
    # Final output
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "Installation Complete!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Quick Quarm server details:" -ForegroundColor Cyan
    Write-Host "  VM Name: $VMName" -ForegroundColor White
    Write-Host "  VM IP: $vmActualIP" -ForegroundColor White
    Write-Host "  Server Address: ${vmActualIP}:6000" -ForegroundColor White
    Write-Host "  SSH Key: $sshKeyPath" -ForegroundColor White
    Write-Host "  SSH Port Forward: localhost:2222 -> ${vmActualIP}:22" -ForegroundColor White
    Write-Host ""
    Write-Host "To connect to VM via SSH:" -ForegroundColor Cyan
    Write-Host "  ssh -i `"$sshKeyPath`" -p 2222 ${InstallUser}@localhost" -ForegroundColor White
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "1. Download TAKP v2.2 Client from PQ Discord #server-files" -ForegroundColor White
    Write-Host "2. Edit eqhost.txt and change server to: ${vmIP}:6000" -ForegroundColor White
    Write-Host "3. Run the client and login with any username/password" -ForegroundColor White
    Write-Host "4. Select your Quick Quarm server and create a character" -ForegroundColor White
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

