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

$ErrorActionPreference = "Stop"
$base   = "C:\MyfxRealProxy"
$logs   = "$base\logs"
$python = "$env:ProgramFiles\Python312\python.exe"
$mitmd  = "$env:ProgramFiles\Python312\Scripts\mitmdump.exe"
$nssm   = "$base\nssm.exe"

New-Item -ItemType Directory -Path $base -ErrorAction SilentlyContinue | Out-Null
New-Item -ItemType Directory -Path $logs -ErrorAction SilentlyContinue | Out-Null

# 1. Install Python 3.12 if missing
if (-not (Test-Path $python)) {
    Write-Host "[*] Installing Python..."
    $pyUrl = "https://www.python.org/ftp/python/3.12.3/python-3.12.3-amd64.exe"
    $pyTmp = "$env:TEMP\py312.exe"
    Invoke-WebRequest -Uri $pyUrl -OutFile $pyTmp
    & $pyTmp /quiet InstallAllUsers=1 PrependPath=1 Include_test=0
    if ($LASTEXITCODE -ne 0) { throw "Python installation failed." }
}

# 2. Install mitmproxy
Write-Host "[*] Installing mitmproxy..."
& $python -m pip install --upgrade pip
& $python -m pip install mitmproxy==10.*

# 3. Download payload files
$repo = "https://raw.githubusercontent.com/yourrepo/myfxrealproxy/main"
$files = @("force_real.py","service_wrapper.bat","watchdog.ps1","update.bat")
foreach ($f in $files) {
    Invoke-WebRequest -Uri "$repo/$f" -OutFile "$base\$f"
}

# 4. Generate mitmproxy CA cert & trust
& $mitmd -q --set confdir=$base init
$certPem = "$base\.mitmproxy\mitmproxy-ca-cert.pem"
certutil -addstore -f "Root" $certPem

# 5. Store existing proxy and set new proxy
$prevProxy = (netsh winhttp show proxy) 2>&1
$prevProxy | Out-File "$base\prev_proxy.txt"
netsh winhttp set proxy 127.0.0.1:8080

# 6. Download NSSM and create service
$nssmZip = "$env:TEMP\nssm.zip"
$nssmUrl = "https://nssm.cc/release/nssm-2.24.zip"
Invoke-WebRequest -Uri $nssmUrl -OutFile $nssmZip
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::ExtractToDirectory($nssmZip,$base)
Copy-Item "$base\nssm-2.24\win64\nssm.exe" $nssm -Force

& $nssm install MyfxRealProxy $mitmd "-s" "$base\force_real.py" "--listen-port" "8080" "--ssl-insecure" "--quiet"
& $nssm set MyfxRealProxy AppDirectory $base
& $nssm set MyfxRealProxy Start SERVICE_AUTO_START
& $nssm set MyfxRealProxy AppStdout "$logs\service.log"
& $nssm set MyfxRealProxy AppStderr "$logs\service.err"
& $nssm start MyfxRealProxy

# 7. Create watchdog (every 30 s) and updater (7‑day)
$watchArgs = "-ExecutionPolicy Bypass -File `"$base\watchdog.ps1`""
schtasks /Create /TN "MyfxRealProxy Watchdog" /TR "powershell.exe $watchArgs" /SC SECOND /MO 30 /F

schtasks /Create /TN "MyfxRealProxy Update" /TR "$base\update.bat" /SC DAILY /MO 7 /ST 03:00 /F

Write-Host "[+] Installation complete. Reboot Windows to apply certificate trust."