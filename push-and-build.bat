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

:do_probe
rem sets PROBEOK=1 on success; honours PROXYARG when it is defined
set "PROBEOK="
set "PXC="
if defined PROXYARG set "PXC=-c http.proxy=%PROXYARG%"
"%GITEXE%" %PXC% ls-remote --heads "%REPOURL%" >> "%LOG%" 2>&1
if errorlevel 1 goto :eof
set "PROBEOK=1"
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
set "PROBEOK="
set "PROXYARG="
set "PROBE_TRY=0"
:probe_loop
set /a PROBE_TRY+=1
call :do_probe
if defined PROBEOK goto :probe_ok
if %PROBE_TRY% GEQ 3 goto :try_local_proxy
echo   not reachable yet (attempt %PROBE_TRY% of 3) - retrying in 6s ...
echo   probe attempt %PROBE_TRY% failed >> "%LOG%" 2>&1
timeout /t 6 /nobreak >nul
goto :probe_loop

:try_local_proxy
rem ---- local proxy fallback ----
rem Why this exists: direct connectivity to github.com:443 from CN is bursty.
rem It works for a while, then answers "Could not connect to server" for a while
rem (that is exactly how attempt #3 of this script died at 16:37).
rem If a local proxy happens to be running (Clash / v2ray / ...), it is worth a try.
rem Trust rule: a port is only accepted if ls-remote REALLY succeeds through it.
rem No guessing, no silent config changes - the probe decides.
echo   [i] direct probes failed - looking for a local proxy that really works ...
set "PROXYARG="
for %%P in (7890 7897 10809 10808 1080 8888 2080 33210) do call :try_proxy_port %%P
if not defined PROXYARG echo   [i] no usable local proxy found
if not defined PROXYARG goto :probe_fail
echo   [ok] reachable THROUGH THE PROXY %PROXYARG% - the push will use it too
goto :probe_ok

:try_proxy_port
rem two gates: (1) something is listening, (2) ls-remote actually works through it.
rem gate 2 is what keeps this honest - a SOCKS-only port accepts a TCP connect
rem but cannot carry an http.proxy, so it must be allowed to fail and move on.
if defined PROXYARG goto :eof
powershell -NoProfile -Command "try{$c=New-Object Net.Sockets.TcpClient;$c.Connect('127.0.0.1',%1);$c.Close();exit 0}catch{exit 1}" >nul 2>&1
if errorlevel 1 goto :eof
echo   [i] port %1 is listening - testing it ...
"%GITEXE%" -c http.proxy=http://127.0.0.1:%1 ls-remote --heads "%REPOURL%" >> "%LOG%" 2>&1
if errorlevel 1 goto :eof
set "PROXYARG=http://127.0.0.1:%1"
goto :eof

:probe_ok
set "PXC="
if defined PROXYARG set "PXC=-c http.proxy=%PROXYARG%"
echo   reachable OK
"%GITEXE%" remote remove origin >nul 2>&1
"%GITEXE%" remote add origin "%REPOURL%"
echo.

echo [7/8] pre-check: is the remote empty?
"%GITEXE%" %PXC% fetch origin >nul 2>&1
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

echo [8/8] pushing (up to 5 attempts - connectivity to github is bursty)
set "TRY=0"
:pushloop
set /a TRY+=1
echo   attempt %TRY% of 5 ...
"%GITEXE%" %PXC% push -u origin main >> "%LOG%" 2>&1
if not errorlevel 1 goto :verify
if %TRY% GEQ 5 goto :push_fail
echo   failed - retrying in 8s ...
echo   push attempt %TRY% failed >> "%LOG%" 2>&1
timeout /t 8 /nobreak >nul
goto :pushloop

:verify
rem NEVER trust the exit code alone - compare the refs.
"%GITEXE%" rev-parse HEAD > "%TEMP%\eles_local.txt" 2>nul
set "LOCAL="
for /f "usebackq tokens=* delims=" %%L in ("%TEMP%\eles_local.txt") do set "LOCAL=%%L"
"%GITEXE%" %PXC% ls-remote origin refs/heads/main > "%TEMP%\eles_remote.txt" 2>nul
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
if defined PROXYARG echo   via    = %PROXYARG%  (local proxy)
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
call :net_diag
echo.
echo   - "repository not found"  -^> url wrong, or repo is private
echo                          and you are not signed in yet
echo   - "Authentication failed" -^> a browser window should open;
echo                          finish the sign-in and run this again
echo   - "Could not connect"/"TIMEOUT" -^> it is the NETWORK, not the script.
echo                          Direct github access from CN flaps: it worked
echo                          20 minutes ago and can be dead for a while.
echo                          Take one of these:
echo                            1) if you normally use a VPN / proxy, turn it
echo                               ON and run this again (the script will
echo                               find a local proxy by itself if there is one)
echo                            2) wait a few minutes and run it again
goto :fail

:net_diag
rem 把"到底是 DNS、TCP 还是 git 自己的问题"摊开写清楚 ——
rem 不写的话，用户只能看到一句 Could not connect，无从判断该修什么。
set "NETOUT=%TEMP%\eles_net.txt"
powershell -NoProfile -Command "try{$ips=([Net.Dns]::GetHostAddresses('github.com') | ForEach-Object {$_.IPAddressToString}) -join ', '; Write-Output ('  DNS github.com      -> ' + $ips)}catch{Write-Output '  DNS github.com      -> FAILED (cannot resolve)'}" > "%NETOUT%" 2>&1
powershell -NoProfile -Command "try{$c=New-Object Net.Sockets.TcpClient;$r=$c.BeginConnect('github.com',443,$null,$null);if($r.AsyncWaitHandle.WaitOne(8000)){$c.EndConnect($r);$c.Close();Write-Output '  TCP github.com:443  -> OK'}else{Write-Output '  TCP github.com:443  -> TIMEOUT (blocked / no route)'}}catch{Write-Output ('  TCP github.com:443  -> FAILED ' + $_.Exception.Message)}" >> "%NETOUT%" 2>&1
powershell -NoProfile -Command "$p=@();foreach($n in 7890,7897,10809,10808,1080,8888,2080,33210){try{$c=New-Object Net.Sockets.TcpClient;$c.Connect('127.0.0.1',$n);$c.Close();$p+=$n}catch{}};if($p.Count -gt 0){Write-Output ('  local proxy ports   -> ' + ($p -join ', '))}else{Write-Output '  local proxy ports   -> none listening'}" >> "%NETOUT%" 2>&1
echo.
echo   --- network diagnostic -------------------------------
type "%NETOUT%"
echo   -----------------------------------------------------
type "%NETOUT%" >> "%LOG%"
goto :eof

:push_fail
echo.
echo   [X] Push failed after 5 attempts. Raw error tail:
powershell -NoProfile -Command "Get-Content -Tail 20 '%LOG%'"
call :net_diag
echo.
echo   If it says "rejected" / "non-fast-forward": the remote is not empty.
echo   Delete the repo, recreate it WITHOUT any initial files, run again.
echo   If it says "Could not connect": it is the network - see the notes above.
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
