@echo off
rem update.bat – weekly auto-update
setlocal
set BASE=C:\MyfxRealProxy
set PY=%ProgramFiles%\Python312\python.exe
set LOGFILE="%BASE%\logs\update_script.log"
set REPO_BASE_URL=https://raw.githubusercontent.com/yourrepo/myfxrealproxy/main

echo %DATE% %TIME% - Update process started >> %LOGFILE%

if exist "%PY%" (
    echo %DATE% %TIME% - Updating mitmproxy... >> %LOGFILE%
    "%PY%" -m pip install --upgrade mitmproxy==10.2.3 >> %LOGFILE% 2>&1
    if errorlevel 1 echo %DATE% %TIME% - mitmproxy update failed. Check log. >> %LOGFILE%
) else (
    echo %DATE% %TIME% - Python not found, cannot update mitmproxy. >> %LOGFILE%
)

set SCRIPTS_TO_UPDATE=force_real.py watchdog.ps1 service_wrapper.bat
echo %DATE% %TIME% - Updating scripts: %SCRIPTS_TO_UPDATE% >> %LOGFILE%

for %%F in (%SCRIPTS_TO_UPDATE%) do (
    echo %DATE% %TIME% - Downloading %%F... >> %LOGFILE%
    curl -s -o "%BASE%\%%F" "%REPO_BASE_URL%/%%F" >> %LOGFILE% 2>&1
    if errorlevel 1 (
        echo %DATE% %TIME% - curl failed for %%F. Trying PowerShell... >> %LOGFILE%
        powershell -ExecutionPolicy Bypass -Command "try { Invoke-WebRequest -UseBasicParsing -Uri '%REPO_BASE_URL%/%%F' -OutFile '%BASE%\%%F' } catch { Write-Error $_; exit 1 }" >> %LOGFILE% 2>&1
        if errorlevel 1 (
            echo %DATE% %TIME% - PowerShell download also failed for %%F. >> %LOGFILE%
        ) else (
            echo %DATE% %TIME% - %%F downloaded successfully with PowerShell. >> %LOGFILE%
        )
    ) else (
        echo %DATE% %TIME% - %%F downloaded successfully with curl. >> %LOGFILE%
    )
)

echo %DATE% %TIME% - Checking for new version of update.bat... >> %LOGFILE%
curl -s -o "%BASE%\update_new.bat" "%REPO_BASE_URL%/update.bat" >> %LOGFILE% 2>&1
if errorlevel 1 (
    echo %DATE% %TIME% - curl failed for update.bat. Trying PowerShell... >> %LOGFILE%
    powershell -ExecutionPolicy Bypass -Command "try { Invoke-WebRequest -UseBasicParsing -Uri '%REPO_BASE_URL%/update.bat' -OutFile '%BASE%\update_new.bat' } catch { Write-Error $_; exit 1 }" >> %LOGFILE% 2>&1
    if errorlevel 1 (
        echo %DATE% %TIME% - PowerShell download also failed for update.bat. >> %LOGFILE%
    ) else (
        echo %DATE% %TIME% - New version of update.bat downloaded to update_new.bat. It will be used on next scheduled run if manually replaced. >> %LOGFILE%
    )
) else (
    echo %DATE% %TIME% - New version of update.bat downloaded to update_new.bat with curl. It will be used on next scheduled run if manually replaced. >> %LOGFILE%
)

echo %DATE% %TIME% - Restarting MyfxRealProxy service... >> %LOGFILE%
nssm stop MyfxRealProxy >> %LOGFILE% 2>&1
nssm start MyfxRealProxy >> %LOGFILE% 2>&1
echo %DATE% %TIME% - Update process finished. >> %LOGFILE%
endlocal