@echo off
title WinOpt Suite - Developed by Leone
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0WinOptSuite.ps1"
