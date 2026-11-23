@echo off

set SCRIPTDIR=%~dp0
set SCRIPTDIR=%SCRIPTDIR:~0,-1%
set PATH=%SCRIPTDIR%;%PATH%
set USER=%USERNAME%
set HOME=%USERPROFILE%
set ENV=%SCRIPTDIR%\localrc

call %~dp0busybox sh

exit
