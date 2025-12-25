# SwiftMTP - iFlow 项目文档

## 项目概述
macOS 原生 Android MTP 文件传输工具，通过 USB 在 Mac 和 Android 设备间传输文件。

## 核心特性
USB 自动检测、文件浏览/上传/下载（支持 >4GB）、批量操作、多语言支持（中/英/日/韩）。

## 技术架构
- **语言**: Swift 5.9+, Go 1.22+
- **UI**: SwiftUI
- **架构**: MVVM, Combine
- **依赖**: libmtp, go-mtpx, libusb-1.0
- **桥接**: CGO (Swift ↔ C ↔ Go)

## 项目结构
Native/ (Go 桥接), Scripts/ (构建脚本), SwiftMTP/ (App/Models/Services/Views/Resources/)

## 常用命令
```bash
# 构建
xcodebuild -project SwiftMTP.xcodeproj -scheme SwiftMTP -configuration Debug

# 清理
xcodebuild clean -project SwiftMTP.xcodeproj -scheme SwiftMTP

# 依赖
brew install go
```

## 代码验证
每次修改代码后必须编译验证：
```bash
xcodebuild -project SwiftMTP.xcodeproj -scheme SwiftMTP -configuration Debug
```

## 状态管理
DeviceManager.shared: 设备检测
FileSystemManager.shared: 文件浏览
FileTransferManager.shared: 文件传输

## 目标平台与限制
macOS 13.0+, Android MTP 模式。单设备支持、需禁用沙盒、仅单个文件上传。

## 许可证
MIT License