# watchdog.ps1 – restart service if not running
$logDir = "C:\MyfxRealProxy\logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$svc = Get-Service -Name MyfxRealProxy -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -ne 'Running') {
    Start-Service MyfxRealProxy
    Add-Content "$logDir\watchdog.log" "$(Get-Date -f o) restarted service"
}