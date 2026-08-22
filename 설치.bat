@echo off
rem ------------------------------------------------------------------
rem  hwptopdf - Hancom automation security module installer (launcher)
rem  Run once per PC. No administrator rights needed (HKCU only).
rem
rem    install    :  double-click this file
rem    uninstall  :  run with  -Uninstall
rem
rem  ASCII-only AND CRLF line endings on purpose.
rem  cmd.exe reads .bat in the OEM codepage, and with LF-only endings it
rem  tracks the file position wrongly and can re-run the script after pause.
rem ------------------------------------------------------------------
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
echo.
pause
endlocal
exit /b
