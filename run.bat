@echo off
rem Starts the game. Set GODOT to your Godot 4.7 executable if it lives elsewhere.
if "%GODOT%"=="" set "GODOT=%USERPROFILE%\Documents\Godot\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT%" (
  echo Godot 4.7 not found at "%GODOT%". Set the GODOT variable to its path.
  pause
  exit /b 1
)
start "" "%GODOT%" --path "%~dp0."
