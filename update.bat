@echo off
rem update.bat – weekly auto‑update
setlocal
set BASE=C:\MyfxRealProxy
set PY=%ProgramFiles%\Python312\python.exe

if exist "%PY%" (
    "%PY%" -m pip install --upgrade mitmproxy==10.* >> "%BASE%\logs\update.log" 2>&1
) else (
    echo Python not found >> "%BASE%\logs\update.log"
    goto :eof
)

curl -s -o "%BASE%\\force_real.py" https://raw.githubusercontent.com/yourrepo/myfxrealproxy/main/force_real.py 2>>"%BASE%\\logs\\update.log"
if %errorlevel% neq 0 (
    powershell -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/yourrepo/myfxrealproxy/main/force_real.py' -OutFile '%BASE%\\force_real.py'"
)

nssm stop MyfxRealProxy
nssm start MyfxRealProxy