@echo off
cd /d "%~dp0"

set "BDSROOT="
for /f "tokens=*" %%K in ('reg query "HKLM\SOFTWARE\WOW6432Node\Embarcadero\BDS" 2^>nul') do set "BDSVER=%%~nxK"
for /f "tokens=2,*" %%A in ('reg query "HKLM\SOFTWARE\WOW6432Node\Embarcadero\BDS\%BDSVER%" /v RootDir 2^>nul ^| %SystemRoot%\System32\findstr.exe /i "RootDir"') do set "BDSROOT=%%B"

if "%BDSROOT%"=="" (
  echo [ERREUR] Delphi introuvable dans le registre BDS.
  exit /b 1
)
echo Studio %BDSVER% : %BDSROOT%

if not exist bin\Win64\dcu mkdir bin\Win64\dcu

"%BDSROOT%bin\dcc64.exe" -U"%BDSROOT%lib\Win64\release" -U"%BDSROOT%lib\Win64\debug" Cabinet.dpr
echo.
echo Exit code: %ERRORLEVEL%
exit /b %ERRORLEVEL%
