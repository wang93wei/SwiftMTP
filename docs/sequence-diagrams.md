# SwiftMTP 时序图

## 1. 语言切换时序图

```mermaid
sequenceDiagram
    participant User as 用户
    participant App as SwiftMTPApp
    participant SV as SettingsView
    participant LM as LanguageManager
    participant Bundle as Bundle
    participant NC as NotificationCenter
    participant Views as 所有视图
    participant Menu as 菜单栏

    Note over User,App: 应用启动
    App->>LM: init() 初始化
    LM->>LM: 从 UserDefaults 读取语言设置
    LM->>LM: updateBundle() 更新语言包
    
    alt 已保存语言设置
        LM->>Bundle: path(forResource: "en/zh-Hans", ofType: "lproj")
        Bundle-->>LM: 返回语言包路径
        LM->>LM: 加载对应语言包
        LM->>App: setAppleLanguages()
        App->>App: 设置 AppleLanguages
        Note over App: 影响菜单栏和文件选择器
    else 无保存设置
        LM->>Bundle: 使用 Bundle.main (系统默认)
    end

    Note over App: 自定义菜单栏
    App->>App: .commands 修饰符
    App->>Menu: 创建应用菜单
    App->>Menu: 创建语言菜单
    Note over Menu: 菜单项使用 L10n 本地化

    Note over User,LM: 用户切换语言 (方式1: 菜单栏)
    User->>Menu: 点击菜单栏语言菜单
    Menu->>LM: currentLanguage = .english/.chinese/.system
    Note over LM: 语言切换流程
    LM->>LM: didSet 触发
    LM->>LM: saveLanguage() 保存到 UserDefaults
    LM->>LM: updateBundle() 更新语言包
    LM->>Bundle: path(forResource: localeIdentifier, ofType: "lproj")
    Bundle-->>LM: 返回新语言包路径
    LM->>LM: 加载新语言包
    LM->>NC: post(.languageDidChange)
    
    Note over SV: 显示重启提示
    SV->>SV: .onChange(of: currentLanguage)
    SV->>SV: showingRestartAlert = true
    SV->>User: 显示重启确认对话框
    
    alt 用户点击"立即重启"
        User->>SV: 确认重启
        SV->>SV: restartApplication()
        SV->>SV: /usr/bin/open bundleURL
        SV->>SV: NSApp.terminate()
        Note over App: 应用重启，AppleLanguages 生效
    else 用户点击"稍后"
        Note over App: 继续使用，下次启动生效
    end

    Note over User,LM: 用户切换语言 (方式2: 设置窗口)
    User->>SV: 打开设置窗口
    SV->>SV: 显示语言选择器
    User->>SV: 选择新语言
    SV->>LM: currentLanguage = .english/.chinese/.system
    Note over LM: 语言切换流程 (同上)
    LM->>LM: saveLanguage()
    LM->>LM: updateBundle()
    LM->>NC: post(.languageDidChange)
    Note over SV: 显示重启提示 (同上)
    
    Note over NC,Views: 视图刷新 (立即生效)
    NC->>Views: 发送语言改变通知
    
    par 所有视图响应
        Views->>MainWindowView: onReceive(.languageDidChange)
        MainWindowView->>MainWindowView: refreshID = UUID()
        MainWindowView->>MainWindowView: 强制刷新视图
        
        Views->>DeviceListView: onReceive(.languageDidChange)
        DeviceListView->>DeviceListView: refreshID = UUID()
        DeviceListView->>DeviceListView: title = L10n.DeviceList.devices
        
        Views->>FileBrowserView: onReceive(.languageDidChange)
        FileBrowserView->>FileBrowserView: refreshID = UUID()
        
        Views->>FileTransferView: onReceive(.languageDidChange)
        FileTransferView->>FileTransferView: refreshID = UUID()
        
        Views->>SettingsView: onReceive(.languageDidChange)
        SettingsView->>SettingsView: refreshID = UUID()
    end
    
    Note over Views: UI 更新完成
    Views->>Views: 应用内文本显示新语言
    Note over Menu,Views: 菜单栏和文件选择器<br/>需要重启后生效
```

## 2. 设备检测时序图

```mermaid
sequenceDiagram
    participant App as SwiftMTP App
    participant DM as DeviceManager
    participant Bridge as Kalam Bridge
    participant Go as Go桥接层 (Kalam)
    participant MTP as MTP驱动层
    participant Device as Android设备

    Note over App,DM: 应用启动阶段
    App->>DM: App 启动 (static shared)
    DM->>Bridge: Kalam_Init()
    
    Note over DM: 定时扫描启动
    DM->>DM: startScanning()
    DM->>DM: 启动 Timer (3秒间隔)
    DM->>DM: 立即触发首次 scanDevices()

    Note over DM: 扫描设备流程
    DM->>DM: isScanning = true (主线程)
    DM->>Bridge: Kalam_Scan() (全局队列)
    
    Note over Bridge,Go: CGo 跨语言调用
    Bridge->>Go: C.CString(json)
    Go->>MTP: mtpx.Initialize()
    MTP->>Device: USB 连接
    Device-->>MTP: 设备信息响应
    
    MTP->>MTP: FetchDeviceInfo()
    MTP->>MTP: FetchStorages()
    
    Go-->>Bridge: JSON 字符串指针
    Bridge->>Go: Kalam_FreeString() 释放内存
    
    Note over DM: 处理扫描结果
    DM->>DM: JSONDecoder 解码
    DM->>DM: mapToDevice() 映射数据
    DM->>DM: updateDevices() 更新状态
    DM->>DM: isScanning = false (主线程)
    
    alt 仅有一个设备
        DM->>DM: auto-select 设备
    end

    Note over DM: 自适应扫描频率
    alt 无设备连接
        DM->>DM: 间隔 3 秒扫描
    else 设备已连接
        DM->>DM: 间隔 5 秒扫描
    end

    Note over DM,Device: 设备断开检测
    loop 定时扫描
        DM->>Bridge: Kalam_Scan()
        alt 设备断开
            Bridge-->>DM: 返回 nil/空
            DM->>DM: handleDeviceDisconnection()
            DM->>DM: 清空设备列表
            DM->>DM: 清除缓存
            DM->>DM: 发送通知
        end
    end
```

## 3. 文件浏览时序图

```mermaid
sequenceDiagram
    participant View as FileBrowserView
    participant FSM as FileSystemManager
    participant Bridge as Kalam Bridge
    participant Go as Go桥接层
    participant MTP as MTP驱动层

    Note over View: 用户浏览文件
    View->>FSM: getRootFiles(for: device)
    
    alt 有缓存且未过期
        FSM-->>View: 返回缓存数据
    else 无缓存/已过期
        FSM->>Bridge: Kalam_ListFiles(storageId, parentId)
        
        Note over Bridge,Go: CGo 调用
        Bridge->>Go: ListFiles()
        Go->>Go: withDevice() 设备连接
        Go->>MTP: GetObjectHandles()
        MTP-->>Go: 文件句柄列表
        
        loop 遍历每个文件
            Go->>MTP: GetObjectInfo(handle)
            MTP-->>Go: 文件信息
            Go->>Go: 构建 FileJSON
        end
        
        Go-->>Bridge: JSON 结果
        Bridge-->>FSM: JSON 字符串
        
        FSM->>FSM: JSONDecoder 解码
        FSM->>FSM: mapToFileItem() 映射
        FSM->>FSM: 存入缓存 (30秒过期)
        FSM-->>View: 文件列表
    
    Note over View,FSM: 用户进入文件夹
    View->>FSM: getChildrenFiles(for: device, parent)
    FSM->>FSM: getFileList() 查询子文件
    FSM-->>View: 子文件列表
    END
```

## 4. 文件下载时序图

```mermaid
sequenceDiagram
    participant View as FileBrowserView
    participant FTM as FileTransferManager
    participant Bridge as Kalam Bridge
    participant Go as Go桥接层
    participant MTP as MTP驱动层
    participant Device as Android设备

    Note over View: 用户点击下载
    View->>FTM: downloadFile(from:device, fileItem, to:url)
    
    Note over FTM: 创建传输任务
    FTM->>FTM: 创建 TransferTask
    FTM->>FTM: 添加到 activeTasks
    FTM->>FTM: 提交到 transferQueue

    Note over FTM: 执行下载
    FTM->>FTM: performDownload()
    
    Note over FTM: 验证设备连接
    FTM->>Bridge: Kalam_Scan()
    alt 设备已断开
        Bridge-->>FTM: 返回空
        FTM->>FTM: task.updateStatus(.failed)
        FTM->>FTM: 移动到 completedTasks
        Note over View: 显示错误提示
    end
    
    Note over FTM: 开始下载
    FTM->>Bridge: Kalam_DownloadFile(objectId, destPath, taskId)
    
    Note over Bridge,Go: CGo 调用
    Bridge->>Go: DownloadFile()
    
    Go->>Go: 验证目标路径
    Go->>Go: 创建文件
    
    Go->>Go: 重试机制 (最多3次)
    loop 最多3次重试
        Go->>MTP: GetObjectInfo(objectId)
        MTP-->>Go: 文件信息
        
        alt 文件过大
            Go->>Go: 警告: 可能耗时较长
        end
        
        Go->>MTP: GetObject(objectId, file)
        MTP->>Device: 请求文件数据
        Device-->>MTP: 文件流数据
        MTP-->>Go: 写入本地文件
        
        alt 下载成功
            Go->>Go: 验证文件大小
            Go->>Go: file.Sync() 同步
            Go->>Go: file.Close()
            Note over Go: 跳出重试循环
        else 下载失败
            Go->>Go: 移除部分文件
            Go->>Go: 等待指数退避
            Go->>Go: 继续重试
        end
    end
    
    Note over FTM: 下载结果处理
    alt 下载成功
        Bridge-->>FTM: 返回 1
        FTM->>FTM: 验证本地文件
        FTM->>FTM: task.updateProgress()
        FTM->>FTM: task.updateStatus(.completed)
    else 下载失败
        Bridge-->>FTM: 返回 0
        FTM->>FTM: task.updateStatus(.failed)
    end
    
    FTM->>FTM: 移动到 completedTasks
    Note over View: 更新传输列表 UI
```

## 5. 文件上传时序图

```mermaid
sequenceDiagram
    participant View as FileBrowserView
    participant FTM as FileTransferManager
    participant Bridge as Kalam Bridge
    participant Go as Go桥接层
    participant MTP as MTP驱动层
    participant Device as Android设备

    Note over View: 用户选择上传文件
    View->>FTM: uploadFile(to:device, sourceURL, parentId, storageId)
    
    Note over FTM: 验证源文件
    FTM->>FTM: 检查文件是否存在
    FTM->>FTM: 检查是否为目录
    FTM->>FTM: 获取文件大小
    
    Note over FTM: 创建任务并执行
    FTM->>FTM: 创建 TransferTask
    FTM->>FTM: 添加到 activeTasks
    FTM->>FTM: 提交到 transferQueue
    
    FTM->>FTM: performUpload()
    
    Note over FTM: 开始上传
    FTM->>Bridge: Kalam_UploadFile(storageId, parentId, sourcePath, taskId)
    
    Note over Bridge,Go: CGo 调用
    Bridge->>Go: UploadFile()
    
    Go->>Go: 验证源文件存在
    
    Go->>Go: withDevice() 连接设备
    
    Note over Go: Step 1 - 发送对象信息
    Go->>MTP: SendObjectInfo(storageId, parentId, &objInfo)
    MTP->>Device: 发送文件元数据
    Device-->>MTP: 确认接收
    MTP-->>Go: 返回新对象句柄
    
    Note over Go: Step 2 - 发送文件数据
    Go->>MTP: SendObject(objectHandle, file)
    MTP->>Device: 传输文件数据流
    Device-->>MTP: 确认完成
    MTP-->>Go: 传输结果
    
    alt 用户取消任务
        View->>FTM: cancelTask(task)
        FTM->>Bridge: Kalam_CancelTask(taskId)
        Bridge->>Go: 设置取消标记
        Go->>Go: isTaskCancelled() 检查
        Note over Go: 停止传输
    end
    
    Note over FTM: 上传完成处理
    Bridge-->>FTM: 返回结果
    
    alt 上传成功
        FTM->>FTM: task.updateProgress()
        FTM->>FTM: task.updateStatus(.completed)
        
        Note over FTM: 刷新设备存储
        FTM->>Bridge: Kalam_RefreshStorage(storageId)
        FTM->>Bridge: Kalam_ResetDeviceCache()
        FTM->>FSM: clearCache() 清除缓存
        
        FTM->>View: 发送刷新通知
        Note over View: 刷新文件列表
    else 上传失败
        FTM->>FTM: task.updateStatus(.failed)
    end
    
    FTM->>FTM: 移动到 completedTasks
    Note over View: 更新传输列表 UI
```

## 6. 核心组件交互关系图

```mermaid
graph TB
    subgraph SwiftUI 层
        APP[SwiftMTPApp<br/>应用入口]
        MV[MainWindowView]
        DL[DeviceListView]
        FB[FileBrowserView]
        FT[FileTransferView]
        SV[SettingsView]
        Menu[自定义菜单栏<br/>Commands]
    end

    subgraph Service 层
        DM[DeviceManager<br/>单例 - 设备检测]
        FSM[FileSystemManager<br/>单例 - 文件浏览]
        FTM[FileTransferManager<br/>单例 - 传输管理]
        LM[LanguageManager<br/>单例 - 语言管理]
        L10N[LocalizationManager<br/>静态 - 本地化访问]
    end

    subgraph CGo Bridge 层
        Bridge[Kalam Bridge<br/>CGO 桥接函数]
    end

    subgraph Go 桥接层
        Go[Go Kalam Kernel<br/>MTP 协议实现]
    end

    subgraph 底层驱动
        USB[libusb-1.0]
        MTP[MTP Protocol]
    end

    subgraph 语言资源
        Base[Base.lproj<br/>基础语言包]
        EN[en.lproj<br/>英文语言包]
        ZH[zh-Hans.lproj<br/>简体中文语言包]
    end

    subgraph 系统设置
        UD[UserDefaults<br/>语言设置]
        AL[AppleLanguages<br/>菜单栏和文件选择器]
    end

    APP -->|初始化| LM
    APP -->|设置 AppleLanguages| AL
    APP -->|创建| Menu
    APP -->|环境对象| MV
    APP -->|环境对象| SV

    MV --> DM
    MV --> FSM
    MV --> FTM
    MV --> LM

    DM --> Bridge
    FSM --> Bridge
    FTM --> Bridge

    SV --> LM
    SV --> L10N

    Menu --> LM
    Menu --> L10N

    DL --> L10N
    FB --> L10N
    FT --> L10N
    MV --> L10N
    SV --> L10N

    LM -->|保存语言设置| UD
    LM -->|语言包切换| Base
    LM -->|语言包切换| EN
    LM -->|语言包切换| ZH

    L10N --> LM

    Bridge -->|CGo 调用| Go

    Go -->|USB 通信| USB
    Go -->|MTP 协议| MTP

    USB -->|USB 协议| Device[Android 设备]
    MTP -->|MTP 协议| Device

    AL -->|影响| Menu
    AL -->|影响| Panel[文件选择器]
```

## 7. 线程模型时序图

```mermaid
sequenceDiagram
    participant MainThread as 主线程 (UI)
    participant GlobalQueue as 全局队列 (Background)
    participant TransferQueue as 传输队列 (Transfer)
    participant Bridge as Kalam Bridge

    Note over MainThread: UI 事件触发
    MainThread->>GlobalQueue: 异步提交任务
    GlobalQueue->>Bridge: CGo 调用 (阻塞)
    
    Note over Bridge: CGo 会切换到 Go runtime 线程
    Bridge->>Bridge: Go 协程执行
    
    alt 快速操作 (设备扫描)
        Bridge-->>GlobalQueue: 返回结果
        GlobalQueue->>MainThread: DispatchQueue.main.async
        Note over MainThread: 更新 @Published 属性
        Note over MainThread: SwiftUI 自动刷新
    end

    alt 耗时操作 (文件传输)
        MainThread->>TransferQueue: transferQueue.async
        TransferQueue->>Bridge: Kalam_DownloadFile
        
        Note over TransferQueue: 长时间阻塞等待
        Bridge-->>TransferQueue: 传输完成
        
        TransferQueue->>TransferQueue: 验证结果
        TransferQueue->>MainThread: DispatchQueue.main.async
        Note over MainThread: 更新任务状态
    end

    Note over MainThread: 进度更新
    loop 传输过程中
        Bridge->>TransferQueue: 进度回调
        TransferQueue->>TransferQueue: 更新任务进度
        TransferQueue->>MainThread: DispatchQueue.main.async
        MainThread->>MainThread: 更新 UI
    end
```

## 关键交互总结

| 场景 | 发起方 | 桥接层 | Go层 | 线程处理 |
|------|--------|--------|------|----------|
| 设备扫描 | DeviceManager | Kalam_Scan | withDeviceQuick | 全局队列 → 主线程 |
| 文件浏览 | FileSystemManager | Kalam_ListFiles | withDevice | 全局队列 → 主线程 |
| 文件下载 | FileTransferManager | Kalam_DownloadFile | withDevice + 重试 | 传输队列 → 主线程 |
| 文件上传 | FileTransferManager | Kalam_UploadFile | withDevice | 传输队列 → 主线程 |
| 设备断开 | DeviceManager | Kalam_Scan 返回空 | - | 主线程处理通知 |
| 语言切换 (菜单栏) | SwiftMTPApp | - | - | 主线程 + 通知机制 |
| 语言切换 (设置) | SettingsView | - | - | 主线程 + 通知机制 |
| 应用重启 | SettingsView | - | - | Process + NSApp.terminate |
| 本地化访问 | 各视图 | - | - | 计算属性实时获取 |

## 语言切换机制说明

### 组件职责

- **SwiftMTPApp**: 应用启动时设置 AppleLanguages，创建自定义菜单栏
- **LanguageManager**: 管理语言状态，保存用户偏好，切换语言包
- **LocalizationManager (L10n)**: 提供类型安全的本地化字符串访问
- **各视图**: 监听语言改变通知，触发视图刷新
- **菜单栏**: 通过 SwiftUI commands 自定义，使用 L10n 本地化

### 刷新机制

各视图通过以下方式响应语言切换：
1. 添加 `@State private var refreshID = UUID()`
2. 监听 `.languageDidChange` 通知
3. 通知触发时更新 `refreshID = UUID()`
4. 使用 `.id(refreshID)` 修饰符强制视图重建
5. 计算属性 `L10n.*` 自动获取新语言的文本

### 语言包优先级

1. **系统默认**: 使用 `Bundle.main`，跟随 macOS 系统语言
2. **English**: 使用 `en.lproj` 语言包
3. **中文**: 使用 `zh-Hans.lproj` 语言包

语言设置保存在 `UserDefaults`，应用重启后自动恢复。

### 语言切换生效范围

| 组件 | 生效方式 | 是否需要重启 |
|------|----------|--------------|
| 应用内界面 (所有视图) | NotificationCenter + refreshID | ❌ 否 |
| 自定义菜单栏 | L10n 本地化字符串 | ❌ 否 |
| macOS 系统菜单栏 | AppleLanguages | ✅ 是 |
| 文件选择器 (NSOpenPanel/NSSavePanel) | AppleLanguages | ✅ 是 |

### 重启机制

当用户切换语言时：
1. 应用内界面立即更新语言
2. 系统显示重启提示对话框
3. 用户可选择"立即重启"或"稍后"
4. 重启后，AppleLanguages 生效，菜单栏和文件选择器使用新语言
5. 重启通过 `/usr/bin/open` 命令实现，确保应用正常启动
