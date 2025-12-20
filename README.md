# SwiftMTP

一个 macOS 原生的 Android MTP (Media Transfer Protocol) 文件传输工具，使用 Swift 和 SwiftUI 构建。

## 功能特性

- ✅ 自动检测连接的 Android 设备
- ✅ 浏览设备文件系统
- ✅ 文件上传和下载
- ✅ 实时传输进度显示
- ✅ 支持大文件传输 (>4GB)
- ✅ 批量文件操作
- ✅ 现代化的 SwiftUI 界面
- ✅ 设备存储信息显示
- ✅ 电池电量显示

## 系统要求

- macOS 13.0+ (Ventura 或更高版本)
- Xcode 15.0+
- Homebrew (用于安装 libmtp)

## 安装步骤

### 1. 安装 libmtp

```bash
brew install libmtp
```

### 2. 创建 Xcode 项目

1. 打开 Xcode，选择 **File > New > Project**
2. 选择 **macOS > App**，点击 Next
3. 填写项目信息：
   - Product Name: `SwiftMTP`
   - Team: 选择你的开发团队
   - Organization Identifier: 填写你的组织标识符
   - Interface: **SwiftUI**
   - Language: **Swift**
   - 取消勾选 **Use Core Data** 和 **Include Tests**
4. 选择保存位置为 `/Users/alanwang/git/SwiftMTP`

### 3. 删除默认文件并导入源代码

1. 在 Xcode 项目导航器中，删除自动生成的 `ContentView.swift`
2. 将项目中已创建的 `SwiftMTP` 文件夹拖拽到 Xcode 项目中
3. 确保选中 **Copy items if needed** 和 **Create groups**

### 4. 配置构建设置

#### 4.1 添加桥接头文件

1. 在 Xcode 中选择项目 > Target > Build Settings
2. 搜索 "Bridging Header"
3. 在 **Objective-C Bridging Header** 中设置：
   ```
   SwiftMTP/SwiftMTP-Bridging-Header.h
   ```

#### 4.2 配置头文件搜索路径

1. 在 Build Settings 中搜索 "Header Search Paths"
2. 添加以下路径（根据你的 Homebrew 安装位置）：
   ```
   /opt/homebrew/Cellar/libmtp/1.1.22/include
   /opt/homebrew/Cellar/libusb/1.0.29/include/libusb-1.0
   ```
   设置为 **non-recursive**

#### 4.3 配置库搜索路径

1. 在 Build Settings 中搜索 "Library Search Paths"
2. 添加：
   ```
   /opt/homebrew/Cellar/libmtp/1.1.22/lib
   ```

#### 4.4 链接库文件

1. 选择 Target > General > Frameworks, Libraries, and Embedded Content
2. 点击 `+` 按钮
3. 点击 **Add Other... > Add Files...**
4. 导航到 `/opt/homebrew/Cellar/libmtp/1.1.22/lib/`
5. 选择 `libmtp.dylib` 并添加

或者在 Build Phases > Link Binary With Libraries 中添加：
- 点击 `+`
- 点击 **Add Other...**
- 选择 `libmtp.dylib`

#### 4.5 添加 MTPBridge 源文件

1. 确保 `MTPBridge.c` 和 `MTPBridge.h` 已添加到项目中
2. 在项目导航器中找到 `MTPBridge.c`
3. 右键点击 > Show File Inspector
4. 确认 **Target Membership** 中 SwiftMTP 已勾选

### 5. 设置部署目标

1. 在项目设置中，将 **Deployment Target** 设置为 **macOS 13.0**

### 6. 禁用沙盒（临时）

由于需要访问 USB 设备，需要临时禁用沙盒：

1. 选择 Target > Signing & Capabilities
2. 如果有 **App Sandbox**，点击减号删除

### 7. 构建和运行

1. 连接 Android 设备并设置为 **文件传输模式 (MTP)**
2. 在 Xcode 中按 `Cmd + R` 构建并运行
3. 应用启动后应该能检测到你的设备

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

### 查看传输进度

- 点击工具栏的 **传输任务** 按钮
- 查看活动传输和已完成的传输
- 可以取消正在进行的传输

## 项目结构

```
SwiftMTP/
├── App/
│   └── SwiftMTPApp.swift           # 应用入口
├── Models/
│   ├── Device.swift                # 设备模型
│   ├── FileItem.swift              # 文件项模型
│   └── TransferTask.swift          # 传输任务模型
├── Services/
│   └── MTP/
│       ├── MTPBridge.h/c           # C 桥接层
│       ├── DeviceManager.swift     # 设备管理
│       ├── FileSystemManager.swift # 文件系统管理
│       └── FileTransferManager.swift # 文件传输管理
├── Views/
│   ├── MainWindowView.swift       # 主窗口
│   ├── DeviceListView.swift       # 设备列表
│   ├── FileBrowserView.swift      # 文件浏览器
│   ├── FileTransferView.swift     # 传输视图
│   ├── SettingsView.swift         # 设置面
│   └── Components/                # 可复用组件
└── SwiftMTP-Bridging-Header.h    # Swift 桥接头文件
```

## 技术栈

- **语言**: Swift 5.9+
- **UI 框架**: SwiftUI
- **MTP 库**: libmtp 1.1.22
- **架构**: MVVM
- **并发**: DispatchQueue

## 已知限制

1. 某些 Android 设备的 MTP 实现可能不完全兼容
2. 需要禁用沙盒才能访问 USB 设备
3. 传输速度受 MTP 协议限制
4. 目前不支持文件夹上传（仅支持单个文件）

## 故障排除

### 设备未被检测到

- 确保设备已开启 **文件传输 (MTP)** 模式
- 尝试断开重连 USB 线
- 点击 **刷新设备** 按钮
- 重启应用

### 编译错误

- 检查 libmtp 是否正确安装：`brew list libmtp`
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
- [ ] 完整的国际化支持
- [ ] 沙盒支持 (需要申请 USB 权限)

## 许可证

MIT License

## 致谢

- [libmtp](http://libmtp.sourceforge.net/) - MTP 协议实现
- Apple SwiftUI - 现代化 UI 框架

---

**注意**: 此应用仅供学习和个人使用，不保证与所有 Android 设备兼容。
