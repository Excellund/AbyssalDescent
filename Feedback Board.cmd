@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\feedback-board\start.ps1" %*
if errorlevel 1 pause
