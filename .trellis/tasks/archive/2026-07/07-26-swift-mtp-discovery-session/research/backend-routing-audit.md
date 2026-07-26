# Research: Backend Routing Audit

- Query: 审查当前 `MTPBackend` / `MTPBackendRouter` / Go backend，以及正在形成的 Swift discovery/session/coordinator seam；重点核验同 VID/PID 多设备精确路由、扫描部分失败、candidate/session 所有权、重复 connect/disconnect、Go 默认 provider 与未来 managers 协议边界。
- Scope: internal
- Date: 2026-07-27

## Files Found

- `SwiftMTP/Services/MTP/Backend/MTPBackend.swift` — provider-neutral snapshot、backend 与 session 协议。
- `SwiftMTP/Services/MTP/Backend/MTPBackendRouter.swift` — provider 锁定、单 session 排他和 backend 生命周期包装。
- `SwiftMTP/Services/MTP/Backend/GoMTPBackend.swift` — Kalam C ABI 的适配雏形；尚无可用生产 `GoMTPKernelBoundary.openSession` 实现。
- `SwiftMTP/Services/MTP/Backend/MTPDeviceSession.swift` — Swift MTP session/TID 状态机和 discovery transactions。
- `SwiftMTP/Services/MTP/Transport/USBDescriptors.swift` — Swift USB stable ID 与 MTP interface 选择。
- `SwiftMTP/Services/MTP/Transport/USBDeviceEnumerator.swift` — libusb 枚举、candidate retain 与逐设备描述符容错。
- `SwiftMTP/Services/MTP/Transport/LibUSBDeviceHandle.swift` — candidate/handle/claim 生命周期。
- `SwiftMTP/Services/MTP/DeviceManager.swift` — 当前生产 Go 扫描、UI UUID 缓存与选择状态。
- `SwiftMTP/Services/MTP/FileSystemManager.swift` — 当前文件系统仍直接调用全局 Kalam ABI。
- `SwiftMTP/Services/Protocols/DeviceManaging.swift` — UI manager 协议，当前没有 opaque transport ID/session 概念。
- `SwiftMTP/Services/Protocols/FileSystemManaging.swift` — 以 `Device` 参数表达目标，但实现未把它传到 Go ABI。
- `SwiftMTP/Services/Protocols/FileTransferManaging.swift` — 以 `Device` 参数表达目标，但现有 Kalam 操作仍依赖全局设备连接。
- `SwiftMTP/Models/Device.swift` — UI 设备仅含 UUID、Go `deviceIndex` 与 serial，没有 `MTPDeviceID`。
- `Native/kalam_bridge.go` — Go 扫描固定返回单设备、固定 `ID: 1`。
- `Native/kalam_pool.go` — 全局 pool 获取任意空闲连接，创建时调用无目标参数的 `mtpx.Initialize`。
- `SwiftMTPTests/MTP/Backend/MTPBackendRouterTests.swift` — Router provider/device 锁定、幂等 close、失败恢复与 in-flight close 测试。
- `SwiftMTPTests/MTP/Backend/MTPDeviceSessionTests.swift` — discovery TID、already-open recovery 与 invalidation 测试。
- `SwiftMTPTests/MTP/Transport/MTPInterfaceSelectorTests.swift` — stable ID 与 endpoint shape 测试。
- `SwiftMTPTests/MTP/Transport/USBDeviceEnumeratorTests.swift` — C descriptor 映射、unsupported 过滤和引用释放测试。

## Findings

### 1. Stable ID 生成基础正确，但“精确重开”闭环尚不存在

- `USBDeviceEnumerator.descriptorSnapshot(for:)` 采集 bus、port path、VID/PID（`SwiftMTP/Services/MTP/Transport/USBDeviceEnumerator.swift:62-108`）。
- `MTPInterfaceSelector.stableID(for:)` 生成 `swift:<bus>:<port-path>:<vid>:<pid>`（`SwiftMTP/Services/MTP/Transport/USBDescriptors.swift:98-108`）。因此两个同 VID/PID、但端口路径不同的设备可以得到不同 ID。
- `MTPUSBInterface` 把该 ID 与 configuration/interface/endpoints 绑定（`SwiftMTP/Services/MTP/Transport/USBDescriptors.swift:42-49,72-83`）；`LibUSBDeviceCandidate` 同时拥有 retained `rawDevice` 和该 interface（`SwiftMTP/Services/MTP/Transport/LibUSBDeviceHandle.swift:3-26`）。
- 但仓库当前没有 `SwiftMTPBackend.swift`、`MTPConnectionCoordinator.swift`，也没有 candidate registry 或 “按 ID 重新枚举并精确匹配” 实现。现状只能证明 ID 可区分，不能证明 snapshot → selection → reopen 不串设备。
- `MTPDeviceSnapshot` 携带 `MTPDeviceID`（`SwiftMTP/Services/MTP/Backend/MTPBackend.swift:8-14`），`MTPBackend.openSession(for:)` 要求 exact ID（同文件 `47-51`），Router 还会核验返回 session 的 provider/device（`SwiftMTP/Services/MTP/Backend/MTPBackendRouter.swift:43-59`）；这些是正确的协议锚点，但尚无 Swift backend 实现闭环。

风险：

1. 若未来 backend 仅按 VID/PID、enumeration index 或第一个 candidate 打开，同 VID/PID 双设备必然可能串路由。
2. `getPortNumbers` 只分配 8 层路径；`LIBUSB_ERROR_OVERFLOW` 被容忍后落入 `portCount <= 0` 并清空路径（`USBDeviceEnumerator.swift:71-81`），ID 会退化为 `root`。同 bus、同 VID/PID 的多个退化 candidate 会碰撞。
3. 真正的稳定性是“同一次物理拓扑连接期间稳定”；换 USB 端口后 ID 会变化。若产品需要跨端口稳定，需要成功 open 后的 serial 参与独立 UI identity，但 serial 不应替代本次 transport reopen key。

建议的 ownership/lookup 规则：

- scan 期间每个 snapshot 只暴露 opaque `MTPDeviceID`；UI 不解析字符串。
- backend 不应长期持有 scan candidate 作为唯一重开依据。`openSession(for:)` 应重新枚举，并以完整 `MTPDeviceID` 精确匹配，匹配数必须恰好为 1；0 个返回 `noDevice`，大于 1 个返回 protocol/identity collision 错误。
- 如果为性能短暂缓存 retained candidate，cache 必须由 backend/context 所有，按 scan generation 失效；session 创建成功后由 session/handle 独占相关 handle，scan 临时 session 必须关闭。

### 2. 当前 Go backend 无法满足多设备精确路由

- `Kalam_Scan` 通过 `withDeviceQuick` 只操作一个 `*mtp.Device`，构造的列表只 append 一个设备且 `ID: 1`（`Native/kalam_bridge.go:44-108`，尤其 `80-100`）。
- pool entry 没有 physical identity 字段，只有 `device/lastUsed/inUse`（`Native/kalam_pool.go:19-23`）；`getDeviceFromPool` 返回任意空闲 entry（`68-96`）。
- `createNewDevice` 调用无目标参数的 `mtpx.Initialize`（`Native/kalam_pool.go:153-168`），不能表达 exact `MTPDeviceID`。
- Swift 适配层把 Go ID 映射为 `go:<id>`（`SwiftMTP/Services/MTP/Backend/GoMTPBackend.swift:83-97`），因此当前永远近似 `go:1`；`openSession(for:)` 虽检查 prefix 和返回 session identity（`57-67`），但底层 boundary 尚没有可见的、按物理设备 ID 打开的实现。

结论：KD3“生产默认仍为 Go”当前成立，但 Go 默认路径仍是历史单设备全局语义，不应被当作多设备精确路由的参考实现。若 filesystem 阶段要支持多个设备，必须让 Go boundary 也接受可解析的稳定 identity，或明确 Go provider 在迁移期只支持单设备并在多设备时 fail closed。

### 3. 扫描部分失败目前只在枚举层被吞掉，协议层无法聚合诊断

- `USBDeviceEnumerator.enumerate()` 对单设备 descriptor/config 错误记录日志后继续（`USBDeviceEnumerator.swift:31-59`），unsupported interface 也仅日志并忽略（`37-40`）。这能保住其他 candidate，但错误不会返回调用者。
- `MTPBackend.scanDevices()` 返回单一 `[MTPDeviceSnapshot]` 或抛全局错误（`MTPBackend.swift:47-51`），没有 per-candidate failure 载体。
- `MTPDeviceSnapshot` 的 `storages` 是纯成功数组（`MTPBackend.swift:8-14`），无法表达“设备信息成功但某 storage 失败”。
- Go `Kalam_Scan` 在 storage 查询失败时降级为空 storage 并打印日志（`Native/kalam_bridge.go:55-61`），调用侧无法区分“确实无 storage”和“storage 查询失败”。
- `DeviceManager.scanDevices()` 把 Kalam `nil`、UTF-8/JSON decode failure 都走向全局 disconnection（`SwiftMTP/Services/MTP/DeviceManager.swift:227-310`），会清空所有设备，而不是保留其他成功设备。

建议的最小协议形状：

```swift
struct MTPScanResult: Sendable {
    let snapshots: [MTPDeviceSnapshot]
    let failures: [MTPScanFailure]
}

struct MTPScanFailure: Sendable {
    let deviceID: MTPDeviceID?
    let stage: MTPScanStage // descriptor/open/claim/deviceInfo/storageIDs/storageInfo/close
    let storageID: MTPStorageID?
    let error: MTPCoreError
}
```

全局 enumeration/context 失败才 throw；candidate 级失败追加到 `failures` 并继续。若不愿变更 `MTPBackend.scanDevices()`，至少需要单独 diagnostics sink/callback，但返回 typed result 更适合测试与 manager 映射。

### 4. Router 的单 session 生命周期基本可靠，但 coordinator seam 缺失

- Router 默认 provider 是 `.go`（`MTPBackendRouter.swift:11-16`）。
- `hasOpenSession` 在选 factory 前受锁保护，重复 open 和 session 存活期 provider 切换都会返回 `.busy`（`19-41`）。
- open 失败会 shutdown backend 并释放 router 状态（`43-64`）。
- routed session 的 `close()` 受独立锁保护，底层只 close 一次；deinit 也会 close（`74-90,143-166`）。现有测试覆盖重复 close、deinit、open failure 和 close 等待 in-flight delegation（`SwiftMTPTests/MTP/Backend/MTPBackendRouterTests.swift:37-133`）。
- 但是需求中的“切换设备关闭旧 session，然后打开新 session”不是 Router 行为：Router 在旧 session 存活时直接 `.busy`。需要 `MTPConnectionCoordinator` 原子执行 close-old → clear mapping → open exact new ID → publish mapping。
- 当前没有 `app Device.id → (provider, MTPDeviceID, session)` 映射。`Device` 也不携带 opaque transport ID（`SwiftMTP/Models/Device.swift:49-74`）。

coordinator 必须成为 session 的唯一 owner：

- key：UI `Device.id`。
- value：固定 provider、snapshot `MTPDeviceID`、唯一 open `MTPBackendSession`。
- `connect(same app ID, same transport ID)` 应幂等返回现有 session，或明确 `.busy`，不能创建第二个底层 session。
- `connect(other ID)` 必须同步关闭旧 session并等待完成，再 open 新 session；open 新 session 失败时不得恢复/复用已关闭旧 session。
- `disconnect`、重复 `disconnect`、session deinit、USB invalidation 都必须最终只触发一次底层 close/shutdown，并清除 mapping。
- session 操作前同时校验 app ID mapping 和 `session.deviceID`，防止 UI stale selection 路由到当前另一个设备。

### 5. Provider 默认仍是 Go，但 Router 目前不在生产调用链

- `DeviceManager` 初始化时直接 `Kalam_Init()`（`SwiftMTP/Services/MTP/DeviceManager.swift:118-133`），扫描直接 `Kalam_Scan()`（`227-251`）。
- `FileSystemManager` 直接调用 `Kalam_ListFiles(storageId,parentId)`，虽然方法收到了 `Device`，却只用于 cache key，没有传递设备 identity（`SwiftMTP/Services/MTP/FileSystemManager.swift:106-129,202-213`）。
- transfer/create/delete/refresh 同样是全局 Kalam ABI；调用没有 session/device handle（例如 `SwiftMTP/Services/MTP/FileTransferManager+DirectoryUpload.swift:181-182,249,348`）。
- `MTPBackendRouter` 没有 `scanDevices` API，也没有生产 composition root/factory。其 `.go` 默认值只能证明类的局部默认，不能证明生产 manager 已经通过 Router。

因此当前“Go 默认”由历史 manager 直连实现，而非 Router provider selection 实现。未来接入时应在应用 composition root 创建一个长期 coordinator/router，并把 provider 在“扫描/新 session 建立前”冻结；不要让 DeviceManager、FileSystemManager、FileTransferManager 各自创建 router/backend，否则会破坏 session/provider 一致性。

### 6. 未来 managers 切换所需协议边界

现有 manager protocols 仍是 UI-oriented：

- `DeviceManaging` 暴露 `Device` 列表和 `selectDevice`，没有 typed scan result、transport ID 或 connect/disconnect（`SwiftMTP/Services/Protocols/DeviceManaging.swift:13-55`）。
- `FileSystemManaging` 和 `FileTransferManaging` 虽接收 `Device`（`FileSystemManaging.swift:15-43`; `FileTransferManaging.swift:25-46`），但 `Device` 只有 UI UUID/legacy index/serial。
- `MTPBackendSession` 已经是合适的 provider-neutral filesystem/transfer 边界（`MTPBackend.swift:54-79`）。

建议边界：

1. DeviceManager 只负责 `MTPScanResult → Device view model`，并维护 `Device.id ↔ MTPDeviceID` 的 coordinator mapping；不要让 `Device` 字符串化/解析 transport ID。
2. FileSystemManager/FileTransferManager 依赖注入 session resolver，例如 `session(for appDeviceID: UUID) throws -> any MTPBackendSession`，所有调用经 session 协议，不再直接调用 Kalam。
3. provider selection 属于“下一次新 session”的配置；已有 session 的 provider 固定。Router 已提供该约束，但 scan 也需在同一 provider selection 下执行。
4. `scanDevices` 最好移入 Router，或新增 provider lease，使 `initialize → scan → shutdown` 与 `initialize → open session → close → shutdown` 都有明确所有权，避免多个 backend 实例共享/重复 shutdown 同一个 libusb context。

## Risk Ranking

| Priority | Risk | Evidence | Impact |
|---|---|---|---|
| P0 | Swift snapshot 尚不能按 stable ID 精确 reopen | 无 `SwiftMTPBackend` / candidate lookup / coordinator | 双设备可能串路由，核心 AC 未闭环 |
| P0 | Go 路径固定单设备 `ID:1` 且 pool 无 identity | `kalam_bridge.go:80-100`; `kalam_pool.go:19-23,153-168` | 多设备选择形同虚设 |
| P0 | managers 丢弃目标 device identity | `FileSystemManager.swift:112-129`; 全局 Kalam ABI | UI 选 B 仍可能操作 A |
| P1 | scan API 无 per-device/per-storage failure | `MTPBackend.swift:47-51`; snapshot `8-14` | 部分失败不可诊断或被误报为空 |
| P1 | coordinator 不存在，切换只能靠调用方手工 close/open | Router `.busy` 语义 `31-41` | 重复连接、切换竞态、stale session |
| P1 | port path overflow 退化为 `root` | `USBDeviceEnumerator.swift:71-81` | 深层 hub 下 stable ID 碰撞 |
| P2 | 生产默认由直连 Go 隐式保证，不是统一 composition | `DeviceManager.swift:118-133,227-251` | 后续局部迁移易产生 provider 混用 |

## Executable Test Matrix

以下矩阵应优先用 scripted libusb/function table + scripted MTP transport；每个测试都断言 exact `MTPDeviceID`、open/close 次数和事件顺序。

| ID | Scenario | Setup | Assertions |
|---|---|---|---|
| R1 | 同 VID/PID、不同 port path | candidates A=`bus1/2.3/18d1:4ee7`，B=`bus1/2.4/18d1:4ee7` | scan 返回两个不同 ID；选择 B 后只有 B 的 `rawDevice` 被 open/claim；A 的 scripted transport 无消费 |
| R2 | enumeration 顺序翻转 | 第一次 `[A,B]`，第二次 `[B,A]` | 用 snapshot A 的 ID reopen 仍打开 A，不依赖 index |
| R3 | ID 不存在 | scan 后移除 B，再 `openSession(B.id)` | `.noDevice`；A 不被打开；所有 retained refs 释放 |
| R4 | identity collision | 两 candidate 强制相同 bus/root/VID/PID | fail closed，返回 identity collision/protocol error；不得任取第一个 |
| R5 | port path overflow | `getPortNumbers` 返回 `LIBUSB_ERROR_OVERFLOW` | 不得静默生成可碰撞 `root` ID；candidate failure 可诊断 |
| R6 | descriptor 部分失败 | A descriptor no-device，B valid | snapshots 含 B；failures 含 A/descriptor；总 scan 不 throw |
| R7 | unsupported + valid | A unsupported，B valid | B 成功；A 作为 ignored diagnostic（是否计 failure 由契约固定） |
| R8 | open/claim 部分失败 | A claim busy/permission/no-device，B 成功 | B snapshot 保留；A failure stage/error 精确；A handle reverse cleanup |
| R9 | DeviceInfo 失败 | A OpenSession 成功、GetDeviceInfo mismatch；B 全成功 | A session invalid+close，B snapshot 成功；failure=A/deviceInfo |
| R10 | 单 storage 失败 | 设备有 S1/S2，S1 成功、S2 GetStorageInfo 失败 | snapshot 保留设备与 S1；failure 指向 S2；不得把整机当 disconnected |
| R11 | scan inspection ownership | A/B 临时 session 均成功 | scan 返回后两个 inspection session/handle 均已 close，candidate refs 成对 unref |
| R12 | exact session ownership | coordinator connect A 后执行 list；切换 B 再执行 list | 顺序 `A.close → B.open → B.list`；第二次 list 只到 B |
| R13 | duplicate connect same device | 并发/连续两次 connect A | 只创建一个底层 session；结果按契约为同一 session 或第二次 `.busy` |
| R14 | duplicate disconnect | connect A 后两次 disconnect + wrapper deinit | underlying close=1、backend shutdown=1、mapping 清空 |
| R15 | switch open failure | A open；切换 B，B open `.permissionDenied` | A 已 close 且不复用；无 active mapping；错误保持 typed |
| R16 | operation vs disconnect | A operation 阻塞时 disconnect | disconnect 等 operation 完成后 close；无 use-after-close（可复用 Router 现有并发模式） |
| R17 | provider fixed | `.go` session open 后请求 `.swift` 并 connect B | provider switch `.busy`；旧 session 不受影响；close 后新 session 可用 Swift |
| R18 | default provider | production composition 未设置开发开关 | scan/open 走 Go factory；Swift factory instantiate/open count=0 |
| R19 | developer Swift opt-in | session 前选择 Swift | scan 与随后 open 都走同一个 Swift provider；不得 Go scan + Swift open 混搭 |
| R20 | stale UI UUID mapping | scan generation 1 的 app UUID 指向 A；generation 2 A 消失/B 出现 | 对旧 UUID 的 operation `.disconnected/noDevice`；不得路由到 B |
| R21 | Go multi-device guard | Go provider 检测到多设备但无法 exact route | fail closed/unsupported；不得都映射 `go:1` |
| R22 | manager integration | DeviceManager 选 B，filesystem/transfer 发起操作 | resolver 收到 B 的 app UUID，session.deviceID=B；Kalam global ABI 不被直接调用 |

已有覆盖可复用：

- Router exact device/provider 锁定：`MTPBackendRouterTests.swift:5-35`。
- close 幂等、deinit、失败恢复、等待 in-flight：`MTPBackendRouterTests.swift:37-133`。
- OpenSession TID 0 / 首条 TID 1 / CloseSession 当前 TID：`MTPDeviceSessionTests.swift:5-71`。
- already-open recovery：`MTPDeviceSessionTests.swift:73-108`。
- response TID mismatch 后失效：`MTPDeviceSessionTests.swift:110-139`。
- stable ID 单例断言：`MTPInterfaceSelectorTests.swift:5-45`。
- enumerator unsupported/descriptor failure cleanup：`USBDeviceEnumeratorTests.swift:5-50`。

缺口：目前没有 R1-R5、R8-R15、R17-R22 的闭环测试；R6/R7 只覆盖 enumerator 返回数组和日志吞错，未覆盖 typed failure aggregation。

## External References

- 无。本次是仓库内部静态审计，未查询外部文档或运行硬件。

## Related Specs

- `.trellis/tasks/07-26-swift-mtp-discovery-session/prd.md` — stable ID、部分失败、双设备路由、provider 默认 AC。
- `.trellis/tasks/07-26-swift-mtp-discovery-session/design.md` — stable identity、scan semantics、coordinator/session ownership 设计。
- `.trellis/tasks/07-26-swift-mtp-discovery-session/implement.md` — TDD 顺序与双设备/provider/session 测试计划。
- `.trellis/spec/guides/cross-layer-thinking-guide.md` — backend/session 与 manager/UI 边界必须有单一 typed contract owner。
- `.trellis/spec/backend/error-handling.md`、`.trellis/spec/backend/quality-guidelines.md` — 当前仍为占位，未提供额外项目约束。

## Caveats / Not Found

- 未找到 `SwiftMTPBackend`、`MTPConnectionCoordinator` 或对应测试；结论基于 2026-07-27 当前工作树快照，其他代理仍可能正在写入。
- 遵循 `trellis-research` 角色隔离要求，未读取 `implement.jsonl` / `check.jsonl`，也未修改任何源码、测试或 spec。
- 未运行 build/tests：研究角色只允许写任务 `research/`，执行 Xcode/Go 测试会在其他目录产生构建产物；以上为静态证据与建议测试矩阵，不代表动态通过。
- 硬件多设备、deep-hub port path、claim busy/permission/disconnect 均未实机验证。
