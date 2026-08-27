# BT Safe

> 一个**注重安全**的 BitTorrent 下载工具，桌面端 Flutter 实现。
> 支持 macOS / Windows / Linux 三端。

## 下载

到 [Releases](https://github.com/WilliamSuiself/BT/releases) 页面下载对应平台版本：

| 平台 | 文件 |
|---|---|
| Windows x64 | `bt_safe_windows_x64.zip` |
| macOS Universal (arm64 + x64) | `bt_safe_macos_universal.zip` |
| Linux x64 | `bt_safe_linux_x64.tar.gz` |

## 功能

- ✅ .torrent 文件解析（bencode 编码 + 正确 infoHash 计算）
- ✅ 磁力链解析（hex/base32）
- ✅ Tracker 客户端（HTTP / UDP，BEP-3 / BEP-15）
- ✅ Peer Wire Protocol（BEP-3 / BEP-10 Extension）
- ✅ Piece 下载 + SHA1 校验 + 断点续传
- ✅ ClamAV 病毒扫描集成（需本地 clamd）
- 🚧 VPN/TUN 流量加密框架已就位（需自行实现原生层）
- 🚧 DHT 元数据拉取（BEP-9）未实现

## 安全能力

1. **种子/磁力链解析与校验** — infoHash 严格按 BEP-3 计算（对 info 字典原文独立 SHA1）
2. **VPN 代理支持** — UI 可切换 SOCKS5 代理或 TUN 透明代理
3. **病毒扫描** — 下载完成可触发 clamd INSTREAM 扫描

## 从源码运行

需要 Flutter 3.41+：

```bash
cd bt_safe
flutter pub get
flutter run -d macos       # 或 -d windows / -d linux
```

## 自行编译 Release

```bash
flutter build macos --release
flutter build windows --release
flutter build linux --release
```

## 发布新版本

打 tag 并 push：

```bash
git tag v1.0.0
git push origin v1.0.0
```

GitHub Actions 会自动编译三端并发布到 [Releases](https://github.com/WilliamSuiself/BT/releases) 页面。

## 项目结构

```
bt_safe/
├── lib/
│   ├── core/
│   │   ├── bencode/         # BT 编码
│   │   ├── bittorrent/      # tracker / peer / magnet / parser / session
│   │   ├── storage/         # piece 落盘 + 断点续传
│   │   ├── security/        # VPN/TUN 接口
│   │   └── antivirus/       # ClamAV 客户端
│   ├── features/            # UI（添加任务 / 下载列表 / 设置）
│   ├── widgets/             # 通用组件
│   ├── models/              # 数据模型
│   └── main.dart            # 入口
├── .github/workflows/       # CI/CD
└── test/                    # 单元测试
```

## License

MIT
