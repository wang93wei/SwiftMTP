# Transfer Migration Design

## 1. Dependency and Rollout Boundary

filesystem 的功能、测试、build、ABI 与 race gate 已通过。transfer 子任务
继续以 provider pinning、streaming ownership、目录状态机、单一
finalization 和 error presentation 为显式交付范围，并通过对应自动化证据
验收。

本任务结束时生产默认仍为 Go。下一 cutover 子任务才让 Swift 成为新会话首选并保留 Go fallback；Go 删除只在用户未来再次明确授权后进行。

## 2. Runtime Flow

```text
FileBrowserView / FileTransferView
  → FileTransferManager (DispatchQueue + NSLock)
    → MTPConnectionCoordinator
      → provider-fixed MTPBackendSession
        → SwiftMTPBackendSession
          → MTPDeviceSession
            → LibUSBTransport / LibUSBTransfer
              → CLibUSB → libusb
        → KalamMTPBackendSession
          → token-aware Kalam transfer ABI
            → existing Go MTP implementation → libusb
```

`FileTransferManager` 只持有 app-facing `Device.id`、immutable `MTPDeviceIdentity`、typed storage/object IDs 和 task-scoped cancellation。它不持有 backend、session、libusb handle、C strings 或 native token。

## 3. Provider and Submission Contracts

`MTPConnectionCoordinator` 增加与 filesystem 同形的 typed forwarding：

```swift
func download(
    appDeviceID: UUID,
    deviceID: MTPDeviceID,
    request: MTPDownloadRequest,
    progress: @escaping MTPTransferProgress,
    cancellation: MTPCancellationToken
) throws

func upload(
    appDeviceID: UUID,
    deviceID: MTPDeviceID,
    request: MTPUploadRequest,
    progress: @escaping MTPTransferProgress,
    cancellation: MTPCancellationToken
) throws
```

转发前复用 active registration/session 的 app UUID、provider 和 transport ID 校验。coordinator lock 覆盖同步传输，selection/shutdown 等待当前 operation terminal；取消通过独立 token 进入正在阻塞的 provider，不等待 coordinator lock。

manager 的公开入口统一为可观察的 submission：有效请求返回 `TransferTask`，preflight 拒绝抛 typed error。view 在现有 alert/toast 边界展示错误，不再发生“静默 return 且没有 task”。

## 4. Streaming Transport Contract

保留现有 materialized metadata `MTPTransport.transact`，新增同步 streaming primitive：

- inbound 接受 command、预期 operation/TID、task-scoped sink 和 cancellation；
- outbound 接受 command、data header、known/unknown byte-count source 和 cancellation；
- 返回 response code/parameters 与实测字节数；
- source/sink 在现有 serial transfer queue 中调用，不需要 Actor/AsyncSequence。

每个 chunk 使用一个 `LibUSBTransfer`，并且只有上一 chunk terminal 后才提交下一 chunk。既有 ownership 不变：

1. allocate transfer/buffer；
2. context + handle 强持有 operation；
3. submit；
4. cancellation 只请求 `libusb_cancel_transfer`；
5. terminal callback 复制/确认 bytes、释放 retained callback box、唤醒 owner；
6. owner 注销 context/handle，最后 free/deallocate。

submit 明确失败是唯一不等 callback 即可释放的路径。cancel 返回码不能被解释为 transfer 已停止。

## 5. MTP Streaming Framing

普通 `MTPContainer` 继续只表示 materialized container。新增 streaming data header/state，不让 `length == 0xFFFFFFFF` 进入普通 framer：

- exact data length = payload + 12，最大精确 payload 为 `0xFFFFFFF3`；
- 更大或协议未知长度使用 `0xFFFFFFFF`；
- command、data header、data chunks、response 的 operation/TID 必须一致；
- response-before-stream-terminal、额外 data、partial header、short/overrun 均为 protocol violation 并失效 session。

`MTPDeviceSession` 把 caller 的 cancellation token 传到 transport，不再为每笔 transfer 私建不可观察 token。

## 6. Download

1. manager 校验 replacement policy 和目的目录，但不删除既有目标；
2. 在同目录建立唯一临时文件；
3. session 读取 ObjectInfo；若 size sentinel，尝试读取 64-bit ObjectSize property；
4. 执行 GetObject streaming，将 payload 顺序写入临时文件；
5. callback progress 仅携带安全的 transferred/expected byte counts；
6. 校验 response、实测 bytes 和已知 expected size；
7. sync/close 后原子 replace/move；
8. 任一失败/取消删除临时文件，既有目标保持不变。

零字节文件是合法成功，不再以 `fileSize > 0` 判损坏。

## 7. Upload

Swift 与 Go 两个 provider 都在实际 provider 边界执行 caller-independent preflight：

- absolute/standardized local URL；
- `lstat`/resource values 拒绝 symlink、目录、package 和非 regular source；
- 可读取 size 且不超过集中配置；
- storage 存在且 free space 足够；
- source name 满足 MTP wire 约束。

Swift session：

1. SendObjectInfo，ObjectInfo size `>= 0xFFFFFFFF` 写 sentinel；
2. 校验三项 response parameters，记录新 handle；
3. SendObject streaming，payload `> 0xFFFFFFF3` 使用 streaming sentinel；
4. source short-read/overrun、response error、cancel/timeout/disconnect 均失败；
5. 若阶段 1 已提交而阶段 3 失败，按 session 安全状态 best-effort DeleteObject；补偿失败附加到 typed diagnostic。

任何写入阶段都不自动 replay。重新提交只能由用户在新、明确选择的 session 发起。

## 8. Go Fallback Adapter

Native 新 ABI 必须携带 opaque exact-session token；Go session adapter 把 typed request、task ID/cancellation 和结果转换为 `MTPCoreError`。旧 `Kalam_DownloadFile` / `Kalam_UploadFile` 可暂时保留供二进制兼容，但 manager 不再调用；旧 ABI 仍只能复用一个 unambiguous active exact session。

Native upload policy 先于 MTP mutation 执行，并由不需要 libusb 的窄 seam 测试。cancellation registry 在 operation terminal 后清理，task ID 不能永久 pre-cancel。

Go fallback 是当前 production oracle，不是 Swift operation 的自动 retry target。

## 9. Manager State and Directory Upload

每个 active task 保存：

- immutable typed request/device identity；
- `MTPCancellationToken`；
- current operation ID/native task ID（Go adapter 内部）；
- lock-backed once-only terminal state。

`TransferTask` 仍由 MainActor 更新；transfer queue 通过明确 main-queue hop 更新 progress/status。`moveTaskToCompleted` 只由唯一 finalizer 调用。

目录上传使用 task-scoped operation：

```text
preflight
  → create root / required file-bearing folders
  → upload files serially
  → accumulate per-file outcomes
  → completed | partial | failed | cancelled
  → finalize once
```

两个并发目录 operation 的 token、folder cache 和 summary 相互隔离。只复制 regular files；隐藏文件/package/空目录策略保持现状。

## 10. Completion and Presentation

一个 `MTPTransferFinalizer`/等价窄 collaborator 负责：

- once-only terminal transition；
- current-task 清理；
- 若远端发生 mutation，typed storage refresh 和 device-scoped cache invalidation；
- 发布 `TransferCompletionEvent(appDeviceID, storageID, parentID, outcome)`。

`FileBrowserView` 消费 typed event，只刷新相关 device/path；删除 `RefreshFileList` 字符串通知、延迟 sleep 和全局 cache reset。

`MTPCoreError` 在 UI 边界映射为稳定本地化 presentation。Logger 保留 provider、opaque device ID、storage/object ID、bytes、duration、phase 和 error category；不记录完整本地路径、文件内容或 serial。

## 11. Retry and Session Invalidation

- 本任务不自动跨 provider fallback。
- download 只允许在没有最终文件副作用、且已完成 cancel-and-join 后由同 provider fresh session 显式重试；首版 manager 不自动重试。
- upload/create/delete 不自动重试。
- transport/protocol/timeout/disconnect/cancel 使 session invalid；local validation、unsupported provider 和 ordinary object/storage response 按现有 typed policy处理。

## 12. Rollback

在 cutover 前生产默认仍是 Go。若 Swift transfer 自动化或真机失败，保留本任务代码用于诊断，继续为新会话选择 Go。不得在 operation 已提交后切 provider。
