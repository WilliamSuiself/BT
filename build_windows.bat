@echo off
chcp 65001 > nul
setlocal

echo ========================================
echo   BT Safe - Windows 编译脚本
echo ========================================
echo.

REM ---------- 1. 检查 Flutter ----------
where flutter > nul 2>&1
if errorlevel 1 (
    echo [ERROR] 未检测到 flutter 命令
    echo 请先安装 Flutter SDK 并加入 PATH：
    echo   https://docs.flutter.dev/get-started/install/windows
    echo 安装后重启此脚本。
    pause
    exit /b 1
)

echo [1/5] flutter 版本：
flutter --version
echo.

REM ---------- 2. pub get ----------
echo [2/5] flutter pub get ...
call flutter pub get
if errorlevel 1 goto :error
echo.

REM ---------- 3. 启用 windows desktop ----------
echo [3/5] flutter config --enable-windows-desktop
call flutter config --enable-windows-desktop
echo.

REM ---------- 4. 构建 release ----------
echo [4/5] flutter build windows --release ...
call flutter build windows --release
if errorlevel 1 goto :error
echo.

REM ---------- 5. 复制运行时 DLL ----------
echo [5/5] 复制运行时 DLL 到输出目录 ...
set "SRC=build\windows\x64\runner\Release"
set "DST=%SRC%\bt_safe"
if not exist "%DST%" mkdir "%DST%"

REM 把 bt_safe.exe 同级的运行时依赖拷贝到 bt_safe 子目录，
REM 这样用户拿整个 %DST% 就能直接运行
copy /Y "%SRC%\bt_safe.exe" "%DST%\" > nul
copy /Y "%SRC%\*.dll" "%DST%\" > nul
copy /Y "%SRC%\data" "%DST%\" > nul 2>&1
xcopy /Y /E /I "%SRC%\data" "%DST%\data" > nul 2>&1

echo.
echo ========================================
echo   编译成功！
echo ========================================
echo.
echo 输出目录：
echo   %CD%\%DST%
echo.
echo 进入该目录双击 bt_safe.exe 即可运行。
echo.
pause
exit /b 0

:error
echo.
echo [ERROR] 编译失败，请查看上方日志
pause
exit /b 1
