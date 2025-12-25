# SwiftMTP - iFlow 项目文档

## 项目概述

SwiftMTP 是一个原生的 macOS 应用程序，用于在 Mac 和 Android 设备之间通过 MTP (Media Transfer Protocol) 传输文件。它提供现代化的 SwiftUI 界面，用于浏览设备存储和管理文件传输。

## 核心特性

- ✅ 通过 USB 自动检测连接的 Android 设备
- ✅ 设备文件系统浏览与文件夹导航
- ✅ 文件上传/下载，带进度跟踪
- ✅ 支持大文件传输 (>4GB)
- ✅ 批量文件操作
- ✅ 实时显示设备存储和电池信息
- ✅ 现代化的 SwiftUI 界面
- ✅ 多语言支持：简体中文、英文、日语、韩语

## 技术架构

### 语言与框架
- **Swift 5.9+**: 主要应用语言
- **SwiftUI**: 所有视图的 UI 框架
- **Go**: 原生桥接层 (Kalam Kernel)
- **C**: Swift 和 Go 之间的 FFI 桥接

### 架构模式
- **MVVM**: 模型-视图-ViewModel 模式
- **并发**: 使用 DispatchQueue 进行异步操作
- **状态管理**: Combine 框架与 @Published 属性

### 关键依赖
- **libmtp 1.1.22**: MTP 协议实现 (通过 Homebrew)
- **go-mtpx**: Go MTP 库包装器 (github.com/ganeshrvel/go-mtpx)
- **go-mtpfs**: Go MTP 文件系统库 (github.com/ganeshrvel/go-mtpfs)

## 项目结构

```
SwiftMTP/
├── Native/                          # 基于 Go 的 MTP 桥接 (Kalam Kernel)
│   ├── kalam_bridge.go             # 主要 Go 桥接实现
│   ├── go.mod                      # Go 模块定义
│   └── go.sum                      # Go 依赖校验和
│
├── Scripts/
│   └── build_kalam.sh              # Go 桥接构建脚本
│
├── SwiftMTP/                       # 主要 Swift 应用
│   ├── App/
│   │   ├── SwiftMTPApp.swift      # 应用入口点 (@main)
│   │   └── Info.plist             # 应用元数据
│   │
│   ├── Models/                     # 数据模型
│   │   ├── Device.swift           # 设备和 StorageInfo 结构体
│   │   ├── FileItem.swift         # 文件/文件夹表示
│   │   └── TransferTask.swift     # 传输操作模型
│   │
│   ├── Services/                   # 业务逻辑层
│   │   ├── MTP/
│   │   │   ├── DeviceManager.swift        # 设备检测和管理
│   │   │   ├── FileSystemManager.swift    # 文件浏览操作
│   │   │   └── FileTransferManager.swift  # 上传/下载操作
│   │   └── Utilities/              # (空 - 保留给辅助工具)
│   │
│   ├── Views/                      # SwiftUI 视图
│   │   ├── MainWindowView.swift           # 带导航的根窗口
│   │   ├── DeviceListView.swift          # 侧边栏设备列表
│   │   ├── FileBrowserView.swift         # 主文件浏览器
│   │   ├── FileTransferView.swift        # 传输进度面板
│   │   ├── SettingsView.swift            # 设置窗口
│   │   └── Components/                    # 可重用视图组件
│   │       ├── DeviceRowView.swift       # 设备列表项
│   │       └── TransferTaskRowView.swift # 传输任务项
│   │
│   ├── ViewModels/                 # (空 - 在视图中使用 @StateObject)
│   ├── Resources/                  # 资源文件
│   │   ├── Base.lproj/            # 基础语言包（英文）
│   │   ├── en.lproj/              # 英文语言包
│   │   ├── zh-Hans.lproj/         # 简体中文语言包
│   │   ├── ja.lproj/              # 日语语言包
│   │   └── ko.lproj/              # 韩语语言包
│   │
│   ├── SwiftMTP-Bridging-Header.h # Swift-C 桥接头文件
│   ├── libkalam.dylib             # 编译的 Go 桥接 (生成)
│   └── libkalam.h                 # Go 桥接的 C 头文件 (生成)
│
├── SwiftMTP.xcodeproj/            # Xcode 项目文件
├── .kiro/                         # iFlow AI 助手配置
│   └── steering/                  # 项目指导文档
│       ├── product.md             # 产品概述
│       ├── structure.md           # 项目结构
│       └── tech.md                # 技术栈
│
└── README.md                       # 项目文档 (中文)
```

## 常用命令

### 构建原生桥接

```bash
# 手动构建 Kalam 桥接
./Scripts/build_kalam.sh

# 脚本处理:
# - Go 模块初始化
# - 依赖获取 (go get, go mod tidy)
# - 编译为共享库
# - 设置 install_name for @rpath
# - 代码签名 (在 Xcode 环境中)
```

### Xcode 构建

```bash
# 从命令行构建
xcodebuild -project SwiftMTP.xcodeproj -scheme SwiftMTP -configuration Debug

# 清理构建
xcodebuild clean -project SwiftMTP.xcodeproj -scheme SwiftMTP
```

### 运行应用

- 使用 Xcode: Cmd+R
- 确保 Android 设备以 MTP 模式连接
- 应用需要 USB 设备访问权限 (禁用沙盒)

### 安装依赖

```bash
# 通过 Homebrew 安装 libmtp
brew install libmtp

# 安装 Go (如果不存在)
brew install go

# Go 依赖由构建脚本自动获取
```

## 构建配置说明

### 必需的 Xcode 设置

1. **桥接头文件**: `SwiftMTP/SwiftMTP-Bridging-Header.h`
2. **头文件搜索路径**: 
   - `/opt/homebrew/Cellar/libmtp/1.1.22/include`
   - `/opt/homebrew/Cellar/libusb/1.0.29/include/libusb-1.0`
3. **库搜索路径**: `/opt/homebrew/Cellar/libmtp/1.1.22/lib`
4. **部署目标**: macOS 13.0
5. **沙盒**: 禁用 (USB 访问需要)

### 运行脚本阶段

项目包含一个运行脚本构建阶段，执行 `Scripts/build_kalam.sh` 在编译前构建 Go 桥接。这确保 libkalam.dylib 始终是最新的。

## 代码签名

构建脚本在 Xcode 环境中运行时自动处理 libkalam.dylib 的代码签名，使用 `EXPANDED_CODE_SIGN_IDENTITY`。

## FFI 模式

Swift ↔ C ↔ Go 通信:
- Go 使用 `//export` 指令导出函数
- Go 使用 `-buildmode=c-shared` 构建创建 .dylib 和 .h
- Swift 通过桥接头文件导入
- 内存管理: Go 使用 C.CString 分配，Swift 必须调用 Kalam_FreeString

## 开发指南

### 模型 (`SwiftMTP/Models/`)
- 纯 Swift 结构体/类
- 根据需要遵循 `Identifiable`, `Codable`, `Hashable`
- 不包含业务逻辑 - 仅数据结构
- 包含派生值的计算属性

### 服务 (`SwiftMTP/Services/`)
- 使用 `static let shared` 单例模式
- 遵循 `ObservableObject` 进行状态发布
- 对触发 UI 更新的属性使用 `@Published`
- 处理所有 MTP 操作和设备通信
- 异步操作使用 `DispatchQueue.global(qos: .userInitiated)`

### 视图 (`SwiftMTP/Views/`)
- 纯 SwiftUI 视图
- 对管理器实例使用 `@StateObject`
- 对本地视图状态使用 `@State`
- `Components/` 子文件夹中的组件可在视图间重用
- 包含 `#Preview` 用于 Xcode 预览

### 原生桥接 (`Native/`)
- 导出 C 函数的 Go 包 `main`
- 所有导出函数前缀为 `Kalam_`
- 复杂数据结构使用 JSON 序列化
- 内存管理: 使用 C.CString 分配，使用 Kalam_FreeString 释放

## 代码验证

**重要**: 每次修改代码后，务必执行编译以确保修改正确无误，避免引入语法错误或逻辑错误。

```bash
# 编译项目（Debug 配置）
xcodebuild -project SwiftMTP.xcodeproj -scheme SwiftMTP -configuration Debug

# 如果需要清理后重新编译
xcodebuild clean -project SwiftMTP.xcodeproj -scheme SwiftMTP
xcodebuild -project SwiftMTP.xcodeproj -scheme SwiftMTP -configuration Debug
```

### 验证要点
- 检查编译是否成功（应看到 `** BUILD SUCCEEDED **`）
- 如果编译失败，检查错误信息并修复
- 修改本地化文件（Localizable.strings）后，确保所有语言文件同步更新
- 修改枚举类型（如 AppLanguage）后，确保所有 switch 语句都已更新

## 状态管理模式

应用使用集中管理器模式:

1. **DeviceManager.shared**: 设备检测和选择
2. **FileSystemManager.shared**: 文件浏览和导航
3. **FileTransferManager.shared**: 上传/下载操作

视图使用 `@StateObject` 观察这些管理器，并对 `@Published` 属性变化做出反应。

## 构建产物

生成的文件 (不在源代码控制中):
- `SwiftMTP/libkalam.dylib`: 编译的 Go 桥接
- `SwiftMTP/libkalam.h`: 自动生成的 C 头文件
- `Native/vendor/`: 供应商化的 Go 依赖 (如果使用供应商模式)

## 关键集成点

1. **Swift → Go**: 通过导入 libkalam.h 的桥接头文件
2. **Go → MTP**: 通过 go-mtpx 库包装 libmtp
3. **UI → Services**: 通过 @StateObject 和 @Published 属性
4. **Services → Native**: 直接 C 函数调用与 JSON 编组

## 目标平台

- macOS 13.0+ (Ventura 或更高版本)
- 需要以 MTP 模式通过 USB 连接到 Android 设备

## 主要限制

- 单设备支持 (一次一个设备)
- 无沙盒支持 (需要 USB 设备访问)
- 仅单个文件上传 (尚不支持文件夹上传)
- 传输速度受 MTP 协议限制
- 设备兼容性因 Android MTP 实现而异

## 语言

主要文档和 UI 文本支持以下语言：
- 简体中文 (zh-Hans)
- 英文 (en)
- 日语 (ja)
- 韩语 (ko)

## 故障排除

### 设备未检测到
- 确保设备已开启 **文件传输 (MTP)** 模式
- 尝试断开重连 USB 线
- 点击 **刷新设备** 按钮
- 重启应用

### 编译错误
- 检查 libmtp 是否正确安装: `brew list libmtp`
- 确认头文件搜索路径正确
- 确认桥接头文件路径正确
- Clean Build Folder (Cmd + Shift + K)

### 传输失败
- 检查设备是否仍然连接
- 确认设备有足够的存储空间
- 查看错误提示信息

## 后续改进计划

- [ ] 文件夹批量上传
- [ ] 拖拽文件上传支持
- [ ] 文件搜索功能
- [ ] 自动备份功能
- [x] 完整的国际化支持 (已支持简体中文、英文、日语、韩语)
- [ ] 沙盒支持 (需要申请 USB 权限)

## 许可证

MIT License

## 致谢

- [libmtp](http://libmtp.sourceforge.net/) - MTP 协议实现
- Apple SwiftUI - 现代化 UI 框架

---

**注意**: 此应用仅供学习和个人使用，不保证与所有 Android 设备兼容。