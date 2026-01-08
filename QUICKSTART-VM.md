# Quick Start: Hyper-V VM Installation

## Prerequisites

- Windows 10/11 **Pro, Enterprise, or Education** (Hyper-V NOT available on Home edition)
- Administrator privileges
- 8GB RAM (4GB for VM, 4GB for Windows)
- 60GB free disk space
- Active internet connection

## Installation Steps

### Step 1: Open PowerShell as Administrator

1. Press `Win + X`
2. Select "Windows PowerShell (Admin)" or "Terminal (Admin)"

### Step 2: Navigate to Quick Quarm Directory

```powershell
cd D:\Code\GameSpecific\Everquest\quick-quarm
```

*(Adjust path as needed for your installation)*

### Step 3: Run the Installer

```powershell
.\setup\QuarmInstaller-HyperV.ps1
```

### Step 4: Wait for Installation

The script will automatically:
- Enable Hyper-V (requires reboot if not already enabled)
- Install required tools (Chocolatey, qemu-img, git, xorriso)
- Download Ubuntu 22.04 cloud image (~700MB)
- Create Hyper-V VM
- Install Quick Quarm
- Start the server

**Total time: 30-45 minutes**

## What Gets Installed

- **Hyper-V VM** named "QuickQuarm"
  - 4GB RAM
  - 2 virtual CPUs
  - 60GB virtual disk
- **Ubuntu 22.04 LTS** server
- **Quick Quarm** with all dependencies
- **SSH key pair** for secure access (stored in `%USERPROFILE%\QuickQuarm-VM\`)

## After Installation

### Get VM IP Address

```powershell
Get-VMNetworkAdapter -VMName QuickQuarm | Select-Object IPAddresses
```

### Connect via SSH

```powershell
ssh -i "$env:USERPROFILE\QuickQuarm-VM\id_rsa" root@<VM_IP>
```

### Configure EQ Client

1. Download TAKP v2.2 Client from Project Quarm Discord (#server-files)
2. Extract to a new folder (separate from your main PQ installation)
3. Edit `eqhost.txt` and change the line to:
   ```
   <VM_IP>:6000
   ```
   (Replace `<VM_IP>` with the actual IP address from the installation output)
4. Run the EQ client
5. Login with any username/password (will fail first time - this is expected)
6. Press ENTER again to login
7. Select your Quick Quarm server
8. Create a character and enter the world!

### Grant GM Powers

Connect to VM:
```powershell
ssh -i "$env:USERPROFILE\QuickQuarm-VM\id_rsa" root@<VM_IP>
```

Grant GM:
```bash
cd ~/quick-quarm
./scripts/eq/makegm -l YOUR_LOGIN_ACCOUNT
```

In-game, type `/sit` and `/camp login`, then log back in to activate powers.

## Managing the Server

### Start/Stop VM

```powershell
# Start VM
Start-VM -Name QuickQuarm

# Stop VM (graceful)
Stop-VM -Name QuickQuarm

# Force stop
Stop-VM -Name QuickQuarm -TurnOff

# Check status
Get-VM -Name QuickQuarm
```

### Start/Stop Quick Quarm Services (via SSH)

```bash
# Start
sudo systemctl start quick-quarm.target

# Stop
sudo systemctl stop quick-quarm.target

# Restart
sudo systemctl restart quick-quarm.target

# Check status
sudo systemctl status quick-quarm.target
```

## Customizing Installation

You can customize the VM configuration:

```powershell
.\setup\QuarmInstaller-HyperV.ps1 `
  -VMName "MyCustomName" `
  -VMMemory 8GB `
  -VMProcessors 4 `
  -InstallUser "quarm" `
  -InstallPassword "MySecurePassword"
```

## Troubleshooting

### "Hyper-V is not available"

**Solution:** You need Windows Pro/Enterprise/Education. Home edition doesn't support Hyper-V. Use the WSL2 installer instead:
```powershell
.\setup\QuarmInstaller.ps1
```

### "Script requires Administrator"

**Solution:** Right-click PowerShell and select "Run as Administrator"

### VM Won't Start

**Check Hyper-V status:**
```powershell
Get-WindowsOptionalFeature -FeatureName Microsoft-Hyper-V-All -Online
```

### Can't Connect via SSH

**Get VM IP:**
```powershell
Get-VMNetworkAdapter -VMName QuickQuarm | Select-Object IPAddresses
```

**Test SSH:**
```powershell
Test-NetConnection -ComputerName <VM_IP> -Port 22
```

### EQ Client Can't Connect

1. Verify Quick Quarm services are running (SSH to VM and check)
2. Verify `eqhost.txt` has correct IP
3. Ensure client is run as Administrator
4. Check Windows Firewall isn't blocking the connection

## Updating Quick Quarm

SSH to VM and run:
```bash
cd ~/quick-quarm
./scripts/update
sudo systemctl restart quick-quarm.target
```

## Uninstalling

### Remove VM and Files

```powershell
Stop-VM -Name QuickQuarm -TurnOff
Remove-VM -Name QuickQuarm -Force
Remove-Item -Path "$env:USERPROFILE\QuickQuarm-VM" -Recurse -Force
```

### (Optional) Remove Tools

```powershell
choco uninstall qemu-img xorriso -y
```

## Need Help?

- **Quick Quarm Issues:** https://github.com/ryhoneyman/quick-quarm
- **Project Quarm:** Discord server
- **Hyper-V Help:** `Get-Help about_Hyper-V` in PowerShell

## File Locations

- **VM Files:** `%USERPROFILE%\QuickQuarm-VM\`
- **SSH Keys:** `%USERPROFILE%\QuickQuarm-VM\id_rsa` (private) and `id_rsa.pub` (public)
- **Ubuntu Image:** `%USERPROFILE%\QuickQuarm-VM\ubuntu-22.04-server.img`
- **VM Disk:** `%USERPROFILE%\QuickQuarm-VM\QuickQuarm.vhdx`
- **Quick Quarm (on VM):** `/root/quick-quarm/`
- **Server Logs (on VM):** `/root/quick-quarm/logs/`

## Why Choose Hyper-V VM?

✅ Complete isolation from Windows  
✅ Dedicated resources  
✅ Easy to snapshot/backup  
✅ Can migrate to other Hyper-V hosts  
✅ SSH key-based authentication  
✅ Professional-grade virtualization  

## Alternative: WSL2 Installation

If you have Windows Home, or prefer a lighter-weight option, use the WSL2 installer:
```powershell
.\setup\QuarmInstaller.ps1
```

See `README.md` for more details.





