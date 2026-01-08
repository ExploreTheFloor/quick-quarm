# Quick Quarm Hyper-V Management Scripts

This directory contains PowerShell scripts for managing your Quick Quarm Hyper-V VM.

## Scripts Overview

### 1. QuarmInstaller-HyperV.ps1
**Purpose:** Complete installation of Quick Quarm on a Hyper-V VM

**Usage:**
```powershell
# Run as Administrator
.\QuarmInstaller-HyperV.ps1
```

**What it does:**
- Enables Hyper-V if not already enabled
- Installs required tools (qemu-img, git, oscdimg)
- Downloads Ubuntu 22.04 cloud image
- Creates and configures a Hyper-V VM
- Installs Quick Quarm server inside the VM
- Sets up port forwarding for network access

**Requirements:**
- Windows 10/11 Pro, Enterprise, or Education
- Administrator privileges
- 4GB+ RAM available
- 20GB+ disk space

---

### 2. Manage-QuarmVM.ps1
**Purpose:** Control and monitor the Quick Quarm VM

**Usage:**
```powershell
# Start the VM
.\Manage-QuarmVM.ps1 -Action Start

# Stop the VM
.\Manage-QuarmVM.ps1 -Action Stop

# Restart the VM
.\Manage-QuarmVM.ps1 -Action Restart

# Check VM status
.\Manage-QuarmVM.ps1 -Action Status

# Connect to VM via SSH
.\Manage-QuarmVM.ps1 -Action SSH

# View Quick Quarm logs
.\Manage-QuarmVM.ps1 -Action Logs
```

**Examples:**
```powershell
# Check if server is running
.\Manage-QuarmVM.ps1 -Action Status

# Restart the VM after making changes
.\Manage-QuarmVM.ps1 -Action Restart

# Connect to VM to run commands
.\Manage-QuarmVM.ps1 -Action SSH
```

---

### 3. Connection-HyperV.ps1
**Purpose:** Diagnose and fix network connectivity issues

**Usage:**
```powershell
# Check connection status
.\Connection-HyperV.ps1 -Action Diagnose

# Fix connection issues (run as Administrator)
.\Connection-HyperV.ps1 -Action Fix

# Undo connection fixes (run as Administrator)
.\Connection-HyperV.ps1 -Action Undo
```

**When to use:**
- Cannot connect to server from EQ client
- Port forwarding not working
- Firewall blocking connections

**What Fix does:**
- Sets up port forwarding for ports 6000, 5998, 9000
- Configures Windows Firewall rules
- Updates VM network configuration

---

### 4. QuarmUninstaller-HyperV.ps1
**Purpose:** Complete removal of Quick Quarm VM

**Usage:**
```powershell
# Run as Administrator
.\QuarmUninstaller-HyperV.ps1
```

**What it removes:**
- Hyper-V VM
- VM files and SSH keys
- Port forwarding rules
- Windows Firewall rules

**Warning:** This will delete the VM and all data inside it. Make backups if needed!

---

## Common Workflows

### First Time Setup
```powershell
# 1. Install Quick Quarm
.\QuarmInstaller-HyperV.ps1

# 2. Wait for installation to complete (15-25 minutes)

# 3. Check status
.\Manage-QuarmVM.ps1 -Action Status

# 4. If connection issues, run Fix
.\Connection-HyperV.ps1 -Action Fix
```

### Daily Use
```powershell
# Start server
.\Manage-QuarmVM.ps1 -Action Start

# Check if running
.\Manage-QuarmVM.ps1 -Action Status

# Stop server when done
.\Manage-QuarmVM.ps1 -Action Stop
```

### Troubleshooting
```powershell
# Check for issues
.\Connection-HyperV.ps1 -Action Diagnose

# View logs
.\Manage-QuarmVM.ps1 -Action Logs

# Connect to VM directly
.\Manage-QuarmVM.ps1 -Action SSH

# Inside VM, check services:
systemctl status quick-quarm.target
```

### Reinstalling
```powershell
# 1. Uninstall
.\QuarmUninstaller-HyperV.ps1

# 2. Reinstall
.\QuarmInstaller-HyperV.ps1
```

---

## File Locations

- **VM Files:** `C:\Users\Laptop\QuickQuarm-VM\`
- **SSH Key:** `C:\Users\Laptop\QuickQuarm-VM\id_rsa`
- **VHDX (VM Disk):** `C:\Users\Laptop\QuickQuarm-VM\QuickQuarm.vhdx`

---

## Network Configuration

The VM uses Hyper-V's network switches (in priority order):

1. **Default Switch** (preferred)
   - NAT network with automatic DHCP
   - Port forwarding required for host access
   - Works with Wi-Fi

2. **External Switch** (fallback)
   - Bridges to physical network adapter
   - VM gets IP from network DHCP
   - Requires wired connection

3. **Internal Switch** (last resort)
   - VM-to-host only, no internet
   - Not recommended

Port forwarding maps host ports to VM:
- `0.0.0.0:6000` → `VM:6000` (Login Server - UDP)
- `0.0.0.0:5998` → `VM:5998` (Login Server - TCP)
- `0.0.0.0:9000` → `VM:9000` (World Server)
- `0.0.0.0:2222` → `VM:22` (SSH)

---

## Connecting from EQ Client

1. Get your Windows host IP:
   ```powershell
   .\Manage-QuarmVM.ps1 -Action Status
   # Look for "Windows Host IP" in output
   ```

2. Edit `eqhost.txt` in your EQ client directory:
   ```
   [LoginServer]
   Host=YOUR_HOST_IP:6000
   ```

3. Launch EQ client and connect

---

## Tips

- **VM Won't Start:** Check if Hyper-V is enabled in Windows Features
- **No Network Access:** Run `.\Connection-HyperV.ps1 -Action Fix`
- **Slow Performance:** Increase VM memory in Hyper-V Manager
- **Can't SSH:** Check that SSH key exists in `C:\Users\Laptop\QuickQuarm-VM\id_rsa`
- **Port Forwarding Lost:** Run `.\Connection-HyperV.ps1 -Action Fix` after VM restarts

---

## Differences from WSL2 Version

| Feature | WSL2 | Hyper-V |
|---------|------|---------|
| Installation | Faster | Slower (downloads image) |
| RAM Usage | Lower | Higher |
| Network Setup | Simpler | Requires port forwarding |
| Wi-Fi Support | Yes | Yes (via Default Switch) |
| SSH Access | Direct | Via port forwarding |
| File Sharing | Easy (`\\wsl$`) | SSH/SCP only |
| Snapshots | No | Yes (via Hyper-V Manager) |

---

## Getting Help

If you encounter issues:

1. Run diagnostics: `.\Connection-HyperV.ps1 -Action Diagnose`
2. Check VM status: `.\Manage-QuarmVM.ps1 -Action Status`
3. View logs: `.\Manage-QuarmVM.ps1 -Action Logs`
4. Connect to VM: `.\Manage-QuarmVM.ps1 -Action SSH`

For more information, see the main Quick Quarm documentation.




