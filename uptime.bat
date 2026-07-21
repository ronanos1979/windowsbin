@rem Summary:
@rem   Prints the Windows system boot time using systeminfo.
@rem Parameters:
@rem   None. This script does not read command-line arguments.

if /i "%~1"=="/?" goto :help
if /i "%~1"=="-help" goto :help
goto :main

:help
echo.
echo uptime.bat
echo ----------
echo Displays the Windows system boot time using systeminfo.
goto :eof

:main
rem powershell
rem (get-date) - (gcim Win32_OperatingSystem).LastBootUpTime

systeminfo | findstr /i "boot time"
