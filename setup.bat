@echo off
:: This is a shim for backward compatibility with older dashboard binaries 
:: tracking the project root and expecting setup.bat to exist.
call "%~dp0install.bat" %*
