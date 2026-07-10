@rem Summary:
@rem   Prints the Windows system boot time using systeminfo.
@rem Parameters:
@rem   None. This script does not read command-line arguments.

rem powershell
rem (get-date) - (gcim Win32_OperatingSystem).LastBootUpTime

systeminfo | findstr /i "boot time"
