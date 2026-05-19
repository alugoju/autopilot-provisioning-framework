@echo off
REM =========================================================
REM  SetupComplete.cmd - Automatic SCCM Cleanup for Autopilot
REM
REM  Purpose: Removes SCCM client and all artifacts after OOBE
REM           so device can enroll cleanly in Intune Autopilot
REM           without dual-management conflicts.
REM
REM  Execution: Windows runs this automatically after OOBE via
REM             C:\Windows\Setup\Scripts\ mechanism.
REM
REM  This script deletes itself after execution to prevent
REM  re-running on subsequent boots.
REM =========================================================

setlocal enabledelayedexpansion
set LogFile=C:\Windows\Temp\SetupComplete.log

echo ========================================================= >> "%LogFile%"
echo [%date% %time%] Starting SCCM Cleanup for Autopilot >> "%LogFile%"
echo ========================================================= >> "%LogFile%"

:: Wait for Windows services to stabilize after OOBE
timeout /t 20 >nul

:: Uninstall SCCM client via ccmsetup if present
if exist "%windir%\ccmsetup\ccmsetup.exe" (
    echo [%date% %time%] Uninstalling SCCM client... >> "%LogFile%"
    "%windir%\ccmsetup\ccmsetup.exe" /uninstall
    timeout /t 30 >nul
)

:: Stop and remove SCCM services
for %%S in (CcmExec ccmsetup smstsmgr) do (
    sc stop %%S >nul 2>&1
    sc delete %%S >nul 2>&1
)

:: Remove SCCM directories
for %%F in (
    "%windir%\CCM"
    "%windir%\CCMCache"
    "%windir%\ccmsetup"
    "%windir%\CCMTemp"
    "%windir%\SMS"
    "%ProgramFiles%\CCM"
    "%ProgramFiles(x86)%\CCM"
) do (
    if exist %%F (
        echo [%date% %time%] Removing %%F >> "%LogFile%"
        rmdir /s /q %%F
    )
)

:: Remove SCCM registry keys
for %%R in (
    "HKLM\SOFTWARE\Microsoft\CCM"
    "HKLM\SOFTWARE\Microsoft\CCMSetup"
    "HKLM\SOFTWARE\Microsoft\SMS"
    "HKLM\SOFTWARE\WOW6432Node\Microsoft\CCM"
    "HKLM\SYSTEM\CurrentControlSet\Services\CcmExec"
    "HKLM\SYSTEM\CurrentControlSet\Services\ccmsetup"
) do (
    reg delete %%R /f >nul 2>&1
)

:: Remove Software Center shortcuts
for %%L in (
    "%ProgramData%\Microsoft\Windows\Start Menu\Programs\Microsoft Endpoint Manager\Software Center.lnk"
    "%ProgramData%\Microsoft\Windows\Start Menu\Programs\System Center\Software Center.lnk"
) do (
    if exist %%L del /f /q %%L
)

:: Remove SCCM scheduled tasks
schtasks /delete /tn "Configuration Manager*" /f >nul 2>&1

echo [%date% %time%] SCCM cleanup completed successfully >> "%LogFile%"
echo ========================================================= >> "%LogFile%"

:: Self-delete to prevent re-execution on subsequent boots
del "%~f0"

endlocal
exit /b 0
