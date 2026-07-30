# 迁移 MTP 文件系统操作

## Goal

在已验证的 Swift libusb/MTP session 上实现当前生产使用的对象与目录操作，并将设备扫描、目录浏览、建目录和删除收口到 typed backend/coordinator 边界。用户继续使用现有 SwiftUI 文件浏览器；本子阶段因上传/下载尚未迁移，生产默认仍为 Go，但显式开发/测试配置可以在新会话选择 Swift provider。全链路完成后按父任务切换为 Swift 优先、Go 回退；删除 Go 必须等待用户后续明确授权。

## Background

- Foundation 与 discovery/session 已分别完成 codec、typed backend、libusb 生命周期、精确设备 ID、MTP session/transaction 和设备/存储扫描验证。
- 当前 `DeviceManager`、`FileSystemManager` 及 FileBrowser 创建/删除动作仍直接调用 `Kalam_*`；新 `MTPConnectionCoordinator` 尚无生产调用者。
- 当前 Swift transaction 只支持 command → 可选 data-in → response，且未保留 response parameters；`SendObjectInfo` 所需 command → data-out → response 仍缺失。
- 当前目录读取把 `nil`、JSON 错误、设备错误和合法空目录都折叠成 `[]`，无法区分失败与空目录。
- 当前 Go scan 固定返回 legacy `id = 1`，Native 文件系统 ABI 不接收 device/session identity，连接池会取任意空闲设备；Swift facade 的 provider/device 校验无法证明 live Go 操作命中同一物理设备。
- 当前 libusb 继续保留；Go/CGO/libkalam 在 Swift-first 观察期保留为 fallback，本任务不得删除或扩散其调用边界。最终删除是独立的用户授权门槛。

## In Scope

- ObjectInfo dataset、对象列表、目录创建、对象删除和 storage refresh。
- 为小型 MTP metadata data-out 扩展 transaction/transport seam，并保留后续流式传输扩展边界。
- Swift 与迁移期 Go provider 的 typed filesystem session contract。
- Go fallback 的稳定 USB topology locator、exact open、opaque native session token 与 session-aware filesystem ABI。
- `DeviceManager`、`FileSystemManager` 和 FileBrowser 创建/删除动作接入 provider-fixed coordinator。
- 设备级目录缓存、失败语义、结构化诊断和自动化测试。

## Key Decisions

- **KD1 — Provider default:** `AppConfiguration` 的生产默认在本任务前后均为 `.go`，避免与尚未迁移的传输路径混用 provider；Swift 仅由显式开发/测试配置为新会话选择。全链路完成后的目标是 Swift 优先、Go 回退，且活动会话不得切 provider。
- **KD2 — Integration boundary:** Manager 注入 coordinator/runtime 抽象，不注入裸 `MTPBackend` 后自行打开 session。
- **KD3 — Listing result:** 合法空目录返回成功空 listing；整体失败抛 typed error；可恢复的单项 ObjectInfo response 失败保留其余对象并附带结构化 warning。
- **KD4 — Session safety:** transport、协议、transaction mismatch、session-not-open 等失同步错误中止列表并使 session 失效；不能为了复刻 Go 的 `continue` 而吞掉失同步错误。
- **KD5 — Cache:** 只缓存成功 listing；TTL 使用集中配置和可注入 clock；成功创建/删除后才失效受影响设备缓存，失败不得预先清缓存或伪刷新。
- **KD6 — Identity:** app UUID 只作为 UI key；每次文件系统操作同时绑定 immutable `(provider, MTPDeviceID)`。Go locator 使用完整 USB `(bus, port path, VID, PID)`，不得使用 `deviceIndex`、device address、serial、单独 VID/PID 或枚举顺序重连。
- **KD7 — Unicode:** 保留现有名称非法字符约束，但按 MTP UTF-16 code units 验证 wire 长度，正确支持 surrogate pair，不复制 Go vendor 的非 BMP 损坏行为。
- **KD8 — Native session pinning:** Go fallback open 返回 opaque native token；list/create/delete/refresh 和 close 都必须携带该 token。旧 transfer ABI 在本任务保留，但不得绕过 active exact session 去任取另一设备；若无法安全兼容则 fail closed，不扩大为传输迁移。

## Requirements

- **R1 — ObjectInfo codec:** 完整解码/编码标准 ObjectInfo 字段；映射名称、storage/parent/object ID、compressed size、folder association、修改时间与关键词。拒绝截断、尾随数据、embedded NUL 和超长 MTP string。
- **R2 — Transaction phases:** 支持 response-only、data-in 和小型 data-out 三种 transaction；所有 container 使用同一 operation/TID，response parameters 必须保留并校验。普通可恢复 MTP response 不应无条件销毁 session。
- **R3 — List objects:** `GetObjectHandles(storage, 0, parent)` 后按 handle 顺序执行 `GetObjectInfo`。handle-list 失败、transport/protocol/session 失败必须整体抛错；合法空 handles 返回成功空 listing。
- **R4 — Partial object diagnostics:** 单个对象的可恢复 MTP response 失败可跳过，但结果必须包含 device/storage/parent/object ID、阶段和 typed error；不记录文件内容、完整本地路径或设备 serial。
- **R5 — Create folder:** `SendObjectInfo` 使用 folder format `0x3001`、size `0`、给定 storage/parent 和合法 Unicode 名称；成功 response 必须包含 storage、parent、新 handle 三项且均与请求/类型约束一致。
- **R6 — Delete and refresh:** `DeleteObject(handle, format 0)` 只在 OK response 后成功；zero handle 在 Swift 边界拒绝。Refresh 只声明重新读取 storage info，不声称清除设备端缓存。
- **R7 — Go migration adapter:** 迁移期 Go provider 经同一 typed filesystem contract 调用 Kalam。Scan 返回稳定 topology locator；exact open 创建 opaque token；所有 filesystem 操作只通过该 token 访问同一 Native device。所有非 nil C string 在成功、decode 失败和 typed validation 失败路径均恰好释放一次；不得复制字符串分类重试或重复提交写操作。
- **R8 — Device integration:** `DeviceManager` 通过可注入 provider runtime 接收 `MTPScanResult(snapshots, failures)`，维护 transport identity → app UUID 映射并注册 coordinator。只有成功扫描确认 selected identity 消失或明确 transport disconnect 才执行断连清理；timeout/decode/protocol 等可重试失败保留当前连接。所有发布仍在 `@MainActor`。
- **R9 — Filesystem integration:** `FileSystemManager` 保持 actor，通过可注入 coordinator facade 执行 list/create/delete/refresh。App model 与 filesystem API 持续使用 `MTPStorageID`/`MTPObjectID`；批量删除返回命名结果，分别保留成功 ID 与逐项 typed error；排序仍由现有 UI 负责。
- **R10 — UI integration:** FileBrowser 的 listing、单删、批删和建目录不得再直接调用 `Kalam_*`。合法空目录显示现有空目录视图；失败走现有错误 alert/toast，不伪装为空目录。
- **R11 — Cache correctness:** cache key 至少包含 app UUID、provider、transport ID、storage 和 parent；TTL 为 60 秒集中配置；断连和成功写操作按设备失效；旧请求不得在失效后回写 stale cache。
- **R12 — Diagnostics and tests:** USB/MTP/object/cache 失败使用 `MTPCoreError` 与 `Logger` 分类；纯逻辑、backend contract、manager integration 和 optional hardware matrix 均有明确证据。
- **R13 — Lifecycle and ownership cleanup:** Go Native config/pool worker 仅由显式 `Kalam_Init/Cleanup` 创建、停止和重建；cleanup join worker 后清 sessions/pool。删除无生产消费者的 `MTPBackendRouter`，保留 `MTPConnectionCoordinator` 为唯一 production session owner。

## Acceptance Criteria

- [x] **AC1 (R1):** file/folder、BMP/emoji Unicode、UTC/offset timestamp、32-bit size sentinel、截断、尾随与 malformed ObjectInfo exact-wire tests 通过。
- [x] **AC2 (R2):** response-only、data-in、metadata data-out、response parameters、wrong operation/TID/order、short OUT 与普通 response 后 session 可继续均有测试。
- [x] **AC3 (R3–R4):** root、多 storage、合法空目录、文件/文件夹、单项可恢复失败、handles/transport/protocol 终止失败均有 backend tests；空目录与失败可观察地区分。
- [x] **AC4 (R5):** folder ObjectInfo exact bytes、Unicode/非法名称、缺少 response params、mismatched storage/parent 与 zero handle 均有测试。
- [x] **AC5 (R6):** delete exact request/response、invalid handle、MTP/USB error 与 typed storage refresh 有测试；失败不产生伪成功。
- [x] **AC6 (R7/KD8):** Go/Swift/fake backend filesystem contract tests 通过；两个同 VID/PID locator、枚举重排、exact open、A/B token 交错操作、stale token、幂等 close/cleanup 和 Go C string 所有权均有独立断言。旧 transfer symbols 保持链接且不会绕过 active exact session。
- [x] **AC7 (R8):** DeviceManager 的 app UUID 映射来自 live-shaped Go topology identity，不依赖枚举顺序或 legacy `deviceIndex`；两设备、重排、partial success、empty success、timeout/decode、明确断连、selected identity 消失和 provider-fixed registration tests 通过；测试不再用真实时间轮询，所有 published 状态仍在 MainActor 更新。
- [x] **AC8 (R9–R11):** `Device` operational identity 非 optional；`StorageInfo`/`FileItem`/filesystem API 使用 typed IDs。FileSystemManager cache hit/TTL/设备隔离/失效代际、mapping、空目录、失败未缓存、成功写后失效、失败写不失效、批删成功/逐项失败及 scoped late-response tests 通过。
- [x] **AC9 (R10):** `FileSystemManager`、FileBrowser 建目录/单删/批删生产源码不再命中 `Kalam_ListFiles/Kalam_CreateFolder/Kalam_DeleteObject`；错误沿现有 UI 提示路径呈现。
- [x] **AC10 (KD1/KD6/KD8):** 默认 provider 配置与生产构造路径仍为 Go；仅显式测试/开发配置可为新会话选择 Swift；活动 session 的 provider/device identity/native token 不可改变，Native 操作不再使用 unkeyed `withDevice`。
- [x] **AC11:** libusb/CLibUSB/LibUSBTransport 保持原边界，Go/CGO/libkalam 未删除；本任务不引入 IOKit 替代路径。
- [x] **AC12:** 聚焦 tests、全部 `SwiftMTPTests`、arm64 Debug/Release build、arm64 Analyze、Go normal/race/vet、native/ABI 检查与 `git diff --check` 通过并写入 `verification.md`。
- [x] **AC13:** 若有 Android 硬件，记录 provider、设备/OS 和 scan→root→nested→create→refresh→delete 原始结果；若不可用，明确标记 unavailable，且不得据此宣称真机 parity 或允许最终 cutover。
- [x] **AC14 (R13):** `MTPBackendRouter` 与专属死测试已删除；Native 未在 package load 时读取 live config 或启动 worker，init/cleanup/re-init、worker join 和 race tests 通过。

## Out of Scope

- 文件内容上传、下载、进度、取消、超时重试和目录上传。
- 重写 Go 上传/下载数据算法或修改 `FileTransferManager*.swift` 的 `DispatchQueue + NSLock` 并发模型；本任务只允许为 exact-device 兼容复用 active native session。
- rename、move、copy、thumbnail、MTP event endpoint 和对象属性编辑。
- 在传输尚未迁移时提前将 Swift 设为生产默认，或删除 Go/CGO/libkalam、替换/移除 libusb。
- SwiftUI 信息架构改版；仅复用现有加载、空目录和错误提示状态。
- 解决现有 universal Release/DMG 的 arm64-only dylib 分发限制。

## Deferred Risks

- 无 Android 硬件时只能证明 wire、contract 与 manager 行为，不能证明设备 quirks 或真实写入互操作。
- vendor-specific `0xFF` interface 策略沿用 discovery/session；quirk allowlist 不在本任务扩展。
- 没有两台真实 Android 时，topology locator 与 no-cross-device mutation 只能由 fake enumerator/opener 证明；必须保留 hardware unavailable 标记。
- 文件传输所需 streaming data phase 由下一子任务实现；本任务的数据发送仅覆盖小型 ObjectInfo metadata，但接口不得阻断后续流式扩展。
