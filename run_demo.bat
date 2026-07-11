@echo off
setlocal
set "PROJECT_DIR=%~dp0"
set "AHK_EXE=D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"

if exist "%AHK_EXE%" goto run

for /f "tokens=2,*" %%A in ('reg query "HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall\AutoHotkey" /v InstallLocation 2^>nul ^| find "InstallLocation"') do set "AHK_HOME=%%B"
if defined AHK_HOME set "AHK_EXE=%AHK_HOME%\v2\AutoHotkey64.exe"
if exist "%AHK_EXE%" goto run

echo 未找到 AutoHotkey v2，请确认已安装 AutoHotkey 2.x。
pause
exit /b 1

:run
start "" "%AHK_EXE%" "%PROJECT_DIR%tools\demo_target.ahk"
exit /b 0
