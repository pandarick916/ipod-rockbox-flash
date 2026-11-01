@echo off
chcp 65001 >nul
title iPod 刷机 - 第 2 步：正式刷
cd /d "%~dp0"
echo.
echo  接下来会真的写入你的 iPod。
echo  倒计时 3 秒后自动开始，要取消就按 Ctrl+C。
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\ipod-setup.ps1"
echo.
echo  按任意键关闭
pause >nul
