@echo off
rem Wrapper for triage.ps1. Runs it with ExecutionPolicy Bypass.
rem Use /? or -help to see full help from triage.ps1.

if /i "%~1"=="/?" powershell -ExecutionPolicy Bypass -File "%~dp0triage.ps1" -Help & goto :eof
if /i "%~1"=="-help" powershell -ExecutionPolicy Bypass -File "%~dp0triage.ps1" -Help & goto :eof

powershell -ExecutionPolicy Bypass -File "%~dp0triage.ps1"
