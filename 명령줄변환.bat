@echo off
rem ------------------------------------------------------------------
rem  hwptopdf - HWP / HWPX to PDF batch converter (command line)
rem  For the app window, run hwptopdf.vbs instead.
rem  Drag a folder onto this file, or pass a path as an argument.
rem
rem  ASCII-only AND CRLF line endings on purpose. See install bat.
rem ------------------------------------------------------------------
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0convert.ps1" %*
echo.
pause
endlocal
exit /b
