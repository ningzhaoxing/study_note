@echo off
chcp 65001 > nul
setlocal enabledelayedexpansion

:: 修正版同步脚本（避免中文乱码问题）
set REMOTE=origin
set BRANCH=main

:: 检查git命令可用性
where git >nul 2>&1
if %errorlevel% neq 0 (
    echo 错误：系统未找到git命令，请先安装Git！
    pause
    exit /b 1
)

:: 验证git仓库
git rev-parse --is-inside-work-tree 2>nul
if errorlevel 1 (
    echo 错误：当前目录不是Git仓库！
    pause
    exit /b 1
)

:: 使用英文提示避免乱码
echo Pulling latest changes from %REMOTE%/%BRANCH%...
git pull %REMOTE% %BRANCH%
if errorlevel 1 (
    echo [ERROR] Pull failed
    pause
    exit /b 1
)

git add -A

git diff-index --quiet HEAD --
if errorlevel 1 (
    git commit -m "Auto-commit: %date% %time%"
    echo Pulling again before push...
    git pull %REMOTE% %BRANCH%
    git push %REMOTE% %BRANCH%
) else (
    echo No changes to commit.
)

pause