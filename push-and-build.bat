@echo off
chcp 65001 >nul 2>&1
title Elese Cattery - push to GitHub and let CI compile
setlocal
set "HERE=%~dp0"
cd /d "%HERE%"
if errorlevel 1 goto :no_dir
set "LOG=%HERE%push-log.txt"
echo === Elese Cattery push log  %DATE% %TIME% === > "%LOG%"

echo ============================================================
echo   Elese Cattery  -  push + cloud build
echo   repo: %HERE%
echo   full log: push-log.txt
echo ============================================================
echo.

echo [1/7] locating git ...
set "GITEXE="
if exist "C:\Program Files\Git\cmd\git.exe" set "GITEXE=C:\Program Files\Git\cmd\git.exe"
if defined GITEXE goto :git_ok
for /d %%D in ("%USERPROFILE%\.workbuddy\binaries\PortableGit\versions\*") do call :try_portable "%%~fD"
if defined GITEXE goto :git_ok
where git.exe >nul 2>&1
if not errorlevel 1 set "GITEXE=git.exe"
if defined GITEXE goto :git_ok
echo   [X] git not found on this machine.
echo       Install Git for Windows, or keep the portable copy under
echo       %%USERPROFILE%%\.workbuddy\binaries\PortableGit\
goto :fail

:try_portable
if defined GITEXE goto :eof
if exist "%~1\cmd\git.exe" set "GITEXE=%~1\cmd\git.exe"
goto :eof

:git_ok
for %%P in ("%GITEXE%") do set "GITDIR=%%~dpP"
rem IMPORTANT: put git on PATH. The credential manager shells out to `git`
rem internally -- without PATH it dies with "git: command not found" and the
rem failure looks like "no credentials", not "PATH is broken".
set "PATH=%GITDIR%;%PATH%"
echo   git = %GITEXE%
"%GITEXE%" --version
"%GITEXE%" --version >> "%LOG%" 2>&1
echo.

echo [2/7] local repo state
"%GITEXE%" log --oneline -1
echo   -- uncommitted changes --
"%GITEXE%" status --short
echo   -- (empty above = clean) --
"%GITEXE%" log --oneline -1 >> "%LOG%" 2>&1
echo.

echo [3/7] credential helper
"%GITEXE%" config --global --get-all credential.helper
"%GITEXE%" config credential.helper manager
echo   (an empty line above is normal - it CLEARS the inherited list,
echo    then "manager" is appended. That is the intended fix.)
echo.

echo [4/7] remote url
set "URLFILE=%HERE%.push-url"
set "REPOURL="
if exist "%URLFILE%" for /f "usebackq tokens=* delims=" %%V in ("%URLFILE%") do set "REPOURL=%%V"
if defined REPOURL goto :have_url
echo   Create an EMPTY repo on GitHub first, then paste its URL here.
echo   Do NOT tick "Add a README" / ".gitignore" / "License" - that would
echo   make the remote non-empty and the push will be rejected.
echo.
set /p REPOURL="   repo url: "
if not defined REPOURL goto :fail
> "%URLFILE%" echo %REPOURL%
:have_url
echo   %REPOURL%
echo %REPOURL% >> "%LOG%" 2>&1
echo.

echo [5/7] probing the target (separates wrong-url / auth / network)
"%GITEXE%" ls-remote --heads "%REPOURL%" >> "%LOG%" 2>&1
if errorlevel 1 goto :probe_fail
echo   reachable OK
"%GITEXE%" remote remove origin >nul 2>&1
"%GITEXE%" remote add origin "%REPOURL%"
echo.

echo [6/7] pre-check: is the remote empty?
"%GITEXE%" fetch origin >nul 2>&1
"%GITEXE%" rev-list --count FETCH_HEAD > "%TEMP%\eles_rcount.txt" 2>nul
set "RCOUNT="
for /f "usebackq tokens=* delims=" %%C in ("%TEMP%\eles_rcount.txt") do set "RCOUNT=%%C"
if not defined RCOUNT set "RCOUNT=0"
if "%RCOUNT%"=="0" goto :proceed
echo   Remote already has %RCOUNT% commit(s).
echo   A plain push may be rejected (non-fast-forward).
set /p GO="   push anyway? (Y/N): "
if /i not "%GO%"=="Y" goto :abort
:proceed
echo.

echo [7/7] pushing (up to 3 attempts - github connectivity is bursty)
set "TRY=0"
:pushloop
set /a TRY+=1
echo   attempt %TRY% ...
"%GITEXE%" push -u origin main >> "%LOG%" 2>&1
if not errorlevel 1 goto :verify
if %TRY% GEQ 3 goto :push_fail
echo   failed - retrying in 5s ...
timeout /t 5 /nobreak >nul
goto :pushloop

:verify
rem NEVER trust the exit code alone. Compare the refs.
"%GITEXE%" rev-parse HEAD > "%TEMP%\eles_local.txt" 2>nul
set "LOCAL="
for /f "usebackq tokens=* delims=" %%L in ("%TEMP%\eles_local.txt") do set "LOCAL=%%L"
"%GITEXE%" ls-remote origin refs/heads/main > "%TEMP%\eles_remote.txt" 2>nul
set "REMOTE="
for /f "usebackq tokens=1" %%L in ("%TEMP%\eles_remote.txt") do set "REMOTE=%%L"
if /i "%LOCAL%"=="%REMOTE%" goto :success
echo   push said OK but the refs differ - treating as FAILURE.
echo   local  = %LOCAL%
echo   remote = %REMOTE%
goto :fail

:success
set "WEBURL=%REPOURL:.git=%"
echo.
echo ============================================================
echo   PUSHED OK
echo   local  = %LOCAL%
echo   remote = %REMOTE%
echo.
echo   The cloud build starts automatically.
echo   Watch it here:  %WEBURL%/actions
echo.
echo   For the compile result: open the run, then the step
echo   "摘出错误与警告清单" - that step prints the error list.
echo ============================================================
start "" "%WEBURL%/actions"
pause
exit /b 0

:probe_fail
echo.
echo   [X] Cannot reach the remote. Read push-log.txt for the raw error.
echo       - "repository not found"   -> url wrong, or the repo is private
echo                                     and you are not authenticated yet
echo       - "Authentication failed"  -> a browser window should have opened;
echo                                     finish the login and run this again
echo       - "Could not connect" / "timed out" -> network. Just run again
echo         later; github connectivity from CN is intermittent.
echo       - proxy errors             -> try turning the VPN off or on
echo.
echo   Raw error tail:
powershell -NoProfile -Command "Get-Content -Tail 12 '%LOG%'"
goto :fail

:push_fail
echo.
echo   [X] Push failed after 3 attempts. Raw error tail:
powershell -NoProfile -Command "Get-Content -Tail 20 '%LOG%'"
echo.
echo   If it mentions "rejected" / "non-fast-forward":
echo     the remote is not empty. Delete the repo and recreate it
echo     WITHOUT any initial files, then run this script again.
goto :fail

:abort
echo   aborted by user.
pause
exit /b 1

:no_dir
echo   [X] cannot enter the script directory.
pause
exit /b 1

:fail
echo.
echo   ---- full log ----
echo   %LOG%
echo   (send this file if you cannot tell what went wrong)
pause
exit /b 1
