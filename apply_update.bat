@echo off
:wait
tasklist /FI "PID eq 93772" 2>NUL | find "93772" >NUL
if not errorlevel 1 (timeout /t 1 /nobreak >NUL && goto wait)
xcopy /Y /E "C:\Users\mikel\AppData\Roaming\Godot\app_userdata\AbyssalDescent\updates\staging\*" "C:\Mike\Godot Projects\godot-2026\"
start "" "C:\Mike\Godot Projects\godot-2026\AbyssalDescent.exe"
rd /S /Q "C:\Users\mikel\AppData\Roaming\Godot\app_userdata\AbyssalDescent\updates\staging"
del /F /Q "C:/Users/mikel/AppData/Roaming/Godot/app_userdata/AbyssalDescent/updates/AbyssalDescent-Windows.zip"
