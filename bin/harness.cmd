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

if exist "%BINARY%" (
  "%BINARY%" %*
  exit /b %ERRORLEVEL%
)

echo chanpark-harness: no binary for windows-%ARCH% at %BINARY% (command %1 skipped). 1>&2
exit /b 0
