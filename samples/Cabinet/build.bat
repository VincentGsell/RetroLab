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

rem GS-Core : par defaut, le dossier indique dans dcc64.cfg.
rem Si GS-Core est ailleurs sur ce poste, definir GSCORE (ex. setx GSCORE "D:\libs\GS-Core").
set "GSCORE_U="
if defined GSCORE (
  if not exist "%GSCORE%\core\" (
    echo [ERREUR] GSCORE=%GSCORE% : pas de dossier core.
    exit /b 1
  )
  echo GS-Core : %GSCORE%
  set GSCORE_U=-U"%GSCORE%\core" -U"%GSCORE%\json\src" -U"%GSCORE%\json\src\impl\gsJson"
)

if not exist bin\Win64\dcu mkdir bin\Win64\dcu

"%BDSROOT%bin\dcc64.exe" -U"%BDSROOT%lib\Win64\release" -U"%BDSROOT%lib\Win64\debug" %GSCORE_U% Cabinet.dpr
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" if not defined GSCORE echo [AIDE] Unite GS.* ou gs.json* introuvable ? GS-Core est ailleurs sur ce poste : definir GSCORE.
echo.
echo Exit code: %RC%
exit /b %RC%
