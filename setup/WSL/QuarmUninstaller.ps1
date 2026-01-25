# Quick Quarm Uninstallation Script for Windows (WSL2)
# This script removes Quick Quarm installation components

#Requires -RunAsAdministrator

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

# Function to check if Ubuntu 22.04 is installed
function Test-Ubuntu2204 {
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
        $distrosRaw = wsl -l -v 2>&1
        $distros = if ($distrosRaw -is [string]) { $distrosRaw } else { $distrosRaw | Out-String }
        $distrosStr = $distros.ToString().ToLower()
        
        $noSpaces = $distrosStr -replace '\s', ''
        if ($noSpaces.Contains("ubuntu-22.04")) {
            return $true
        }
        
        $lines = $distrosStr -split "`r?`n"
        foreach ($line in $lines) {
            $lineNoSpaces = $line -replace '\s', ''
            if ($lineNoSpaces.Contains("ubuntu-22.04")) {
                return $true
            }
        }
        
        if ($distrosStr.Contains("ubuntu-22.04") -or ($distrosStr.Contains("ubuntu") -and $distrosStr.Contains("22.04"))) {
            return $true
        }
        
        if ($distrosStr -match "ubuntu-22\.04" -or $distrosStr -match "ubuntu.*22\.04") {
            return $true
        }
        
        return $false
    }
    catch {
        return $false
    }
}

# Function to check if Ubuntu 22.04 is functional
function Test-Ubuntu2204Functional {
    if (-not (Test-Ubuntu2204)) {
        return $false
    }
    
    try {
        $testResult = wsl -d Ubuntu-22.04 echo "test" 2>&1
        if ($LASTEXITCODE -eq 0 -and $testResult -notmatch "error" -and $testResult -notmatch "not found" -and $testResult -notmatch "not registered") {
            return $true
        }
        return $false
    }
    catch {
        return $false
    }
}

# Function to check if Quick Quarm services are installed
function Test-QuickQuarmServices {
    $requiredServices = @(
        "quick-quarm.target",
        "eqemu-shared-memory.service",
        "eqemu-loginserver.service",
        "eqemu-ucs.service",
        "eqemu-queryserv.service",
        "eqemu-world.service",
        "eqemu-zone.service",
        "eqemu-boats.service"
    )
    
    $foundServices = @()
    
    try {
        foreach ($service in $requiredServices) {
            $result = wsl -d Ubuntu-22.04 -u root -- systemctl list-unit-files $service 2>&1 | Out-String
            if ($result -match $service) {
                $foundServices += $service
            }
        }
        return $foundServices
    }
    catch {
        return @()
    }
}

# Function to check if Quick Quarm repository exists
function Test-QuickQuarmRepository {
    try {
        $result = wsl -d Ubuntu-22.04 -u root -- test -d /root/quick-quarm 2>&1
        return $LASTEXITCODE -eq 0
    }
    catch {
        return $false
    }
}

# Function to check if database exists
function Test-QuickQuarmDatabase {
    param([string]$DBName = "quarm")
    
    try {
        # Check if MySQL is available at all
        $mysqlCheck = wsl -d Ubuntu-22.04 -u root -- bash -c "test -x /usr/bin/mysql && echo 'ok' || echo 'notfound'" 2>&1 | Out-String
        if ($mysqlCheck.Trim() -ne "ok") {
            return $false
        }
        
        # Try to read database credentials from .env file if it exists
        $envFile = "/root/quick-quarm/etc/.env"
        $dbUser = $null
        $dbPass = $null
        
        $envExists = wsl -d Ubuntu-22.04 -u root -- bash -c "test -f $envFile && echo 'yes' || echo 'no'" 2>&1 | Out-String
        if ($envExists.Trim() -eq "yes") {
            # Extract DBUSER and DBPASS from .env file
            $envContent = wsl -d Ubuntu-22.04 -u root -- bash -c "cat $envFile 2>/dev/null" | Out-String
            
            if ($envContent -match "export DBUSER='([^']+)'") {
                $dbUser = $matches[1]
            }
            elseif ($envContent -match "export DBUSER=([^\s]+)") {
                $dbUser = $matches[1]
            }
            
            if ($envContent -match "export DBPASS='([^']+)'") {
                $dbPass = $matches[1]
            }
            elseif ($envContent -match "export DBPASS=([^\s]+)") {
                $dbPass = $matches[1]
            }
        }
        
        # Method 1: List all databases and search for our database (simplest and most reliable)
        # This works regardless of authentication method
        $dbListOutput = wsl -d Ubuntu-22.04 -u root -- bash -c "/usr/bin/mysql -uroot -e 'SHOW DATABASES;' 2>&1" 2>&1
        $dbList = $dbListOutput | Out-String
        
        # Check if we got a valid database list (not an error)
        if ($dbList -and $dbList -notmatch "ERROR" -and $dbList -notmatch "Access denied" -and $dbList -notmatch "command not found") {
            # Look for the database name as a whole word on its own line
            $lines = $dbList -split "`r?`n"
            foreach ($line in $lines) {
                $trimmedLine = $line.Trim()
                if ($trimmedLine -eq $DBName) {
                    return $true
                }
            }
        }
        
        # Method 2: Try connecting with database user credentials (if we have them)
        if ($dbUser -and $dbPass) {
            $testCmd = "export MYSQL_PWD='$dbPass'; /usr/bin/mysql -u$dbUser $DBName -e 'SELECT 1;' >/dev/null 2>&1; echo `$?"
            $result = wsl -d Ubuntu-22.04 -u root -- bash -c $testCmd 2>&1 | Out-String
            if ($result.Trim() -eq "0") {
                return $true
            }
        }
        
        # Method 3: Try connecting as root (no password)
        $testCmd = "/usr/bin/mysql -uroot -e 'USE $DBName; SELECT 1;' >/dev/null 2>&1; echo `$?"
        $result = wsl -d Ubuntu-22.04 -u root -- bash -c $testCmd 2>&1 | Out-String
        if ($result.Trim() -eq "0") {
            return $true
        }
        
        # Method 4: Try with root and common passwords
        $commonPasswords = @("root", "quarm", "")
        foreach ($pwd in $commonPasswords) {
            if ($pwd -eq "") {
                $testCmd = "/usr/bin/mysql -uroot -e 'USE $DBName; SELECT 1;' >/dev/null 2>&1; echo `$?"
            } else {
                $testCmd = "/usr/bin/mysql -uroot -p$pwd -e 'USE $DBName; SELECT 1;' >/dev/null 2>&1; echo `$?"
            }
            $result = wsl -d Ubuntu-22.04 -u root -- bash -c $testCmd 2>&1 | Out-String
            if ($result.Trim() -eq "0") {
                return $true
            }
        }
        
        return $false
    }
    catch {
        return $false
    }
}

# Function to check for cloud-init configuration
function Test-CloudInitConfig {
    $userHome = $env:USERPROFILE
    $cloudInitDir = Join-Path $userHome ".cloud-init"
    $userDataFile = Join-Path $cloudInitDir "Ubuntu-22.04.user-data"
    
    $found = @()
    if (Test-Path $cloudInitDir) {
        $found += $cloudInitDir
    }
    if (Test-Path $userDataFile) {
        $found += $userDataFile
    }
    
    return $found
}

# Function to stop and remove Quick Quarm services
function Remove-QuickQuarmServices {
    param([bool]$ShouldRemove = $true)
    
    Write-Host "[STEP 1/6] Removing Quick Quarm systemd services..." -ForegroundColor Yellow
    
    if (-not $ShouldRemove) {
        Add-UninstallResult -ComponentName "Systemd Services" -Status "Skipped" -Message "Service removal not requested"
        Write-Host "  - Skipping service removal" -ForegroundColor Gray
        return
    }
    
    if (-not (Test-Ubuntu2204Functional)) {
        Add-UninstallResult -ComponentName "Systemd Services" -Status "Skipped" -Message "Ubuntu 22.04 is not functional, cannot remove services"
        Write-Host "  ! Ubuntu 22.04 is not functional, skipping service removal" -ForegroundColor Yellow
        return
    }
    
    $services = Test-QuickQuarmServices
    
    if ($services.Count -eq 0) {
        Add-UninstallResult -ComponentName "Systemd Services" -Status "Not Found" -Message "No Quick Quarm services found"
        Write-Host "  [OK] No Quick Quarm services found" -ForegroundColor Green
        return
    }
    
    Write-Host "  - Found $($services.Count) service(s) to remove" -ForegroundColor Gray
    
    # Stop services first
    Write-Host "  - Stopping services..." -ForegroundColor Gray
    try {
        wsl -d Ubuntu-22.04 -u root -- systemctl stop quick-quarm.target 2>&1 | Out-Null
        Start-Sleep -Seconds 2
    }
    catch {
        # Continue even if stop fails
    }
    
    # Disable and remove each service
    $removedCount = 0
    $failedServices = @()
    
    foreach ($service in $services) {
        try {
            # Disable service
            wsl -d Ubuntu-22.04 -u root -- systemctl disable $service 2>&1 | Out-Null
            
            # Remove service file
            $serviceFile = "/lib/systemd/system/$service"
            wsl -d Ubuntu-22.04 -u root -- rm -f $serviceFile 2>&1 | Out-Null
            
            $removedCount++
        }
        catch {
            $failedServices += $service
        }
    }
    
    # Reload systemd daemon
    try {
        wsl -d Ubuntu-22.04 -u root -- systemctl daemon-reload 2>&1 | Out-Null
    }
    catch {
        # Continue
    }
    
    if ($failedServices.Count -gt 0) {
        Add-UninstallResult -ComponentName "Systemd Services" -Status "Failed" -Message "Removed $removedCount/$($services.Count) services. Failed: $($failedServices -join ', ')"
        Write-Host "  ! Removed $removedCount/$($services.Count) services" -ForegroundColor Yellow
        Write-Host "    Failed to remove: $($failedServices -join ', ')" -ForegroundColor Red
    }
    else {
        Add-UninstallResult -ComponentName "Systemd Services" -Status "Removed" -Message "Successfully removed $removedCount service(s)"
        Write-Host "  [OK] Successfully removed $removedCount service(s)" -ForegroundColor Green
    }
}

# Function to remove Quick Quarm repository
function Remove-QuickQuarmRepository {
    param([bool]$ShouldRemove = $true)
    
    Write-Host "[STEP 2/6] Removing Quick Quarm repository..." -ForegroundColor Yellow
    
    if (-not $ShouldRemove) {
        Add-UninstallResult -ComponentName "Quick Quarm Repository" -Status "Skipped" -Message "Repository removal not requested"
        Write-Host "  - Skipping repository removal" -ForegroundColor Gray
        return
    }
    
    if (-not (Test-Ubuntu2204Functional)) {
        Add-UninstallResult -ComponentName "Quick Quarm Repository" -Status "Skipped" -Message "Ubuntu 22.04 is not functional, cannot remove repository"
        Write-Host "  ! Ubuntu 22.04 is not functional, skipping repository removal" -ForegroundColor Yellow
        return
    }
    
    if (-not (Test-QuickQuarmRepository)) {
        Add-UninstallResult -ComponentName "Quick Quarm Repository" -Status "Not Found" -Message "Repository directory /root/quick-quarm does not exist"
        Write-Host "  [OK] Repository not found" -ForegroundColor Green
        return
    }
    
    Write-Host "  - Removing /root/quick-quarm directory..." -ForegroundColor Gray
    
    try {
        wsl -d Ubuntu-22.04 -u root -- rm -rf /root/quick-quarm 2>&1 | Out-Null
        Start-Sleep -Seconds 1
        
        # Verify removal
        if (-not (Test-QuickQuarmRepository)) {
            Add-UninstallResult -ComponentName "Quick Quarm Repository" -Status "Removed" -Message "Successfully removed /root/quick-quarm"
            Write-Host "  [OK] Repository removed successfully" -ForegroundColor Green
        }
        else {
            Add-UninstallResult -ComponentName "Quick Quarm Repository" -Status "Failed" -Message "Directory still exists after removal attempt"
            Write-Host "  ! Failed to remove repository" -ForegroundColor Red
        }
    }
    catch {
        Add-UninstallResult -ComponentName "Quick Quarm Repository" -Status "Failed" -Message "Error: $($_.Exception.Message)"
        Write-Host "  ! Error removing repository: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Function to remove database
function Remove-QuickQuarmDatabase {
    param([bool]$ShouldRemove)
    
    Write-Host "[STEP 3/6] Removing Quick Quarm database..." -ForegroundColor Yellow
    
    if (-not $ShouldRemove) {
        Add-UninstallResult -ComponentName "Database" -Status "Skipped" -Message "Database removal not requested"
        Write-Host "  - Skipping database removal" -ForegroundColor Gray
        return
    }
    
    if (-not (Test-Ubuntu2204Functional)) {
        Add-UninstallResult -ComponentName "Database" -Status "Skipped" -Message "Ubuntu 22.04 is not functional, cannot remove database"
        Write-Host "  ! Ubuntu 22.04 is not functional, skipping database removal" -ForegroundColor Yellow
        return
    }
    
    # Try to detect database name from common locations
    $dbName = "quarm"
    
    if (-not (Test-QuickQuarmDatabase -DBName $dbName)) {
        Add-UninstallResult -ComponentName "Database" -Status "Not Found" -Message "Database '$dbName' does not exist"
        Write-Host "  [OK] Database '$dbName' not found" -ForegroundColor Green
        return
    }
    
    Write-Host "  - Removing database '$dbName'..." -ForegroundColor Gray
    
    $confirm = Read-Host "  Are you sure you want to delete the database $dbName? This cannot be undone! (yes/no)"
    if ($confirm -ne "yes") {
        Add-UninstallResult -ComponentName "Database" -Status "Skipped" -Message "User cancelled database removal"
        Write-Host "  - Database removal cancelled" -ForegroundColor Yellow
        return
    }
    
    try {
        wsl -d Ubuntu-22.04 -u root -- bash -c "mysql -e 'DROP DATABASE IF EXISTS $dbName;' 2>&1" | Out-Null
        
        # Verify removal
        Start-Sleep -Seconds 1
        if (-not (Test-QuickQuarmDatabase -DBName $dbName)) {
            Add-UninstallResult -ComponentName "Database" -Status "Removed" -Message "Successfully removed database '$dbName'"
            Write-Host "  [OK] Database removed successfully" -ForegroundColor Green
        }
        else {
            Add-UninstallResult -ComponentName "Database" -Status "Failed" -Message "Database still exists after removal attempt"
            Write-Host "  ! Failed to remove database" -ForegroundColor Red
        }
    }
    catch {
        Add-UninstallResult -ComponentName "Database" -Status "Failed" -Message "Error: $($_.Exception.Message)"
        Write-Host "  ! Error removing database: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Function to remove cloud-init configuration
function Remove-CloudInitConfig {
    param([bool]$ShouldRemove = $true)
    
    Write-Host "[STEP 4/6] Removing cloud-init configuration..." -ForegroundColor Yellow
    
    if (-not $ShouldRemove) {
        Add-UninstallResult -ComponentName "Cloud-Init Configuration" -Status "Skipped" -Message "Cloud-init removal not requested"
        Write-Host "  - Skipping cloud-init removal" -ForegroundColor Gray
        return
    }
    
    $cloudInitFiles = Test-CloudInitConfig
    
    if ($cloudInitFiles.Count -eq 0) {
        Add-UninstallResult -ComponentName "Cloud-Init Configuration" -Status "Not Found" -Message "No cloud-init configuration files found"
        Write-Host "  [OK] No cloud-init configuration found" -ForegroundColor Green
        return
    }
    
    Write-Host "  - Found $($cloudInitFiles.Count) cloud-init file(s)" -ForegroundColor Gray
    
    $removedCount = 0
    $failedFiles = @()
    
    foreach ($file in $cloudInitFiles) {
        try {
            if (Test-Path $file) {
                Remove-Item -Path $file -Force -ErrorAction Stop
                $removedCount++
            }
        }
        catch {
            $failedFiles += $file
        }
    }
    
    if ($failedFiles.Count -gt 0) {
        Add-UninstallResult -ComponentName "Cloud-Init Configuration" -Status "Failed" -Message "Removed $removedCount/$($cloudInitFiles.Count) file(s). Failed: $($failedFiles -join ', ')"
        Write-Host "  ! Removed $removedCount/$($cloudInitFiles.Count) file(s)" -ForegroundColor Yellow
        Write-Host "    Failed to remove: $($failedFiles -join ', ')" -ForegroundColor Red
    }
    else {
        Add-UninstallResult -ComponentName "Cloud-Init Configuration" -Status "Removed" -Message "Successfully removed $removedCount file(s)"
        Write-Host "  [OK] Successfully removed $removedCount file(s)" -ForegroundColor Green
    }
}

# Function to remove Ubuntu 22.04
function Remove-Ubuntu2204 {
    param([bool]$ShouldRemove)
    
    Write-Host "[STEP 5/6] Removing Ubuntu 22.04..." -ForegroundColor Yellow
    
    if (-not $ShouldRemove) {
        Add-UninstallResult -ComponentName "Ubuntu 22.04" -Status "Skipped" -Message "Ubuntu removal not requested"
        Write-Host "  - Skipping Ubuntu removal" -ForegroundColor Gray
        return
    }
    
    if (-not (Test-Ubuntu2204)) {
        Add-UninstallResult -ComponentName "Ubuntu 22.04" -Status "Not Found" -Message "Ubuntu 22.04 distribution not found"
        Write-Host "  [OK] Ubuntu 22.04 not found" -ForegroundColor Green
        return
    }
    
    Write-Host "  - WARNING: This will remove Ubuntu 22.04 and all data within it!" -ForegroundColor Yellow
    
    $confirm = Read-Host "  Are you sure you want to unregister Ubuntu 22.04? This cannot be undone! (yes/no)"
    if ($confirm -ne "yes") {
        Add-UninstallResult -ComponentName "Ubuntu 22.04" -Status "Skipped" -Message "User cancelled Ubuntu removal"
        Write-Host "  - Ubuntu removal cancelled" -ForegroundColor Yellow
        return
    }
    
    Write-Host "  - Stopping WSL..." -ForegroundColor Gray
    try {
        wsl --shutdown 2>&1 | Out-Null
        Start-Sleep -Seconds 3
    }
    catch {
        # Continue
    }
    
    Write-Host "  - Unregistering Ubuntu 22.04..." -ForegroundColor Gray
    try {
        wsl --unregister Ubuntu-22.04 2>&1 | Out-Null
        Start-Sleep -Seconds 3
        
        # Verify removal
        if (-not (Test-Ubuntu2204)) {
            Add-UninstallResult -ComponentName "Ubuntu 22.04" -Status "Removed" -Message "Successfully unregistered Ubuntu 22.04"
            Write-Host "  [OK] Ubuntu 22.04 removed successfully" -ForegroundColor Green
        }
        else {
            Add-UninstallResult -ComponentName "Ubuntu 22.04" -Status "Failed" -Message "Ubuntu 22.04 still exists after unregister attempt"
            Write-Host "  ! Failed to remove Ubuntu 22.04" -ForegroundColor Red
            Write-Host "    You may need to manually run: wsl --unregister Ubuntu-22.04" -ForegroundColor Yellow
        }
    }
    catch {
        Add-UninstallResult -ComponentName "Ubuntu 22.04" -Status "Failed" -Message "Error: $($_.Exception.Message)"
        Write-Host "  ! Error removing Ubuntu 22.04: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Function to remove WSL2 (optional, very aggressive)
function Remove-WSL2 {
    param([bool]$ShouldRemove)
    
    Write-Host "[STEP 6/6] Removing WSL2..." -ForegroundColor Yellow
    
    if (-not $ShouldRemove) {
        Add-UninstallResult -ComponentName "WSL2" -Status "Skipped" -Message "WSL2 removal not requested"
        Write-Host "  - Skipping WSL2 removal" -ForegroundColor Gray
        return
    }
    
    Write-Host "  - WARNING: This will disable WSL2 and remove all WSL distributions!" -ForegroundColor Red
    
    $confirm = Read-Host "  Are you sure you want to disable WSL2? This will affect ALL WSL distributions! (yes/no)"
    if ($confirm -ne "yes") {
        Add-UninstallResult -ComponentName "WSL2" -Status "Skipped" -Message "User cancelled WSL2 removal"
        Write-Host "  - WSL2 removal cancelled" -ForegroundColor Yellow
        return
    }
    
    Write-Host "  - Disabling WSL feature..." -ForegroundColor Gray
    try {
        Disable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -Remove -NoRestart | Out-Null
        Disable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -Remove -NoRestart | Out-Null
        
        Add-UninstallResult -ComponentName "WSL2" -Status "Removed" -Message "WSL2 features disabled (restart may be required)"
        Write-Host "  [OK] WSL2 features disabled" -ForegroundColor Green
        Write-Host "  ! A system restart may be required to complete WSL2 removal" -ForegroundColor Yellow
    }
    catch {
        Add-UninstallResult -ComponentName "WSL2" -Status "Failed" -Message "Error: $($_.Exception.Message)"
        Write-Host "  ! Error disabling WSL2: $($_.Exception.Message)" -ForegroundColor Red
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
    $foundCount = ($script:UninstallResults | Where-Object { $_.Status -eq "Found" }).Count
    
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
    if ($foundCount -gt 0) {
        Write-Host "  Found: $foundCount component(s)" -ForegroundColor Cyan
    }
    
    Write-Host ""
    
    if ($failedCount -gt 0) {
        Write-Host "========================================" -ForegroundColor Red
        Write-Host "Uninstallation Complete with Errors" -ForegroundColor Red
        Write-Host "========================================" -ForegroundColor Red
        Write-Host ""
        Write-Host "Some components could not be removed:" -ForegroundColor Yellow
        Write-Host ""
        $failedResults = $script:UninstallResults | Where-Object { $_.Status -eq "Failed" }
        foreach ($result in $failedResults) {
            Write-Host "  [FAILED] $($result.Name)" -ForegroundColor Red
            Write-Host "    $($result.Message)" -ForegroundColor Yellow
        }
        Write-Host ""
        return 1
    }
    elseif ($removedCount -gt 0 -or $notFoundCount -gt 0) {
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "Uninstallation Complete" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "Quick Quarm has been successfully uninstalled." -ForegroundColor Green
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
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Quick Quarm Uninstaller" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Scanning for Quick Quarm components..." -ForegroundColor Yellow
    Write-Host ""
    
    # Check what's installed
    $servicesFound = $false
    $repoFound = $false
    $dbFound = $false
    $ubuntuFound = $false
    $cloudInitFound = $false
    
    # Check Ubuntu first (needed for other checks)
    $ubuntuExists = Test-Ubuntu2204
    $ubuntuFunctional = Test-Ubuntu2204Functional
    
    if ($ubuntuFunctional) {
        $services = Test-QuickQuarmServices
        if ($services.Count -gt 0) {
            $servicesFound = $true
        }
        
        if (Test-QuickQuarmRepository) {
            $repoFound = $true
        }
        
        if (Test-QuickQuarmDatabase) {
            $dbFound = $true
        }
    }
    
    $cloudInitFiles = Test-CloudInitConfig
    if ($cloudInitFiles.Count -gt 0) {
        $cloudInitFound = $true
    }
    
    # Display what was found
    Write-Host "Components found:" -ForegroundColor Cyan
    if ($servicesFound) {
        Write-Host "  [OK] Quick Quarm systemd services" -ForegroundColor Green
    }
    else {
        Write-Host "  [ ] Quick Quarm systemd services (not found)" -ForegroundColor Gray
    }
    
    if ($repoFound) {
        Write-Host "  [OK] Quick Quarm repository (/root/quick-quarm)" -ForegroundColor Green
    }
    else {
        Write-Host "  [ ] Quick Quarm repository (not found)" -ForegroundColor Gray
    }
    
    if ($dbFound) {
        Write-Host "  [OK] Quick Quarm database (quarm)" -ForegroundColor Green
    }
    else {
        Write-Host "  [ ] Quick Quarm database (not found)" -ForegroundColor Gray
    }
    
    if ($cloudInitFound) {
        Write-Host "  [OK] Cloud-init configuration files" -ForegroundColor Green
    }
    else {
        Write-Host "  [ ] Cloud-init configuration files (not found)" -ForegroundColor Gray
    }
    
    if ($ubuntuExists) {
        Write-Host "  [OK] Ubuntu 22.04 WSL distribution" -ForegroundColor Green
    }
    else {
        Write-Host "  [ ] Ubuntu 22.04 WSL distribution (not found)" -ForegroundColor Gray
    }
    
    Write-Host ""
    
    # Check if nothing was found
    if (-not $servicesFound -and -not $repoFound -and -not $dbFound -and -not $cloudInitFound -and -not $ubuntuExists) {
        Write-Host "No Quick Quarm components were found." -ForegroundColor Yellow
        Write-Host ""
        return @{
            RemoveServices = $false
            RemoveRepository = $false
            RemoveDatabase = $false
            RemoveCloudInit = $false
            RemoveUbuntu = $false
            RemoveWSL2 = $false
        }
    }
    
    # Prompt for each component
    Write-Host "What would you like to remove?" -ForegroundColor Cyan
    Write-Host ""
    
    $options = @{
        RemoveServices = $false
        RemoveRepository = $false
        RemoveDatabase = $false
        RemoveCloudInit = $false
        RemoveUbuntu = $false
        RemoveWSL2 = $false
    }
    
    # Always remove services and repository if found (core components)
    if ($servicesFound) {
        Write-Host "Quick Quarm systemd services:" -ForegroundColor Yellow
        $response = Read-Host "  Remove systemd services? (Y/n)"
        if ($response -eq '' -or $response -eq 'y' -or $response -eq 'Y') {
            $options.RemoveServices = $true
        }
    }
    
    if ($repoFound) {
        Write-Host "Quick Quarm repository:" -ForegroundColor Yellow
        $response = Read-Host "  Remove repository directory (/root/quick-quarm)? (Y/n)"
        if ($response -eq '' -or $response -eq 'y' -or $response -eq 'Y') {
            $options.RemoveRepository = $true
        }
    }
    
    if ($dbFound) {
        Write-Host "Quick Quarm database:" -ForegroundColor Yellow
        Write-Host "  WARNING: This will permanently delete the database and all character data!" -ForegroundColor Red
        $response = Read-Host "  Remove database? (y/N)"
        if ($response -eq 'y' -or $response -eq 'Y') {
            $options.RemoveDatabase = $true
        }
    }
    
    if ($cloudInitFound) {
        Write-Host "Cloud-init configuration:" -ForegroundColor Yellow
        $response = Read-Host "  Remove cloud-init configuration files? (Y/n)"
        if ($response -eq '' -or $response -eq 'y' -or $response -eq 'Y') {
            $options.RemoveCloudInit = $true
        }
    }
    
    if ($ubuntuExists) {
        Write-Host "Ubuntu 22.04 WSL distribution:" -ForegroundColor Yellow
        Write-Host "  WARNING: This will remove Ubuntu 22.04 and ALL data within it!" -ForegroundColor Red
        $response = Read-Host "  Remove Ubuntu 22.04? (y/N)"
        if ($response -eq 'y' -or $response -eq 'Y') {
            $options.RemoveUbuntu = $true
        }
    }
    
    # Only prompt for WSL2 if Ubuntu is being removed
    if ($options.RemoveUbuntu) {
        Write-Host ""
        Write-Host "WSL2 Windows features:" -ForegroundColor Yellow
        Write-Host "  WARNING: This will disable WSL2 and affect ALL WSL distributions!" -ForegroundColor Red
        $response = Read-Host "  Disable WSL2 Windows features? (y/N)"
        if ($response -eq 'y' -or $response -eq 'Y') {
            $options.RemoveWSL2 = $true
        }
    }
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Uninstallation Summary" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    if ($options.RemoveServices) {
        Write-Host "  [X] Remove systemd services" -ForegroundColor Green
    }
    if ($options.RemoveRepository) {
        Write-Host "  [X] Remove repository" -ForegroundColor Green
    }
    if ($options.RemoveDatabase) {
        Write-Host "  [X] Remove database" -ForegroundColor Yellow
    }
    if ($options.RemoveCloudInit) {
        Write-Host "  [X] Remove cloud-init configuration" -ForegroundColor Green
    }
    if ($options.RemoveUbuntu) {
        Write-Host "  [X] Remove Ubuntu 22.04" -ForegroundColor Yellow
    }
    if ($options.RemoveWSL2) {
        Write-Host "  [X] Disable WSL2" -ForegroundColor Red
    }
    
    $anySelected = $options.RemoveServices -or $options.RemoveRepository -or $options.RemoveDatabase -or $options.RemoveCloudInit -or $options.RemoveUbuntu -or $options.RemoveWSL2
    
    if (-not $anySelected) {
        Write-Host "  (Nothing selected)" -ForegroundColor Gray
    }
    
    Write-Host ""
    
    if ($anySelected) {
        $confirm = Read-Host "Proceed with uninstallation? (Y/n)"
        if ($confirm -ne '' -and $confirm -ne 'y' -and $confirm -ne 'Y') {
            Write-Host ""
            Write-Host "Uninstallation cancelled." -ForegroundColor Yellow
            return $null
        }
    }
    else {
        Write-Host "No components selected for removal. Exiting." -ForegroundColor Yellow
        return $null
    }
    
    Write-Host ""
    
    return $options
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
    $uninstallOptions = Get-UninstallOptions
    
    # Check if user cancelled
    if ($null -eq $uninstallOptions) {
        exit 0
    }
    
    # Clear previous results
    $script:UninstallResults = @()
    
    # Run uninstallation steps
    Remove-QuickQuarmServices -ShouldRemove $uninstallOptions.RemoveServices
    Remove-QuickQuarmRepository -ShouldRemove $uninstallOptions.RemoveRepository
    Remove-QuickQuarmDatabase -ShouldRemove $uninstallOptions.RemoveDatabase
    Remove-CloudInitConfig -ShouldRemove $uninstallOptions.RemoveCloudInit
    Remove-Ubuntu2204 -ShouldRemove $uninstallOptions.RemoveUbuntu
    Remove-WSL2 -ShouldRemove $uninstallOptions.RemoveWSL2
    
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

