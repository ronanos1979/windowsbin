rem powershell
rem (get-date) - (gcim Win32_OperatingSystem).LastBootUpTime

systeminfo | findstr /i "boot time"