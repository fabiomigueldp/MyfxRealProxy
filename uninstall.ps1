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
$RegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Connections"
$ValueName = "WinHttpSettings"
$StoredProxyInfoFile = "$base\prev_proxy_info.txt"

if (Test-Path $StoredProxyInfoFile) {
    $StoredInfo = Get-Content $StoredProxyInfoFile
    $InfoType = $StoredInfo[0]

    if ($InfoType -eq "REG_BINARY_VALUE:") {
        # Extract hex string, convert to byte array, and set registry value
        $HexBytes = ($StoredInfo | Select-Object -Skip 1) -join ""
        # Clean up Format-Hex output: remove address, hyphens, spaces, and any non-hex characters
        $CleanedHex = $HexBytes -replace '(?m)^[0-9a-fA-F]+[\s-]+|[\s-]|[^0-9a-fA-F]'

        $Bytes = [byte[]]::new($CleanedHex.Length / 2)
        for ($i = 0; $i -lt $CleanedHex.Length; $i += 2) {
            $Bytes[$i/2] = [System.Convert]::ToByte($CleanedHex.Substring($i, 2), 16)
        }
        Set-ItemProperty -Path $RegPath -Name $ValueName -Value $Bytes -Type Binary -Force
        Write-Host "Restored WinHTTP proxy settings from stored binary value."
    } elseif (($InfoType -eq "DIRECT_ACCESS_OR_VALUE_ABSENT") -or ($InfoType -eq "DIRECT_ACCESS_KEY_ABSENT")) {
        # Remove the value to revert to direct access
        if (Get-ItemProperty -Path $RegPath -Name $ValueName -ErrorAction SilentlyContinue) {
            Remove-ItemProperty -Path $RegPath -Name $ValueName -Force
        }
        Write-Host "Reset WinHTTP proxy to direct access (value absent or key absent)."
    } else {
        Write-Host "Unknown proxy info type in $StoredProxyInfoFile. Resetting proxy as a fallback."
        netsh winhttp reset proxy
    }
    Remove-Item $StoredProxyInfoFile -ErrorAction SilentlyContinue
} else {
    Write-Host "No previous proxy information found. Resetting proxy as a fallback."
    netsh winhttp reset proxy
}

# Remove mitmproxy cert
certutil -delstore Root "mitmproxy"

# Delete folder
Remove-Item -Recurse -Force $base
Write-Host "MyfxRealProxy removed."