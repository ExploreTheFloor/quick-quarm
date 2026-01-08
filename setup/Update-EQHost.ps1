# Update EQ Host Configuration Script
# This script finds the Quick Quarm server IP and updates the eqhost.txt file in your TAKP client directory

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Quick Quarm - Update EQ Host File" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Function to get the eqemu server IP
function Get-EQemuIP {
    # Method 1: Try to read from WSL configuration file
    try {
        $envContent = wsl -d Ubuntu-22.04 cat /root/quick-quarm/etc/.env 2>&1
        if ($LASTEXITCODE -eq 0 -and $envContent) {
            $hostipLine = $envContent | Select-String -Pattern "^export HOSTIP=" | Select-Object -First 1
            if ($hostipLine) {
                $ip = $hostipLine.ToString() -replace '^export HOSTIP=', '' -replace "'", "" -replace '"', ''
                if ($ip -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
                    Write-Host "  Found IP in Quick Quarm config: $ip" -ForegroundColor Green
                    return $ip
                }
            }
        }
    }
    catch {
        # Continue to next method
    }
    
    # Method 2: Detect from network adapter
    Write-Host "  Detecting IP from network adapter..." -ForegroundColor Gray
    $hostIP = (Get-NetIPAddress -AddressFamily IPv4 | 
               Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' } | 
               Select-Object -First 1).IPAddress
    
    if ($hostIP) {
        Write-Host "  Detected IP from network: $hostIP" -ForegroundColor Green
        return $hostIP
    }
    
    # Fallback
    return "192.168.1.100"
}

# Get the server IP
$serverIP = Get-EQemuIP

Write-Host ""
Write-Host "Quick Quarm Server IP: $serverIP" -ForegroundColor Cyan
Write-Host ""

# Prompt for EQ directory
Write-Host "Please enter the full path to your TAKP client directory" -ForegroundColor Yellow
Write-Host "Example: C:\Games\TAKP" -ForegroundColor Gray
Write-Host ""
$eqDir = Read-Host "TAKP Client Path"

# Validate directory
if (-not (Test-Path $eqDir)) {
    Write-Host ""
    Write-Host "ERROR: Directory not found: $eqDir" -ForegroundColor Red
    Write-Host ""
    exit 1
}

$eqhostFile = Join-Path $eqDir "eqhost.txt"

# Check if eqhost.txt exists
if (Test-Path $eqhostFile) {
    Write-Host ""
    Write-Host "Found existing eqhost.txt" -ForegroundColor Green
    
    # Show current content
    $currentContent = Get-Content $eqhostFile -Raw
    Write-Host "Current content:" -ForegroundColor Gray
    Write-Host "  $($currentContent.Trim())" -ForegroundColor White
    
    # Create backup
    $backupFile = "$eqhostFile.backup"
    Copy-Item $eqhostFile $backupFile -Force
    Write-Host "Created backup: $backupFile" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "eqhost.txt not found - will create new file" -ForegroundColor Yellow
}

# Update the file
$newContent = "${serverIP}:6000"
Set-Content -Path $eqhostFile -Value $newContent -NoNewline

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "SUCCESS!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Updated eqhost.txt to: $newContent" -ForegroundColor Cyan
Write-Host "File location: $eqhostFile" -ForegroundColor Gray
Write-Host ""
Write-Host "Next steps:" -ForegroundColor White
Write-Host "  1. Launch your TAKP client (run as Administrator)" -ForegroundColor Gray
Write-Host "  2. Login with any username/password (first attempt will fail - this is normal)" -ForegroundColor Gray
Write-Host "  3. Click OK and press ENTER again" -ForegroundColor Gray
Write-Host "  4. You should see your Quick Quarm server in the list" -ForegroundColor Gray
Write-Host "  5. Select it, create a character, and enter the world" -ForegroundColor Gray
Write-Host ""
Write-Host "To grant GM powers after logging in:" -ForegroundColor White
Write-Host "  wsl -d Ubuntu-22.04" -ForegroundColor Gray
Write-Host "  cd ~/quick-quarm && ./scripts/eq/makegm -l YOUR_LOGIN_NAME" -ForegroundColor Gray
Write-Host ""

