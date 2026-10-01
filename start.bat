@echo off
setlocal EnableExtensions

rem ============================================================
rem  Launcher for the Godot monopoly project in this folder.
rem  Usage:
rem    start.bat                          find Godot and run the game
rem    start.bat "C:\path\Godot.exe"      run with a specific Godot exe
rem  Double-click friendly.
rem ============================================================

set "PROJECT_DIR=%~dp0."
set "GODOT=%~1"

if defined GODOT if not exist "%GODOT%" set "GODOT="

if not defined GODOT call :find_godot

if not defined GODOT (
    echo.
    echo [ERROR] Godot 4 executable not found.
    echo   - install Godot 4.x from https://godotengine.org/download
    echo   - then either add it to PATH, or run:
    echo       start.bat "C:\path\to\Godot_v4.x-stable_win64.exe"
    echo.
    pause
    exit /b 1
)

rem ---- class-cache freshness check ----
rem .godot/ is gitignored and Godot's game mode never rebuilds the global script
rem class cache (global_script_class_cache.cfg). A pull that adds a class_name
rem script therefore leaves the cache stale: autoloads fail to parse and every
rem menu button touching them goes dead. Import only when the cache is missing
rem or does not know some class declared under scripts/ (where the game's
rem class_name scripts live; tests/ is not loaded by the game).
set "CACHE=%PROJECT_DIR%\.godot\global_script_class_cache.cfg"
set "STALE=1"
if exist "%CACHE%" (
    set "STALE=0"
    pushd "%PROJECT_DIR%"
    for %%F in (scripts\*.gd) do (
        for /f "tokens=2" %%C in ('findstr /b /c:"class_name " "%%F" 2^>nul') do (
            findstr /c:"%%C" ".godot\global_script_class_cache.cfg" >nul 2>nul || set "STALE=1"
        )
    )
    popd
)

if "%STALE%"=="1" (
    echo [setup] importing resources ^(first run, or code changed since last import^)...
    "%GODOT%" --headless --import --path "%PROJECT_DIR%"
    if errorlevel 1 (
        echo [WARN] import returned an error; launching anyway.
    )
)

echo Launching game with: %GODOT%
start "" "%GODOT%" --path "%PROJECT_DIR%"
exit /b 0

:find_godot
rem 1) godot already on PATH
where godot >nul 2>nul && (
    set "GODOT=godot"
    exit /b 0
)
rem 2) known install locations
for %%P in (
    "D:\Godot\Godot_v4.6.2-stable_win64.exe"
    "D:\develp\Godot\Godot_v4.6.2-stable_win64.exe"
    "%ProgramFiles%\Godot\Godot.exe"
    "%ProgramFiles(x86)%\Godot\Godot.exe"
    "%LOCALAPPDATA%\Programs\Godot\Godot.exe"
) do (
    if not defined GODOT if exist "%%~P" set "GODOT=%%~P"
)
if defined GODOT exit /b 0
rem 3) last resort: search likely folders for any Godot_v*.exe
for %%D in (
    "D:\Godot"
    "D:\develp\Godot"
    "%LOCALAPPDATA%\Programs"
    "%ProgramFiles%"
    "%ProgramFiles(x86)%"
) do (
    if not defined GODOT call :search_dir "%%~D"
)
exit /b 0

:search_dir
for /f "delims=" %%F in ('dir /b /s /o-n "%~1\Godot_v*.exe" 2^>nul ^| findstr /i /v "console server linux mac web"') do (
    if not defined GODOT set "GODOT=%%F"
)
exit /b 0
