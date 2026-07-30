# 迁移 MTP 上传下载与取消

## Goal

在现有 typed provider/coordinator/session 边界上完整实现 Swift MTP 单文件下载、单文件上传、目录上传、进度、取消与终态处理，使传输不再从 `FileTransferManager` 直接调用全局 `Kalam_*`。本子任务完成后仍不切换生产默认：cutover 子任务才将 Swift 设为新会话首选，Go 继续通过同一 typed contract 作为人工可选 fallback。只有用户后续再次明确授权，才允许创建并执行 Go 删除子任务；libusb 始终保留。

## Background

- filesystem 子任务已完成 typed device/storage/object identity、provider-fixed coordinator、exact Go native session token、Swift/Go 文件系统操作、缓存代际和显式 Native runtime lifecycle。
- `MTPBackendSession` 已声明 typed `download` / `upload`，但 Swift 与 Go session 当前均返回 `unsupportedDevice`；`MTPConnectionCoordinator` 尚未转发传输。
- `FileTransferManager*.swift` 仍直接调用 `Kalam_Scan`、`Kalam_DownloadFile`、`Kalam_UploadFile`、`Kalam_CancelTask`、`Kalam_RefreshStorage` 和 `Kalam_ResetDeviceCache`。
- 当前 `LibUSBTransfer` 已正确持有 `libusb_transfer`、buffer 和 callback box，取消后等待 terminal callback 才释放；但 transport/session 只支持 materialized `Data`，不能表达流式 GetObject/SendObject。
- 当前目录上传使用 manager 级共享取消 flag、同步 Kalam 调用和不一致的 partial-success 终态；没有自动化测试。
- native upload policy、provider-bound transfer、目录状态机、单一
  finalization 和 error presentation 均属于本子任务的真实交付范围，必须
  以代码、测试和集成证据实际解决。

## Key Decisions

- **KD1 — Traditional concurrency exemption:** `FileTransferManager*.swift` 保持 `DispatchQueue + NSLock`。不得迁移为 Actor、AsyncSequence 驱动的 manager 或全量 Sendable 模型。
- **KD2 — Provider pinning:** 一次提交始终绑定 immutable `(app device UUID, provider, transport device ID, open session)`。执行中不得切 provider；Swift 错误不得自动重放到 Go，尤其不得跨 provider 重放上传、创建或删除。
- **KD3 — Fallback policy:** 本子任务仍保留生产默认 Go。cutover 完成后 Swift 才成为新会话首选，Go 仅作为用户显式选择的新会话 fallback；fallback 只能发生在操作提交前。
- **KD4 — Terminal callback ownership:** timeout/cancel/shutdown 只能请求 libusb cancel；必须等待 terminal callback 后才能释放 transfer、buffer、callback box、handle lease、session 或文件资源。
- **KD5 — Stream shape:** transport/session 使用传统同步、顺序分块的 source/sink seam；每个 endpoint 同时最多一个已提交 chunk，整个 MTP transaction 仍由现有 lock 串行。不得为“流式”引入多个并发 MTP transaction。
- **KD6 — Size semantics:** ObjectInfo 的 `0xFFFFFFFF` 是 size sentinel，不是精确 4 GiB。data-container payload `> 0xFFFFFFF3` 使用 streaming sentinel；下载优先读取 64-bit ObjectSize property，无法取得时进度可 indeterminate，但最终字节数必须实测。
- **KD7 — Mutation ambiguity:** SendObjectInfo 成功后，任何 timeout/disconnect/cancel 都视为可能已提交；不得自动重试创建。SendObject 失败时按安全条件 best-effort 删除返回的 object handle，并记录补偿失败。
- **KD8 — Download finalization:** 下载写入同目录临时文件，允许合法空文件；只有完整协议成功和字节校验后才原子落位，失败/取消不损坏或删除既有最终文件。
- **KD9 — Directory compatibility:** 保留串行逐文件上传和“只传 regular files”的现有用户范围；不新增并行多文件、空目录复制或 package 内容上传。每次目录提交拥有独立取消 token、folder cache、summary 和唯一终态。
- **KD10 — Completion boundary:** 传输完成只经过一个 typed finalization 入口，负责任务终态、current-task 清理、storage refresh、device-scoped cache invalidation 和 UI refresh event；不再使用延迟魔法字符串通知或全局清缓存。

## Requirements

- **R1 — Provider-bound transfer:** coordinator 为 download/upload 提供 typed forwarding，并继续校验 app UUID、transport ID、provider 与 active session。Go fallback 新增 token-aware transfer ABI；manager/view 不再知道 C string 或 Kalam symbol。
- **R2 — Native fallback policy:** Go 上传边界独立执行 source path、长度、regular-file、symlink、size 和 cancellation 校验。旧 C ABI 可保留用于兼容，但 typed Go session 必须使用 exact native token，0/2 个 active session 时继续 fail closed。
- **R3 — Streaming transport:** 在不破坏现有 metadata `transact` 的前提下增加 streaming inbound/outbound primitive。partial、ZLP、short transfer、timeout、cancel、disconnect、submit failure 和 callback race 均有确定性资源生命周期。
- **R4 — Swift download:** 实现 GetObject 流式读取、container header/TID/operation/response 校验、临时文件、原子替换、空文件、fragmentation、进度和取消。
- **R5 — Swift upload:** 实现文件 ObjectInfo、SendObjectInfo、SendObject 流式发送、32-bit metadata sentinel、data-container streaming sentinel、实际字节进度与 orphan cleanup。
- **R6 — Cancellation:** 每个 `TransferTask` 绑定自己的 `MTPCancellationToken`；取消 queued/running task 均幂等并产生一次 `.cancelled` 终态。取消一个目录任务不得影响其他任务。
- **R7 — Submission and task state:** 单文件与目录入口使用一致的 typed submission contract，拒绝必须可观察，不能静默 return。状态准确表达 pending/transferring/completed/failed/cancelled；目录 partial success 使用显式 outcome/summary，不伪装 completed。
- **R8 — Directory state machine:** preflight、root/folder creation、per-file outcome、summary、cancellation 和 finalization 是一个 task-scoped 状态机；路径/size/symlink/storage-space policy 与单文件上传一致。
- **R9 — Completion and UI:** 成功、失败、取消和 partial 的所有退出路径各自只 finalize 一次。只有实际远端 mutation 才 refresh storage/cache；UI 通过 typed observable event/结果刷新并复用或最小补充本地化文案。
- **R10 — Error boundary:** backend/manager 使用 `MTPCoreError`；UI 在一个窄映射边界将 disconnected/busy/permission/timeout/cancel/unsupported/local-file/response 映射为稳定本地化展示，日志保留技术上下文但不记录完整本地路径、文件内容或设备 serial。
- **R11 — Tests and diagnostics:** Swift protocol/transport/backend/coordinator/manager/目录状态、Go policy/ABI/race、build/Analyze/header/symbol、静态架构检查和 `git diff --check` 均有自动化证据；硬件不可用时必须明确标记，不能宣称真机 parity 或允许 cutover。

## Acceptance Criteria

- [ ] **AC1 (R2):** Go upload policy 覆盖不存在、目录、symlink、非 regular、零字节、合法 Unicode/`..` 名称、配置上限、`UInt32.max` 两侧、pre/mid cancel 和 cancellation cleanup；`go test`、`go test -race`、`go vet` 通过。
- [ ] **AC2 (R1/KD2–KD3):** coordinator 只把传输转发给匹配的 active session；Go ABI 收到 exact token；wrong app/device/provider、stale token、0/2 active session 均 fail closed；没有自动 provider 切换或 mutation replay。
- [ ] **AC3 (R3/KD4–KD5):** streaming IN/OUT 的 buffer、transfer、callback box、context/handle lease 只在 terminal callback 后释放；cancel-before-submit、blocked-submit、cancel-vs-complete、timeout、disconnect、shutdown 和 duplicate callback tests 通过。
- [ ] **AC4 (R4/KD6/KD8):** download 覆盖空文件、小文件、fragmentation、split header、ZLP、short/oversized/malformed stream、64-bit ObjectSize、local write error、cancel/timeout/disconnect；失败不损坏既有最终文件且不留临时文件。
- [ ] **AC5 (R5/KD6–KD7):** upload 覆盖 ObjectInfo size `0xFFFFFFFE`/`0xFFFFFFFF`/`0x1_0000_0000`，payload `0xFFFFFFF3` 两侧、source read error、MTP response、cancel/timeout/disconnect 和 compensation success/failure；提交不被自动重放。
- [ ] **AC6 (R6–R7):** manager 的 download/upload submission、progress、cancel 和 pending→terminal 状态有确定性测试；拒绝可观察；任务恰好移动一次；`FileTransferManager.swift` 不再直接引用任何 transfer Kalam symbol。
- [ ] **AC7 (R8/KD9):** 目录上传覆盖 manifest、空间/路径 policy、nested structure、全成功、全失败、partial、pre/mid cancel、两个并发 operation 的取消隔离和单一 summary/finalization；不上传 package 内容或新增空目录语义。
- [ ] **AC8 (R9):** 每次产生远端变更的 operation 只执行一次 typed storage refresh、device-scoped cache invalidation 和 UI event；无 mutation 的拒绝/失败不伪刷新；`RefreshFileList` 字符串通知与全局缓存清理从传输路径移除。
- [ ] **AC9 (R10):** 三个用户可见边界至少覆盖 submission、transfer terminal、directory partial/cancel 的本地化映射；日志不泄露完整路径、文件内容或 serial。
- [ ] **AC10:** focused/full Swift tests、arm64 Debug/Release、Analyze、Go normal/race/vet、`./Scripts/build_kalam.sh`、header parity、dylib arch/minOS/dependencies/symbols、`git diff --check` 全部通过。
- [ ] **AC11:** 静态架构检查证明生产默认仍为 Go，manager/view 无 transfer Kalam 调用、magic refresh、全局 cache reset、`Thread.sleep`、Actor 迁移或跨 provider 自动重放，并在 `verification.md` 记录结果。
- [ ] **AC12:** 有 Android 硬件时完成空/小/嵌套/大文件、SHA-256、取消、拔线和恢复矩阵；不可用时标记 unavailable，本子任务仍不得改变默认 provider 或授权删除 Go。

## Out of Scope

- 将 Swift 设置为生产默认、自动 fallback、跨 provider retry 或最终 cutover。
- 删除 Go/CGO/libkalam、修改 Go 删除计划，或移除/替换 libusb。
- 将 `FileTransferManager*.swift` 改为 Actor/AsyncSequence/Swift concurrency state machine。
- 并行多文件/多设备传输优化、暂停/恢复、断点续传、MTP CancelTransaction event。
- 上传 package 内容、复制空目录、SwiftUI 信息架构改版。
- universal Release/DMG、签名、公证和最终分发验证；这些属于 cutover。

## Deferred Risks

- 无 Android 硬件时只能证明协议、资源生命周期和 manager 合同，不能证明特定设备 quirks、真实大文件或拔线恢复。
- 某些设备不支持 64-bit ObjectSize property；此时下载进度可 indeterminate，但不能截断或伪造精确大小。
- SendObjectInfo 后断连可能无法安全确认或删除 orphan；必须显式报告，不能通过盲目 retry 掩盖。

## Open Questions

无阻塞项。最终 Go 删除仍是独立、尚未授权的父任务门槛。
