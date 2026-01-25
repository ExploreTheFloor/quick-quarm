# Quick Quarm Hyper-V VM Installer

## Overview

This automated PowerShell script creates a Hyper-V virtual machine with Ubuntu 22.04 and installs Quick Quarm, providing a fully isolated environment for running your Project Quarm server.

## Requirements

- **Windows 10/11 Pro, Enterprise, or Education** (Hyper-V is NOT available on Home edition)
- **Administrator privileges**
- **Minimum 8GB RAM** (4GB will be allocated to the VM)
- **60GB free disk space** (for VM disk image)
- **Active internet connection** (for downloading Ubuntu and packages)

## Quick Start

1. Open PowerShell as Administrator
2. Navigate to the Quick Quarm directory
3. Run:
   ```powershell
   .\setup\HyperV\QuarmInstaller-HyperV.ps1
   ```

The script will:
- Enable Hyper-V (if not already enabled)
- Install required tools (Chocolatey, qemu-img, git, xorriso)
- Generate SSH key pair for secure VM access
- Download Ubuntu 22.04 cloud image
- Convert the image to VHDX format
- Create a cloud-init ISO for automated setup
- Create and configure Hyper-V VM
- Start the VM and wait for SSH to be available
- Install Quick Quarm automatically via SSH
- Start the Quick Quarm services

## Advanced Usage

You can customize the installation with parameters:

```powershell
.\setup\HyperV\QuarmInstaller-HyperV.ps1 `
  -VMName "MyQuarmServer" `
  -VMMemory 8GB `
  -VMProcessors 4 `
  -VMDiskSize 80GB `
  -InstallUser "quarm" `
  -InstallPassword "SecurePassword123"
```

### Available Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `VMName` | `QuickQuarm` | Name of the Hyper-V VM |
| `VMMemory` | `4GB` | Amount of RAM to allocate |
| `VMProcessors` | `2` | Number of virtual CPUs |
| `VMDiskSize` | `60GB` | Size of the virtual disk |
| `InstallUser` | `root` | Ubuntu user account |
| `InstallPassword` | `root` | Ubuntu user password |
| `RepoUrl` | SecretsOTheP/EQMacEmu | EQMacEmu repository URL |
| `DBHost` | `localhost` | Database host |
| `DBName` | `quarm` | Database name |
| `DBUser` | `quarm` | Database username |
| `DBPassword` | `quarm` | Database password |
| `UseStaticIP` | `$true` | Use static IP instead of DHCP (auto-detected) |
| `StaticIP` | Auto-detected | Static IP address (auto-detected from Default Switch) |
| `StaticGateway` | Auto-detected | Gateway for static IP (auto-detected) |
| `StaticSubnetMask` | `20` | CIDR notation (20 for Default Switch, 24 for LANs) |
| `StaticDNS` | `8.8.8.8,8.8.4.4` | DNS servers (comma-separated) |

## What Gets Installed

### On Windows Host
- **Chocolatey** - Package manager
- **qemu-img** - Disk image conversion tool
- **git** - Version control (if not already installed)
- **xorriso** - ISO creation tool

### On Ubuntu VM
- **Ubuntu 22.04 LTS** - Server edition (cloud image)
- **Quick Quarm** - Full installation with all dependencies
- **MariaDB** - Database server
- **EQMacEmu** - Compiled server binaries
- **Systemd services** - For automatic server management

## Network Configuration

The script will:
1. Look for the Default Switch (best for Wi-Fi/laptop setups)
2. Look for an existing external Hyper-V switch
3. Create an external switch if none exists (using your first physical network adapter)
4. If no physical adapter is available, create an internal switch

### DHCP vs Static IP

**By default, the VM uses DHCP**, which can cause connectivity issues:
- **DHCP leases expire** if the VM sits idle for extended periods
- The VM may lose network connectivity and require reconfiguration
- Port forwarding may break when the IP changes

**Default behavior:** Uses static IP (auto-detected from your LAN or Default Switch)

**To use DHCP instead (not recommended):**
```powershell
.\setup\HyperV\QuarmInstaller-HyperV.ps1 -UseStaticIP:$false
```

**To override with custom static IP:**
```powershell
.\setup\HyperV\QuarmInstaller-HyperV.ps1 `
  -StaticIP "172.16.0.100" `
  -StaticGateway "172.16.0.1" `
  -StaticSubnetMask "20"
```

**Note:** For Default Switch, use subnet mask `20` (default). For most LANs, use `24`.

## SSH Access

After installation, you can connect to your VM using SSH:

```powershell
ssh -i "$env:USERPROFILE\QuickQuarm-VM\id_rsa" root@<VM_IP>
```

The SSH key pair is stored in: `%USERPROFILE%\QuickQuarm-VM\`

## Managing the VM

### Start/Stop VM

Using Hyper-V Manager GUI:
- Open Hyper-V Manager
- Right-click the VM
- Select Start, Stop, or Shutdown

Using PowerShell:
```powershell
# Start VM
Start-VM -Name QuickQuarm

# Stop VM (graceful shutdown)
Stop-VM -Name QuickQuarm

# Force stop
Stop-VM -Name QuickQuarm -TurnOff

# Check status
Get-VM -Name QuickQuarm
```

### Managing Quick Quarm Services

Connect via SSH first:
```powershell
ssh -i "$env:USERPROFILE\QuickQuarm-VM\id_rsa" root@<VM_IP>
```

Then run commands:
```bash
# Start services
sudo systemctl start quick-quarm.target

# Stop services
sudo systemctl stop quick-quarm.target

# Restart services
sudo systemctl restart quick-quarm.target

# Check status
sudo systemctl status quick-quarm.target

# View logs
journalctl -u quick-quarm.target -f
```

## Connecting with EQ Client

1. Download TAKP v2.2 Client from Project Quarm Discord (#server-files)
2. Install to a separate folder from your main PQ installation
3. Edit `eqhost.txt` file in the client directory
4. Change the line to: `<VM_IP>:6000` (use the VM IP address shown at end of installation)
5. The VM IP is the address to use - NOT your Windows host IP
5. Run the client
6. Login with any username/password
7. Select your Quick Quarm server and create a character

### Grant GM Powers

Connect to the VM via SSH and run:
```bash
cd ~/quick-quarm
./scripts/eq/makegm -l YOUR_LOGIN_ACCOUNT
```

Then in-game, type `/sit` and `/camp login`, then log back in to activate GM powers.

## Troubleshooting

### Network / IP Detection Issues

**Error:** "Could not get VM IP address"

The installer now automatically scans the network to find your VM. If it still fails:
1. **Wait 5 minutes** - First boot takes 3-5 minutes for cloud-init
2. **Run:** `.\Connection-HyperV.ps1 -Action Fix` (it will scan the network)
3. **Run diagnostics:** `.\Diagnose-VMNetwork.ps1`

### Hyper-V Not Available
**Error:** "Hyper-V is not available"
**Solution:** You need Windows 10/11 Pro, Enterprise, or Education. Home edition does not support Hyper-V. Consider using the WSL2 installer instead (`.\setup\WSL\QuarmInstaller.ps1`).

### VM Won't Start
**Check:**
1. Verify Hyper-V is enabled: `Get-WindowsOptionalFeature -FeatureName Microsoft-Hyper-V-All -Online`
2. Check VM state: `Get-VM -Name QuickQuarm`
3. View VM logs in Hyper-V Manager

### SSH Connection Fails
1. VM is running: `Get-VM -Name QuickQuarm`
2. Get VM IP: `Get-VMNetworkAdapter -VMName QuickQuarm | Select-Object IPAddresses`
3. Test SSH port: `Test-NetConnection -ComputerName <VM_IP> -Port 22`
4. Run diagnostics: `.\Diagnose-VMNetwork.ps1`

### Installation Fails
**Check:**
1. Ensure you have administrator privileges
2. Verify internet connection
3. Check disk space (need 60GB+ free)
4. Review error messages in PowerShell output
5. Check logs on VM: `ssh -i "$env:USERPROFILE\QuickQuarm-VM\id_rsa" root@<VM_IP> "sudo journalctl -xe"`

### Can't Connect from EQ Client
**Check:**
1. VM firewall allows connections: `ssh -i "$env:USERPROFILE\QuickQuarm-VM\id_rsa" root@<VM_IP> "sudo ufw status"`
2. Services are running: `ssh -i "$env:USERPROFILE\QuickQuarm-VM\id_rsa" root@<VM_IP> "sudo systemctl status quick-quarm.target"`
3. Verify eqhost.txt has correct IP and port
4. Ensure client is run as Administrator

### VM Stops or Loses Connectivity After Sitting Idle
**Problem:** VM stops responding or loses network connection after being idle for hours/days.

**Causes:**
1. **DHCP lease expiration** - Most common cause
2. **Automatic shutdown settings**
3. **Host power management**

**Solutions:**

1. **Static IP is now the default** - New installations automatically use static IP

2. **Verify automatic shutdown settings**:
   ```powershell
   # Should show "Save" not "ShutDown"
   Get-VM -Name QuickQuarm | Select-Object AutomaticStopAction
   
   # If not set to Save, fix it:
   Set-VM -Name QuickQuarm -AutomaticStopAction Save
   ```

3. **Check port forwarding** (for Default Switch):
   ```powershell
   # View current port forwards
   netsh interface portproxy show v4tov4
   
   # If missing, use Connection-HyperV.ps1 to fix
   .\setup\HyperV\Connection-HyperV.ps1 -Action Fix
   ```

## File Locations

### On Windows Host
- VM files: `%USERPROFILE%\QuickQuarm-VM\`
- SSH keys: `%USERPROFILE%\QuickQuarm-VM\id_rsa` and `id_rsa.pub`
- Ubuntu image: `%USERPROFILE%\QuickQuarm-VM\ubuntu-22.04-server.img`
- VM disk: `%USERPROFILE%\QuickQuarm-VM\QuickQuarm.vhdx`

### On Ubuntu VM
- Quick Quarm: `/root/quick-quarm/`
- Server binaries: `/root/quick-quarm/bin/`
- Logs: `/root/quick-quarm/logs/`
- Database: MariaDB at `localhost:3306`

## Comparison: Hyper-V VM vs WSL2

| Feature | Hyper-V VM | WSL2 |
|---------|------------|------|
| **Isolation** | Full VM isolation | Shared kernel with Windows |
| **Performance** | Native VM performance | Near-native (slightly faster) |
| **Disk Space** | ~60GB | ~20GB |
| **RAM** | Dedicated (e.g., 4GB) | Dynamic (shared with Windows) |
| **Networking** | Separate IP on network | NAT or bridge to Windows |
| **Windows Edition** | Pro/Enterprise/Education | Any (Home, Pro, etc.) |
| **SSH Access** | Yes (key-based) | Yes (but optional) |
| **Backup** | Easy (export VM) | More complex |
| **Snapshots** | Yes (Hyper-V checkpoints) | No |

## Why Choose Hyper-V VM?

**Choose Hyper-V VM if you:**
- Want complete isolation from Windows
- Need to take VM snapshots for easy rollback
- Plan to run the server 24/7 (dedicated resources)
- Want to easily migrate the VM to another host
- Have Windows Pro/Enterprise/Education
- Prefer SSH-based remote management

**Choose WSL2 if you:**
- Have Windows Home edition
- Want lighter weight / less disk usage
- Prefer direct integration with Windows
- Don't need complete isolation
- Want slightly better performance (no VM overhead)

## Updating Quick Quarm

To update Quick Quarm to the latest version:

1. Connect via SSH:
   ```powershell
   ssh -i "$env:USERPROFILE\QuickQuarm-VM\id_rsa" root@<VM_IP>
   ```

2. Run update script:
   ```bash
   cd ~/quick-quarm
   ./scripts/update
   sudo systemctl restart quick-quarm.target
   ```

## Uninstalling

To completely remove the VM and all files:

1. Stop and remove the VM:
   ```powershell
   Stop-VM -Name QuickQuarm -TurnOff
   Remove-VM -Name QuickQuarm -Force
   ```

2. Delete VM files:
   ```powershell
   Remove-Item -Path "$env:USERPROFILE\QuickQuarm-VM" -Recurse -Force
   ```

3. (Optional) Remove installed tools:
   ```powershell
   choco uninstall qemu-img xorriso -y
   ```

## Support

For issues specific to:
- **Quick Quarm**: https://github.com/ryhoneyman/quick-quarm
- **Project Quarm**: Project Quarm Discord server
- **This installer**: Create an issue in the Quick Quarm repository





