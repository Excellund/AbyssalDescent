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
  echo   launch_mp_duo.bat
  echo   launch_mp_duo.bat "C:\Path\To\AbyssalDescent.exe"
  pause
  exit /b 1
)

echo Using executable:
echo   "%GODOT_EXE%"
echo.
echo Both instances will go through the real Cloudflare tunnel path.
echo Host writes the room code to user://mp_duo_room_code.txt; joiner reads it.
echo.

echo Launching host instance (real tunnel)...
start "Godot Duo Host" /D "%PROJECT_DIR%" "%GODOT_EXE%" --mp-duo-host

timeout /t 2 /nobreak >nul

echo Launching joiner instance (real tunnel)...
start "Godot Duo Join" /D "%PROJECT_DIR%" "%GODOT_EXE%" --mp-duo-join

echo Launched host and joiner instances.
endlocal
