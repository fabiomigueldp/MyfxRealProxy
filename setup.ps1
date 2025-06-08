<#
  MyfxRealProxy setup.ps1
  One‑click installer – run as Administrator
#>
param()
Function Need-Admin {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object System.Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Need-Admin)) {
    Write-Host "Run this script as Administrator." -ForegroundColor Red
    exit 1
}

$InstallBase = "C:\MyfxRealProxy"

# Define expected SHA256 checksums for downloaded files
# IMPORTANT: These checksums MUST be updated if the files change.
$ExpectedChecksums = @{
    "python-3.12.3-amd64.exe" = "PYTHON_INSTALLER_SHA256_CHECKSUM_PLACEHOLDER" # Replace with actual checksum
    "nssm-2.24.zip"           = "NSSM_ZIP_SHA256_CHECKSUM_PLACEHOLDER"           # Replace with actual checksum
    "force_real.py"           = "FORCE_REAL_PY_SHA256_CHECKSUM_PLACEHOLDER"      # Replace with actual checksum
    "service_wrapper.bat"     = "SERVICE_WRAPPER_BAT_SHA256_CHECKSUM_PLACEHOLDER" # Replace with actual checksum
    "watchdog.ps1"            = "WATCHDOG_PS1_SHA256_CHECKSUM_PLACEHOLDER"       # Replace with actual checksum
    "update.bat"              = "UPDATE_BAT_SHA256_CHECKSUM_PLACEHOLDER"         # Replace with actual checksum
}

# Helper function to verify file checksum
function Test-FileChecksum {
    param (
        [string]$FilePath,
        [string]$ExpectedChecksum
    )
    if (-not (Test-Path $FilePath)) {
        Write-Host "File not found for checksum: $FilePath" -ForegroundColor Red
        return $false
    }
    $FileChecksum = (Get-FileHash -Algorithm SHA256 $FilePath).Hash.ToLower()
    if ($FileChecksum -ne $ExpectedChecksum.ToLower()) {
        Write-Host "Checksum mismatch for $FilePath." -ForegroundColor Red
        Write-Host "Expected: $ExpectedChecksum" -ForegroundColor Red
        Write-Host "Actual:   $FileChecksum" -ForegroundColor Red
        return $false
    }
    Write-Host "Checksum verified for $FilePath" -ForegroundColor Green
    return $true
}

$ErrorActionPreference = "Stop"
$logs   = "$InstallBase\logs"
$python = "$env:ProgramFiles\Python312\python.exe"
$mitmd  = "$env:ProgramFiles\Python312\Scripts\mitmdump.exe"
$nssm   = "$InstallBase\nssm.exe"

New-Item -ItemType Directory -Path $InstallBase -ErrorAction SilentlyContinue | Out-Null
New-Item -ItemType Directory -Path $logs -ErrorAction SilentlyContinue | Out-Null

# 1. Install Python 3.12 if missing
if (-not (Test-Path $python)) {
    Write-Host "[*] Installing Python..."
    $pyUrl = "https://www.python.org/ftp/python/3.12.3/python-3.12.3-amd64.exe"
    $pyTmp = "$env:TEMP\py312.exe"
    Invoke-WebRequest -Uri $pyUrl -OutFile $pyTmp
    if (-not (Test-FileChecksum -FilePath $pyTmp -ExpectedChecksum $ExpectedChecksums["python-3.12.3-amd64.exe"])) {
        throw "Checksum validation failed for Python installer. Aborting installation."
    }
    & $pyTmp /quiet InstallAllUsers=1 PrependPath=1 Include_test=0
    if ($LASTEXITCODE -ne 0) { throw "Python installation failed." }
}

# 2. Install mitmproxy
Write-Host "[*] Installing mitmproxy..."
& $python -m pip install --upgrade pip
& $python -m pip install mitmproxy==10.2.3

# 3. Download payload files
$repo = "https://raw.githubusercontent.com/yourrepo/myfxrealproxy/main"
$files = @("force_real.py","service_wrapper.bat","watchdog.ps1","update.bat") # Ensure this list is accurate
foreach ($f in $files) {
    $FilePath = "$InstallBase\$f"
    Invoke-WebRequest -Uri "$repo/$f" -OutFile $FilePath
    if (-not (Test-FileChecksum -FilePath $FilePath -ExpectedChecksum $ExpectedChecksums[$f])) {
        throw "Checksum validation failed for $f. Aborting installation."
    }
}

# 4. Generate mitmproxy CA cert & trust
& $mitmd -q --set confdir=$InstallBase init
$certPem = "$InstallBase\.mitmproxy\mitmproxy-ca-cert.pem"
certutil -addstore -f "Root" $certPem

# 5. Store existing proxy and set new proxy
# Define registry path and value name for WinHTTP proxy settings
$RegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Connections"
$ValueName = "WinHttpSettings"
$StoredProxyInfoFile = "$InstallBase\prev_proxy_info.txt"

# Check if the registry value exists and save its content or a marker
if (Test-Path -Path "$RegPath") {
    $CurrentProxySettings = Get-ItemProperty -Path $RegPath -Name $ValueName -ErrorAction SilentlyContinue
    if ($null -ne $CurrentProxySettings) {
        # Save the type and content. Content is byte array.
        "REG_BINARY_VALUE:" | Out-File $StoredProxyInfoFile
        $CurrentProxySettings.WinHttpSettings | Format-Hex - suffitWidth 4096 | Out-File -Append $StoredProxyInfoFile
    } else {
        # Value doesn't exist, means direct access or no specific proxy set at this level
        "DIRECT_ACCESS_OR_VALUE_ABSENT" | Out-File $StoredProxyInfoFile
    }
} else {
    # Key itself doesn't exist, also means direct access generally
    "DIRECT_ACCESS_KEY_ABSENT" | Out-File $StoredProxyInfoFile
}

# $prevProxy = (netsh winhttp show proxy) 2>&1
# $prevProxy | Out-File "$InstallBase\prev_proxy.txt"
netsh winhttp set proxy 127.0.0.1:8080

# 6. Download NSSM and create service
$nssmZip = "$env:TEMP\nssm.zip"
$nssmUrl = "https://nssm.cc/release/nssm-2.24.zip"
Invoke-WebRequest -Uri $nssmUrl -OutFile $nssmZip
if (-not (Test-FileChecksum -FilePath $nssmZip -ExpectedChecksum $ExpectedChecksums["nssm-2.24.zip"])) {
    throw "Checksum validation failed for NSSM zip. Aborting installation."
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::ExtractToDirectory($nssmZip,$InstallBase)
Copy-Item "$InstallBase\nssm-2.24\win64\nssm.exe" $nssm -Force

& $nssm install MyfxRealProxy "$InstallBase\service_wrapper.bat"
& $nssm set MyfxRealProxy AppDirectory $InstallBase
& $nssm set MyfxRealProxy Start SERVICE_AUTO_START
& $nssm set MyfxRealProxy AppStdout "$logs\service_wrapper_stdout.log"
& $nssm set MyfxRealProxy AppStderr "$logs\service_wrapper_stderr.log"
& $nssm start MyfxRealProxy

# 7. Create watchdog (every 30 s) and updater (7‑day)
$watchArgs = "-ExecutionPolicy Bypass -File `"$InstallBase\watchdog.ps1`""
schtasks /Create /TN "MyfxRealProxy Watchdog" /TR "powershell.exe $watchArgs" /SC SECOND /MO 30 /F

schtasks /Create /TN "MyfxRealProxy Update" /TR "$InstallBase\update.bat" /SC DAILY /MO 7 /ST 03:00 /F

Write-Host "[+] Installation complete. Reboot Windows to apply certificate trust."