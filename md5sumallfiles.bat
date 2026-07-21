@echo off
rem Summary:
rem   Writes MD5 hashes for files in the current directory to md5_hashes.txt.
rem Parameters:
rem   None. This script does not read command-line arguments.

if /i "%~1"=="/?" goto :help
if /i "%~1"=="-help" goto :help
goto :main

:help
echo.
echo md5sumallfiles.bat
echo ------------------
echo Writes MD5 hash of every file in the current directory to md5_hashes.txt
echo using certutil.
echo.
echo Run from the folder you want to hash.
goto :eof

:main
set "OUT=md5_hashes.txt"

echo MD5 hashes for files in %CD% > "%OUT%"
echo. >> "%OUT%"

for %%F in (*) do (
  if not exist "%%F\" (
    echo %%F
    echo %%F >> "%OUT%"
    certutil -hashfile "%%F" MD5 | findstr /v "hash CertUtil" >> "%OUT%"
    echo. >> "%OUT%"
  )
)

echo Done. Results saved to %OUT%
pause
