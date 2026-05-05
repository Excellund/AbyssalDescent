@echo off
setlocal

set "PROJECT_DIR=%~dp0"
set "DEFAULT_EXE=%PROJECT_DIR%AbyssalDescent.exe"

if "%~1"=="" (
  set "GODOT_EXE=%DEFAULT_EXE%"
) else (
  set "GODOT_EXE=%~1"
)

if not exist "%GODOT_EXE%" (
  echo Could not find executable:
  echo   "%GODOT_EXE%"
  echo.
  echo Usage:
  echo   launch_local_mp_pair.bat
  echo   launch_local_mp_pair.bat "C:\Path\To\AbyssalDescent.exe"
  pause
  exit /b 1
)

echo Using executable:
echo   "%GODOT_EXE%"

echo Launching host instance...
start "Godot Local Host" /D "%PROJECT_DIR%" "%GODOT_EXE%" --mp-dev-host

timeout /t 1 /nobreak >nul

echo Launching joiner instance...
start "Godot Local Join" /D "%PROJECT_DIR%" "%GODOT_EXE%" --mp-dev-join

echo Launched host and joiner instances.
endlocal
