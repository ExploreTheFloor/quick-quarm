# Quick Quarm Installation Script for Windows (Hyper-V VM)
# This script creates a Hyper-V VM with Ubuntu 22.04 and installs Quick Quarm
#
# Ubuntu 22.04 Jammy Cloud-Init Bug Workaround:
# Bug #1961832: ds-identify runs before SATA CDROM is detected, causing cloud-init to not run
# Solution: Use 'ubuntu' as default user (guaranteed to work with cloud-init), configure datasource
#           via bootcmd, and set up root access via runcmd. This works around the timing issue.

#Requires -RunAsAdministrator

param(
    [string]$VMName = "QuickQuarm",
    [string]$VMMemory = 4GB,
    [int]$VMProcessors = 2,
    [string]$VMDiskSize = 60GB,
    [string]$InstallUser = "ubuntu",
    [string]$InstallPassword = "ubuntu",
    [string]$RepoUrl = "https://github.com/SecretsOTheP/EQMacEmu.git",
    [string]$DBHost = "localhost",
    [string]$DBName = "quarm",
    [string]$DBUser = "quarm",
    [string]$DBPassword = "quarm",
    [string]$StaticIP = "",
    [string]$Gateway = "",
    [string]$Netmask = "",
    [string]$DNS = "8.8.8.8,8.8.4.4"
)

# ============================================================================
# LOGGING SETUP
# ============================================================================

# Create logs directory
$LogDir = Join-Path $PSScriptRoot "logs"
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

# Start transcript with timestamp
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$LogFile = Join-Path $LogDir "QuarmInstaller-$Timestamp.log"
Start-Transcript -Path $LogFile -Append

Write-Host "Logging to: $LogFile" -ForegroundColor Gray
Write-Host ""

# ============================================================================

try {

# Disable QuickEdit mode to prevent script from pausing when console is clicked
$quickEditCode = @'
using System;
using System.Runtime.InteropServices;
public class QuickEditMode {
    const uint ENABLE_QUICK_EDIT = 0x0040;
    const int STD_INPUT_HANDLE = -10;
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr GetStdHandle(int nStdHandle);
    [DllImport("kernel32.dll")]
    static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
    [DllImport("kernel32.dll")]
    static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
    public static void Disable() {
        IntPtr consoleHandle = GetStdHandle(STD_INPUT_HANDLE);
        uint consoleMode;
        if (GetConsoleMode(consoleHandle, out consoleMode)) {
            consoleMode &= ~ENABLE_QUICK_EDIT;
            SetConsoleMode(consoleHandle, consoleMode);
        }
    }
}
'@
try {
    Add-Type -TypeDefinition $quickEditCode -ErrorAction SilentlyContinue
    [QuickEditMode]::Disable()
} catch {
    # QuickEdit disable failed, continue anyway
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Quick Quarm VM Installation for Windows" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Import shared module
$modulePath = Join-Path $PSScriptRoot "HyperV-QuarmCommon.psm1"
if (Test-Path $modulePath) {
    Import-Module $modulePath -Force
} else {
    Write-Host "ERROR: Shared module not found at: $modulePath" -ForegroundColor Red
    exit 1
}

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

# Get-DefaultSwitchNetworkConfig is now in the shared module

# Note: Removed Add-NoCloudKernelParameter function as Windows cannot read Linux ext4 filesystems
# The workaround is now applied via cloud-init bootcmd (see user-data configuration)

# Function to create cloud-init ISO
function New-CloudInitISO {
    param(
        [string]$ISOPath,
        [string]$PublicKeyPath,
        [string]$Username,
        [string]$Password,
        [string]$StaticIP = "",
        [string]$Gateway = "",
        [string]$Netmask = "",
        [string]$DNS = "8.8.8.8,8.8.4.4"
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
    # Follows verified pattern from working Hyper-V cloud-init examples
    $userData = @'
#cloud-config
# Force NoCloud datasource to ensure cloud-init detects config on Hyper-V
datasource_list: [ NoCloud, None ]
datasource:
  NoCloud:
    fs_label: cidata
# Automatically grow root partition to fill disk
growpart:
  mode: auto
  devices: ['/']
  ignore_growroot_disabled: false
# Configure ubuntu user with SSH key
users:
  - name: ubuntu
    gecos: Quick Quarm User
    groups: [adm, audio, cdrom, dialout, dip, floppy, netdev, plugdev, sudo, video]
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    lock_passwd: false
    ssh_authorized_keys:
      - {PUBLICKEY}
# Set password for ubuntu user
chpasswd:
  list: |
    ubuntu:{PASSWORD}
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
  - echo "===== CLOUD-INIT BOOTCMD STARTING =====" | tee -a /var/log/hyperv-install.log
  - date | tee -a /var/log/hyperv-install.log
  - echo "Loading Hyper-V kernel modules..." | tee -a /var/log/hyperv-install.log
  - modprobe hv_balloon
  - modprobe hv_utils
  - modprobe hv_vmbus
  - modprobe hv_sock
  - modprobe hv_storvsc
  - modprobe hv_netvsc
  - echo "Hyper-V modules loaded" | tee -a /var/log/hyperv-install.log
  - lsmod | grep hv_ | tee -a /var/log/hyperv-install.log
  - echo "Persisting Hyper-V modules..." | tee -a /var/log/hyperv-install.log
  - sh -c 'echo "hv_balloon\nhv_utils\nhv_vmbus\nhv_sock\nhv_storvsc\nhv_netvsc" >>/etc/initramfs-tools/modules' && update-initramfs -k all -u
  - echo "===== CLOUD-INIT BOOTCMD COMPLETED =====" | tee -a /var/log/hyperv-install.log
runcmd:
  - echo "===== CLOUD-INIT RUNCMD STARTING =====" | tee -a /var/log/hyperv-install.log
  - date | tee -a /var/log/hyperv-install.log
  - echo "Ensuring SSH service is enabled..." | tee -a /var/log/hyperv-install.log
  - systemctl enable ssh
  - echo "Restarting SSH to apply cloud-init configuration..." | tee -a /var/log/hyperv-install.log
  - systemctl restart ssh
  - sleep 2
  - systemctl status ssh --no-pager | tee -a /var/log/hyperv-install.log
  - echo "Verifying SSH key injection..." | tee -a /var/log/hyperv-install.log
  - ls -la /home/ubuntu/.ssh/ | tee -a /var/log/hyperv-install.log
  - echo "SSH authorized_keys content:" | tee -a /var/log/hyperv-install.log
  - cat /home/ubuntu/.ssh/authorized_keys | tee -a /var/log/hyperv-install.log
  - echo "Network configuration:" | tee -a /var/log/hyperv-install.log
  - ip addr show | tee -a /var/log/hyperv-install.log
  - echo "===== CLOUD-INIT RUNCMD COMPLETED =====" | tee -a /var/log/hyperv-install.log
  - date | tee -a /var/log/hyperv-install.log
'@
    
    # Replace placeholders with actual values
    $userData = $userData -replace '\{USERNAME\}', $Username
    $userData = $userData -replace '\{PASSWORD\}', $Password
    $userData = $userData -replace '\{PUBLICKEY\}', $publicKey
    
    # Write configuration files
    $metaDataPath = Join-Path $tempDir "meta-data"
    $userDataPath = Join-Path $tempDir "user-data"
    
    $metaData | Out-File -FilePath $metaDataPath -Encoding ASCII -NoNewline
    $userData | Out-File -FilePath $userDataPath -Encoding ASCII -NoNewline
    
    # Debug: Log first few lines of user-data to verify NoCloud datasource config
    Write-Host "    [DEBUG] Cloud-init user-data configuration:" -ForegroundColor DarkGray
    $userDataLines = Get-Content $userDataPath | Select-Object -First 10
    foreach ($line in $userDataLines) {
        Write-Host "      $line" -ForegroundColor DarkGray
    }
    
    # Create network-config file
    # Use static IP if provided, otherwise use DHCP
    if (-not [string]::IsNullOrEmpty($StaticIP) -and -not [string]::IsNullOrEmpty($Gateway) -and -not [string]::IsNullOrEmpty($Netmask)) {
        # Convert netmask to prefix length if needed
        $prefixLength = $Netmask
        if ($Netmask -match '^\d+\.\d+\.\d+\.\d+$') {
            # Convert dotted decimal to prefix length
            $octets = $Netmask.Split('.')
            $binary = ""
            foreach ($octet in $octets) {
                $binary += [Convert]::ToString([int]$octet, 2).PadLeft(8, '0')
            }
            $prefixLength = ($binary -replace '0+$', '').Length
        }
        
        # Validate network configuration before proceeding
        Write-Host "  - Validating network configuration..." -ForegroundColor Gray
        
        # Validate static IP and gateway are valid IPv4 addresses
        try {
            $staticIPObj = [System.Net.IPAddress]::Parse($StaticIP)
            $gatewayObj = [System.Net.IPAddress]::Parse($Gateway)
        }
        catch {
            Write-Host "  ! ERROR: Invalid IP address format" -ForegroundColor Red
            Write-Host "    Static IP: $StaticIP" -ForegroundColor Red
            Write-Host "    Gateway: $Gateway" -ForegroundColor Red
            throw "Invalid network configuration"
        }
        
        # Validate static IP and gateway are in same subnet
        $staticIPBytes = $staticIPObj.GetAddressBytes()
        $gatewayBytes = $gatewayObj.GetAddressBytes()
        
        # Calculate subnet mask as integer
        $maskInt = [Convert]::ToUInt32(("1" * $prefixLength).PadRight(32, "0"), 2)
        
        # Calculate network addresses (bitwise AND with mask)
        $staticNetwork = [System.BitConverter]::ToUInt32($staticIPBytes[3..0], 0) -band $maskInt
        $gatewayNetwork = [System.BitConverter]::ToUInt32($gatewayBytes[3..0], 0) -band $maskInt
        
        if ($staticNetwork -ne $gatewayNetwork) {
            Write-Host "  ! ERROR: Static IP and Gateway are not in same subnet" -ForegroundColor Red
            Write-Host "    Static IP: $StaticIP/$prefixLength" -ForegroundColor Red
            Write-Host "    Gateway: $Gateway" -ForegroundColor Red
            throw "Static IP and Gateway must be in same subnet"
        }
        
        # Check static IP is not network address, broadcast, or gateway
        $staticIPInt = [System.BitConverter]::ToUInt32($staticIPBytes[3..0], 0)
        $gatewayIPInt = [System.BitConverter]::ToUInt32($gatewayBytes[3..0], 0)
        $broadcastInt = $staticNetwork -bor (-bnot $maskInt -band 0xFFFFFFFF)
        
        if ($staticIPInt -eq $staticNetwork) {
            Write-Host "  ! ERROR: Static IP cannot be the network address" -ForegroundColor Red
            throw "Invalid static IP (network address)"
        }
        if ($staticIPInt -eq $broadcastInt) {
            Write-Host "  ! ERROR: Static IP cannot be the broadcast address" -ForegroundColor Red
            throw "Invalid static IP (broadcast address)"
        }
        if ($staticIPInt -eq $gatewayIPInt) {
            Write-Host "  ! ERROR: Static IP cannot be the same as gateway" -ForegroundColor Red
            throw "Invalid static IP (same as gateway)"
        }
        
        Write-Host "  + Network configuration validated" -ForegroundColor Green
        
        # Parse DNS servers
        $dnsServers = $DNS -split ',' | ForEach-Object { $_.Trim() }
        
        # Validate DNS servers are valid IPv4 addresses
        foreach ($dnsServer in $dnsServers) {
            try {
                $null = [System.Net.IPAddress]::Parse($dnsServer)
                if ($dnsServer -eq "0.0.0.0" -or $dnsServer -eq "255.255.255.255") {
                    Write-Host "  ! ERROR: Invalid DNS server: $dnsServer" -ForegroundColor Red
                    throw "Invalid DNS server address"
                }
            }
            catch {
                Write-Host "  ! ERROR: Invalid DNS server format: $dnsServer" -ForegroundColor Red
                throw "Invalid DNS server configuration"
            }
        }
        
        $dnsServersYaml = $dnsServers -join ', '
        Write-Host "  + DNS servers validated: $($dnsServers -join ', ')" -ForegroundColor Green
        
        Write-Host "  - Configuring static IP: $StaticIP/$prefixLength" -ForegroundColor Gray
        $networkConfig = @"
version: 2
ethernets:
  id0:
    match:
      name: "eth*"
    addresses:
      - $StaticIP/$prefixLength
    routes:
      - to: default
        via: $Gateway
    nameservers:
      addresses: [$dnsServersYaml]
  id1:
    match:
      name: "en*"
    addresses:
      - $StaticIP/$prefixLength
    routes:
      - to: default
        via: $Gateway
    nameservers:
      addresses: [$dnsServersYaml]
"@
    }
    else {
        # Use DHCP for all interfaces
        # This works with External switches (physical network DHCP)
        # For Default Switch/Internal switches, DHCP may not work but VM will still boot
        Write-Host "  - Configuring DHCP (dynamic IP)" -ForegroundColor Gray
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
    }
    
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
    
    # Create ISO using oscdimg with Joliet format (required for Hyper-V cloud-init detection)
    # -j1 creates both Joliet AND ISO 9660 file systems (required for Hyper-V NoCloud datasource)
    # -lcidata sets volume label to CIDATA (required by cloud-init NoCloud)
    # -r resolves symbolic links
    Write-Host "    [DEBUG] Creating ISO with NoCloud datasource..." -ForegroundColor DarkGray
    Write-Host "      Source: $tempDir" -ForegroundColor DarkGray
    Write-Host "      Target: $ISOPath" -ForegroundColor DarkGray
    Write-Host "      Volume label: CIDATA (required for NoCloud)" -ForegroundColor DarkGray
    
    $oscdimgOutput = & $oscdimgPath $tempDir $ISOPath -j1 -lcidata -r 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ! WARNING: oscdimg returned exit code $LASTEXITCODE" -ForegroundColor Yellow
        Write-Host "    Output: $oscdimgOutput" -ForegroundColor Gray
    } else {
        Write-Host "    [DEBUG] ISO created successfully with CIDATA label" -ForegroundColor DarkGray
    }
    
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
    
    # Configure Secure Boot for Ubuntu compatibility (Gen2 VM requires UEFI cert authority)
    Set-VMFirmware -VMName $Name -EnableSecureBoot On -SecureBootTemplate 'MicrosoftUEFICertificateAuthority'
    
    # Configure VM to start automatically on host boot/resume
    Write-Host "  - Configuring VM auto-start..." -ForegroundColor Gray
    Set-VM -VMName $Name -AutomaticStartAction Start -AutomaticStartDelay 0
    Set-VM -VMName $Name -AutomaticStopAction Save
    Write-Host "  + VM auto-start configured" -ForegroundColor Green
    
    Write-Host "  + VM created successfully" -ForegroundColor Green
    
    return $vm
}

# Get-VMIPAddress is now in the shared module

# Helper function for SSH port forwarding (2222->22) - different from game ports
function Set-SSHPortForward {
    param(
        [string]$VMIPAddress,
        [int]$HostPort = 2222,
        [int]$VMPort = 22
    )
    
    Write-Host "  - Setting up SSH port forwarding (localhost:${HostPort} -> ${VMIPAddress}:${VMPort})..." -ForegroundColor Gray
    
    # Remove any existing port forward
    $existing = netsh interface portproxy show v4tov4 | Select-String "0.0.0.0\s+$HostPort"
    if ($existing) {
        netsh interface portproxy delete v4tov4 listenaddress=0.0.0.0 listenport=$HostPort | Out-Null
    }
    
    # Add new port forward
    $result = netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=$HostPort connectaddress=$VMIPAddress connectport=$VMPort
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  + SSH port forwarding configured" -ForegroundColor Green
        return $true
    }
    else {
        Write-Host "  ! Failed to configure SSH port forwarding" -ForegroundColor Red
        return $false
    }
}

# Function to start VM and wait for SSH
function Start-VMAndWaitForSSH {
    param(
        [string]$VMName,
        [int]$TimeoutSeconds = 300,
        [int]$SSHPort = 22,
        [string]$StaticIP = "",
        [string]$SSHKeyPath,
        [string]$Username
    )
    
    Write-Host "  - Starting VM..." -ForegroundColor Gray
    Write-Host "    [DEBUG] VM Name: $VMName" -ForegroundColor DarkGray
    Write-Host "    [DEBUG] Static IP: $StaticIP" -ForegroundColor DarkGray
    Write-Host "    [DEBUG] Current time: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor DarkGray
    Start-VM -Name $VMName
    Write-Host "  + VM started at $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Green
    
    Write-Host "  - Waiting for VM to boot and cloud-init to complete (5 minutes)..." -ForegroundColor Gray
    Write-Host "    Cloud-init with package updates can take 3-7 minutes on first boot" -ForegroundColor Gray
    Write-Host "    This ensures SSH keys and user accounts are fully configured" -ForegroundColor Gray
    Start-Sleep -Seconds 300
    
    # Remove cloud-init DVD drive after cloud-init has run
    Write-Host "  - Removing cloud-init DVD drive..." -ForegroundColor Gray
    try {
        $dvdDrives = Get-VMDvdDrive -VMName $VMName
        $cloudInitDrive = $dvdDrives | Where-Object { $_.Path -like "*cloud-init*" }
        if ($cloudInitDrive) {
            $cloudInitDrive | Remove-VMDvdDrive -ErrorAction SilentlyContinue
            Write-Host "  + Cloud-init DVD drive removed" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "  ! Could not remove DVD drive (non-critical)" -ForegroundColor Yellow
    }
    
    # Detect VM IP address (use static IP if provided, otherwise scan)
    $vmIP = Get-VMIPAddress -VMName $VMName -TimeoutSeconds 120 -StaticIP $StaticIP
    
    if (-not $vmIP) {
        Write-Host "  ! Could not detect VM IP address" -ForegroundColor Red
        return $null
    }
    
    Write-Host "  + VM IP detected: $vmIP" -ForegroundColor Green
    
    # Verify cloud-init completed via direct SSH connection
    Write-Host "  - Verifying cloud-init completed via SSH..." -ForegroundColor Gray
    $cloudInitVerified = $false
    $maxAttempts = 10  # 10 attempts * 5 seconds = 50 seconds max
    $attempt = 0
    
    while ($attempt -lt $maxAttempts -and -not $cloudInitVerified) {
        $attempt++
        
        # Try SSH connection to verify cloud-init
        $sshTest = & ssh -i $SSHKeyPath -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL "${Username}@${vmIP}" "cloud-init status 2>&1" 2>&1
        
        if ($LASTEXITCODE -eq 0 -and $sshTest -match "status: done") {
            Write-Host "  + Cloud-init completed successfully" -ForegroundColor Green
            $cloudInitVerified = $true
        }
        elseif ($attempt -lt $maxAttempts) {
            if ($attempt % 3 -eq 0) {
                Write-Host "    Waiting for cloud-init... (attempt $attempt/$maxAttempts)" -ForegroundColor Gray
            }
            Start-Sleep -Seconds 5
        }
    }
    
    if (-not $cloudInitVerified) {
        Write-Host "  ! Cloud-init status could not be verified via SSH" -ForegroundColor Yellow
        Write-Host "    Continuing anyway - SSH connection will be tested next" -ForegroundColor Gray
    }
    
    # Set up port forwarding for SSH access
    $portForward = Set-SSHPortForward -VMIPAddress $vmIP -HostPort 2222 -VMPort 22
    
    if (-not $portForward) {
        Write-Host "  ! Could not set up port forwarding" -ForegroundColor Red
        Write-Host "    Will try direct IP connection as fallback" -ForegroundColor Yellow
    }
    
    # Test SSH connection - try port forward first, then direct IP
    Write-Host "  - Testing SSH connection..." -ForegroundColor Gray
    Start-Sleep -Seconds 3
    
    $sshWorking = $false
    $connectionString = ""
    
    # Try port forward first
    if ($portForward) {
        $portTest = Test-NetConnection -ComputerName "localhost" -Port 2222 -InformationLevel Quiet -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        if ($portTest) {
            $sshKeyTest = & ssh -i $SSHKeyPath -p 2222 -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL "${Username}@localhost" "echo 'SSH OK'" 2>&1
            if ($LASTEXITCODE -eq 0 -and $sshKeyTest -match "SSH OK") {
                Write-Host "  + SSH via port forward (localhost:2222) working" -ForegroundColor Green
                $sshWorking = $true
                $connectionString = "localhost:2222"
            }
        }
    }
    
    # Fallback to direct IP if port forward failed
    if (-not $sshWorking) {
        Write-Host "    Port forward not working, trying direct IP connection..." -ForegroundColor Gray
        $sshKeyTest = & ssh -i $SSHKeyPath -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL "${Username}@${vmIP}" "echo 'SSH OK'" 2>&1
        if ($LASTEXITCODE -eq 0 -and $sshKeyTest -match "SSH OK") {
            Write-Host "  + SSH via direct IP ($vmIP) working" -ForegroundColor Green
            $sshWorking = $true
            $connectionString = $vmIP
        }
    }
    
    if ($sshWorking) {
        return @{
            ConnectionString = $connectionString
            ActualIP = $vmIP
        }
    }
    else {
        Write-Host "  ! SSH connection failed (both port forward and direct IP)" -ForegroundColor Red
        return $null
    }
}

# Function to install Quick Quarm via SSH
function Install-QuickQuarmViaSSH {
    param(
        [string]$VMIPAddress,  # Can be "IP" or "localhost:port"
        [string]$ActualVMIP,   # The real VM IP for configuration
        [string]$Username,
        [string]$Password,
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
    $sshHost = "localhost"
    $sshPort = 2222
    if ($VMIPAddress -match '^(.+):(\d+)$') {
        $sshHost = $matches[1]
        $sshPort = [int]$matches[2]
    } elseif ($VMIPAddress -notmatch ':') {
        # Plain IP without port - must be direct connection
        $sshHost = $VMIPAddress
        $sshPort = 22
    }
    
    Write-Host "  [DEBUG] SSH connection: ${sshHost}:${sshPort}" -ForegroundColor DarkGray
    
    # Create installation script
    $installScript = @'
#!/bin/bash
set -e

echo '[1/7] Waiting for cloud-init to complete...'
echo '  (This ensures system initialization is finished)'
# Wait for cloud-init to finish
sudo cloud-init status --wait || true
echo '  + Cloud-init completed'

# Verify SSH key was injected properly
if [ ! -f /home/ubuntu/.ssh/authorized_keys ]; then
    echo '  ! ERROR: SSH authorized_keys file not found'
    echo '  Expected: /home/ubuntu/.ssh/authorized_keys'
    echo '  Cloud-init may not have run properly'
    exit 1
fi

if ! grep -q "quickquarm@hyperv" /home/ubuntu/.ssh/authorized_keys 2>/dev/null; then
    echo '  ! ERROR: SSH key not found in authorized_keys'
    echo '  Cloud-init did not inject the SSH key properly'
    exit 1
fi
echo '  + SSH key properly configured'

echo '[2/7] Updating system...'
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -qq
sudo apt-get upgrade -y -qq

echo '[3/7] Installing git...'
sudo apt-get install -y -qq git

echo '[4/7] Cloning Quick Quarm repository...'
cd ~
if [ -d quick-quarm ]; then
    cd quick-quarm && git pull -q
else
    git clone -q https://github.com/ryhoneyman/quick-quarm.git
    cd quick-quarm
fi

echo '[5/7] Creating configuration file...'
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

echo '[6/7] Running Quick Quarm setup...'
echo '  (This is the longest step - 15-20 minutes)'
sudo bash -c 'cat /tmp/qq_answers.txt | ./scripts/setup'
rm -f /tmp/qq_answers.txt

echo '[7/7] Verifying and starting Quick Quarm services...'

# Check if services are already running (install-systemd may have started them)
if systemctl is-active --quiet quick-quarm.target; then
    echo '  + Services are already running (started by install-systemd)'
else
    echo '  - Services are not running, checking prerequisites...'
    
    # Check if services are enabled
    if systemctl is-enabled --quiet quick-quarm.target 2>/dev/null; then
        echo '  + Services are enabled for auto-start'
    else
        echo '  - Enabling services for auto-start...'
        if ! sudo systemctl enable quick-quarm.target; then
            echo '  ! ERROR: Failed to enable services'
            exit 1
        fi
    fi
    
    # Verify prerequisites before starting
    echo '  - Verifying prerequisites...'
    
    # Check if database is running
    if ! systemctl is-active --quiet mariadb.service; then
        echo '  ! ERROR: MariaDB/MySQL is not running'
        echo '  Attempting to start database...'
        if ! sudo systemctl start mariadb.service; then
            echo '  ! ERROR: Failed to start database'
            exit 1
        fi
        sleep 3
        if ! systemctl is-active --quiet mariadb.service; then
            echo '  ! ERROR: Database did not start'
            exit 1
        fi
    fi
    echo '    + Database service is running'
    
    # Wait for database to be truly ready (not just active)
    echo '  - Waiting for database to accept connections...'
    DB_READY=0
    for i in {1..30}; do
        if mysqladmin -u {DBUSER} -p{DBPASSWORD} ping >/dev/null 2>&1; then
            DB_READY=1
            echo '    + Database is ready and accepting connections'
            break
        fi
        sleep 1
    done
    
    if [ $DB_READY -eq 0 ]; then
        echo '  ! WARNING: Database not responding to connections after 30 seconds'
        echo '  Attempting to continue anyway...'
    fi
    
    # Check if binaries exist
    QQDIR="$HOME/quick-quarm"
    if [ ! -f "$QQDIR/bin/world" ] || [ ! -f "$QQDIR/bin/loginserver" ]; then
        echo '  ! ERROR: Server binaries not found'
        echo "  Expected location: $QQDIR/bin/"
        echo '  This indicates the build step may have failed'
        exit 1
    fi
    echo '    + Binaries found'
    
    # Check if binaries are executable
    if [ ! -x "$QQDIR/bin/world" ] || [ ! -x "$QQDIR/bin/loginserver" ]; then
        echo '  - Making binaries executable...'
        chmod +x "$QQDIR/bin"/*
    fi
    
    # Reload systemd to ensure services are up to date
    echo '  - Reloading systemd daemon...'
    sudo systemctl daemon-reload
    
    # Start the services with proper error handling
    echo '  - Starting Quick Quarm services...'
    if ! sudo systemctl start quick-quarm.target; then
        echo ''
        echo '  ! ERROR: Failed to start services'
        echo ''
        echo '  Service status:'
        systemctl status quick-quarm.target --no-pager -l || true
        echo ''
        echo '  Recent service logs:'
        journalctl -u quick-quarm.target -n 30 --no-pager || true
        echo ''
        echo '  Individual service status:'
        for service in eqemu-shared-memory eqemu-loginserver eqemu-ucs eqemu-queryserv eqemu-world eqemu-zone eqemu-boats; do
            status=$(systemctl is-active $service.service 2>/dev/null || echo 'inactive')
            echo "    $service.service: $status"
            if [ "$status" != "active" ]; then
                echo "      Recent errors:"
                journalctl -u $service.service -n 5 --no-pager | grep -iE '(error|failed|Error|Failed|ERROR|FAILED)' | tail -3 | sed 's/^/        /' || echo "        (no errors found)"
            fi
        done
        exit 1
    fi
    
    # Wait for services to start
    echo '  - Waiting for services to initialize...'
    sleep 5
    
    # Verify services are actually running
    if ! systemctl is-active --quiet quick-quarm.target; then
        echo ''
        echo '  ! ERROR: Services did not start properly'
        echo ''
        echo '  Service status:'
        systemctl status quick-quarm.target --no-pager -l || true
        echo ''
        echo '  Recent service logs:'
        journalctl -u quick-quarm.target -n 30 --no-pager || true
        echo ''
        echo '  Individual service failures:'
        for service in eqemu-shared-memory eqemu-loginserver eqemu-ucs eqemu-queryserv eqemu-world eqemu-zone eqemu-boats; do
            if ! systemctl is-active --quiet $service.service 2>/dev/null; then
                echo "    $service.service: FAILED"
                echo "      Status: $(systemctl is-active $service.service 2>/dev/null || echo 'inactive')"
                echo "      Recent logs:"
                journalctl -u $service.service -n 10 --no-pager | grep -iE '(error|failed|Error|Failed|ERROR|FAILED|cannot|Cannot|CANNOT)' | tail -3 | sed 's/^/        /' || echo "        (check logs manually)"
            fi
        done
        exit 1
    fi
    echo '  + Services started successfully'
fi

# Final verification of all individual services
echo '  - Verifying all services are running...'
ALL_RUNNING=true
for service in eqemu-shared-memory eqemu-loginserver eqemu-ucs eqemu-queryserv eqemu-world eqemu-zone eqemu-boats; do
    if systemctl is-active --quiet $service.service 2>/dev/null; then
        echo "    + $service.service: running"
    else
        echo "    ! $service.service: NOT running"
        ALL_RUNNING=false
    fi
done

if [ "$ALL_RUNNING" = "false" ]; then
    echo ''
    echo '  ! WARNING: Some services are not running'
    echo '  Check logs with: sudo journalctl -u quick-quarm.target -f'
    exit 1
fi

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
    
    # Save script to temp file with Unix line endings (LF only)
    $scriptPath = [System.IO.Path]::GetTempFileName() + ".sh"
    # Convert to Unix line endings (LF only) and save as UTF-8 without BOM
    $installScript = $installScript -replace "`r`n", "`n" -replace "`r", "`n"
    [System.IO.File]::WriteAllText($scriptPath, $installScript, [System.Text.UTF8Encoding]::new($false))
    
    # Wait for SSH service to be ready and test connection with retries
    Write-Host "  - Waiting for SSH service to be ready (will retry for up to 8 minutes)..." -ForegroundColor Gray
    $maxRetries = 48  # 48 retries * 10 seconds = 8 minutes max
    $retryCount = 0
    $sshSuccess = $false
    
    while ($retryCount -lt $maxRetries -and -not $sshSuccess) {
        # First check if SSH port is open
        $portOpen = $false
        try {
            $testPort = if ($sshPort -ne 22) { $sshPort } else { 22 }
            $testHost = if ($sshPort -ne 22) { "localhost" } else { $sshHost }
            $tcpTest = Test-NetConnection -ComputerName $testHost -Port $testPort -WarningAction SilentlyContinue -InformationLevel Quiet -ErrorAction SilentlyContinue
            $portOpen = $tcpTest
        }
        catch {
            $portOpen = $false
        }
        
        if ($portOpen) {
            # Port is open, try SSH key authentication
            $testResult = & ssh -i $PrivateKeyPath -p $sshPort -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL -o ConnectTimeout=10 "${Username}@${sshHost}" "echo 'SSH test successful'" 2>&1
            if ($LASTEXITCODE -eq 0 -and $testResult -match "SSH test successful") {
                $sshSuccess = $true
                Write-Host "  + SSH connection successful" -ForegroundColor Green
            }
            else {
                $retryCount++
                if ($retryCount -lt $maxRetries) {
                    # Show more detailed progress
                    if ($retryCount % 6 -eq 0) {
                        $elapsed = [math]::Round($retryCount * 10 / 60, 1)
                        Write-Host "    After $elapsed minutes: SSH port open but authentication failing (cloud-init still configuring)" -ForegroundColor Gray
                    }
                    Start-Sleep -Seconds 10
                }
            }
        }
        else {
            # Port not open yet
            $retryCount++
            if ($retryCount -lt $maxRetries) {
                if ($retryCount % 6 -eq 0) {
                    $elapsed = [math]::Round($retryCount * 10 / 60, 1)
                    Write-Host "    After $elapsed minutes: SSH port not ready yet (waiting for cloud-init)" -ForegroundColor Gray
                }
                Start-Sleep -Seconds 10
            }
        }
    }
    
    if (-not $sshSuccess) {
        Write-Host ""
        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Red
        Write-Host "  SSH CONNECTION FAILED" -ForegroundColor Red
        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Red
        Write-Host ""
        Write-Host "  SSH key authentication failed after $maxRetries attempts (8 minutes)" -ForegroundColor Yellow
        Write-Host "  This usually means cloud-init or SSH key injection encountered an issue." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Last SSH output:" -ForegroundColor Gray
        Write-Host "  $testResult" -ForegroundColor DarkGray
        Write-Host ""
        
        # Try to get cloud-init status via password authentication if available
        Write-Host "  Attempting to retrieve cloud-init logs for diagnosis..." -ForegroundColor Gray
        try {
            $cloudInitDiag = & plink -batch -ssh -P $sshPort -pw $Password "$Username@$sshHost" "sudo cloud-init status --long 2>&1; echo '---'; sudo tail -20 /var/log/cloud-init.log 2>&1" 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host ""
                Write-Host "  Cloud-init status and recent logs:" -ForegroundColor Cyan
                Write-Host "  ─────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
                $cloudInitDiag -split "`n" | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
                Write-Host "  ─────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
                Write-Host ""
            }
        }
        catch {
            Write-Host "  (Could not retrieve cloud-init logs automatically)" -ForegroundColor DarkGray
        }
        
        Write-Host "  POSSIBLE CAUSES:" -ForegroundColor Yellow
        Write-Host "  • Cloud-init failed to complete successfully" -ForegroundColor White
        Write-Host "  • SSH key was not properly injected into authorized_keys" -ForegroundColor White
        Write-Host "  • File permissions on /home/$Username/.ssh/ are incorrect" -ForegroundColor White
        Write-Host "  • Network connectivity or port forwarding issue" -ForegroundColor White
        Write-Host "  • VM disk ran out of space during initialization" -ForegroundColor White
        Write-Host ""
        Write-Host "  MANUAL TROUBLESHOOTING STEPS:" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  Step 1: Check cloud-init status via VM console" -ForegroundColor Yellow
        Write-Host "    • Right-click VM '$VMName' in Hyper-V Manager → Connect" -ForegroundColor White
        Write-Host "    • Login with username: $Username, password: $Password" -ForegroundColor White
        Write-Host "    • Run: sudo cloud-init status --long" -ForegroundColor Gray
        Write-Host "    • Check for errors: sudo tail -50 /var/log/cloud-init.log" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  Step 2: Verify SSH key was injected" -ForegroundColor Yellow
        Write-Host "    • Run: cat /home/$Username/.ssh/authorized_keys" -ForegroundColor Gray
        Write-Host "    • Should contain: ssh-rsa ...quickquarm@hyperv" -ForegroundColor Gray
        Write-Host "    • Check permissions: ls -la /home/$Username/.ssh/" -ForegroundColor Gray
        Write-Host "    • Should be: drwx------ (700) and -rw------- (600)" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  Step 3: Try password authentication" -ForegroundColor Yellow
        Write-Host "    • Run: ssh -p $sshPort ${Username}@${sshHost}" -ForegroundColor Gray
        Write-Host "    • Password: $Password" -ForegroundColor Gray
        Write-Host "    • If this works, the issue is with SSH key authentication" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  Step 4: Check system resources" -ForegroundColor Yellow
        Write-Host "    • Run: df -h (check disk space)" -ForegroundColor Gray
        Write-Host "    • Run: free -m (check memory)" -ForegroundColor Gray
        Write-Host "    • Run: systemctl status ssh (check SSH service)" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  For more help, check the Quick Quarm documentation or Discord." -ForegroundColor Cyan
        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Red
        Write-Host ""
        exit 1
    }
    
    # Verify cloud-init completed successfully
    Write-Host "  - Verifying cloud-init completed..." -ForegroundColor Gray
    $cloudInitCmd = if ($sshPort -ne 22) {
        "ssh -i $PrivateKeyPath -p $sshPort -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL `"${Username}@${sshHost}`" `"cloud-init status --wait`""
    } else {
        "ssh -i $PrivateKeyPath -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL `"${Username}@${sshHost}`" `"cloud-init status --wait`""
    }
    
    $cloudInitResult = Invoke-Expression $cloudInitCmd 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  + Cloud-init completed successfully" -ForegroundColor Green
    } else {
        Write-Host "  ! Warning: Cloud-init status check failed" -ForegroundColor Yellow
        Write-Host "  Continuing anyway..." -ForegroundColor Gray
    }
    
    # Copy script to VM
    Write-Host "  - Copying installation script to VM..." -ForegroundColor Gray
    & scp -i $PrivateKeyPath -P $sshPort -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL $scriptPath "${Username}@${sshHost}:/tmp/install_qq.sh" 2>&1 | Out-Null
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ! ERROR: Failed to copy installation script to VM" -ForegroundColor Red
        exit 1
    }
    Write-Host "  + Installation script copied" -ForegroundColor Green
    
    # Make script executable and run it
    Write-Host "  - Executing installation on VM..." -ForegroundColor Gray
    Write-Host ""
    
    & ssh -i $PrivateKeyPath -p $sshPort -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL "${Username}@${sshHost}" "chmod +x /tmp/install_qq.sh && /tmp/install_qq.sh"
    
    # Cleanup
    Remove-Item $scriptPath -Force
    
    Write-Host ""
    Write-Host "  + Quick Quarm installation complete" -ForegroundColor Green
}

# Main installation process
try {
    # Check if running as administrator
    if (-not (Test-Administrator)) {
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
    
    # Auto-detect Default Switch network if static IP not provided
    $networkConfig = $null
    if ([string]::IsNullOrEmpty($StaticIP) -or [string]::IsNullOrEmpty($Gateway) -or [string]::IsNullOrEmpty($Netmask)) {
        Write-Host '[STEP 6/8] Auto-detecting Default Switch network...' -ForegroundColor Yellow
        $networkConfig = Get-DefaultSwitchNetworkConfig -PreferredHostID 100
        
        if ($networkConfig) {
            # Use auto-detected values if not provided
            if ([string]::IsNullOrEmpty($StaticIP)) {
                $StaticIP = $networkConfig.StaticIP
            }
            if ([string]::IsNullOrEmpty($Gateway)) {
                $Gateway = $networkConfig.Gateway
            }
            if ([string]::IsNullOrEmpty($Netmask)) {
                $Netmask = $networkConfig.Netmask
            }
            Write-Host "  + Using static IP: $StaticIP/$($networkConfig.PrefixLength)" -ForegroundColor Green
            Write-Host "  + Gateway: $Gateway" -ForegroundColor Green
        }
        else {
            Write-Host "  ! Could not auto-detect network, will use DHCP" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host '[STEP 6/8] Using provided static IP configuration...' -ForegroundColor Yellow
        Write-Host "  + Static IP: $StaticIP" -ForegroundColor Green
        Write-Host "  + Gateway: $Gateway" -ForegroundColor Green
    }
    
    # Create cloud-init ISO with SSH key
    New-CloudInitISO -ISOPath $cloudInitISO -PublicKeyPath "$sshKeyPath.pub" -Username $InstallUser -Password $InstallPassword -StaticIP $StaticIP -Gateway $Gateway -Netmask $Netmask -DNS $DNS
    
    # Create VM
    $vm = New-QuickQuarmVM -Name $VMName -VHDPath $vhdxPath -CloudInitISO $cloudInitISO -Memory $VMMemory -ProcessorCount $VMProcessors
    
    # Start VM and wait for SSH (pass static IP if configured)
    $vmConnection = Start-VMAndWaitForSSH -VMName $VMName -TimeoutSeconds 300 -StaticIP $StaticIP -SSHKeyPath $sshKeyPath -Username $InstallUser
    
    if (-not $vmConnection) {
        Write-Host ""
        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Red
        Write-Host "  VM CONNECTION FAILED" -ForegroundColor Red
        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Could not detect VM IP address or SSH port is not responding" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  POSSIBLE CAUSES:" -ForegroundColor Yellow
        Write-Host "  • VM failed to boot or is still booting" -ForegroundColor White
        Write-Host "  • Network adapter configuration issue" -ForegroundColor White
        Write-Host "  • Hyper-V Default Switch not functioning properly" -ForegroundColor White
        Write-Host "  • DHCP not working (if not using static IP)" -ForegroundColor White
        Write-Host "  • VM disk image is corrupted" -ForegroundColor White
        Write-Host ""
        Write-Host "  MANUAL TROUBLESHOOTING:" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  Step 1: Check VM status in Hyper-V Manager" -ForegroundColor Yellow
        Write-Host "    • Open Hyper-V Manager" -ForegroundColor White
        Write-Host "    • Check if VM '$VMName' is running" -ForegroundColor White
        Write-Host "    • Right-click → Connect to open console" -ForegroundColor White
        Write-Host ""
        Write-Host "  Step 2: Verify network connectivity from VM console" -ForegroundColor Yellow
        Write-Host "    • Login to VM console (username: $InstallUser, password: $InstallPassword)" -ForegroundColor White
        Write-Host "    • Run: ip addr show (check for IP address)" -ForegroundColor Gray
        Write-Host "    • Run: ping -c 4 8.8.8.8 (test internet connectivity)" -ForegroundColor Gray
        Write-Host "    • Run: systemctl status ssh (verify SSH is running)" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  Step 3: Check Hyper-V networking" -ForegroundColor Yellow
        Write-Host "    • In PowerShell (as Admin), run:" -ForegroundColor White
        Write-Host "      Get-VMNetworkAdapter -VMName '$VMName'" -ForegroundColor Gray
        Write-Host "      Get-NetIPAddress -InterfaceAlias 'vEthernet (Default Switch)'" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  Step 4: Try manual SSH connection" -ForegroundColor Yellow
        Write-Host "    • From VM console, get IP: ip addr show | grep 'inet '" -ForegroundColor Gray
        Write-Host "    • From Windows, try: ssh -i `"$sshKeyPath`" ${InstallUser}@<VM_IP>" -ForegroundColor Gray
        Write-Host ""
        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Red
        Write-Host ""
        exit 1
    }
    
    $sshConnection = $vmConnection.ConnectionString
    $vmActualIP = $vmConnection.ActualIP
    
    # Install Quick Quarm via SSH
    Install-QuickQuarmViaSSH -VMIPAddress $sshConnection -ActualVMIP $vmActualIP -Username $InstallUser -Password $InstallPassword -PrivateKeyPath $sshKeyPath -RepoUrl $RepoUrl -DBHost $DBHost -DBName $DBName -DBUser $DBUser -DBPassword $DBPassword
    
    # Wait a moment for services to fully start after installation
    Write-Host ""
    Write-Host "Waiting for services to initialize..." -ForegroundColor Yellow
    Start-Sleep -Seconds 10
    
    # Verify installation
    Write-Host ""
    Write-Host "Verifying installation..." -ForegroundColor Yellow
    try {
        & "$PSScriptRoot\QuarmFixer-HyperV.ps1" -Action Verify -VMName $VMName -SSHKeyPath $sshKeyPath -VMUser $InstallUser -DBUser $DBUser -DBPassword $DBPassword
        if ($LASTEXITCODE -ne 0) {
            Write-Host ""
            Write-Host "Verification failed. Attempting to start services..." -ForegroundColor Yellow
            & "$PSScriptRoot\QuarmFixer-HyperV.ps1" -Action Start -VMName $VMName -SSHKeyPath $sshKeyPath -VMUser $InstallUser
            Write-Host ""
            Write-Host "Re-running verification..." -ForegroundColor Yellow
            & "$PSScriptRoot\QuarmFixer-HyperV.ps1" -Action Verify -VMName $VMName -SSHKeyPath $sshKeyPath -VMUser $InstallUser -DBUser $DBUser -DBPassword $DBPassword
            if ($LASTEXITCODE -ne 0) {
                Write-Host ""
                Write-Host "WARNING: Verification still failed after attempting to start services." -ForegroundColor Yellow
                Write-Host "Services may need manual attention. Check logs with:" -ForegroundColor Yellow
                Write-Host "  .\QuarmFixer-HyperV.ps1 -Action Logs" -ForegroundColor Cyan
                Write-Host ""
            }
        }
    }
    catch {
        Write-Host ""
        Write-Host "WARNING: Verification encountered an error: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "You can manually verify and start services with:" -ForegroundColor Yellow
        Write-Host "  .\QuarmFixer-HyperV.ps1 -Action Start" -ForegroundColor Cyan
        Write-Host ""
    }
    
    # Set up game port forwarding and firewall rules
    Write-Host ""
    Write-Host "Setting up port forwarding for game ports..." -ForegroundColor Yellow
    $portCount = Set-PortForwarding -VMIP $vmActualIP -VerifyConnectivity
    if ($portCount -gt 0) {
        Write-Host "  + Port forwarding configured for $portCount port(s)" -ForegroundColor Green
    } else {
        Write-Host "  ! Warning: Port forwarding configuration had issues" -ForegroundColor Yellow
        Write-Host "    You may need to manually configure port forwarding" -ForegroundColor Yellow
    }
    
    Write-Host "Configuring Windows Firewall..." -ForegroundColor Yellow
    $firewallCount = Set-FirewallRules
    if ($firewallCount -gt 0) {
        Write-Host "  + Firewall rules configured for $firewallCount port(s)" -ForegroundColor Green
    } else {
        Write-Host "  ! Warning: Firewall configuration had issues" -ForegroundColor Yellow
    }
    
    # Get Windows host IP for client configuration
    $hostIP = Get-WindowsHostIPv4
    
    # Save VM configuration for other scripts to use
    if (-not [string]::IsNullOrEmpty($StaticIP)) {
        $configFile = Join-Path $workDir "vm-config.json"
        $vmConfig = @{
            VMName = $VMName
            StaticIP = $StaticIP
            Gateway = $Gateway
            Netmask = $Netmask
            DNS = $DNS
            ActualIP = $vmActualIP
            SSHKeyPath = $sshKeyPath
            InstallUser = $InstallUser
            InstallPassword = $InstallPassword
            DBUser = $DBUser
            DBPassword = $DBPassword
            DBHost = $DBHost
            DBName = $DBName
        }
        
        # Add network config if auto-detected
        if ($networkConfig) {
            $vmConfig.Network = $networkConfig.Network
            $vmConfig.PrefixLength = $networkConfig.PrefixLength
        }
        
        $vmConfig | ConvertTo-Json | Out-File -FilePath $configFile -Encoding UTF8
        Write-Host "  + VM configuration saved to: $configFile" -ForegroundColor Gray
    }
    
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
    Write-Host "  Game Port Forwarding: Configured (ports 6000, 5998, 9000)" -ForegroundColor White
    Write-Host "  Windows Firewall: Configured" -ForegroundColor White
    Write-Host ""
    Write-Host "To connect to VM via SSH:" -ForegroundColor Cyan
    Write-Host "  ssh -i `"$sshKeyPath`" -p 2222 ${InstallUser}@localhost" -ForegroundColor White
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "1. Download TAKP v2.2 Client from PQ Discord #server-files" -ForegroundColor White
    if ($hostIP) {
        Write-Host "2. Edit eqhost.txt and change server to: ${hostIP}:6000" -ForegroundColor White
    } else {
        Write-Host "2. Edit eqhost.txt and change server to: ${vmActualIP}:6000" -ForegroundColor White
        Write-Host "   (Note: Port forwarding configured, but host IP could not be detected)" -ForegroundColor Yellow
    }
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

} finally {
    # Stop transcript logging
    Stop-Transcript
}