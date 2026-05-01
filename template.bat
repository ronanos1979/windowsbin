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

