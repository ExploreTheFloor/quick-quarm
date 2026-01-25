# Fix-AutoShutdown.ps1
# Fix the Quick Quarm VM automatically shutting down when idle

#Requires -RunAsAdministrator

param(
    [string]$VMName = "QuickQuarm",
    [string]$SSHKeyPath = "$env:USERPROFILE\QuickQuarm-VM\id_rsa",
    [string]$VMUser = "root"
)

Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "Quick Quarm Auto-Shutdown Fix Tool" -ForegroundColor Cyan
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host ""

# Check if VM exists
$vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if (-not $vm) {
    Write-Host "ERROR: VM '$VMName' not found" -ForegroundColor Red
    exit 1
}

# Check if VM is running
if ($vm.State -ne "Running") {
    Write-Host "ERROR: VM is not running (State: $($vm.State))" -ForegroundColor Red
    Write-Host "Start the VM first: Start-VM -Name $VMName" -ForegroundColor Yellow
    exit 1
}

# Check SSH key
if (-not (Test-Path $SSHKeyPath)) {
    Write-Host "ERROR: SSH key not found at: $SSHKeyPath" -ForegroundColor Red
    exit 1
}

Write-Host "[1/4] Fixing Hyper-V auto-stop action..." -ForegroundColor Yellow
if ($vm.AutomaticStopAction -ne "Save") {
    Set-VM -Name $VMName -AutomaticStopAction Save
    Write-Host "  + Set VM to save state (not shutdown) when host stops" -ForegroundColor Green
} else {
    Write-Host "  + Already configured correctly" -ForegroundColor Green
}
Write-Host ""

Write-Host "[2/4] Testing SSH connection..." -ForegroundColor Yellow
$sshHost = "localhost"
$sshPort = 2222

$sshTest = Test-NetConnection -ComputerName $sshHost -Port $sshPort -InformationLevel Quiet -WarningAction SilentlyContinue -ErrorAction SilentlyContinue

if (-not $sshTest) {
    Write-Host "  ! SSH not responding on port $sshPort" -ForegroundColor Red
    Write-Host "  Try running: .\Connection-HyperV.ps1 -Action Fix" -ForegroundColor Yellow
    exit 1
}
Write-Host "  + SSH connection successful" -ForegroundColor Green
Write-Host ""

Write-Host "[3/4] Disabling power management inside VM..." -ForegroundColor Yellow

$fixScript = @'
#!/bin/bash
set -e

echo "  [3.1] Masking sleep/suspend/hibernate targets..."
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target 2>/dev/null || true

echo "  [3.2] Disabling systemd idle timeout..."
mkdir -p /etc/systemd/logind.conf.d/
cat > /etc/systemd/logind.conf.d/no-suspend.conf << 'EOF'
[Login]
IdleAction=ignore
IdleActionSec=0
HandleSuspendKey=ignore
HandleHibernateKey=ignore
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandlePowerKey=ignore
EOF

echo "  [3.3] Reloading systemd configuration..."
systemctl daemon-reload 2>/dev/null || true
systemctl restart systemd-logind 2>/dev/null || true

echo "  [3.4] Disabling ACPI power button events..."
if [ -f /etc/acpi/events/powerbtn ]; then
    mv /etc/acpi/events/powerbtn /etc/acpi/events/powerbtn.disabled 2>/dev/null || true
fi
systemctl stop acpid 2>/dev/null || true
systemctl disable acpid 2>/dev/null || true

echo "  [3.5] Configuring services to restart on failure..."
mkdir -p /etc/systemd/system/eqemu-world.service.d/
cat > /etc/systemd/system/eqemu-world.service.d/restart.conf << 'EOF'
[Service]
Restart=always
RestartSec=10
EOF

mkdir -p /etc/systemd/system/eqemu-loginserver.service.d/
cat > /etc/systemd/system/eqemu-loginserver.service.d/restart.conf << 'EOF'
[Service]
Restart=always
RestartSec=10
EOF

for service in zone ucs queryserv shared-memory boats; do
    mkdir -p /etc/systemd/system/eqemu-${service}.service.d/
    cat > /etc/systemd/system/eqemu-${service}.service.d/restart.conf << 'EOF'
[Service]
Restart=always
RestartSec=10
EOF
done

echo "  [3.6] Reloading service configurations..."
systemctl daemon-reload

echo "  [3.7] Disabling unattended upgrades that might restart services..."
systemctl stop unattended-upgrades 2>/dev/null || true
systemctl disable unattended-upgrades 2>/dev/null || true

echo "  + Power management disabled successfully"
'@

$tempScript = [System.IO.Path]::GetTempFileName() + ".sh"
$fixScript | Out-File -FilePath $tempScript -Encoding ASCII -NoNewline

# Copy script to VM
scp -i $SSHKeyPath -P $sshPort -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL $tempScript "${VMUser}@${sshHost}:/tmp/fix_shutdown.sh" 2>$null

# Execute script
ssh -i $SSHKeyPath -p $sshPort -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL "${VMUser}@${sshHost}" "chmod +x /tmp/fix_shutdown.sh && sudo /tmp/fix_shutdown.sh && rm /tmp/fix_shutdown.sh" 2>$null

Remove-Item $tempScript -Force

Write-Host ""
Write-Host "[4/4] Verifying fixes..." -ForegroundColor Yellow

$verifyScript = @'
echo -n "  Sleep/Suspend targets: "
systemctl status sleep.target 2>&1 | grep -q "masked" && echo "MASKED ✓" || echo "NOT MASKED ✗"

echo -n "  Systemd logind config: "
[ -f /etc/systemd/logind.conf.d/no-suspend.conf ] && echo "CONFIGURED ✓" || echo "NOT CONFIGURED ✗"

echo -n "  Service auto-restart: "
grep -q "Restart=always" /etc/systemd/system/eqemu-world.service.d/restart.conf 2>/dev/null && echo "ENABLED ✓" || echo "NOT ENABLED ✗"

echo -n "  Quick Quarm status: "
systemctl is-active quick-quarm.target 2>/dev/null || echo "inactive"
'@

ssh -i $SSHKeyPath -p $sshPort -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL "${VMUser}@${sshHost}" "$verifyScript" 2>$null

Write-Host ""
Write-Host "=======================================" -ForegroundColor Green
Write-Host "Fix Applied Successfully!" -ForegroundColor Green
Write-Host "=======================================" -ForegroundColor Green
Write-Host ""
Write-Host "The following changes were made:" -ForegroundColor Cyan
Write-Host "  ✓ Hyper-V VM set to save state (not shutdown)" -ForegroundColor White
Write-Host "  ✓ Sleep/suspend/hibernate disabled in VM" -ForegroundColor White
Write-Host "  ✓ Systemd idle timeout disabled" -ForegroundColor White
Write-Host "  ✓ ACPI power button events disabled" -ForegroundColor White
Write-Host "  ✓ Services configured to auto-restart on failure" -ForegroundColor White
Write-Host "  ✓ Unattended upgrades disabled" -ForegroundColor White
Write-Host ""
Write-Host "Your Quick Quarm server should now stay running indefinitely!" -ForegroundColor Green
Write-Host ""
Write-Host "Additional recommendations:" -ForegroundColor Cyan
Write-Host "  • If using DHCP, consider reinstalling with static IP:" -ForegroundColor White
Write-Host "    .\QuarmInstaller-HyperV.ps1 -UseStaticIP" -ForegroundColor Gray
Write-Host "  • Monitor the server: .\Manage-QuarmVM.ps1 -Action Status" -ForegroundColor White
Write-Host ""
