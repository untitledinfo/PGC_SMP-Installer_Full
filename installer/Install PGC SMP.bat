@echo off
title PGC SMP Installer
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-PGC-SMP.ps1"
pause
