@echo off
rem Summary:
rem   Writes MD5 hashes for files in the current directory to md5_hashes.txt.
rem Parameters:
rem   None. This script does not read command-line arguments.

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
