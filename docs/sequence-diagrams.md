# SwiftMTP 时序图

## 1. 设备检测时序图

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

## 2. 文件浏览时序图

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

## 3. 文件下载时序图

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

## 4. 文件上传时序图

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

## 5. 核心组件交互关系图

```mermaid
graph TB
    subgraph SwiftUI 层
        MV[MainWindowView]
        DL[DeviceListView]
        FB[FileBrowserView]
        FT[FileTransferView]
    end

    subgraph Service 层
        DM[DeviceManager<br/>单例 - 设备检测]
        FSM[FileSystemManager<br/>单例 - 文件浏览]
        FTM[FileTransferManager<br/>单例 - 传输管理]
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

    MV --> DM
    MV --> FSM
    MV --> FTM

    DM --> Bridge
    FSM --> Bridge
    FTM --> Bridge

    Bridge -->|CGo 调用| Go

    Go -->|USB 通信| USB
    Go -->|MTP 协议| MTP

    USB -->|USB 协议| Device[Android 设备]
    MTP -->|MTP 协议| Device
```

## 6. 线程模型时序图

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
