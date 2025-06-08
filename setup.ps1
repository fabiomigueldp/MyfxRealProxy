<#
  MyfxRealProxy setup.ps1
  One‑click installer – run as Administrator
  Enhanced with maximum transparency and progress tracking
#>
param()

# Enhanced logging and progress functions
Function Write-Progress-Header {
    param([string]$Message)
    Write-Host ""
    Write-Host "=" * 60 -ForegroundColor Cyan
    Write-Host "  $Message" -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host "=" * 60 -ForegroundColor Cyan
    Write-Host ""
}

Function Write-Step {
    param([string]$Message, [string]$Color = "Yellow")
    Write-Host "[STEP] $Message" -ForegroundColor $Color
}

Function Write-SubStep {
    param([string]$Message, [string]$Color = "Gray")
    Write-Host "  -> $Message" -ForegroundColor $Color
}

Function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

Function Write-Error-Detail {
    param([string]$Message, $Exception = $null)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
    if ($Exception) {
        Write-Host "  Details: $($Exception.Message)" -ForegroundColor Red
        if ($Exception.InnerException) {
            Write-Host "  Inner Exception: $($Exception.InnerException.Message)" -ForegroundColor Red
        }
        if ($global:LASTEXITCODE -and $global:LASTEXITCODE -ne 0) {
            Write-Host "  Exit Code: $global:LASTEXITCODE" -ForegroundColor Red
        }
        if ($Exception.ScriptStackTrace) {
            Write-Host "  Stack Trace: $($Exception.ScriptStackTrace)" -ForegroundColor Red
        }
    }
}

Function Test-Command {
    param([string]$Command, [string]$Description)
    Write-SubStep "Testing if $Description is available..."
    try {
        $result = Get-Command $Command -ErrorAction Stop
        Write-SubStep "$Description found at: $($result.Source)" -Color "Green"
        return $true
    } catch {
        Write-SubStep "$Description not found" -Color "Red"
        return $false
    }
}

Function Need-Admin {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object System.Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Start installation with banner
Clear-Host
Write-Progress-Header "MyfxRealProxy Installation Starting"
Write-Host "Installation Date: $(Get-Date)" -ForegroundColor Gray
Write-Host "Computer: $env:COMPUTERNAME" -ForegroundColor Gray
Write-Host "User: $env:USERNAME" -ForegroundColor Gray
Write-Host ""

# Check administrator privileges
Write-Step "Checking administrator privileges..."
if (-not (Need-Admin)) {
    Write-Error-Detail "This script must be run as Administrator."
    Write-Host "Please right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}
Write-Success "Running with administrator privileges"

# Configuration and setup
Write-Step "Setting up configuration..."
$ErrorActionPreference = "Stop"
$base   = "C:\MyfxRealProxy"
$logs   = "$base\logs"
$python = "$env:ProgramFiles\Python312\python.exe"
$mitmd  = "$env:ProgramFiles\Python312\Scripts\mitmdump.exe"
$nssm   = "$base\nssm.exe"

Write-SubStep "Base directory: $base"
Write-SubStep "Logs directory: $logs"
Write-SubStep "Python path: $python"
Write-SubStep "Mitmdump path: $mitmd"
Write-SubStep "NSSM path: $nssm"

# Create directories
Write-Step "Creating directories..."
try {
    Write-SubStep "Creating base directory: $base"
    New-Item -ItemType Directory -Path $base -ErrorAction SilentlyContinue | Out-Null
    if (Test-Path $base) {
        Write-Success "Base directory created/verified: $base"
    } else {
        throw "Failed to create base directory"
    }
    
    Write-SubStep "Creating logs directory: $logs"
    New-Item -ItemType Directory -Path $logs -ErrorAction SilentlyContinue | Out-Null
    if (Test-Path $logs) {
        Write-Success "Logs directory created/verified: $logs"
    } else {
        throw "Failed to create logs directory"
    }
} catch {
    Write-Error-Detail "Failed to create directories" $_
    exit 1
}

# STEP 1: Python Installation
Write-Progress-Header "STEP 1/7: Python 3.12 Installation"
Write-Step "Checking if Python 3.12 is installed..."

# Pre-installation system checks
Write-SubStep "Performing pre-installation checks..."
Write-SubStep "Available disk space in TEMP: $([math]::Round((Get-WmiObject -Class Win32_LogicalDisk | Where-Object {$_.DeviceID -eq (Split-Path $env:TEMP -Qualifier)}).FreeSpace / 1GB, 2)) GB"
Write-SubStep "Available disk space in Program Files: $([math]::Round((Get-WmiObject -Class Win32_LogicalDisk | Where-Object {$_.DeviceID -eq (Split-Path $env:ProgramFiles -Qualifier)}).FreeSpace / 1GB, 2)) GB"

if (-not (Test-Path $python)) {
    Write-SubStep "Python 3.12 not found, downloading and installing..."
    $pyUrl = "https://www.python.org/ftp/python/3.12.3/python-3.12.3-amd64.exe"
    $pyTmp = "$env:TEMP\py312.exe"
    
    try {
        $useExisting = $false
        $installSuccess = $false
        
        Write-SubStep "Downloading Python from: $pyUrl"
        Write-SubStep "Saving to: $pyTmp"
        $progressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $pyUrl -OutFile $pyTmp -UseBasicParsing
        $progressPreference = 'Continue'
        
        if (Test-Path $pyTmp) {
            $fileSize = (Get-Item $pyTmp).Length / 1MB
            Write-Success "Python installer downloaded successfully ($([math]::Round($fileSize, 2)) MB)"
        } else {
            throw "Download failed - file not found"
        }
        
        Write-SubStep "Installing Python (this may take several minutes)..."
        Write-SubStep "Installation parameters: /quiet InstallAllUsers=1 PrependPath=1 Include_test=0"
        Write-SubStep "Starting Python installer process..."
        
        $installProcess = Start-Process -FilePath $pyTmp -ArgumentList "/quiet", "InstallAllUsers=1", "PrependPath=1", "Include_test=0" -Wait -PassThru -RedirectStandardOutput "$env:TEMP\python_install_out.log" -RedirectStandardError "$env:TEMP\python_install_err.log"
        
        Write-SubStep "Installation process completed with exit code: $($installProcess.ExitCode)"
        
        # Read installation logs
        if (Test-Path "$env:TEMP\python_install_out.log") {
            $installOut = Get-Content "$env:TEMP\python_install_out.log" -ErrorAction SilentlyContinue
            if ($installOut) {
                Write-SubStep "Installation output: $($installOut -join '; ')" -Color "Gray"
            }
        }
        
        if (Test-Path "$env:TEMP\python_install_err.log") {
            $installErr = Get-Content "$env:TEMP\python_install_err.log" -ErrorAction SilentlyContinue
            if ($installErr) {
                Write-SubStep "Installation errors: $($installErr -join '; ')" -Color "Red"
            }
        }
        
        if ($installProcess.ExitCode -ne 0) {
            # Handle specific exit codes
            switch ($installProcess.ExitCode) {
                1638 { 
                    Write-SubStep "Exit code 1638: Another version of Python is already installed" -Color "Yellow"
                    Write-SubStep "Searching for existing compatible Python installations..." -Color "Yellow"
                    
                    # Try to find existing Python installations
                    $existingPythons = @()
                    $searchPaths = @(
                        "${env:ProgramFiles}\Python*\python.exe",
                        "${env:ProgramFiles(x86)}\Python*\python.exe",
                        "${env:LOCALAPPDATA}\Programs\Python\Python*\python.exe",
                        "${env:USERPROFILE}\AppData\Local\Programs\Python\Python*\python.exe"
                    )
                    
                    foreach ($searchPath in $searchPaths) {
                        $found = Get-ChildItem -Path $searchPath -ErrorAction SilentlyContinue
                        if ($found) {
                            $existingPythons += $found
                        }
                    }
                    
                    if ($existingPythons.Count -gt 0) {
                        Write-SubStep "Found existing Python installations:" -Color "Green"
                        $compatiblePython = $null
                        
                        foreach ($py in $existingPythons) {
                            try {
                                $version = & $py.FullName --version 2>&1
                                Write-SubStep "  $($py.FullName) - $version" -Color "Green"
                                
                                # Check if this is Python 3.9+ (compatible with mitmproxy)
                                if ($version -match "Python 3\.(\d+)\.") {
                                    $majorMinor = [int]$matches[1]
                                    if ($majorMinor -ge 9) {
                                        if (-not $compatiblePython) {
                                            $compatiblePython = $py.FullName
                                            Write-SubStep "    -> This Python version is compatible with mitmproxy" -Color "Green"
                                        } else {
                                            Write-SubStep "    -> This Python version is also compatible" -Color "Green"
                                        }
                                    } else {
                                        Write-SubStep "    -> This Python version is too old (need 3.9+)" -Color "Yellow"
                                    }
                                }
                            } catch {
                                Write-SubStep "  $($py.FullName) - Could not get version" -Color "Gray"
                            }
                        }
                        
                        if ($compatiblePython) {
                            Write-Success "Using compatible existing Python installation: $compatiblePython"
                            $python = $compatiblePython
                            $pythonDir = Split-Path $compatiblePython
                            $mitmd = Join-Path $pythonDir "Scripts\mitmdump.exe"
                            Write-SubStep "Updated mitmdump path: $mitmd" -Color "Green"
                            $useExisting = $true
                            $installSuccess = $true
                        } else {
                            Write-SubStep "No compatible Python 3.9+ found in existing installations" -Color "Yellow"
                            Write-SubStep "You may need to upgrade your Python installation manually" -Color "Yellow"
                        }
                    } else {
                        Write-SubStep "No existing Python installations found in standard locations" -Color "Yellow"
                        
                        # Try to find Python in PATH as last resort
                        Write-SubStep "Checking if Python is available in system PATH..." -Color "Yellow"
                        try {
                            $pathPython = Get-Command python -ErrorAction Stop
                            $pathVersion = & python --version 2>&1
                            Write-SubStep "Found Python in PATH: $pathVersion at $($pathPython.Source)" -Color "Green"
                            
                            if ($pathVersion -match "Python 3\.(\d+)\.") {
                                $majorMinor = [int]$matches[1]
                                if ($majorMinor -ge 9) {
                                    Write-Success "PATH Python is compatible - using: $($pathPython.Source)"
                                    $python = $pathPython.Source
                                    $pythonDir = Split-Path $python
                                    $mitmd = Join-Path $pythonDir "Scripts\mitmdump.exe"
                                    Write-SubStep "Updated mitmdump path: $mitmd" -Color "Green"
                                    $useExisting = $true
                                    $installSuccess = $true
                                } else {
                                    Write-SubStep "PATH Python is too old (need 3.9+): $pathVersion" -Color "Yellow"
                                }
                            }
                        } catch {
                            Write-SubStep "No Python found in system PATH" -Color "Yellow"
                        }
                    }
                    
                    if (-not $useExisting) {
                        Write-Error-Detail "Exit code 1638 indicates another Python version is installed, but no compatible Python 3.9+ was found."
                        Write-SubStep "Please install Python 3.9 or later manually and run this script again." -Color "Yellow"
                        throw "No compatible Python installation found"
                    }
                }
                3010 { 
                    Write-SubStep "Exit code 3010: Installation successful, reboot required" -Color "Yellow"
                    $installSuccess = $true
                }
                0 { 
                    Write-SubStep "Exit code 0: Installation successful" -Color "Green"
                    $installSuccess = $true
                }
                default { 
                    Write-SubStep "Exit code $($installProcess.ExitCode): Installation failed" -Color "Red"
                }
            }
            
            if (-not $useExisting -and -not $installSuccess) {
                throw "Python installation failed with exit code: $($installProcess.ExitCode)"
            }
        } else {
            $installSuccess = $true
        }
        
        Write-Success "Python 3.12 installation process completed successfully"
        
        # Verify installation or existing Python
        if ($useExisting) {
            Write-SubStep "Using existing Python installation, skipping installation verification"
        } else {
            Write-SubStep "Waiting for installation to settle..."
            Start-Sleep -Seconds 5
        }
        
        Write-SubStep "Verifying Python installation..."
        if (Test-Path $python) {
            try {
                $pythonVersion = & $python --version 2>&1
                Write-Success "Python verification successful: $pythonVersion"
            } catch {
                Write-SubStep "Python executable found but version check failed: $($_.Exception.Message)" -Color "Yellow"
                Write-SubStep "This may be normal - continuing with installation..." -Color "Yellow"
            }
        } else {
            # Try alternative Python locations (only if we didn't already use existing)
            if (-not $useExisting) {
                Write-SubStep "Python not found at expected location, checking alternatives..." -Color "Yellow"
                
                $altPaths = @(
                    "${env:ProgramFiles}\Python312\python.exe",
                    "${env:ProgramFiles(x86)}\Python312\python.exe",
                    "${env:LOCALAPPDATA}\Programs\Python\Python312\python.exe",
                    "${env:USERPROFILE}\AppData\Local\Programs\Python\Python312\python.exe"
                )
                
                $foundPython = $false
                foreach ($altPath in $altPaths) {
                    if (Test-Path $altPath) {
                        Write-SubStep "Found Python at alternative location: $altPath" -Color "Green"
                        $python = $altPath
                        $mitmd = "$([System.IO.Path]::GetDirectoryName($altPath))\Scripts\mitmdump.exe"
                        Write-SubStep "Updated mitmdump path: $mitmd" -Color "Green"
                        $foundPython = $true
                        break
                    }
                }
                
                if (-not $foundPython) {
                    Write-SubStep "Python installation may have failed - executable not found at any expected location" -Color "Red"
                    Write-SubStep "Expected location: $python" -Color "Red"
                    Write-SubStep "Alternative locations checked: $($altPaths -join ', ')" -Color "Red"
                    
                    # Try to get more information about what went wrong
                    Write-SubStep "Checking if Python is in PATH..." -Color "Yellow"
                    try {
                        $pythonInPath = Get-Command python -ErrorAction Stop
                        Write-SubStep "Python found in PATH at: $($pythonInPath.Source)" -Color "Green"
                        $python = $pythonInPath.Source
                        $pythonDir = Split-Path $python
                        $mitmd = Join-Path $pythonDir "Scripts\mitmdump.exe"
                        Write-SubStep "Updated mitmdump path: $mitmd" -Color "Green"
                    } catch {
                        Write-SubStep "Python not found in PATH either" -Color "Red"
                        throw "Python installation verification failed - executable not found"
                    }
                }
            } else {
                throw "Selected existing Python installation not found at: $python"
            }
        }
        
        # Cleanup
        Write-SubStep "Cleaning up installer and temporary files..."
        Remove-Item $pyTmp -ErrorAction SilentlyContinue
        Remove-Item "$env:TEMP\python_install_out.log" -ErrorAction SilentlyContinue
        Remove-Item "$env:TEMP\python_install_err.log" -ErrorAction SilentlyContinue
        
    } catch {
        Write-Error-Detail "Python installation failed" $_
        exit 1
    }
} else {
    Write-SubStep "Python 3.12 found at: $python"
    try {
        $pythonVersion = & $python --version 2>&1
        Write-Success "Existing Python version: $pythonVersion"
    } catch {
        Write-Error-Detail "Python exists but cannot execute" $_
        exit 1
    }
}

# STEP 2: mitmproxy Installation
Write-Progress-Header "STEP 2/7: mitmproxy Installation"
Write-Step "Checking if mitmproxy is already installed..."

# First check if mitmdump already exists (in case of existing Python installation)
$needsMitmInstall = $true
if (Test-Path $mitmd) {
    Write-SubStep "mitmdump found at: $mitmd"
    try {
        $mitmVersion = & $mitmd --version 2>&1
        Write-Success "Existing mitmproxy found: $($mitmVersion[0])"
        
        # Check if it's a compatible version (10.x preferred)
        if ($mitmVersion[0] -match "mitmdump (\d+)\.") {
            $majorVersion = [int]$matches[1]
            if ($majorVersion -ge 10) {
                Write-SubStep "mitmproxy version is compatible (v$majorVersion)" -Color "Green"
                $needsMitmInstall = $false
            } else {
                Write-SubStep "mitmproxy version is older (v$majorVersion), will upgrade to v10" -Color "Yellow"
            }
        } else {
            Write-SubStep "Could not determine mitmproxy version, will reinstall" -Color "Yellow"
        }
    } catch {
        Write-SubStep "mitmdump exists but cannot execute, will reinstall" -Color "Yellow"
    }
} else {
    Write-SubStep "mitmdump not found at expected location: $mitmd"
}

if ($needsMitmInstall) {
    Write-Step "Installing/upgrading mitmproxy via pip..."
} else {
    Write-Step "mitmproxy already installed and compatible, skipping installation"
}
if ($needsMitmInstall) {
    try {
        Write-SubStep "Upgrading pip to latest version..."
        $pipUpgrade = & $python -m pip install --upgrade pip 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Pip upgraded successfully"
            Write-SubStep "Pip output: $($pipUpgrade -join ' ')"
        } else {
            Write-Error-Detail "Pip upgrade failed with exit code: $LASTEXITCODE"
            Write-SubStep "Output: $($pipUpgrade -join ' ')"
        }
        
        Write-SubStep "Installing mitmproxy version 10.x..."
        Write-SubStep "This may take several minutes depending on your internet connection..."
        $mitmInstall = & $python -m pip install mitmproxy==10.* 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Success "mitmproxy installed successfully"
            Write-SubStep "Installation output: $($mitmInstall[-5..-1] -join ' ')"
        } else {
            throw "mitmproxy installation failed with exit code: $LASTEXITCODE. Output: $($mitmInstall -join ' ')"
        }
        
    } catch {
        Write-Error-Detail "mitmproxy installation failed" $_
        exit 1
    }
}

# Verify mitmproxy installation (regardless of whether we just installed it or it was already there)
Write-SubStep "Verifying mitmproxy installation..."
try {
    if (Test-Path $mitmd) {
        Write-Success "mitmdump executable found at: $mitmd"
        try {
            $mitmVersion = & $mitmd --version 2>&1
            Write-Success "mitmproxy version: $($mitmVersion[0])"
        } catch {
            Write-SubStep "Could not get mitmproxy version, but executable exists" -Color "Yellow"
        }
    } else {
        throw "mitmproxy installation completed but mitmdump not found at: $mitmd"
    }
} catch {
    Write-Error-Detail "mitmproxy verification failed" $_
    exit 1
}

# STEP 3: Download Payload Files
Write-Progress-Header "STEP 3/7: Downloading Payload Files"
$repo = "https://raw.githubusercontent.com/yourrepo/myfxrealproxy/main"
$files = @("force_real.py","service_wrapper.bat","watchdog.ps1","update.bat")

Write-Step "Downloading required files from repository..."
Write-SubStep "Repository: $repo"
Write-SubStep "Files to download: $($files -join ', ')"

$downloadSuccess = 0
$downloadTotal = $files.Count

foreach ($f in $files) {
    try {
        $url = "$repo/$f"
        $destination = "$base\$f"
        Write-SubStep "Downloading: $f"
        Write-SubStep "From: $url"
        Write-SubStep "To: $destination"
        
        $progressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $url -OutFile $destination -UseBasicParsing
        $progressPreference = 'Continue'
        
        if (Test-Path $destination) {
            $fileSize = (Get-Item $destination).Length
            Write-Success "Downloaded $f successfully ($fileSize bytes)"
            $downloadSuccess++
        } else {
            throw "File not found after download"
        }
    } catch {
        Write-Error-Detail "Failed to download $f" $_
        Write-SubStep "URL attempted: $url" -Color "Red"
    }
}

Write-Step "Download summary: $downloadSuccess/$downloadTotal files downloaded successfully"
if ($downloadSuccess -lt $downloadTotal) {
    Write-Error-Detail "Not all files were downloaded successfully"
    exit 1
}

# STEP 4: Certificate Generation and Trust
Write-Progress-Header "STEP 4/7: mitmproxy Certificate Setup"
Write-Step "Generating mitmproxy CA certificate..."
try {
    Write-SubStep "Initializing mitmproxy configuration..."
    Write-SubStep "Command: $mitmd -q --set confdir=$base init"
    
    $initOutput = & $mitmd -q --set confdir=$base init 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Success "mitmproxy initialized successfully"
    } else {
        Write-Error-Detail "mitmproxy initialization failed with exit code: $LASTEXITCODE"
        Write-SubStep "Output: $($initOutput -join ' ')" -Color "Red"
    }
    
    $certPem = "$base\.mitmproxy\mitmproxy-ca-cert.pem"
    Write-SubStep "Looking for certificate at: $certPem"
    
    if (Test-Path $certPem) {
        $certInfo = Get-Item $certPem
        Write-Success "Certificate found: $($certInfo.Name) ($($certInfo.Length) bytes)"
        Write-SubStep "Certificate location: $($certInfo.FullName)"
        
        Write-SubStep "Adding certificate to Windows certificate store..."
        Write-SubStep "Command: certutil -addstore -f Root $certPem"
        
        $certutilOutput = certutil -addstore -f "Root" $certPem 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Certificate added to Root store successfully"
            Write-SubStep "Certificate is now trusted by Windows"
        } else {
            Write-Error-Detail "Failed to add certificate to Root store"
            Write-SubStep "Certutil output: $($certutilOutput -join ' ')" -Color "Red"
        }
    } else {
        throw "Certificate file not found at: $certPem"
    }
} catch {
    Write-Error-Detail "Certificate setup failed" $_
    exit 1
}

# STEP 5: Proxy Configuration
Write-Progress-Header "STEP 5/7: Proxy Configuration"
Write-Step "Configuring system proxy settings..."
try {
    Write-SubStep "Backing up current proxy settings..."
    $prevProxy = (netsh winhttp show proxy) 2>&1
    $backupFile = "$base\prev_proxy.txt"
    $prevProxy | Out-File $backupFile
    
    if (Test-Path $backupFile) {
        Write-Success "Current proxy settings backed up to: $backupFile"
        Write-SubStep "Current proxy configuration:"
        $prevProxy | ForEach-Object { Write-SubStep "  $_" -Color "Gray" }
    } else {
        Write-Error-Detail "Failed to backup proxy settings"
    }
    
    Write-SubStep "Setting new proxy: 127.0.0.1:8080"
    $proxyResult = netsh winhttp set proxy 127.0.0.1:8080 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Proxy set successfully"
        Write-SubStep "New proxy: 127.0.0.1:8080"
        
        # Verify proxy setting
        Write-SubStep "Verifying new proxy settings..."
        $newProxy = netsh winhttp show proxy 2>&1
        Write-SubStep "Current proxy configuration:"
        $newProxy | ForEach-Object { Write-SubStep "  $_" -Color "Green" }
    } else {
        Write-Error-Detail "Failed to set proxy"
        Write-SubStep "netsh output: $($proxyResult -join ' ')" -Color "Red"
    }
} catch {
    Write-Error-Detail "Proxy configuration failed" $_
    exit 1
}

# STEP 6: Service Setup
Write-Progress-Header "STEP 6/7: Windows Service Setup"
Write-Step "Downloading and configuring NSSM (Non-Sucking Service Manager)..."
try {
    $nssmZip = "$env:TEMP\nssm.zip"
    $nssmUrl = "https://nssm.cc/release/nssm-2.24.zip"
    
    Write-SubStep "Downloading NSSM from: $nssmUrl"
    Write-SubStep "Saving to: $nssmZip"
    
    $progressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $nssmUrl -OutFile $nssmZip -UseBasicParsing
    $progressPreference = 'Continue'
    
    if (Test-Path $nssmZip) {
        $zipSize = (Get-Item $nssmZip).Length / 1KB
        Write-Success "NSSM downloaded successfully ($([math]::Round($zipSize, 2)) KB)"
    } else {
        throw "NSSM download failed"
    }
    
    Write-SubStep "Extracting NSSM archive..."
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory($nssmZip, $base)
    
    $nssmSource = "$base\nssm-2.24\win64\nssm.exe"
    if (Test-Path $nssmSource) {
        Write-Success "NSSM extracted successfully"
        Write-SubStep "Copying NSSM executable..."
        Copy-Item $nssmSource $nssm -Force
        
        if (Test-Path $nssm) {
            Write-Success "NSSM ready at: $nssm"
        } else {
            throw "Failed to copy NSSM executable"
        }
    } else {
        throw "NSSM executable not found in archive"
    }
    
    # Cleanup
    Write-SubStep "Cleaning up temporary files..."
    Remove-Item $nssmZip -ErrorAction SilentlyContinue
    Remove-Item "$base\nssm-2.24" -Recurse -ErrorAction SilentlyContinue
    
} catch {
    Write-Error-Detail "NSSM setup failed" $_
    exit 1
}

Write-Step "Creating Windows service..."
try {
    # Check if service already exists
    $existingService = Get-Service -Name "MyfxRealProxy" -ErrorAction SilentlyContinue
    if ($existingService) {
        Write-SubStep "Service 'MyfxRealProxy' already exists, removing..."
        & $nssm remove MyfxRealProxy confirm 2>&1 | Out-Null
        Start-Sleep -Seconds 2
    }
    
    Write-SubStep "Installing service with NSSM..."
    $serviceArgs = @($mitmd, "-s", "$base\force_real.py", "--listen-port", "8080", "--ssl-insecure", "--quiet")
    Write-SubStep "Service command: $mitmd"
    Write-SubStep "Service arguments: $($serviceArgs[1..($serviceArgs.Length-1)] -join ' ')"
    
    $installResult = & $nssm install MyfxRealProxy $mitmd "-s" "$base\force_real.py" "--listen-port" "8080" "--ssl-insecure" "--quiet" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Service installed successfully"
    } else {
        throw "Service installation failed: $($installResult -join ' ')"
    }
    
    Write-SubStep "Configuring service parameters..."
    & $nssm set MyfxRealProxy AppDirectory $base 2>&1 | Out-Null
    & $nssm set MyfxRealProxy Start SERVICE_AUTO_START 2>&1 | Out-Null
    & $nssm set MyfxRealProxy AppStdout "$logs\service.log" 2>&1 | Out-Null
    & $nssm set MyfxRealProxy AppStderr "$logs\service.err" 2>&1 | Out-Null
    Write-Success "Service configured successfully"
    
    Write-SubStep "Starting service..."
    $startResult = & $nssm start MyfxRealProxy 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Service started successfully"
        
        # Verify service status
        Start-Sleep -Seconds 3
        $serviceStatus = Get-Service -Name "MyfxRealProxy" -ErrorAction SilentlyContinue
        if ($serviceStatus) {
            Write-SubStep "Service status: $($serviceStatus.Status)" -Color "Green"
        }
    } else {
        Write-Error-Detail "Failed to start service: $($startResult -join ' ')"
    }
    
} catch {
    Write-Error-Detail "Service creation failed" $_
    exit 1
}

# STEP 7: Scheduled Tasks
Write-Progress-Header "STEP 7/7: Creating Scheduled Tasks"
Write-Step "Creating scheduled tasks for maintenance..."
try {
    # Create watchdog task
    Write-SubStep "Creating watchdog task (runs every 30 seconds)..."
    $watchArgs = "-ExecutionPolicy Bypass -File `"$base\watchdog.ps1`""
    Write-SubStep "Watchdog command: powershell.exe $watchArgs"
    
    # Remove existing task if it exists
    schtasks /Delete /TN "MyfxRealProxy Watchdog" /F 2>&1 | Out-Null
    
    $watchdogResult = schtasks /Create /TN "MyfxRealProxy Watchdog" /TR "powershell.exe $watchArgs" /SC SECOND /MO 30 /F 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Watchdog task created successfully"
        Write-SubStep "Task will run every 30 seconds to monitor service"
    } else {
        Write-Error-Detail "Failed to create watchdog task"
        Write-SubStep "schtasks output: $($watchdogResult -join ' ')" -Color "Red"
    }
    
    # Create update task
    Write-SubStep "Creating update task (runs every 7 days at 3:00 AM)..."
    Write-SubStep "Update command: $base\update.bat"
    
    # Remove existing task if it exists
    schtasks /Delete /TN "MyfxRealProxy Update" /F 2>&1 | Out-Null
    
    $updateResult = schtasks /Create /TN "MyfxRealProxy Update" /TR "$base\update.bat" /SC DAILY /MO 7 /ST 03:00 /F 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Update task created successfully"
        Write-SubStep "Task will run every 7 days at 3:00 AM"
    } else {
        Write-Error-Detail "Failed to create update task"
        Write-SubStep "schtasks output: $($updateResult -join ' ')" -Color "Red"
    }
    
    # List created tasks
    Write-SubStep "Verifying created tasks..."
    $tasks = schtasks /Query /TN "MyfxRealProxy*" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Tasks verification:"
        $tasks | ForEach-Object { Write-SubStep "  $_" -Color "Green" }
    }
    
} catch {
    Write-Error-Detail "Scheduled tasks creation failed" $_
    Write-SubStep "This is not critical - the service will still work" -Color "Yellow"
}

# Installation Complete
Write-Progress-Header "INSTALLATION COMPLETED SUCCESSFULLY"
Write-Host ""
Write-Success "MyfxRealProxy has been installed and configured!"
Write-Host ""
Write-Host "INSTALLATION SUMMARY:" -ForegroundColor White -BackgroundColor DarkGreen
Write-Host "====================="
Write-Host "[+] Python 3.12 installed/verified" -ForegroundColor Green
Write-Host "[+] mitmproxy installed and configured" -ForegroundColor Green
Write-Host "[+] Payload files downloaded" -ForegroundColor Green
Write-Host "[+] SSL certificate generated and trusted" -ForegroundColor Green
Write-Host "[+] System proxy configured (127.0.0.1:8080)" -ForegroundColor Green
Write-Host "[+] Windows service created and started" -ForegroundColor Green
Write-Host "[+] Scheduled tasks configured" -ForegroundColor Green
Write-Host ""
Write-Host "IMPORTANT NEXT STEPS:" -ForegroundColor Yellow -BackgroundColor DarkRed
Write-Host "===================="
Write-Host "1. REBOOT Windows to apply certificate trust changes" -ForegroundColor Yellow
Write-Host "2. Service logs can be found in: $logs" -ForegroundColor Gray
Write-Host "3. Service status: " -NoNewline -ForegroundColor Gray
try {
    $finalServiceStatus = Get-Service -Name "MyfxRealProxy" -ErrorAction Stop
    Write-Host "$($finalServiceStatus.Status)" -ForegroundColor Green
} catch {
    Write-Host "Unknown" -ForegroundColor Red
}
Write-Host ""
Write-Host "Installation completed at: $(Get-Date)" -ForegroundColor Gray
Write-Host ""
Read-Host "Press Enter to exit"