@echo off
rem Harness runtime shim (Windows) — dispatches to the platform Go binary.
rem Mirrors bin/harness (the POSIX /bin/sh shim) so that, once bin\ is on
rem PATH, a bare `harness <cmd>` works from cmd.exe and PowerShell (both
rem resolve .cmd via PATHEXT; the extension-less sh shim is not runnable
rem on Windows outside Git Bash).
rem On missing binary: emit a diagnostic on stderr and exit 0 with empty
rem stdout, matching the sh shim — so CC hooks treat it as "no decision"
rem and non-hook subcommands no-op silently. Never print JSON here.
setlocal

set "SCRIPT_DIR=%~dp0"

set "ARCH=amd64"
if /I "%PROCESSOR_ARCHITECTURE%"=="ARM64" set "ARCH=arm64"
if /I "%PROCESSOR_ARCHITEW6432%"=="ARM64" set "ARCH=arm64"

set "BINARY=%SCRIPT_DIR%harness-windows-%ARCH%.exe"

rem No native arm64 binary is shipped (bin/ would grow ~11MB for every user, and
rem every consumer clones the whole repo). Windows 11 on ARM runs the x64 build
rem under emulation, so fall back to it rather than giving up. If an arm64 binary
rem is ever added to bin/, the check above picks it up and this never fires.
if not exist "%BINARY%" set "BINARY=%SCRIPT_DIR%harness-windows-amd64.exe"

if not exist "%BINARY%" goto :nobinary

rem Dispatch outside a parenthesized block on purpose: cmd.exe expands %ERRORLEVEL%
rem when it PARSES a block, so `if exist (...) ... exit /b %ERRORLEVEL%` would return
rem the errorlevel from before the binary ran, not the binary's own exit code.
"%BINARY%" %*
exit /b %ERRORLEVEL%

:nobinary
echo chanpark-harness: no binary for windows-%ARCH% at %BINARY% (command %1 skipped). 1>&2
exit /b 0
