# SwiftMTP

一个 macOS 原生的 Android MTP (Media Transfer Protocol) 文件传输工具，使用 Swift 和 SwiftUI 构建。

## 功能特性

- ✅ 自动检测连接的 Android 设备
- ✅ 浏览设备文件系统
- ✅ 文件上传和下载
- ✅ 支持大文件传输 (>4GB)
- ✅ 批量文件操作
- ✅ 现代化的 SwiftUI 界面
- ✅ 设备存储信息显示

## 系统要求

- macOS 13.0+ (Ventura 或更高版本)
- Xcode 15.0+
- Homebrew (用于安装 libmtp)

## 安装步骤

### 1. 安装依赖

```bash
brew install libmtp go
```

### 2. 构建项目

1. 克隆仓库到本地
2. 打开 `SwiftMTP.xcodeproj`
3. 连接 Android 设备并设置为 MTP 模式
4. 在 Xcode 中按 `Cmd + R` 构建并运行

## 使用说明

### 连接设备

1. 通过 USB 将 Android 设备连接到 Mac
2. 在设备上选择 **文件传输 (MTP)** 模式
3. SwiftMTP 会自动检测并显示设备

### 浏览文件

- 从左侧设备列表选择设备
- 双击文件夹进入
- 使用面包屑导航返回上级目录

### 下载文件

- 右键点击文件 > **下载**
- 或选择多个文件，右键 > **下载所选文件**
- 选择保存位置

### 上传文件

- 点击工具栏的 **上传文件** 按钮
- 选择要上传的文件
- 文件会上传到当前浏览的文件夹

## 项目结构

```
SwiftMTP/
├── Native/                         # Go 桥接层 (Kalam Kernel)
│   ├── kalam_bridge.go            # 主要 Go 桥接实现
│   └── vendor/                    # Go 依赖
├── Scripts/
│   └── build_kalam.sh             # Go 桥接构建脚本
├── SwiftMTP/                      # Swift 应用
│   ├── App/
│   ├── Models/
│   ├── Services/MTP/
│   ├── Views/
│   └── Components/
└── SwiftMTP.xcodeproj/
```

## 技术栈

- **语言**: Swift 5.9+, Go
- **UI 框架**: SwiftUI
- **MTP 库**: libmtp 1.1.22, go-mtpx
- **架构**: MVVM

## 已知限制

1. 需要禁用沙盒才能访问 USB 设备
2. 传输速度受 MTP 协议限制
3. 目前不支持文件夹上传（仅支持单个文件）

## 故障排除

### 设备未被检测到

- 确保设备已开启 **文件传输 (MTP)** 模式
- 尝试断开重连 USB 线
- 重启应用

### 编译错误

- 检查 libmtp 是否正确安装：`brew list libmtp`
- 运行构建脚本：`./Scripts/build_kalam.sh`

## 许可证

MIT License