@echo off
chcp 65001 >nul
title iPod 刷机 - 第 1 步：试跑（不改任何东西）
cd /d "%~dp0"
echo.
echo  这一步只看不写，你的 iPod 不会被改动。
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\ipod-setup.ps1" -DryRun
echo.
echo  按任意键关闭
pause >nul
