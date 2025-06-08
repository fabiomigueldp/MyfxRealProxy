@echo off
rem service_wrapper.bat – launched by NSSM
setlocal
set "PATH=%ProgramFiles%\Python312;%ProgramFiles%\Python312\Scripts;%PATH%"
cd /d C:\MyfxRealProxy
if not exist logs mkdir logs
mitmdump -s force_real.py --listen-port 8080 --ssl-insecure --quiet --set log_file=logs\proxy.log