# uninstall.ps1 – remove MyfxRealProxy completely
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Run as Administrator." -ForegroundColor Red
    exit 1
}
$base = "C:\MyfxRealProxy"
$nssm = "$base\nssm.exe"
if (Test-Path $nssm) {
    & $nssm stop MyfxRealProxy
    & $nssm remove MyfxRealProxy confirm
}
schtasks /Delete /TN "MyfxRealProxy Watchdog" /F
schtasks /Delete /TN "MyfxRealProxy Update" /F

# Restore previous proxy if stored
$prevFile = "$base\prev_proxy.txt"
if (Test-Path $prevFile) {
    $prev = Get-Content $prevFile
    if ($prev -match "Direct access") {
        netsh winhttp reset proxy
    } else {
        # Expect format "Proxy Server(s): proxy:port"
        $parts = ($prev | Select-String -Pattern "Proxy Server") -replace ".*:\s*"
        if ($parts) {
            netsh winhttp set proxy $parts
        }
    }
} else {
    netsh winhttp reset proxy
}

# Remove mitmproxy cert
certutil -delstore Root "mitmproxy"

# Delete folder
Remove-Item -Recurse -Force $base
Write-Host "MyfxRealProxy removed."