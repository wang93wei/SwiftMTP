# SwiftMTP

<div align="center">

<img src="../SwiftMTP/App/Resources/SwiftMTP_Logo.svg" alt="SwiftMTP Logo" width="128">

**macOS 原生 Android MTP 文件传输工具**

[![Swift Version](https://img.shields.io/badge/Swift-5.9+-F05138?logo=swift)](https://swift.org)
[![Platform](https://img.shields.io/badge/macOS-26.0+-000000?logo=apple)](https://www.apple.com/macos/)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](../LICENSE)

</div>

---

**🌍 语言:** [English](../README.md) | [简体中文](README.zh-CN.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Русский](README.ru.md) | [Français](README.fr.md) | [Deutsch](README.de.md)

---

## ✨ 功能特性

| 功能 | 描述 |
|------|------|
| 🔌 **设备自动检测** | 自动识别连接 Android 设备 |
| 📁 **文件浏览** | 流畅浏览设备文件系统 |
| ⬇️ **文件下载** | 支持单个和批量文件下载 |
| ⬆️ **文件上传** | 支持按钮选择和拖放上传文件 |
| 💾 **大文件支持** | 支持 >4GB 文件传输 |
| 📦 **批量操作** | 批量选择和处理文件 |
| 🎨 **现代化 UI** | 精美的 SwiftUI 界面 |
| 📊 **存储信息** | 显示设备存储使用情况 |
| 🌍 **多语言支持** | 支持简体中文、英文、日语、韩语、俄语、法语、德语，可跟随系统语言 |

## 📸 应用截图
![SwiftMTP Logo](../SwiftMTP/Resources/cap_2025-12-24%2005.29.36.png)

## 🚀 快速开始

### 环境要求

| 依赖 | 版本要求 |
|------|----------|
| macOS | 26.0+ (或更高) |
| Xcode | 26.0+ |
| Homebrew | 最新版本 |

### 安装依赖

```bash
brew install libusb-1.0 go
```

### 构建运行

```bash
# 克隆项目
git clone https://github.com/wang93wei/SwiftMTP.git
cd SwiftMTP

# 构建 Go 桥接层
./Scripts/build_kalam.sh

# 在 Xcode 中打开并运行
open SwiftMTP.xcodeproj
```

> 📝 **说明**: 项目配置文件已提交到版本控制，首次克隆后直接在 Xcode 中打开项目即可使用，无需额外配置。

> 💡 **提示**: 连接 Android 设备后，在设备上选择 **文件传输 (MTP)** 模式即可使用。

### 创建安装包

```bash
# 简化版打包（无需开发者证书）
./Scripts/create_dmg_simple.sh

# 完整版打包（需要开发者证书）
./Scripts/create_dmg.sh
```

DMG 文件将生成在 `build/` 目录中。

## 📖 使用指南

### 连接设备

1. 通过 USB 将 Android 设备连接到 Mac
2. 在设备上选择 **文件传输 (MTP)** 模式
3. SwiftMTP 会自动检测并显示设备

### 文件操作

| 操作 | 方法 |
|------|------|
| 浏览文件 | 双击文件夹进入，面包屑导航返回 |
| 下载文件 | 右键点击文件 → **下载** |
| 批量下载 | 多选文件 → 右键 → **下载所选文件** |
| 上传文件 | 点击工具栏 **上传文件** 按钮或直接拖放文件到窗口 |
| 拖放上传 | 将文件拖放到文件浏览器窗口即可上传 |

### 语言设置

1. 打开 **设置** 窗口（⌘ + ,）
2. 在 **通用** 标签页中选择语言
3. 可选语言：
   - **系统默认** - 跟随 macOS 系统语言
   - **English** - 英文界面
   - **中文** - 简体中文界面
   - **日本語** - 日语界面
   - **한국어** - 韩语界面
   - **Русский** - 俄语界面
   - **Français** - 法语界面
   - **Deutsch** - 德语界面
4. 应用内界面会立即更新语言
5. **菜单栏和文件选择器**需要重启应用才能生效，系统会提示是否立即重启

## 🏗️ 项目架构

```
SwiftMTP/
├── Native/                         # Go 桥接层 (Kalam Kernel)
│   ├── kalam_bridge.go            # 主要桥接实现 (CGO)
│   ├── kalam_bridge_test.go       # Go 单元测试
│   ├── libkalam.h                 # C 头文件（Swift 桥接）
│   ├── go.mod / go.sum            # Go 模块依赖
│   └── vendor/                    # Go 依赖 (go-mtpx, usb)
├── Scripts/
│   ├── build_kalam.sh             # 构建 Go 动态库
│   ├── create_dmg.sh              # DMG 打包脚本
│   ├── create_dmg_simple.sh       # 简化版打包
│   ├── generate_icons.sh          # 图标生成脚本
│   ├── run_tests.sh               # 运行测试脚本
│   └── SwiftMTP/                  # 资源脚本
│       └── App/Assets.xcassets/   # 应用图标资源
├── SwiftMTP/                      # Swift 应用
│   ├── App/                       # 应用入口
│   │   ├── SwiftMTPApp.swift      # App 入口
│   │   ├── Info.plist             # 应用配置
│   │   ├── Assets.xcassets/       # 资源包（图标）
│   │   └── Resources/             # 应用资源
│   │       └── SwiftMTP_Logo.svg  # 应用 Logo
│   ├── Models/                    # 数据模型
│   │   ├── Device.swift           # 设备模型
│   │   ├── FileItem.swift         # 文件模型
│   │   ├── TransferTask.swift     # 传输任务模型
│   │   └── AppLanguage.swift      # 语言模型
│   ├── Services/                  # 服务层
│   │   ├── MTP/                   # MTP 服务
│   │   │   ├── DeviceManager.swift    # 设备管理
│   │   │   ├── FileSystemManager.swift# 文件系统
│   │   │   └── FileTransferManager.swift # 传输管理
│   │   ├── LanguageManager.swift  # 语言管理器
│   │   └── LocalizationManager.swift # 本地化管理器
│   ├── Views/                     # SwiftUI 视图
│   │   ├── MainWindowView.swift   # 主窗口
│   │   ├── DeviceListView.swift   # 设备列表
│   │   ├── FileBrowserView.swift  # 文件浏览器
│   │   ├── FileTransferView.swift # 传输视图
│   │   ├── SettingsView.swift     # 设置窗口
│   │   └── Components/            # 可复用组件
│   │       ├── DeviceRowView.swift
│   │       ├── LiquidGlassView.swift
│   │       └── TransferTaskRowView.swift
│   ├── Resources/                 # 资源文件
│   │   ├── Kalam.bundle/          # Go 动态库 Bundle
│   │   │   └── Contents/MacOS/Kalam
│   │   ├── Base.lproj/            # 基础语言包（英文）
│   │   │   ├── InfoPlist.strings
│   │   │   └── Localizable.strings
│   │   ├── en.lproj/              # 英文语言包
│   │   │   ├── InfoPlist.strings
│   │   │   └── Localizable.strings
│   │   ├── zh-Hans.lproj/         # 简体中文语言包
│   │   │   ├── InfoPlist.strings
│   │   │   └── Localizable.strings
│   │   ├── ja.lproj/              # 日语语言包
│   │   │   ├── InfoPlist.strings
│   │   │   └── Localizable.strings
│   │   ├── ko.lproj/              # 韩语语言包
│   │   │   ├── InfoPlist.strings
│   │   │   └── Localizable.strings
│   │   ├── ru.lproj/              # 俄语语言包
│   │   │   ├── InfoPlist.strings
│   │   │   └── Localizable.strings
│   │   ├── fr.lproj/              # 法语语言包
│   │   │   ├── InfoPlist.strings
│   │   │   └── Localizable.strings
│   │   └── de.lproj/              # 德语语言包
│   │       ├── InfoPlist.strings
│   │       └── Localizable.strings
│   ├── libkalam.dylib             # Go 动态库
│   ├── libkalam.h                 # C 头文件
│   └── SwiftMTP-Bridging-Header.h # Swift-C 桥接头文件
├── SwiftMTPTests/                 # Swift 单元测试
│   ├── AppLanguageTests.swift
│   ├── DeviceTests.swift
│   ├── FileBrowserViewTests.swift
│   ├── FileItemTests.swift
│   ├── FileSystemManagerTests.swift
│   ├── FileTransferManagerTests.swift
│   ├── LanguageManagerTests.swift
│   ├── SwiftMTPTests.swift
│   └── TransferTaskTests.swift
├── docs/                          # 项目文档
│   ├── sequence-diagrams.md       # 序列图文档
│   ├── TESTING.md                 # 测试文档
│   └── WIKI.md                    # 项目 Wiki
├── build/                         # 构建输出目录
├── .github/workflows/             # GitHub Actions
│   └── test.yml                   # CI 测试配置
└── SwiftMTP.xcodeproj/            # Xcode 项目
```

### 技术栈

- **语言**: Swift 6+, Go 1.22+
- **UI 框架**: SwiftUI
- **MTP 库**: go-mtpx (基于 libusb-1.0)
- **架构模式**: MVVM
- **桥接方式**: CGO
- **国际化**: Swift 本地化框架 (NSLocalizedString)

## ⚠️ 已知限制

1. 需要禁用沙盒才能访问 USB 设备
2. 传输速度受 MTP 协议限制
3. 目前仅支持单个文件上传（不支持文件夹）

## 🔧 故障排除

### 设备未被检测到

```
✓ 确保设备已开启 MTP 模式
✓ 尝试断开重连 USB 线
✓ 重启应用
✓ 检查 USB 线是否支持数据传输
```

### 编译错误

```bash
# 检查 libusb-1.0 安装
brew list libusb-1.0

# 重新构建 Go 桥接层
./Scripts/build_kalam.sh

# 清理并重新构建
xcodebuild clean
xcodebuild
```

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

本项目采用 MIT License - 详见 [LICENSE](../LICENSE) 文件。

---

<div align="center">

**如果这个项目对你有帮助，欢迎 ⭐ Star 支持！**

[![Star History Chart](https://api.star-history.com/svg?repos=wang93wei/SwiftMTP&type=Date)](https://star-history.com/#wang93wei/SwiftMTP&Date)

</div>