@echo off
setlocal
title After The Storm - Launcher
set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "GODOT_EXE="

if exist "%SCRIPT_DIR%\Godot_v4.7.2-stable_win64.exe" set "GODOT_EXE=%SCRIPT_DIR%\Godot_v4.7.2-stable_win64.exe"
if "%GODOT_EXE%"=="" if exist "K:\Godot_v4.7.2-stable_win64.exe" set "GODOT_EXE=K:\Godot_v4.7.2-stable_win64.exe"
if "%GODOT_EXE%"=="" if exist "%SCRIPT_DIR%\..\TankCity\.godot-bin\Godot_v4.3-stable_win64.exe" set "GODOT_EXE=%SCRIPT_DIR%\..\TankCity\.godot-bin\Godot_v4.3-stable_win64.exe"
if "%GODOT_EXE%"=="" if exist "K:\Test\TankCity\.godot-bin\Godot_v4.3-stable_win64.exe" set "GODOT_EXE=K:\Test\TankCity\.godot-bin\Godot_v4.3-stable_win64.exe"
if "%GODOT_EXE%"=="" (
    for %%F in ("%SCRIPT_DIR%\godot*.exe" "%SCRIPT_DIR%\Godot*.exe") do (
        if exist "%%~fF" set "GODOT_EXE=%%~fF"
    )
)
if "%GODOT_EXE%"=="" (
    where godot >nul 2>&1
    if not errorlevel 1 set "GODOT_EXE=godot"
)

if "%GODOT_EXE%"=="" (
    echo [ERROR] Godot engine executable was not found.
    echo Please place a Godot 4.3+ executable in this directory:
    echo   %SCRIPT_DIR%
    pause
    exit /b 1
)

echo ========================================================
echo             AFTER THE STORM / AFTER WIND
echo              Game Launcher (Godot 4)
echo ========================================================
echo [OK] Engine: %GODOT_EXE%
echo [OK] Project: %SCRIPT_DIR%
echo.

if "%~1"=="--test" goto do_test
if "%~1"=="-t" goto do_test
if "%~1"=="--editor" goto do_editor
if "%~1"=="-e" goto do_editor

if "%~1"=="" (
    echo Launching game...
    start "" "%GODOT_EXE%" --path "%SCRIPT_DIR%"
    goto done
) else (
    echo Launching with arguments: %*
    start "" "%GODOT_EXE%" --path "%SCRIPT_DIR%" %*
    goto done
)

:do_editor
echo Launching Godot Editor...
start "" "%GODOT_EXE%" -e --path "%SCRIPT_DIR%"
goto done

:do_test
echo Running test suite headless...
"%GODOT_EXE%" --headless --path "%SCRIPT_DIR%" -s "tests/test_stage13_polish_and_finale.gd"
goto done

:done
