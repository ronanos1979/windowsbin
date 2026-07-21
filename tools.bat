@rem Summary:
@rem   Switches to drive C: and changes to the c:\tools directory.
@rem Parameters:
@rem   None. This script does not read command-line arguments.

if /i "%~1"=="/?" goto :help
if /i "%~1"=="-help" goto :help
goto :main

:help
echo.
echo tools.bat
echo ---------
echo Switches to C:\tools.
echo.
echo Note: use `call tools` if you want it to affect your current shell's working directory.
goto :eof

:main
c:
cd c:\tools
