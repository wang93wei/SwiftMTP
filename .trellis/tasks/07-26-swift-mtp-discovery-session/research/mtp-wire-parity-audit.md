# Research: MTP wire parity audit

- Query: 对照当前 Swift Core/Transport/Backend 与 Native Go 行为，审查 discovery/session/transaction 所需 MTP 线协议契约：container framing、split header、短读、ZLP、transaction ID、OpenSession/CloseSession、GetDeviceInfo/GetStorageIDs/GetStorageInfo、响应码与错误传播。
- Scope: mixed
- Date: 2026-07-27

## Findings

### Files found

| Path | Description |
| --- | --- |
| `SwiftMTP/Services/MTP/Core/MTPContainer.swift` | 12-byte MTP container 编解码与跨 USB fragment 的增量 framing。 |
| `SwiftMTP/Services/MTP/Core/MTPBinaryReader.swift` | 严格 little-endian 读取、截断检查、MTP UTF-16LE 字符串读取。 |
| `SwiftMTP/Services/MTP/Core/MTPDatasets.swift` | DeviceInfo、StorageIDs、StorageInfo typed dataset 解码。 |
| `SwiftMTP/Services/MTP/Transport/LibUSBTransfer.swift` | async libusb transfer、`actual_length`、取消与 callback 后释放。 |
| `SwiftMTP/Services/MTP/Transport/LibUSBTransport.swift` | command bulk OUT 与循环 bulk IN，直到完整 response container。 |
| `SwiftMTP/Services/MTP/Backend/MTPDeviceSession.swift` | session 状态、TID 分配、command/data/response transaction 校验。 |
| `SwiftMTP/Services/MTP/Backend/SwiftMTPBackend.swift` | 当前新增中的 Swift discovery backend、逐设备/逐 storage 扫描和临时 session。 |
| `SwiftMTP/Services/MTP/Transport/LibUSBDeviceHandle.swift` | open/configure/claim/alternate/release/close 生命周期。 |
| `SwiftMTP/Services/MTP/Transport/USBDeviceEnumerator.swift` | 全 configuration/interface/alternate/endpoint 枚举。 |
| `SwiftMTP/Services/MTP/Transport/USBDescriptors.swift` | MTP/PTP endpoint 选择与 `MTPDeviceID`。 |
| `SwiftMTPTests/MTP/Core/MTPContainerTests.swift` | 精确 header 与 fragmented header/payload 测试。 |
| `SwiftMTPTests/MTP/Transport/LibUSBTransportTests.swift` | split header、短 response、ZLP 后继续读取测试。 |
| `SwiftMTPTests/MTP/Backend/MTPDeviceSessionTests.swift` | OpenSession/首命令/CloseSession TID、already-open recovery、TID mismatch 测试。 |
| `Native/vendor/github.com/ganeshrvel/go-mtpfs/mtp/mtp.go` | Go vendor 的 USB packet、transaction、response、ZLP/短包处理。 |
| `Native/vendor/github.com/ganeshrvel/go-mtpfs/mtp/ops.go` | Go OpenSession/CloseSession 与 discovery operation 包装。 |
| `Native/vendor/github.com/ganeshrvel/go-mtpfs/mtp/encoding.go` | Go dataset/string/array 解码。 |
| `Native/vendor/github.com/ganeshrvel/go-mtpx/main.go` | Go GetDeviceInfo/GetStorageIDs/GetStorageInfo 聚合。 |
| `Native/kalam_domain.go` | 当前 Go scan JSON 行为。 |
| `Native/kalam_pool.go` | Go 连接池、quick scan 重试和错误恢复。 |

### 必须保留的正确语义

1. **Container wire contract 必须保持严格 little-endian 12-byte header。**
   `MTPContainer.encoded()` 写入 `length/type/code/transactionID/payload`，`decode` 拒绝 `< 12`、未知 type、declared length 不等于实际长度与 materialized `0xFFFFFFFF` sentinel（`SwiftMTP/Services/MTP/Core/MTPContainer.swift:34-72`，符号 `MTPContainer.encoded/decode`）。精确 wire fixture 已覆盖 command/data/response（`SwiftMTPTests/MTP/Core/MTPContainerTests.swift:12-45`）。
   建议测试：增加 declared length 大于可用 bytes、两个 container 同一 fragment、response 后多余完整 container、`0xFFFFFFFF` sentinel 的独立回归。

2. **Split header/短读必须按 container 声明长度增量重组，不能把一次 libusb completion 当成 container 边界。**
   `MTPContainerFramer.append` 在不足 12 bytes 时保留 buffer，拿到 header 后继续等待完整 declared length（`SwiftMTP/Services/MTP/Core/MTPContainer.swift:76-107`）；`LibUSBTransport.transact` 将每次 `actual_length` 对应的 fragment 喂给同一 framer（`SwiftMTP/Services/MTP/Transport/LibUSBTransport.swift:48-81`）。现有测试已把 12-byte response header 切在 5 bytes，并验证短 response packet（`SwiftMTPTests/MTP/Transport/LibUSBTransportTests.swift:6-35`）；core 测试还覆盖 3/5/5 字节切片（`SwiftMTPTests/MTP/Core/MTPContainerTests.swift:74-83`）。
   建议测试：data container 的 header 恰好 12 bytes、随后 payload 多次短读；header 按 1/1/10 bytes；data 尾部与 response header 同一 libusb completion。

3. **ZLP 不是 transaction response，也不能提前结束 transaction。**
   Swift 当前遇到空 fragment 会继续读，只有看到完整 response container 才返回（`SwiftMTP/Services/MTP/Transport/LibUSBTransport.swift:63-81`）；测试覆盖一个 ZLP 后再收到 response（`SwiftMTPTests/MTP/Transport/LibUSBTransportTests.swift:37-66`）。Go 的可保留经验是：数据长度落在 max-packet 边界时，下一次 IN 可能是 ZLP，也可能直接是 response，因此必须检查下一次读取内容而不是假设必为空（`Native/vendor/github.com/ganeshrvel/go-mtpfs/mtp/mtp.go:638-654`，符号 `Device.bulkRead`）。
   建议测试：完整 data container 长度恰为 endpoint max packet 的整数倍，随后分别走 `ZLP -> response` 与 `response directly`；ZLP 穿插在 split response header 前后。

4. **OpenSession command/response TID 为 0，成功后第一条 in-session command 为 1；CloseSession 消耗当前 TID。**
   Swift 明确以 TID 0 发 OpenSession，成功后置 `nextTransactionID = 1`（`SwiftMTP/Services/MTP/Backend/MTPDeviceSession.swift:37-80`）；CloseSession 使用当前 `nextTransactionID`（同文件 `108-122`）。端到端 scripted 测试已证明 Open=0、GetDeviceInfo=1、GetStorageIDs=2、GetStorageInfo=3、Close=4（`SwiftMTPTests/MTP/Backend/MTPDeviceSessionTests.swift:5-67`）。Go 也在 session 未建立时隐式使用 0，建立后从 1 开始（`Native/vendor/github.com/ganeshrvel/go-mtpfs/mtp/ops.go:19-40`；`Native/vendor/github.com/ganeshrvel/go-mtpfs/mtp/mtp.go:403-408`）。
   建议测试：OpenSession response TID 非 0 必须失败；CloseSession response TID mismatch；TID 达到 `UInt32.max` 后不得 wrap 到保留给 OpenSession 的 0。

5. **每个收到的 data/response container 都必须校验请求 TID；data code 必须等于 operation code；顺序只能是可选 data 后一个 response。**
   Swift 对每个 container 先校验 TID，再校验 data 的 expectsData/唯一性/operation code，并拒绝 command/event、duplicate response、缺 response、成功但缺 data（`SwiftMTP/Services/MTP/Backend/MTPDeviceSession.swift:198-231`，符号 `MTPDeviceSession.transact`）。已有测试证明 in-session response TID mismatch 会使 session 后续不可用（`SwiftMTPTests/MTP/Backend/MTPDeviceSessionTests.swift:110-139`）。
   建议测试：OpenSession TID mismatch、data TID mismatch、data operation mismatch、response-before-data、duplicate data、duplicate response、unexpected event/command、non-OK response 无 data。

6. **普通 MTP response code 应保留原始 UInt16 并向上抛出 typed error；协议/USB 错误后 session 不得复用。**
   `MTPResponseCode` 保留 raw value，已列出 discovery 常见错误（`SwiftMTP/Services/MTP/Core/MTPConstants.swift:23-38`）；in-session `execute` 将非 OK 映射为 `MTPCoreError.response`，任何 transport/framing/response/dataset decode error 都把 state 置为 invalid（`SwiftMTP/Services/MTP/Backend/MTPDeviceSession.swift:135-166`）。这比 Go 仅在 `usb.Error`/`SyncError` 时关闭连接的策略更符合本任务 KD2（Go 位置：`Native/vendor/github.com/ganeshrvel/go-mtpfs/mtp/mtp.go:377-395`）。
   建议测试：`deviceBusy`、`operationNotSupported`、未知 response code、USB timeout/disconnect、dataset decode error 后，第二次调用均返回 disconnected 且不消费 transport step。

7. **Discovery dataset 必须完整消费 payload，截断或 trailing bytes 都是协议错误。**
   Swift 的 UInt32 array 先做乘法边界检查，再逐项读取并拒绝 trailing bytes（`SwiftMTP/Services/MTP/Core/MTPDatasets.swift:15-29`）；DeviceInfo 与 StorageInfo 字段顺序符合 PTP/MTP dataset，并拒绝 trailing bytes（同文件 `47-115`）；reader 每次读取都先验证剩余长度（`SwiftMTP/Services/MTP/Core/MTPBinaryReader.swift:29-80`）。fixture 测试覆盖 identity、arrays、64-bit capacity、截断与 trailing input（`SwiftMTPTests/MTP/Core/MTPDiscoveryDatasetTests.swift:5-70`）。
   建议测试：StorageIDs count 溢出/截断、MTP string 缺 null terminator、无效 UTF-16LE、StorageInfo 64-bit 最大值。

8. **Claim 失败必须立即失败并逆序清理，不能继续发 MTP command。**
   Swift 对 get/set configuration、claim、alternate setting 每一步都检查返回码；任一步失败进入 `close()`（`SwiftMTP/Services/MTP/Transport/LibUSBDeviceHandle.swift:47-91`）。busy/access/no-device 的 typed error 与 handle close 已有测试（`SwiftMTPTests/MTP/Transport/LibUSBLifecycleTests.swift:51-88`）。
   建议测试：set-configuration 失败、alternate-setting 失败时分别验证是否只释放已成功取得的资源；claim 失败时零 bulk submit。

9. **async transfer 的 buffer/context/handle 必须活到 terminal callback。**
   Swift 只在 callback 设置 terminal result 后，`execute` 的 defer 才 free transfer/buffer/unregister（`SwiftMTP/Services/MTP/Transport/LibUSBTransfer.swift:84-115,135-167`）；取消与 context shutdown 等待 callback 的测试位于 `SwiftMTPTests/MTP/Transport/LibUSBTransferTests.swift:45-126`。此语义与 libusb “active transfer 不可 free、completion status 不代表请求长度全部传完”一致。

### 不能复制的 Go 缺陷

1. **Go 忽略 interface claim 错误。**
   `Device.Open` 调用 `d.claim()` 却丢弃返回值并继续（`Native/vendor/github.com/ganeshrvel/go-mtpfs/mtp/mtp.go:151-170`，符号 `Device.Open`）。这会把 busy/access/no-device 伪装成后续 MTP I/O 错误。Swift 必须保持当前 fail-fast + cleanup 行为。

2. **Go 假定一次 bulk read 至少包含完整 12-byte header。**
   `fetchPacket` 对单次读取直接 `binary.Read` header（`Native/vendor/github.com/ganeshrvel/go-mtpfs/mtp/mtp.go:320-336`）；它仅特殊处理“完整 12-byte header 与 payload 分包”（同文件 `456-468`），不能重组 `< 12` 的 split header。Swift 不应复制 packet-boundary framing。

3. **Go 用短 libusb read 推断 data phase 结束，而不是严格依赖 container declared length。**
   `bulkRead` 在 `lastRead < len(buffer)` 时退出（`Native/vendor/github.com/ganeshrvel/go-mtpfs/mtp/mtp.go:605-637`）。短 transfer 只是本次 transfer 的实际长度，不能单独证明一个 MTP container 已完成；Swift 当前按 header length framing 更可靠。

4. **Go 的 dataset reader 多处只调用一次 `Read`，没有 `io.ReadFull`。**
   `decodeStr` 单次读取字符串（`Native/vendor/github.com/ganeshrvel/go-mtpfs/mtp/encoding.go:15-33`），`decodeArray` 单次读取数组且不检查 `n`（同文件 `104-117`）。对一般 `io.Reader`，短读可在 `err == nil` 时发生，数组甚至可能静默补零。Swift 必须保留当前严格剩余长度检查。

5. **Go 在 error response 上先返回 RCError，可能跳过 TID mismatch 检查。**
   `decodeRep` 遇到非 OK 立即返回 `RCError`（`Native/vendor/github.com/ganeshrvel/go-mtpfs/mtp/mtp.go:339-360`），而 transaction ID 比对发生在之后（同文件 `493-507`）。因此“错误 response + 错误 TID”不会被标为 SyncError。Swift 当前先校验所有 container TID，再解释 response code，必须保持。

6. **Go 的 OpenSession response TID 没有被校验。**
   `runTransaction` 只在 `d.session != nil` 时比较 response/request TID（`Native/vendor/github.com/ganeshrvel/go-mtpfs/mtp/mtp.go:504-507`）；OpenSession 时 session 尚未建立，所以错误的非零 response TID 可通过。Swift 的 TID 0 校验不能放宽。

7. **Go 的 `SessionAlreadyOpened` 恢复依赖 Android 特例，不是通用协议保证。**
   `Configure` 注释明确说无 transaction ID 的 CloseSession “at least on Android” 可用（`Native/vendor/github.com/ganeshrvel/go-mtpfs/mtp/mtp.go:659-674`）。Swift 当前也实现 TID 0 stale close（`MTPDeviceSession.swift:50-70`），但应把它作为受测试的兼容恢复路径；若 stale close 失败，必须废弃 handle/session 并重连，不能继续复用。

8. **Go scan 不是多设备、稳定身份实现。**
   `mtpx.Initialize` 调用 `SelectDeviceWithDebugging` 选一个设备（`Native/vendor/github.com/ganeshrvel/go-mtpx/main.go:16-35`），`kalam_domain.Scan` 固定输出 `ID: 1`（`Native/kalam_domain.go:117-189`）。不能把 index/常量 1 复制为 Swift snapshot identity。

9. **Go 的 storage 聚合遇到一个 GetStorageInfo 错误就丢弃整个 storage 集合。**
   `FetchStorages` 在循环中首次失败即返回（`Native/vendor/github.com/ganeshrvel/go-mtpx/main.go:55-80`）；上层 scan 又把错误吞成空 storage（`Native/kalam_domain.go:126-131`）。Swift 应保留逐 storage failure，并返回已成功的 storages。

10. **Go quick-scan panic recovery 可把 panic 误报成功。**
    inner recover 只设置 `lastError`，没有同步设置 `err`；外层随后以 `err == nil` 返回成功（`Native/kalam_pool.go:226-245`）。Swift 错误传播不能依赖字符串/panic side channel。

### 当前 Swift 缺口

1. **OpenSession transport/framing throw 后，`MTPDeviceSession` 仍停在 `.idle`，可复用同一对象。**
   `open()` 只对已收到的 non-OK response 显式设 `.invalid`，但 `transact` 在 USB timeout/disconnect、partial container、TID mismatch 等位置抛出时没有统一 catch（`SwiftMTP/Services/MTP/Backend/MTPDeviceSession.swift:37-76`）。这违反“USB、MTP 或 sync 错误后 session 失效；retry 创建 fresh session”。
   建议测试：第一次 OpenSession transport 返回 `.timeout` 或 malformed response；第二次 `open()` 必须直接拒绝且不消费第二个 scripted step。

2. **TID 使用 wrapping increment，`UInt32.max` 后会回到保留的 0。**
   `nextTransactionID &+= 1` 出现在普通 command 与 CloseSession（`MTPDeviceSession.swift:114-115,145-146`）。这不满足“单调 transaction ID”。
   建议测试：注入/构造 `nextTransactionID == UInt32.max`，执行一次后 session 应失效或要求新 session，绝不能再发 TID 0。建议把 TID allocator 建模为可测组件。

3. **CloseSession 的 response code、TID mismatch 与 USB 错误全部只记录日志，调用方不可观测。**
   `close()` 返回 `Void`，non-OK 仅 log，throw 也被吞掉，最后统一 `.closed`（`MTPDeviceSession.swift:108-132`）。资源关闭可保持 best-effort，但 verification/scan 需要可诊断 close 结果。
   建议测试：CloseSession non-OK、mismatch、timeout 时仍释放 handle，同时通过 typed close result/error sink/scan failure 观测根因；不要仅断言“不崩溃”。

4. **Bulk OUT completed 不代表完整 command 已发送，当前忽略 `actual_length`。**
   `LibUSBTransfer.completed` 对 OUT 也只返回 `actual_length` 对应 Data（`SwiftMTP/Services/MTP/Transport/LibUSBTransfer.swift:135-159`），`LibUSBTransport` 对 write result 直接丢弃（`SwiftMTP/Services/MTP/Transport/LibUSBTransport.swift:38-46`）。libusb 明确说明 `LIBUSB_TRANSFER_COMPLETED` 不代表请求长度全部传完。
   建议测试：command 16 bytes、OUT completion `actual_length = 8`；transport 必须报 protocol/USB short-write error，session 失效且不提交 IN transfer。

5. **ZLP 连续次数上限 3 是本地策略，不是 wire contract。**
   `zeroLengthPacketCount <= 3`（`LibUSBTransport.swift:50,63-70`）可防无限循环，但可能把合法/平台异常序列错误归类为 protocol violation；真正的退出边界应由 transaction deadline/cancellation 驱动。
   建议测试：明确产品策略；至少覆盖 3 个 ZLP 后 response 与第 4 个 ZLP 的错误分类，并确认 timeout/cancel 可终止持续 ZLP。

6. **response payload 没有按 UInt32 参数对齐/数量验证。**
   `MTPDeviceSession.transact` 只记录 response code，忽略 `container.payload`（`MTPDeviceSession.swift:216-231`）。Discovery 的 Open/Close/GetDeviceInfo/GetStorageIDs/GetStorageInfo 正常 response 应有明确允许的参数数量；任意 1/2/3-byte payload 当前会被接受。
   建议测试：上述 operation 的 OK response 带非 4-byte-aligned payload 必须 protocolViolation；如需容忍 vendor response 参数，按 operation 定义数量而不是全局忽略。

7. **当前 Swift backend 尚无对应测试文件，scan/session routing AC 未闭环。**
   `SwiftMTPBackend.scanDevices` 已逐 candidate 建 inspection session、逐 storage 记录 failure 并返回 snapshot（`SwiftMTP/Services/MTP/Backend/SwiftMTPBackend.swift:81-148`），`openSession(for:)` 按 exact `MTPDeviceID` 重新枚举并匹配（同文件 `150-165`）；但当前 `SwiftMTPTests` 没有 `SwiftMTPBackendTests.swift`。
   建议测试：无设备、单/多设备、unsupported interface、设备级失败、单 storage 失败、两个 scripted device 的 exact-ID reopen、wrong-device factory、inspection session 必关闭。

8. **一个 storage 的 MTP 错误会使 discovery session invalid；当前循环继续只会为后续 storage 追加 disconnected failure。**
   `MTPDeviceSession.execute` 对所有错误 invalidates（`MTPDeviceSession.swift:163-165`），而 backend 的 storage loop catch 后继续复用同一 session（`SwiftMTPBackend.swift:95-119`）。若 storage A 失败、B 可用，B 当前不会被读取。
   建议测试：两个 storage，A 返回 non-OK、B 正常；明确期望是“保留设备 identity 并 fresh-reopen 后继续 B”还是“停止本设备剩余 storage 并记录一个根因”，不要生成级联 disconnected 噪音。

9. **`MTPConnectionCoordinator` 尚未落地，无法证明 app Device.id → snapshot identity → provider-fixed session 的全链路。**
   当前只有 backend router 的 provider 固定与 exact returned identity guard（`SwiftMTP/Services/MTP/Backend/MTPBackendRouter.swift:19-64`），没有 design 中的 coordinator 符号。生产 `DeviceManager` 仍直接调用 `Kalam_Scan`（`SwiftMTP/Services/MTP/DeviceManager.swift:227-280`）。
   建议测试：两个 snapshot 映射两个 UI UUID，选择 B 只 open B；切换 A 时先 close B；session 打开期间禁止切 provider；Go 仍为默认。

10. **interface 选择过严且 vendor-specific 匹配过宽。**
    selector 要求 endpoint 总数恰为 3，同时接受任意 class `0xFF`，不检查 Still Image 常见 subclass/protocol（`SwiftMTP/Services/MTP/Transport/USBDescriptors.swift:53-96`）。这可能漏掉含额外 endpoint 的有效设备，也可能误认 vendor interface。
    建议测试：额外无关 endpoint 的有效 MTP alternate、`0x06/0x01/0x01` 标准组合、非 MTP `0xFF` 恰有三 endpoint；策略应基于 descriptor contract/known quirk allowlist，而非仅 endpoint 数量。

11. **扫描失败虽然保存为 `lastScanFailures`，但 public `MTPBackend` contract 只返回 snapshots，调用方可能看不到部分失败。**
    failure 仅存在于 concrete backend 属性（`SwiftMTPBackend.swift:32-41,144-147`），router/manager 未体现 structured partial result。
    建议测试：上层以 protocol 类型持有 backend 时仍能获得每设备失败；可考虑 typed scan result，而不是要求 downcast concrete backend。

### External references

- USB-IF, **Media Transfer Protocol v1.1 specification package**：USB-IF document library 中的 `MTPv1_1.zip`。用于确认 operation/response code、session/TID 与 dataset contract：<https://www.usb.org/documents?field_document_category_tid=All&field_document_type_tid%5B0%5D=107&field_document_type_tid%5B1%5D=86&items_per_page=50&order=name&page=2&search=&sort=desc>
- USB-IF, **Still Image Capture Device Definition 1.0 + errata**：MTP/PTP USB bulk/interrupt endpoint 与 container transport 的基础规范：<https://www.usb.org/document-library/still-image-capture-device-definition-10-and-errata-16-mar-2007>
- libusb **1.0.30 asynchronous I/O API**：`actual_length` 只能在 callback 结果中解释；`LIBUSB_TRANSFER_COMPLETED` 不保证请求长度全部完成；active transfer 不可提前 free：<https://libusb.sourceforge.io/api-1.0/group__libusb__asyncio.html>
- libusb **1.0.30 packets and overflows**：IN transfer 的实际长度由 `actual_length` 给出，buffer 宜为 endpoint max packet 的整数倍：<https://libusb.sourceforge.io/api-1.0/libusb_packetoverflow.html>

### Related specs

- `.trellis/tasks/07-26-swift-mtp-discovery-session/prd.md`：KD1/KD2、session invalidation、scan 与 routing acceptance criteria。
- `.trellis/tasks/07-26-swift-mtp-discovery-session/design.md`：stable identity、event loop、session state、scan partial failure 语义。
- `.trellis/tasks/07-26-swift-mtp-discovery-session/implement.md`：split header、short read、ZLP、response mismatch、dataset fixture 与双设备测试清单。
- `.trellis/spec/backend/error-handling.md`、`.trellis/spec/backend/quality-guidelines.md` 当前仍为占位模板，没有额外项目约束。
- `.trellis/spec/guides/cross-layer-thinking-guide.md`：transport → session → backend → manager 的 format/error 边界需端到端验证。

## Caveats / Not Found

- 这是静态 wire-parity 审查；未运行 Xcode tests、未连接 Android 硬件，不能当作真机 scan/open/close 证据。
- 审查期间 `MTPDeviceSession.swift`、`SwiftMTPBackend.swift` 与对应测试处于工作区未提交/并发新增状态；结论基于 2026-07-27 当前磁盘快照，后续实现变动应重新核验行号和缺口。
- 未读取角色隔离禁止的 `implement.jsonl` / `check.jsonl`；任务 PRD、design、implement 与相关 specs 已读取。
- USB-IF 的 MTP v1.1 主规范以 ZIP 分发，在线索引不能直接展开章节；本文关于仓库行为的判断主要基于当前代码、已 vendor 的 go-mtpfs 行为和官方文档入口。
- Context7 未找到官方 libusb 文档条目，因此 libusb 外部依据使用官方 API reference；未采用非官方 wrapper 文档。
