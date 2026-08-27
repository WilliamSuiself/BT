# BT Safe 运行命令（macOS）

进入项目目录后，按顺序执行以下命令（**不要用 `#` 开头的注释行**，zsh 在多行粘贴时会把它们当成命令）：

```bash
cd /Users/suiyunhai/coding/BT/bt_safe

flutter pub get

flutter run -d macos
```

## 如果想打 release 包

```bash
cd /Users/suiyunhai/coding/BT/bt_safe
flutter build macos --release
```

构建产物路径：

```
build/macos/Build/Products/Release/bt_safe.app
```

直接双击 .app 即可运行。

## 常见问题

- **第一次运行会卡在 "Running pod install..."** —— 等 1~2 分钟，macOS 桌面端用 CocoaPods 拉原生依赖
- **如果提示 "macOS deployment target"** —— 编辑 `macos/Podfile`，把第一行 platform 改成 `:osx, '10.14'`
- **如果端口 6881 被占** —— 在 `lib/features/downloads/download_state.dart` 里改 `listenPort`
