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
        Note over LM: 系统默认模式 - 显式检测系统语言
        LM->>LM: 获取 Locale.preferredLanguages
        alt Locale.preferredLanguages 为空
            LM->>UD: 从 UserDefaults 读取 AppleLanguages
            UD-->>LM: 返回语言列表
        end

        Note over LM: 匹配支持的语言
        LM->>LM: 遍历系统语言列表
        alt 匹配到中文 (zh*)
            LM->>Bundle: path(forResource: "zh-Hans", ofType: "lproj")
        else 匹配到英文 (en*)
            LM->>Bundle: path(forResource: "en", ofType: "lproj")
        end

        alt 找到匹配的语言包
            Bundle-->>LM: 返回语言包路径
            LM->>LM: 加载语言包
        else 未找到匹配语言
            LM->>Bundle: 使用 Bundle.main (系统默认)
        end
    end

    Note over LM: 语言包验证
    LM->>Bundle: 验证语言包有效性
    alt 测试键未找到
        LM->>LM: 回退到 Bundle.main
        LM->>NC: post(.languageBundleLoadFailed)
        Note over NC: 通知用户语言包加载失败
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
    participant User as 用户

    Note over App,DM: 应用启动阶段
    App->>DM: App 启动 (static shared)
    DM->>Bridge: Kalam_Init()

    Note over DM: 定时扫描启动
    DM->>DM: startScanning()
    DM->>DM: 启动 Timer (3秒间隔)
    DM->>DM: consecutiveFailures = 0
    DM->>DM: currentScanInterval = 3.0s
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

    Note over DM: updateDevices() 内部处理
    DM->>DM: 检查选中设备是否断开（序列号比对）
    DM->>DM: 更新设备列表和序列号缓存
    alt 检测到设备
        DM->>DM: consecutiveFailures = 0
        DM->>DM: currentScanInterval = 3.0s
        DM->>DM: showManualRefreshButton = false
    end

    Note over DM: 动态调整扫描间隔
    DM->>DM: 比较当前间隔和用户设置
    alt 间隔变化超过 0.5 秒
        DM->>DM: 停止当前定时器
        DM->>DM: 创建新定时器（用户设置的间隔）
        alt 无设备连接
            DM->>DM: 间隔 currentScanInterval (指数退避)
        else 设备已连接
            DM->>DM: 间隔 userScanInterval (用户设置)
        end
    end

    alt 仅有一个设备
        DM->>DM: auto-select 设备
    end

    Note over DM,Device: 扫描成功路径
    loop 定时扫描
        DM->>Bridge: Kalam_Scan()
        alt 扫描成功
            Bridge-->>DM: 返回设备列表
            DM->>DM: consecutiveFailures = 0
            DM->>DM: currentScanInterval = 3.0s
            DM->>DM: showManualRefreshButton = false
        else 扫描失败
            Bridge-->>DM: 返回 nil/空
            DM->>DM: handleDeviceDisconnection()
        end
    end

    Note over DM,Device: 扫描失败 - 指数退避
    DM->>DM: consecutiveFailures += 1
    DM->>DM: 计算退避间隔 (3 * 2^failures)
    DM->>DM: currentScanInterval = min(backoff, 30s)

    alt consecutiveFailures < 3
        Note over DM: 继续自动扫描
    else consecutiveFailures >= 3
        DM->>DM: showManualRefreshButton = true
        DM->>DM: 停止自动扫描
        Note over User: 显示手动刷新按钮
    end

    Note over User,DM: 用户手动刷新
    User->>DM: 点击手动刷新按钮
    DM->>DM: manualRefresh()
    DM->>DM: consecutiveFailures = 0
    DM->>DM: currentScanInterval = 3.0s
    DM->>DM: showManualRefreshButton = false
    DM->>DM: startScanning()
    Note over DM: 重新开始自动扫描

    Note over DM,Device: 设备断开检测
    loop 定时扫描
        DM->>Bridge: Kalam_Scan()
        alt 设备断开
            Bridge-->>DM: 返回 nil/空
            DM->>DM: handleDeviceDisconnection()
            DM->>DM: 取消所有传输任务
            DM->>DM: 清空设备列表
            DM->>DM: 清除文件系统缓存
            DM->>DM: 发送 DeviceDisconnected 通知
            DM->>DM: connectionError = "设备已断开"
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
        FSM->>FSM: 存入缓存 (60秒过期)
        FSM-->>View: 文件列表
    
    Note over View,FSM: 用户进入文件夹
    View->>FSM: getChildrenFiles(for: device, parent)
    FSM->>FSM: getFileList() 查询子文件
    FSM-->>View: 子文件列表
    END

    Note over FSM: 缓存机制
    FSM->>FSM: 文件列表缓存 60 秒过期
    FSM->>FSM: 使用 NSCache 自动内存管理
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
    participant FS as 文件系统

    Note over View: 用户点击下载
    View->>FTM: downloadFile(from:device, fileItem, to:url, shouldReplace)

    Note over FTM: 创建传输任务
    FTM->>FTM: 创建 TransferTask
    FTM->>FTM: 添加到 activeTasks
    FTM->>FTM: 提交到 transferQueue

    Note over FTM: 执行下载
    FTM->>FTM: performDownload()
    FTM->>FTM: task.updateStatus(.transferring)

    Note over FTM: 验证目标路径
    FTM->>FTM: 获取目标目录
    FTM->>FS: createDirectory(目标目录)
    alt 目录创建失败
        FS-->>FTM: 错误
        FTM->>FTM: task.updateStatus(.failed("无法创建目录"))
        FTM->>FTM: 移动到 completedTasks
    end

    Note over FTM: 检查文件是否存在
    FTM->>FS: fileExists(atPath: 目标路径)
    alt 文件已存在
        alt shouldReplace = true
            FTM->>FS: removeItem(现有文件)
            alt 删除失败
                FS-->>FTM: 错误
                FTM->>FTM: task.updateStatus(.failed("无法替换现有文件"))
                FTM->>FTM: 移动到 completedTasks
            end
        else shouldReplace = false
            FTM->>FTM: task.updateStatus(.failed("文件已存在"))
            FTM->>FTM: 移动到 completedTasks
        end
    end

    Note over FTM: 验证设备连接
    FTM->>Bridge: Kalam_Scan()
    alt 设备已断开
        Bridge-->>FTM: 返回 nil
        FTM->>FTM: task.updateStatus(.failed("设备已断开，请重新连接"))
        FTM->>FTM: 移动到 completedTasks
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

        alt 文件过大 (>100MB)
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
    alt 下载成功 (result > 0)
        Bridge-->>FTM: 返回 1
        FTM->>FS: attributesOfItem(atPath: 目标路径)
        FS-->>FTM: 文件属性

        alt 文件验证成功
            FTM->>FTM: task.updateProgress(transferred: fileSize)
            FTM->>FTM: task.updateStatus(.completed)
        else 文件验证失败 (空文件或损坏)
            FTM->>FS: removeItem(损坏的文件)
            FTM->>FTM: task.updateStatus(.failed("下载的文件无效或损坏"))
        end
    else 下载失败 (result = 0)
        Bridge-->>FTM: 返回 0

        Note over FTM: 二次验证设备连接
        FTM->>Bridge: Kalam_Scan()
        alt 设备已断开
            Bridge-->>FTM: 返回 nil
            FTM->>FTM: task.updateStatus(.failed("设备已断开，请检查USB连接"))
        else 设备连接正常
            FTM->>FTM: task.updateStatus(.failed("下载失败，请检查连接和存储"))
        end
    end

    Note over FTM: 延迟确保文件操作完成
    FTM->>FTM: Thread.sleep(0.5秒)

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
    participant FS as 文件系统

    Note over View: 用户选择上传文件
    View->>FTM: uploadFile(to:device, sourceURL, parentId, storageId)

    Note over FTM: 输入验证 - 第1步：路径验证
    FTM->>FTM: 检查路径是否为空
    alt 路径为空
        FTM->>FTM: 返回错误
    end

    Note over FTM: 输入验证 - 第2步：文件存在性
    FTM->>FS: fileExists(atPath: sourceURL)
    alt 文件不存在
        FS-->>FTM: false
        FTM->>FTM: 返回错误
    end

    Note over FTM: 输入验证 - 第3步：目录检查
    FTM->>FS: fileExists(atPath: sourceURL, isDirectory)
    alt 是目录
        FS-->>FTM: true
        FTM->>FTM: 返回错误（不支持目录上传）
    end

    Note over FTM: 输入验证 - 第4步：文件大小
    FTM->>FS: attributesOfItem(atPath: sourceURL)
    FS-->>FTM: 文件属性
    alt 获取文件大小失败
        FTM->>FTM: 返回错误
    else 文件大小 > 10GB
        FTM->>FTM: 返回错误（文件过大）
    end

    Note over FTM: 输入验证 - 第5步：路径安全验证
    FTM->>FTM: validatePathSecurity()
    Note over FTM: 包含以下检查：
    Note over FTM: - 路径长度限制
    Note over FTM: - 路径遍历攻击检查
    Note over FTM: - 特殊字符检查
    Note over FTM: - 符号链接检查
    Note over FTM: - 允许目录范围验证
    Note over FTM: - 路径标准化验证
    alt 验证失败
        FTM->>FTM: 返回错误
    end

    Note over FTM: 输入验证 - 第6步：存储空间检查
    FTM->>FTM: 查找设备存储 (storageId)
    alt 存储未找到
        FTM->>FTM: 返回错误（存储不存在）
    end
    alt 文件大小 > 存储可用空间
        FTM->>FTM: 返回错误（设备存储空间不足）
    end

    Note over FTM: 创建任务并执行
    FTM->>FTM: 创建 TransferTask
    FTM->>FTM: 添加到 activeTasks
    FTM->>FTM: 提交到 transferQueue

    FTM->>FTM: performUpload()
    FTM->>FTM: task.updateStatus(.transferring)

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

    alt 上传成功 (result > 0)
        FTM->>FTM: task.updateProgress(transferred: fileSize)
        FTM->>FTM: task.updateStatus(.completed)

        Note over FTM: 刷新设备存储
        FTM->>Bridge: Kalam_RefreshStorage(storageId)
        Bridge-->>FTM: 刷新结果

        Note over FTM: 重置设备缓存
        FTM->>Bridge: Kalam_ResetDeviceCache()
        Bridge-->>FTM: 重置结果

        Note over FTM: 清除文件系统缓存
        FTM->>FSM: clearCache(for: device)
        FTM->>FSM: forceClearCache()

        Note over FTM: 发送刷新通知
        FTM->>View: 延迟1秒发送 RefreshFileList 通知
        Note over View: 刷新文件列表
    else 上传失败 (result = 0)
        FTM->>FTM: task.updateStatus(.failed("上传失败"))
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
    participant GoRuntime as Go Runtime

    Note over MainThread: UI 事件触发
    MainThread->>GlobalQueue: 异步提交任务
    GlobalQueue->>Bridge: CGo 调用 (阻塞)

    Note over Bridge,GoRuntime: CGo 线程切换
    Bridge->>GoRuntime: 切换到 Go 协程
    GoRuntime->>GoRuntime: Go 协程执行

    alt 快速操作 (设备扫描)
        GoRuntime-->>Bridge: 返回 JSON 结果
        Bridge-->>GlobalQueue: 返回结果
        GlobalQueue->>MainThread: DispatchQueue.main.async
        Note over MainThread: 更新 @Published 属性
        Note over MainThread: SwiftUI 自动刷新
    end

    alt 耗时操作 (文件传输)
        MainThread->>TransferQueue: transferQueue.async
        TransferQueue->>Bridge: Kalam_DownloadFile

        Note over TransferQueue: 长时间阻塞等待
        Bridge->>GoRuntime: 切换到 Go 协程
        GoRuntime->>GoRuntime: 执行下载逻辑 (重试机制)
        GoRuntime-->>Bridge: 传输完成
        Bridge-->>TransferQueue: 返回结果

        TransferQueue->>TransferQueue: 验证结果
        TransferQueue->>MainThread: DispatchQueue.main.async
        Note over MainThread: 更新任务状态
    end

    Note over MainThread: 进度更新 (已禁用)
    Note over MainThread,TransferQueue: 由于稳定性问题，进度回调已禁用
    Note over MainThread: 传输完成后一次性更新进度到 100%
    Note over MainThread: 不再实时显示传输进度
```

## 线程模型详细说明

### 队列职责

| 队列 | 类型 | 用途 | QoS | 典型操作 |
|------|------|------|-----|----------|
| 主线程 (Main Thread) | 串行 | UI 更新、用户交互 | - | 更新 @Published 属性、SwiftUI 刷新 |
| 全局队列 (Global Queue) | 并发 | 后台快速操作 | .userInitiated | 设备扫描、文件列表获取 |
| 传输队列 (Transfer Queue) | 串行 | 文件传输操作 | .userInitiated | 文件下载、文件上传 |

### 线程切换流程

1. **主线程 → 全局队列/传输队列**
   - 用户操作触发
   - `DispatchQueue.global(qos: .userInitiated).async`
   - `transferQueue.async`

2. **后台队列 → CGo Bridge**
   - 调用 C 函数（阻塞）
   - CGo 自动切换到 Go runtime 线程

3. **Go Runtime → CGo Bridge**
   - Go 协程执行完成
   - 返回结果到 Swift

4. **CGo Bridge → 后台队列**
   - 接收返回结果
   - 处理数据（JSON 解码等）

5. **后台队列 → 主线程**
   - `DispatchQueue.main.async`
   - 更新 UI 状态

### 进度回调机制

**当前状态**: 已禁用

**禁用原因**:
- 稳定性问题：进度回调可能导致传输过程中断或崩溃
- 性能影响：频繁的跨线程调用增加开销
- 用户体验：进度更新不准确，不如等待完成后一次性更新

**替代方案**:
- 传输完成后一次性更新进度到 100%
- 显示传输状态（transferring、completed、failed）
- 提供文件大小和传输时间信息

**未来改进方向**:
- 实现更稳定的进度回调机制
- 使用批处理减少回调频率
- 添加传输速度估算

### 线程安全机制

1. **@Published 属性**
   - SwiftUI 自动处理 UI 更新
   - 必须在主线程更新

2. **缓存锁**
   - `FileSystemManager` 使用 `NSLock`
   - 保护文件缓存读写

3. **任务锁**
   - `FileTransferManager` 使用 `NSLock`
   - 保护 `currentDownloadTask` 访问

4. **原子操作**
   - `isCancelled` 标志
   - 任务状态更新

### 性能优化

1. **缓存策略**
   - 文件列表缓存 60 秒
   - 减少重复的设备查询

2. **自适应扫描**
   - 无设备时使用指数退避
   - 有设备时使用用户设置的扫描间隔（默认3秒）
   - 用户可在设置中调整扫描间隔（1-10秒）

3. **队列优先级**
   - 使用 `.userInitiated` QoS
   - 平衡响应速度和系统资源

4. **批量操作**
   - 文件列表一次性获取
   - 减少设备通信次数

## 关键交互总结

| 场景 | 发起方 | 桥接层 | Go层 | 线程处理 | 特殊处理 |
|------|--------|--------|------|----------|----------|
| 设备扫描 | DeviceManager | Kalam_Scan | withDeviceQuick | 全局队列 → 主线程 | 指数退避策略、手动刷新、用户可配置扫描间隔 |
| 文件浏览 | FileSystemManager | Kalam_ListFiles | withDevice | 全局队列 → 主线程 | 30秒缓存 |
| 文件下载 | FileTransferManager | Kalam_DownloadFile | withDevice + 重试 | 传输队列 → 主线程 | 设备连接验证、文件验证 |
| 文件上传 | FileTransferManager | Kalam_UploadFile | withDevice | 传输队列 → 主线程 | 8步输入验证、上传后刷新 |
| 设备断开 | DeviceManager | Kalam_Scan 返回空 | - | 主线程处理通知 | 取消所有任务、清除缓存 |
| 手动刷新 | 用户 | - | - | 主线程 | 重置失败计数、重启扫描 |
| 语言切换 (菜单栏) | SwiftMTPApp | - | - | 主线程 + 通知机制 | - |
| 语言切换 (设置) | SettingsView | - | - | 主线程 + 通知机制 | - |
| 应用重启 | SettingsView | - | - | Process + NSApp.terminate | - |
| 本地化访问 | 各视图 | - | - | 计算属性实时获取 | - |

## 新增功能说明

### 1. 指数退避策略（设备扫描）
- **目的**: 减少无设备时的扫描频率，节省系统资源
- **机制**:
  - 初始间隔: 用户设置的值（默认3秒）
  - 每次失败后: interval = min(userScanInterval × 2^failures, 30秒)
  - 最大失败次数: 3次
  - 达到最大失败次数后: 停止自动扫描，显示手动刷新按钮
- **用户配置**: 可在设置中调整扫描间隔（1-10秒）

### 2. 手动刷新功能
- **触发条件**: 连续扫描失败3次后
- **用户操作**: 点击手动刷新按钮
- **系统行为**:
  - 重置失败计数为0
  - 重置扫描间隔为用户设置的值（默认3秒）
  - 重新开始自动扫描

### 3. 文件上传输入验证（7步）
1. **路径验证**: 检查路径是否为空
2. **文件存在性**: 验证文件是否存在
3. **目录检查**: 确保不是目录
4. **文件大小**: 获取并验证文件大小（最大10GB）
5. **路径安全验证**: 包含以下检查
   - 路径长度限制（最大4096字符）
   - 路径遍历攻击检查（禁止 ".." 及其编码形式）
   - 特殊字符检查（禁止控制字符）
   - 符号链接检查（禁止符号链接）
   - 允许目录范围验证（仅允许 Downloads、Desktop、Documents）
   - 路径标准化验证（确保无相对引用）
6. **存储空间检查**: 验证设备存储存在且有足够空间

### 4. 文件下载增强
- **设备连接验证**: 下载前和失败后验证设备连接
- **目标目录创建**: 自动创建目标目录
- **文件存在检查**: 检查目标文件是否已存在
- **文件替换选项**: 支持替换现有文件
- **文件验证**: 验证下载文件的大小和完整性
- **损坏文件清理**: 自动删除损坏的文件
- **进度回调**: 已禁用以确保传输稳定性

### 5. 上传后刷新机制
- **刷新设备存储**: `Kalam_RefreshStorage(storageId)`
- **重置设备缓存**: `Kalam_ResetDeviceCache()`
- **清除文件系统缓存**: `FileSystemManager.clearCache(for: device)`
- **发送刷新通知**: 延迟1秒发送 `RefreshFileList` 通知

### 6. 设备断开处理增强
- **取消所有任务**: `FileTransferManager.cancelAllTasks()`
- **清除设备列表**: 清空 `devices` 和 `selectedDevice`
- **清除文件系统缓存**: `FileSystemManager.clearCache()`
- **发送通知**: `DeviceDisconnected` 通知
- **更新错误状态**: `connectionError = "设备已断开"`

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
