# SwiftMTP 项目上下文

## 项目概述

SwiftMTP 是一个用于 Android MTP（媒体传输协议）文件传输的原生 macOS 应用程序。它提供了一个基于现代 SwiftUI 的界面，用于连接 Android 设备并通过 USB 传输文件。该项目使用独特的架构，将 Swift 用于 UI 层，Go 用于低级 MTP 通信层。

### 主要功能
- 自动检测连接的 Android 设备
- 文件浏览，支持流畅导航
- 文件下载（单个和批量）
- 文件上传（按钮选择和拖放）
- 支持大文件（>4GB）
- 批量操作
- 现代 SwiftUI 界面
- 设备存储信息显示
- 多语言支持（英语、简体中文、日语、韩语）

### 架构
- **编程语言**: Swift 5.9+（UI），Go 1.22+（MTP 通信）
- **UI 框架**: SwiftUI
- **MTP 库**: go-mtpx（基于 libusb-1.0）
- **架构模式**: MVVM
- **桥接方法**: CGO（Swift ↔ Go）
- **国际化**: Swift 本地化框架（NSLocalizedString）

## 构建和运行

### 先决条件
- macOS 26.0+（或更高版本）
- Xcode 26.0+
- Homebrew（最新版本）
- 依赖项：`libusb-1.0`, `go`

### 安装
```bash
# 安装依赖项
brew install libusb-1.0 go

# 克隆仓库
git clone https://github.com/wang93wei/SwiftMTP.git
cd SwiftMTP

# 构建 Go 桥接层
./Scripts/build_kalam.sh

# 在 Xcode 中打开并运行
open SwiftMTP.xcodeproj
```

### 构建 Go 桥接层
该项目使用名为 "Kalam Kernel" 的 Go 桥接层来处理低级 MTP 通信。在运行应用程序之前必须构建此层：
```bash
./Scripts/build_kalam.sh
```

### 创建安装包
```bash
# 简化打包（不需要开发者证书）
./Scripts/create_dmg_simple.sh

# 完整打包（需要开发者证书）
./Scripts/create_dmg.sh
```

## 开发规范

### 项目结构
```
SwiftMTP/
├── Native/                         # Go 桥接层 (Kalam Kernel)
│   ├── kalam_bridge.go            # 主桥接实现 (CGO)
│   ├── kalam_bridge_test.go       # Go 单元测试
│   ├── libkalam.h                 # C 头文件 (Swift 桥接)
│   ├── go.mod / go.sum            # Go 模块依赖
│   └── vendor/                    # Go 依赖 (go-mtpx, usb)
├── Scripts/
│   ├── build_kalam.sh             # 构建 Go 动态库
│   ├── create_dmg.sh              # DMG 打包脚本
│   ├── create_dmg_simple.sh       # 简化打包
│   ├── generate_icons.sh          # 图标生成脚本
│   ├── run_tests.sh               # 测试运行脚本
│   └── SwiftMTP/                  # 资源脚本
├── SwiftMTP/                      # Swift 应用程序
│   ├── App/                       # 应用程序入口
│   ├── Models/                    # 数据模型
│   ├── Services/                  # 服务层 (MTP 服务)
│   ├── Views/                     # SwiftUI 视图
│   ├── Resources/                 # 资源文件
│   └── libkalam.dylib             # Go 动态库
├── SwiftMTPTests/                 # Swift 单元测试
├── docs/                          # 项目文档
└── SwiftMTP.xcodeproj/            # Xcode 项目
```

### 核心组件
1. **DeviceManager**: 使用 Kalam Kernel 处理设备检测和连接
2. **FileSystemManager**: 管理 MTP 设备上的文件系统操作和缓存管理
3. **FileTransferManager**: 管理文件上传和下载操作
4. **Kalam Kernel**: 基于 Go 的桥接层，用于与 Android 设备通信

### MTP 通信流程
1. Swift UI 通过 CGO 桥接调用 Go 函数
2. Go 代码使用 go-mtpx 库与 Android 设备通信
3. 通过 USB 执行 MTP 操作（扫描、列出文件、下载、上传）
4. 结果以 JSON 字符串形式返回到 Swift 层

### 测试
- Swift 测试使用 Testing 框架
- Go 测试在 Native 目录中可用
- 项目包含核心功能的单元测试

### 国际化
- 支持简体中文、英语、日语、韩语
- 默认使用系统语言
- 可在应用内更改语言而无需重启（仅 UI - 菜单栏需要重启）

## 已知限制
1. 必须禁用沙盒才能访问 USB 设备
2. 传输速度受 MTP 协议限制
3. 当前仅支持单文件上传（不支持文件夹上传）

## 故障排除
- 设备未检测到：确保设备处于 MTP 模式，尝试重新连接 USB 线缆
- 构建错误：检查 libusb-1.0 安装并重新构建 Go 桥接层
- 传输问题：系统可能需要禁用应用沙盒以访问 USB 设备