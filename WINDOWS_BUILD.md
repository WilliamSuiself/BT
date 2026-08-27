# 在 Windows 上编译 BT Safe

Flutter Desktop **不支持交叉编译**——必须在 Windows 主机上跑 `flutter build windows`。

## 步骤

### 1. 在 Windows 上安装 Flutter

- 下载：https://docs.flutter.dev/get-started/install/windows
- 解压到 `C:\flutter`
- 把 `C:\flutter\bin` 加入系统 PATH
- 重开 PowerShell，验证：

```powershell
flutter --version
```

### 2. 安装 Windows 构建依赖

```powershell
flutter doctor
```

按提示安装：
- **Visual Studio 2022**（含 "Desktop development with C++" 工作负载）
- **Windows 10/11 SDK**

### 3. 把源码包拷到 Windows

把 macOS 上生成的 `bt_safe_source.zip`（约 1.3 MB）通过以下任一方式传到 Windows：
- U 盘
- 网盘（iCloud / OneDrive）
- `scp` / `rsync`
- 邮件给自己

在 Windows 上解压：

```powershell
Expand-Archive bt_safe_source.zip -DestinationPath C:\projects\
cd C:\projects\bt_safe
```

### 4. 一键编译

双击运行：

```
build_windows.bat
```

或命令行：

```powershell
.\build_windows.bat
```

脚本会自动：
1. 检查 Flutter
2. `flutter pub get`
3. `flutter config --enable-windows-desktop`
4. `flutter build windows --release`
5. 把 `bt_safe.exe` 及依赖复制到 `build\windows\x64\runner\Release\bt_safe\`

### 5. 运行

进入输出目录，双击 `bt_safe.exe`：

```
C:\projects\bt_safe\build\windows\x64\runner\Release\bt_safe\bt_safe.exe
```

## 常见错误

| 报错 | 解决 |
|---|---|
| `Visual Studio not found` | 安装 VS2022 + "Desktop development with C++" 工作负载 |
| `Windows 10 SDK not found` | 在 VS Installer 里勾选 |
| `flutter pub get` 失败 | 确认网络能访问 pub.dev |
| 首次编译耗时 5-10 分钟 | 正常，CMake 在编译第三方 C++ 库 |

## 整个文件夹打包带走

如果想把编译完的 `.exe` 拷贝给其他 Windows 机器（不需要装 Flutter）：

```powershell
Compress-Archive -Path C:\projects\bt_safe\build\windows\x64\runner\Release\bt_safe -DestinationPath bt_safe_windows.zip
```

把这个 zip 给别人解压即可，里面 `bt_safe.exe` 是独立可执行的（前提：对方也是 Windows x64 系统）。
