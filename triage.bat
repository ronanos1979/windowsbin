@echo off
rem Summary:
rem   Runs triage.ps1 with PowerShell execution policy bypassed for this invocation.
rem Parameters:
rem   None. This wrapper does not read command-line arguments.

powershell -ExecutionPolicy Bypass -File "%~dp0triage.ps1"
