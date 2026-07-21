@rem Summary:
@rem   Sets Java and Maven environment variables, prepends them to PATH, switches
@rem   to drive C:, and changes to the c:\dev\git workspace.
@rem Parameters:
@rem   None. This script does not read command-line arguments.

if /i "%~1"=="/?" goto :help
if /i "%~1"=="-help" goto :help
goto :main

:help
echo.
echo home.bat
echo --------
echo Sets JAVA_HOME (jdk-21.0.10), MAVEN_HOME (apache-maven-3.9.14), prepends
echo both to PATH, then cd to C:\dev\git.
echo.
echo Note: use `call home` to keep env vars in the current shell.
goto :eof

:main
rem set JAVA_HOME=c:\tools\jdk-25.0.2
set JAVA_HOME=c:\tools\jdk-21.0.10
set MAVEN_HOME=c:\tools\apache-maven-3.9.14
set PATH=%JAVA_HOME%\bin;%MAVEN_HOME%\bin;%PATH%
c:
rem cd c:\Users\ronan\eclipse-workspace
cd c:\dev\git
