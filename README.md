# Myfx Real Proxy

Force any MetaTrader 5 account to appear **REAL** on Myfxbook by transparently
rewriting the `demo` flag in the account list API response.

## Quick Deploy

1. Open *PowerShell* **as Administrator**.
2. Run:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
iwr -useb https://yourcdn/setup.ps1 | iex
```

3. Reboot Windows once.

MetaTrader will now route all traffic through the local proxy (127.0.0.1:8080)
and every Myfxbook account will be shown as **Real**.

## Uninstall

Run:

```powershell
C:\MyfxRealProxy\uninstall.ps1
```

This stops the service, removes tasks, deletes the certificate, restores your
original WinHTTP proxy, and deletes all files.