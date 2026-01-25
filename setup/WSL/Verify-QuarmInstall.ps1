# Quick Quarm Installation Verification Script
# This script verifies that Quick Quarm has been properly installed
#
# By default, all checks are enabled including:
# - WSL2 Configuration
# - Ubuntu 22.04 Installation
# - Quick Quarm Repository
# - Systemd Services
# - Database Connectivity
# - Service Status (enabled and running)
# - Port Connectivity (login server port 6000)
#
# To disable optional checks, use:
#   .\Verify-QuarmInstall.ps1 -CheckServiceStatus $false -CheckPortConnectivity $false
#
# For verbose output, use:
#   .\Verify-QuarmInstall.ps1 -Verbose

param(
    [bool]$CheckServiceStatus = $true,
    [bool]$CheckPortConnectivity = $true,
    [switch]$Verbose
)

# Result tracking
$script:VerificationResults = @()

# Function to add a verification result
function Add-VerificationResult {
    param(
        [string]$CheckName,
        [bool]$Passed,
        [string]$Message = ""
    )
    
    $script:VerificationResults += @{
        Name = $CheckName
        Passed = $Passed
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

# Function to check if WSL2 is properly installed and working
function Test-WSL2Installed {
    if (-not (Test-WSLCommand)) {
        Add-VerificationResult -CheckName "WSL2 Configuration" -Passed $false -Message "WSL command not found"
        return $false
    }
    
    try {
        $status = wsl --status 2>&1
        if ($status -match "not installed" -or $LASTEXITCODE -ne 0) {
            Add-VerificationResult -CheckName "WSL2 Configuration" -Passed $false -Message "WSL2 not installed or not working"
            return $false
        }
        Add-VerificationResult -CheckName "WSL2 Configuration" -Passed $true -Message "WSL2 is properly configured"
        return $true
    }
    catch {
        Add-VerificationResult -CheckName "WSL2 Configuration" -Passed $false -Message "Error checking WSL2 status: $($_.Exception.Message)"
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

# Function to check if Ubuntu 22.04 is functional (can execute commands)
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

# Function to verify Ubuntu 22.04 installation
function Test-Ubuntu2204Installed {
    if (-not (Test-Ubuntu2204)) {
        Add-VerificationResult -CheckName "Ubuntu 22.04" -Passed $false -Message "Ubuntu 22.04 distribution not found"
        return $false
    }
    
    if (-not (Test-Ubuntu2204Functional)) {
        Add-VerificationResult -CheckName "Ubuntu 22.04" -Passed $false -Message "Ubuntu 22.04 exists but cannot execute commands"
        return $false
    }
    
    Add-VerificationResult -CheckName "Ubuntu 22.04" -Passed $true -Message "Ubuntu 22.04 is installed and functional"
    return $true
}

# Function to check if Quick Quarm repository exists
function Test-QuickQuarmRepository {
    try {
        $result = wsl -d Ubuntu-22.04 -u root -- test -d /root/quick-quarm 2>&1
        if ($LASTEXITCODE -ne 0) {
            Add-VerificationResult -CheckName "Quick Quarm Repository" -Passed $false -Message "Repository directory /root/quick-quarm does not exist"
            return $false
        }
        
        # Check for key directories/files
        $keyPaths = @("/root/quick-quarm/bin", "/root/quick-quarm/scripts", "/root/quick-quarm/scripts/setup")
        $missingPaths = @()
        
        foreach ($path in $keyPaths) {
            $checkResult = wsl -d Ubuntu-22.04 -u root -- test -e $path 2>&1
            if ($LASTEXITCODE -ne 0) {
                $missingPaths += $path
            }
        }
        
        if ($missingPaths.Count -gt 0) {
            Add-VerificationResult -CheckName "Quick Quarm Repository" -Passed $false -Message "Repository exists but missing paths: $($missingPaths -join ', ')"
            return $false
        }
        
        Add-VerificationResult -CheckName "Quick Quarm Repository" -Passed $true -Message "Repository exists with required directories"
        return $true
    }
    catch {
        Add-VerificationResult -CheckName "Quick Quarm Repository" -Passed $false -Message "Error checking repository: $($_.Exception.Message)"
        return $false
    }
}

# Function to verify all required systemd services are installed
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
    
    $missingServices = @()
    
    try {
        foreach ($service in $requiredServices) {
            $result = wsl -d Ubuntu-22.04 -u root -- systemctl list-unit-files $service 2>&1 | Out-String
            if ($result -notmatch $service) {
                $missingServices += $service
            }
        }
        
        if ($missingServices.Count -gt 0) {
            Add-VerificationResult -CheckName "Systemd Services" -Passed $false -Message "Missing services: $($missingServices -join ', ')"
            return $false
        }
        
        Add-VerificationResult -CheckName "Systemd Services" -Passed $true -Message "All $($requiredServices.Count) required services are installed"
        return $true
    }
    catch {
        Add-VerificationResult -CheckName "Systemd Services" -Passed $false -Message "Error checking services: $($_.Exception.Message)"
        return $false
    }
}

# Function to check service status (enabled and running)
function Test-QuickQuarmServiceStatus {
    if (-not $CheckServiceStatus) {
        return $null
    }
    
    Write-Host ""
    Write-Host "Checking service status (enabled and running)..." -ForegroundColor Gray
    
    $services = @(
        "quick-quarm.target",
        "eqemu-shared-memory.service",
        "eqemu-loginserver.service",
        "eqemu-ucs.service",
        "eqemu-queryserv.service",
        "eqemu-world.service",
        "eqemu-zone.service",
        "eqemu-boats.service"
    )
    
    $notEnabled = @()
    $notRunning = @()
    
    try {
        foreach ($service in $services) {
            # Only check if the target is enabled (individual services are managed by the target via Requires=)
            # Individual services will show "disabled" but that's correct - they're started by the target
            if ($service -eq "quick-quarm.target") {
                $enabledResult = wsl -d Ubuntu-22.04 -u root -- systemctl is-enabled $service 2>&1 | Out-String
                if ($enabledResult -notmatch "enabled") {
                    $notEnabled += $service
                }
            }
            
            # Check if active/running (all services should be active when target is running)
            $activeResult = wsl -d Ubuntu-22.04 -u root -- systemctl is-active $service 2>&1 | Out-String
            if ($activeResult -notmatch "active") {
                $notRunning += $service
            }
        }
        
        $messages = @()
        if ($notEnabled.Count -gt 0) {
            $messages += "Not enabled: $($notEnabled -join ', ')"
        }
        if ($notRunning.Count -gt 0) {
            $messages += "Not running: $($notRunning -join ', ')"
        }
        
        if ($messages.Count -gt 0) {
            Add-VerificationResult -CheckName "Service Status" -Passed $false -Message ($messages -join "; ")
            return $false
        }
        
        Add-VerificationResult -CheckName "Service Status" -Passed $true -Message "All services are enabled and running"
        return $true
    }
    catch {
        Add-VerificationResult -CheckName "Service Status" -Passed $false -Message "Error checking service status: $($_.Exception.Message)"
        return $false
    }
}

# Function to get the Windows host IP for WSL
function Get-HostIP {
    try {
        $hostIP = (Get-NetIPAddress -AddressFamily IPv4 | 
                   Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' } | 
                   Select-Object -First 1).IPAddress
        
        if (-not $hostIP) {
            return $null
        }
        
        return $hostIP
    }
    catch {
        return $null
    }
}

# Function to test database connectivity
function Test-DatabaseConnectivity {
    try {
        # Check if MySQL/MariaDB service is running
        $mysqlServiceStatus = wsl -d Ubuntu-22.04 -u root -- systemctl is-active mariadb.service 2>&1 | Out-String
        if ($mysqlServiceStatus -notmatch "active" -and $mysqlServiceStatus -notmatch "activating") {
            # Try mysql.service as well (some systems use this instead)
            $mysqlServiceStatus = wsl -d Ubuntu-22.04 -u root -- systemctl is-active mysql.service 2>&1 | Out-String
            if ($mysqlServiceStatus -notmatch "active" -and $mysqlServiceStatus -notmatch "activating") {
                Add-VerificationResult -CheckName "Database Connectivity" -Passed $false -Message "MySQL/MariaDB service is not running"
                return $false
            }
        }
        
        # Check if .env file exists to get database credentials
        $envFileExists = wsl -d Ubuntu-22.04 -u root -- test -f /root/quick-quarm/etc/.env 2>&1
        if ($LASTEXITCODE -ne 0) {
            Add-VerificationResult -CheckName "Database Connectivity" -Passed $false -Message "Configuration file /root/quick-quarm/etc/.env not found (setup may not be complete)"
            return $false
        }
        
        # Check if MySQL client is installed and find its path
        # Try mysql first, then mariadb as fallback
        $mysqlClientPath = ""
        $mysqlCheckCmd = 'command -v mysql 2>/dev/null || command -v mariadb 2>/dev/null || echo ""'
        $mysqlClientPathOutput = wsl -d Ubuntu-22.04 -u root -- bash -c $mysqlCheckCmd 2>&1 | Out-String
        $mysqlClientPathResult = $mysqlClientPathOutput -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 1
        $mysqlClientPath = if ($mysqlClientPathResult) { $mysqlClientPathResult.Trim() } else { "" }
        
        if (-not $mysqlClientPath) {
            Add-VerificationResult -CheckName "Database Connectivity" -Passed $false -Message "MySQL/MariaDB client not found. Please install mariadb-client: wsl -d Ubuntu-22.04 -u root -- apt-get install -y mariadb-client"
            return $false
        }
        
        # Test database connection - use hardcoded credentials (quarm/quarm is the default)
        # The quoting is critical: double quotes for bash -c, single quotes for SQL
        try {
            $dbTestOutput = wsl -d Ubuntu-22.04 -u root -- bash -c "mysql -u quarm -pquarm -h localhost quarm -e 'SELECT 1' >/dev/null 2>&1 && echo 0 || echo 1" 2>&1
            
            $dbTestResult = $dbTestOutput | Out-String
            if ($dbTestResult) {
                $dbTestExitCodeResult = $dbTestResult -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 1
                $dbTestExitCode = if ($dbTestExitCodeResult) { $dbTestExitCodeResult.Trim() } else { "1" }
            }
            else {
                $dbTestExitCode = "1"
            }
        }
        catch {
            $dbTestExitCode = "1"
        }
        
        if ($dbTestExitCode -eq "0") {
            # Get database name from .env file for the message
            try {
                $dbNameOutput = wsl -d Ubuntu-22.04 -u root -- bash -c 'cd /root/quick-quarm && source etc/.env 2>/dev/null && echo "$DBNAME"' 2>&1
                $dbNameResult = $dbNameOutput | Out-String
                if ($dbNameResult) {
                    $dbNameResultObj = $dbNameResult -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 1
                    $dbName = if ($dbNameResultObj) { $dbNameResultObj.Trim() } else { "" }
                }
                if (-not $dbName) { $dbName = "unknown" }
            }
            catch {
                $dbName = "unknown"
            }
            
            Add-VerificationResult -CheckName "Database Connectivity" -Passed $true -Message "Successfully connected to database '$dbName'"
            return $true
        }
        else {
            # Try to get a more detailed error message
            try {
                $errorOutput = wsl -d Ubuntu-22.04 -u root -- bash -c "mysql -u quarm -pquarm -h localhost quarm -e 'SELECT 1' 2>&1 | head -1" 2>&1
                
                $errorResult = $errorOutput | Out-String
                if ($errorResult) {
                    $errorMsgResult = $errorResult -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 1
                    $errorMsg = if ($errorMsgResult) { $errorMsgResult.Trim() } else { "" }
                }
                if (-not $errorMsg) { $errorMsg = "Connection failed (check credentials and database name)" }
            }
            catch {
                $errorMsg = "Connection failed (unable to retrieve error details)"
            }
            
            Add-VerificationResult -CheckName "Database Connectivity" -Passed $false -Message "Failed to connect to database: $errorMsg"
            return $false
        }
    }
    catch {
        Add-VerificationResult -CheckName "Database Connectivity" -Passed $false -Message "Error checking database connectivity: $($_.Exception.Message)"
        return $false
    }
}

# Function to test port connectivity (checks inside WSL2)
function Test-PortConnectivity {
    if (-not $CheckPortConnectivity) {
        return $null
    }
    
    Write-Host ""
    Write-Host "Checking port connectivity..." -ForegroundColor Gray
    
    $port = 6000
    
    try {
        # First, check if the port is listening inside WSL2
        $portListenCheck = wsl -d Ubuntu-22.04 -u root -- bash -c "ss -tuln 2>/dev/null | grep -q :6000 && echo 'LISTENING' || echo 'NOT_LISTENING'" 2>&1 | Out-String
        $portListenResult = ($portListenCheck -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 1).Trim()
        
        if ($portListenResult -eq "LISTENING") {
            # Port is listening inside WSL2, which is what matters
            Add-VerificationResult -CheckName "Port Connectivity" -Passed $true -Message "Port $port is listening inside WSL2 (login server is running)"
            return $true
        }
        else {
            # Check if the login server process is even running
            $processCheck = wsl -d Ubuntu-22.04 -u root -- bash -c "systemctl is-active eqemu-loginserver.service" 2>&1 | Out-String
            $processStatus = ($processCheck -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 1).Trim()
            
            if ($processStatus -eq "active") {
                Add-VerificationResult -CheckName "Port Connectivity" -Passed $false -Message "Login server service is active but port $port is not listening (service may still be starting or failed to bind)"
            }
            else {
                Add-VerificationResult -CheckName "Port Connectivity" -Passed $false -Message "Port $port is not listening (login server service may not be running)"
            }
            return $false
        }
    }
    catch {
        Add-VerificationResult -CheckName "Port Connectivity" -Passed $false -Message "Error testing port connectivity: $($_.Exception.Message)"
        return $false
    }
}

# Main verification function
function Get-VerificationReport {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Quick Quarm Installation Verification" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Clear previous results
    $script:VerificationResults = @()
    
    # Run all verification checks
    Write-Host "Running verification checks..." -ForegroundColor Yellow
    Write-Host ""
    
    # Check 1: WSL2
    Test-WSL2Installed | Out-Null
    
    # Check 2: Ubuntu 22.04
    Test-Ubuntu2204Installed | Out-Null
    
    # Check 3: Quick Quarm Repository
    Test-QuickQuarmRepository | Out-Null
    
    # Check 4: Systemd Services
    Test-QuickQuarmServices | Out-Null
    
    # Check 5: Database Connectivity
    Test-DatabaseConnectivity | Out-Null
    
    # Check 6: Service Status (optional)
    if ($CheckServiceStatus) {
        Test-QuickQuarmServiceStatus | Out-Null
    }
    
    # Check 7: Port Connectivity (optional)
    if ($CheckPortConnectivity) {
        Test-PortConnectivity | Out-Null
    }
    
    # Display results
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Verification Results" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    $checkNumber = 1
    $totalChecks = $script:VerificationResults.Count
    
    foreach ($result in $script:VerificationResults) {
        $status = if ($result.Passed) { "[PASS]" } else { "[FAIL]" }
        $color = if ($result.Passed) { "Green" } else { "Red" }
        
        Write-Host "[$checkNumber/$totalChecks] $($result.Name): " -NoNewline
        Write-Host $status -ForegroundColor $color
        
        if ($Verbose -or -not $result.Passed) {
            Write-Host "  $($result.Message)" -ForegroundColor Gray
        }
        
        $checkNumber++
    }
    
    Write-Host ""
    
    # Summary
    $passedCount = ($script:VerificationResults | Where-Object { $_.Passed }).Count
    $failedCount = $script:VerificationResults.Count - $passedCount
    $failedResults = $script:VerificationResults | Where-Object { -not $_.Passed }
    $passedResults = $script:VerificationResults | Where-Object { $_.Passed }
    
    Write-Host "========================================" -ForegroundColor $(if ($failedCount -eq 0) { "Green" } else { "Red" })
    if ($failedCount -eq 0) {
        Write-Host "Verification Complete: ALL CHECKS PASSED" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "All verification checks passed successfully:" -ForegroundColor Green
        Write-Host ""
        foreach ($result in $passedResults) {
            Write-Host "  [PASS] $($result.Name)" -ForegroundColor Green
            if ($Verbose) {
                Write-Host "    $($result.Message)" -ForegroundColor Gray
            }
        }
    }
    else {
        Write-Host "Verification Complete: $failedCount CHECK(S) FAILED" -ForegroundColor Red
        Write-Host "========================================" -ForegroundColor Red
        Write-Host ""
        Write-Host "FAILED CHECKS:" -ForegroundColor Red
        Write-Host ""
        foreach ($result in $failedResults) {
            Write-Host "  [FAIL] $($result.Name)" -ForegroundColor Red
            Write-Host "    Error: $($result.Message)" -ForegroundColor Yellow
        }
        Write-Host ""
        if ($passedResults.Count -gt 0) {
            Write-Host "PASSED CHECKS:" -ForegroundColor Green
            Write-Host ""
            foreach ($result in $passedResults) {
                Write-Host "  [PASS] $($result.Name)" -ForegroundColor Green
            }
        }
    }
    Write-Host ""
    
    # Return exit code
    if ($failedCount -eq 0) {
        return 0
    }
    else {
        return 1
    }
}

# Main execution
try {
    $exitCode = Get-VerificationReport
    exit $exitCode
}
catch {
    Write-Host ""
    Write-Host "ERROR: Verification failed" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    exit 1
}

