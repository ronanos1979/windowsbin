@rem Summary:
@rem   Sets Java and LexiconLair environment variables, changes into the
@rem   template project folder, and prints common backend/frontend commands.
@rem Parameters:
@rem   None. This script does not read command-line arguments.

if /i "%~1"=="/?" goto :help
if /i "%~1"=="-help" goto :help
goto :main

:help
echo.
echo template.bat
echo ------------
echo Sets JAVA_HOME and LEXICONLAIR_PG_PASSWORD, cd to
echo C:\dev\git\SpringBootApps\template, prints common Gradle/npm commands.
echo.
echo Note: use `call template` to keep env vars in the current shell.
echo Related: llair.bat is the same setup for the LexiconLair project.
goto :eof

:main
rem set JAVA_HOME=c:\tools\jdk-25.0.2
set JAVA_HOME=c:\tools\jdk-21.0.10
set LEXICONLAIR_PG_PASSWORD=change-me

rem set PATH=%JAVA_HOME%\bin;%PATH%

c:

cd c:\dev\git\SpringBootApps\template

@echo off
echo =================================================================================
echo For backend
echo ---------------------------------------------------------------------------------
echo(
echo gradlew clean build test
echo(
echo gradlew bootRun
echo(
echo =================================================================================
echo For Frontend
echo ---------------------------------------------------------------------------------
echo(
echo npm run build
echo(
echo npm run test
echo(
echo npm run preview
echo(
echo npm run dev
echo(
echo ---------------------------------------------------------------------------------
echo(
echo(To kill
echo(
echo netstat -ano ^| findstr :5173
echo(
echo taskkill ^/PID ^<pid^> ^/F
echo(
echo =================================================================================
