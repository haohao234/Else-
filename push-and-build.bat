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

echo [1/8] locating git ...
set "GITEXE="
if exist "C:\Program Files\Git\cmd\git.exe" set "GITEXE=C:\Program Files\Git\cmd\git.exe"
if defined GITEXE goto :git_ok
for /d %%D in ("%USERPROFILE%\.workbuddy\binaries\PortableGit\versions\*") do call :try_portable "%%~fD"
if defined GITEXE goto :git_ok
where git.exe >nul 2>&1
if not errorlevel 1 set "GITEXE=git.exe"
if defined GITEXE goto :git_ok
echo   [X] git not found.
echo       Install Git for Windows:  https://git-scm.com/download/win
goto :fail

:try_portable
if defined GITEXE goto :eof
if exist "%~1\cmd\git.exe" set "GITEXE=%~1\cmd\git.exe"
goto :eof

:git_ok
for %%P in ("%GITEXE%") do set "GITDIR=%%~dpP"
rem ---- 关键：把这几层目录都加进 PATH ----
rem 只加 cmd\ 是不够的：真正的子程序（git-remote-https / 凭据助手）在 mingw64\bin，
rem sh 在 usr\bin。不加会报 "git: 'remote-https' is not a git command"，
rem 或让凭据助手报 "git: command not found" —— 后者看起来像"没登录"，极具误导性。
set "GITBIN=%GITDIR%..\mingw64\bin"
set "GITUSR=%GITDIR%..\usr\bin"
set "PATH=%GITBIN%;%GITUSR%;%GITDIR%;%PATH%"
echo   git = %GITEXE%
"%GITEXE%" --version
"%GITEXE%" --version >> "%LOG%" 2>&1

echo [2/8] checking the https transport ...
"%GITEXE%" --exec-path > "%TEMP%\eles_core.txt" 2>nul
set "CORE="
for /f "usebackq tokens=* delims=" %%P in ("%TEMP%\eles_core.txt") do set "CORE=%%P"
if not defined CORE goto :transport_skip
echo   exec-path = %CORE%
if exist "%CORE%\git-remote-https.exe" goto :transport_ok
echo   [i] remote helper missing from exec-path - this is a known issue of
echo       incompletely-extracted portable builds. Repairing (copy only) ...
if not exist "%GITBIN%\git-remote-https.exe" goto :transport_bad
copy /y "%GITBIN%\git-remote-https.exe" "%CORE%\git-remote-https.exe" >nul 2>&1
if not exist "%GITBIN%\git-remote-http.exe" goto :transport_retest
copy /y "%GITBIN%\git-remote-http.exe" "%CORE%\git-remote-http.exe" >nul 2>&1
:transport_retest
if exist "%CORE%\git-remote-https.exe" echo   [ok] repaired
if not exist "%CORE%\git-remote-https.exe" goto :transport_bad
goto :transport_ok

:transport_bad
echo   [X] Cannot repair the portable git automatically.
echo       Please install Git for Windows instead:  https://git-scm.com/download/win
echo       (it is a normal installer; you do NOT need a Mac for this)
goto :fail

:transport_skip
echo   [i] skipped (git --exec-path returned nothing)
:transport_ok
echo.

echo [3/8] local repo state
"%GITEXE%" log --oneline -1
echo   -- uncommitted changes (empty = clean) --
"%GITEXE%" status --short
"%GITEXE%" log --oneline -1 >> "%LOG%" 2>&1
echo.

echo [4/8] credential helper
"%GITEXE%" config --global --get-all credential.helper
"%GITEXE%" config credential.helper manager
echo   (an empty first line is normal - it CLEARS the inherited helper list,
echo    then "manager" is appended. That is the intended fix.)
echo.

echo [5/8] remote url
set "URLFILE=%HERE%.push-url"
set "REPOURL="
if exist "%URLFILE%" for /f "usebackq tokens=* delims=" %%V in ("%URLFILE%") do set "REPOURL=%%V"
if defined REPOURL goto :have_url
echo   Create an EMPTY repo on GitHub first, then paste its URL here.
echo   Do NOT tick "Add a README" / ".gitignore" / "License" - that makes the
echo   remote non-empty and the push will be rejected.
echo.
set /p REPOURL="   repo url: "
if not defined REPOURL goto :fail
> "%URLFILE%" echo %REPOURL%
:have_url
rem ---- 归一化 .push-url：清掉 BOM 与首尾空白 ----
rem 为什么非做不可：写这个文件的不一定是我们（Windows PowerShell 的 -Encoding utf8
rem 就会写出带 BOM 的 UTF-8）。cmd 读进来时，第一个字符是那个看不见的 BOM，
rem git 收到的就是 "<BOM>https"，于是报：
rem     fatal: protocol 'https' is not supported
rem 这个错看起来像"协议不支持"，其实只是有个隐形字符 —— 靠肉眼查不出来。
powershell -NoProfile -Command "$p='%URLFILE%'; $u=[IO.File]::ReadAllText($p); $u=$u.Trim([char]0xFEFF,[char]0x20,[char]0x09,[char]0x0D,[char]0x0A); [IO.File]::WriteAllText($p,$u,(New-Object Text.UTF8Encoding($false)))" >nul 2>&1
set "REPOURL="
for /f "usebackq tokens=* delims=" %%V in ("%URLFILE%") do if not defined REPOURL set "REPOURL=%%V"
set "HEAD2=%REPOURL:~0,2%"
if /i "%HEAD2%"=="ht" goto :url_ok
if /i "%HEAD2%"=="gi" goto :url_ok
echo   [X] This does not look like a repo url: [%REPOURL%]
echo       Expected something starting with https:// or git@
del "%URLFILE%" >nul 2>&1
goto :fail
:url_ok
echo   %REPOURL%
echo url = %REPOURL% >> "%LOG%" 2>&1
echo.

echo [6/8] probing the target ...
echo   (this step separates wrong-url / auth-expired / network)
"%GITEXE%" ls-remote --heads "%REPOURL%" >> "%LOG%" 2>&1
if errorlevel 1 goto :probe_fail
echo   reachable OK
"%GITEXE%" remote remove origin >nul 2>&1
"%GITEXE%" remote add origin "%REPOURL%"
echo.

echo [7/8] pre-check: is the remote empty?
"%GITEXE%" fetch origin >nul 2>&1
"%GITEXE%" rev-list --count FETCH_HEAD > "%TEMP%\eles_rcount.txt" 2>nul
set "RCOUNT="
for /f "usebackq tokens=* delims=" %%C in ("%TEMP%\eles_rcount.txt") do set "RCOUNT=%%C"
if not defined RCOUNT set "RCOUNT=0"
if "%RCOUNT%"=="0" goto :proceed
echo   Remote already has %RCOUNT% commit(s); a plain push may be rejected.
set /p GO="   push anyway? (Y/N): "
if /i not "%GO%"=="Y" goto :abort
:proceed
echo.

echo [8/8] pushing (up to 3 attempts - connectivity to github is bursty)
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
rem NEVER trust the exit code alone - compare the refs.
"%GITEXE%" rev-parse HEAD > "%TEMP%\eles_local.txt" 2>nul
set "LOCAL="
for /f "usebackq tokens=* delims=" %%L in ("%TEMP%\eles_local.txt") do set "LOCAL=%%L"
"%GITEXE%" ls-remote origin refs/heads/main > "%TEMP%\eles_remote.txt" 2>nul
set "REMOTE="
for /f "usebackq tokens=1" %%L in ("%TEMP%\eles_remote.txt") do set "REMOTE=%%L"
if /i "%LOCAL%"=="%REMOTE%" goto :success
echo   push reported OK but the refs differ - treating as FAILURE.
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
echo   The cloud build starts automatically. Watch it here:
echo   %WEBURL%/actions
echo.
echo   For the compile result open the run, then the step
echo   "摘出错误与警告清单" - that step prints the error list.
echo ============================================================
start "" "%WEBURL%/actions"
pause
exit /b 0

:probe_fail
echo.
echo   [X] Cannot reach the remote. Raw error tail:
powershell -NoProfile -Command "Get-Content -Tail 12 '%LOG%'"
echo.
echo   - "repository not found"  -^> url wrong, or repo is private
echo                          and you are not signed in yet
echo   - "Authentication failed" -^> a browser window should open;
echo                          finish the sign-in and run this again
echo   - "Could not connect"/"timed out" -^> network. Run it again later;
echo                          github connectivity from CN is intermittent
goto :fail

:push_fail
echo.
echo   [X] Push failed after 3 attempts. Raw error tail:
powershell -NoProfile -Command "Get-Content -Tail 20 '%LOG%'"
echo.
echo   If it says "rejected" / "non-fast-forward": the remote is not empty.
echo   Delete the repo, recreate it WITHOUT any initial files, run again.
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
echo   ---- full log: %LOG% ----
echo   (send that file if you cannot tell what went wrong)
pause
exit /b 1
