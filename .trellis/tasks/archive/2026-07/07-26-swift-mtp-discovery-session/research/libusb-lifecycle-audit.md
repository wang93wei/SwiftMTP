# Research: libusb lifecycle audit

- Query: 核验 `LibUSBFunctionTable` / `LibUSBContext` / `LibUSBDeviceHandle` / `LibUSBTransfer` 及 fake/lifecycle/transfer tests：C ABI 映射、retain/free/cancel/callback/event loop/shutdown 顺序，以及 Swift 6 default MainActor 与 C callback 可发送性。
- Scope: mixed
- Date: 2026-07-27

## Findings

### 结论摘要

- **C ABI 映射准确**：当前 function table 的返回值和参数宽度与仓库内 libusb 1.0.29 header 一致，并已由 Swift 6 编译器实际接受；没有发现 ABI 错配。
- **retain/free 的正常单线程路径准确**：device list、candidate device reference、config descriptor、transfer 和 callback context 的成功/失败路径基本成对。
- **生命周期仍有 blocking 风险**：发现 3 个 High、2 个 Medium。最严重的是 context shutdown 不跟踪 open handle、handle close 不等待 active transfer，以及 shutdown 与 transfer submission 之间存在竞态。
- **Swift 6/C callback 可编译但仅属“手工保证”**：`nonisolated` callback 规避了 default MainActor，C trampoline 本身无 capture；但 function table/transfer/context 使用 `@unchecked Sendable`，闭包类型没有声明 `@Sendable`，编译器无法证明线程安全。

### ABI 与所有权核验

#### ABI-OK — `LibUSBFunctionTable` 与 C header 一致

- `libusb_get_device_list` 的 C 返回类型是 `ssize_t`，macOS Swift 导入为 `Int`；table 使用 `Int`：`SwiftMTP/Services/MTP/Transport/LibUSBFunctionTable.swift:13-17`，header 为 `SwiftMTP/Support/CLibUSB/include/libusb.h:1692-1695`。
- libusb 的 `int` 参数/返回值映射为 Swift `Int32`，覆盖 init、descriptor、port path、open/config/claim/release、alloc/submit/cancel 和 event handling：`LibUSBFunctionTable.swift:11-47`；对应 header 见 `libusb.h:1748-1751`、`1771-1786`、`1883-1886`、`2218`。
- bulk transfer 字段宽度准确：endpoint/type 为 `UInt8`、timeout 为 `UInt32`、length/actual_length 为 `Int32`，见 `LibUSBTransfer.swift:74-82`；C helper contract 见 `libusb.h:1951-1964`。
- callback 使用 Clang 导入的精确类型 `libusb_transfer_cb_fn`，而非自行声明 calling convention：`LibUSBTransfer.swift:179-189`；C typedef 为 `libusb.h:1452`。
- 实际验证命令在 Swift 6、`-default-isolation=MainActor` 下完成 app 和 test target 编译；未出现 ABI 或 actor-isolation 编译错误。测试进程随后在 bootstrap 阶段崩溃，详见“验证与 caveat”。

#### OWNERSHIP-OK — 枚举引用配对正确

- `getDeviceList` 成功后 `freeDeviceList(list, 1)` 释放 list 并 unref 原始 device refs：`USBDeviceEnumerator.swift:21-29`。
- 只有选中的 candidate 先 `refDevice`，再由 `LibUSBDeviceCandidate.deinit` 恰好 `unrefDevice` 一次：`USBDeviceEnumerator.swift:42-51`、`LibUSBDeviceHandle.swift:22-25`。
- 每个成功取得的 config descriptor 使用局部 `defer` 释放：`USBDeviceEnumerator.swift:84-100`。
- 注意：现有 `FakeLibUSBFunctions` 没有实现/记录上述 list/ref/unref/config descriptor 调用，因此这些配对没有 fake ordering test 直接保护：`SwiftMTPTests/MTP/Doubles/FakeLibUSBFunctions.swift:30-123`。

#### OWNERSHIP-OK — transfer/callback context 的单次路径配对正确

- `Unmanaged.passRetained` 位于 `LibUSBTransfer.swift:72-73`。
- submit 失败时清空 `user_data` 并显式 `release`：`LibUSBTransfer.swift:91-99`。
- submit 成功时 callback 先清空 `user_data`，再 `takeRetainedValue`：`LibUSBTransfer.swift:179-188`。重复 callback 因 `user_data == nil` 不会 double release。
- transfer 和 buffer 只在 terminal result 唤醒 `execute` 后释放：`LibUSBTransfer.swift:84-89`、`109-115`、`135-167`；现有测试覆盖 callback 前不 free、cancel callback 前不 free、free 先于 context exit：`LibUSBTransferTests.swift:6-43`、`45-84`、`86-126`。

### 风险项

#### HIGH-1 — context 可在 open handle 仍存活时 `libusb_exit`

- **符号**：`LibUSBContext.shutdown()`、`LibUSBDeviceHandle.close()`
- **证据**：context 只登记 `activeTransfers`，不登记 open handles：`LibUSBContext.swift:12-15`、`39-65`。`LibUSBDeviceHandle` 虽强持有 context，但显式 `context.shutdown()` 不受强引用阻止：`LibUSBDeviceHandle.swift:29-35`。当前 lifecycle test 恰好手动先 close handle 再 shutdown，未验证逆序：`LibUSBLifecycleTests.swift:27-48`。
- **影响**：libusb 官方要求 `libusb_exit` 在所有 open devices 关闭后调用。当前 API 允许 exit 后再由 handle 的 `close()` / `deinit` 调用 libusb，形成 invalid context/resource use，可能 crash/UAF。
- **最小修正建议**：让 context 注册/注销 handles；shutdown 设置 closing 后，先禁止 open/enumeration/submit，关闭或等待所有 handle 完成 reverse-order cleanup，再 `libusb_exit`。补 `shutdownWithOpenHandleClosesHandleBeforeExit` ordering test。

#### HIGH-2 — `LibUSBDeviceHandle.close()` 可与 active transfer 并发，导致 handle UAF

- **符号**：`LibUSBDeviceHandle.rawHandleForTransfer()`、`LibUSBDeviceHandle.close()`、`LibUSBTransport.transact()`
- **证据**：`rawHandleForTransfer` 仅在取指针时持锁，返回后立即失去 handle lifetime lease：`LibUSBDeviceHandle.swift:98-119`。`LibUSBTransport` 将裸 handle 传给多个异步 transfer：`LibUSBTransport.swift:36-60`。`LibUSBTransfer` 只持有 `OpaquePointer`，不持有 `LibUSBDeviceHandle`：`LibUSBTransfer.swift:10-20`。
- **影响**：另一线程可在 transfer submitted/active 时 release interface + close handle。libusb 明确不允许对同一资源并发 release/close，且 active transfer 的 `dev_handle` 必须保持有效；结果可能 UAF、callback crash 或不可恢复 I/O 错误。
- **最小修正建议**：transfer 持有 handle owner/lease，而不是裸指针；handle 维护 active-transfer count，`close()` 先拒绝新 lease、cancel active transfers、等待 terminal callbacks/unregister，再 release interface/close。补“close blocks until callback, callback → free transfer → release interface → close”测试。

#### HIGH-3 — shutdown 与 submit 之间有漏取消窗口，可能无限等待

- **符号**：`LibUSBContext.register(_:)`、`LibUSBContext.shutdown()`、`LibUSBTransfer.execute()`、`requestCancellation()`
- **证据**：transfer 在任何 allocation/submission 之前就登记：`LibUSBTransfer.swift:38-40`；shutdown 快照 active transfers 后调用 cancel 并等待字典清空：`LibUSBContext.swift:39-52`。但 cancel 只在 `submitted == true` 时生效：`LibUSBTransfer.swift:122-132`；`submitted` 要等 `libusb_submit_transfer` 返回后才设置：`LibUSBTransfer.swift:91-103`。
- **竞态**：
  1. shutdown 在 register 后、submit 前调用 cancel，因 `submitted == false` 被丢弃；
  2. execute 随后仍允许 submit（没有二次检查 context closing）；
  3. shutdown 等待 callback/unregister；若设备/事件泵不能完成，则可长期或无限阻塞。
  同一窗口也存在于 submit 成功与 `submitted = true` 之间。
- **最小修正建议**：将 transfer lifecycle 建模为一个 condition-guarded state machine（prepared/submitting/submitted/terminal）；context shutdown 设置 cancellation intent 后，submit 前必须原子复查并拒绝，若 cancel intent 与 submit 交错则 submit 成功后立即 cancel。补两个确定性 barrier tests：shutdown-before-submit、shutdown-between-submit-return-and-state-publish。

#### MEDIUM-1 — event loop 自身调用 `shutdown()` 会同步派发死锁；deinit 不能可靠兜底

- **符号**：`LibUSBContext.runEventLoop()`、`shutdown()`、`deinit`
- **证据**：event loop 在专用 serial queue 上运行：`LibUSBContext.swift:10`、`28-31`；shutdown 无条件 `eventQueue.sync {}`：`LibUSBContext.swift:58-60`。若从该 queue（包括 callback/event-handling context）调用 shutdown，会 sync 到自身而死锁。
- `deinit` 调用 shutdown：`LibUSBContext.swift:35-37`；但 `self?.runEventLoop()` 一旦进入长期循环，会在整个方法期间强持有 self，导致没有显式 shutdown 时 deinit 很可能永远无法开始。
- **最小修正建议**：为 event queue 设置 queue-specific key，shutdown 在本 queue 上不做 sync/self-wait；更理想是显式 owner shutdown、event-loop task 不长期强持有 owner。增加“shutdown from event queue does not deadlock”和“owner release stops event loop”测试。

#### MEDIUM-2 — Swift 6 sendability 依赖 `@unchecked`，function table 闭包未声明 `@Sendable`

- **符号**：`LibUSBFunctionTable`、`LibUSBContext`、`LibUSBTransfer`、`LibUSBTransferCallbackBox`、`libUSBTransferCompletionCallback`
- **证据**：项目 app target 使用 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` 与 Swift 6：`SwiftMTP.xcodeproj/project.pbxproj:428-431`、`482-485`。transport 类型使用 `nonisolated`，context/transfer/table 再以 `@unchecked Sendable` 穿越 DispatchQueue/C 边界：`LibUSBFunctionTable.swift:10-47`、`LibUSBContext.swift:7-14`、`LibUSBTransfer.swift:4-20`。
- callback 全局值显式 `nonisolated` 且无 capture，这一点是正确的：`LibUSBTransfer.swift:179-189`。owner 的 mutable state由 `NSCondition` 保护，context 强持有 active transfer，所以 callback 的 weak owner 正常路径不会悬空。
- 但 table 的 stored closure 类型不是 `@Sendable`：`LibUSBFunctionTable.swift:11-47`；`@unchecked Sendable` 因而允许注入捕获非线程安全状态的闭包，编译器无法验证。fake 也有多个未锁属性：`FakeLibUSBFunctions.swift:20-27`。
- **最小修正建议**：所有 function-table closure 加 `@Sendable`；live table 保持无 capture，fake 的可变控制/脚本状态统一纳入锁。保留 `nonisolated` C trampoline；对必须 unchecked 的 pointer owner 写明逐字段锁/所有权 invariant。

#### LOW — `LibUSBTransfer` 未强制 one-shot

- **符号**：`LibUSBTransfer.execute()`
- **证据**：`terminalResult` / `submitted` / `cancellationRequested` 不会在 execute 起点重置，也没有 “idle only” guard：`LibUSBTransfer.swift:16-20`、`38-40`。context registry 以 `ObjectIdentifier` 为 key：`LibUSBContext.swift:76-89`；同一 object 并发 execute 会互相覆盖 registry entry 和共享 terminal state。
- **影响**：当前 `LibUSBTransport` 每次创建新 transfer，生产调用路径暂时不触发；但类型本身未编码该 invariant，未来复用会破坏 shutdown tracking。
- **最小修正建议**：在 condition 下原子地从 idle → preparing，第二次 execute 返回 `.busy`/internal invariant error；补 reuse/concurrent execute test。

### 测试覆盖评价

- 已覆盖：
  - context init/exit idempotency：`LibUSBLifecycleTests.swift:6-17`。
  - config/claim/alternate/release/close 正序及 claim error typed cleanup：`LibUSBLifecycleTests.swift:19-89`。
  - transfer callback 前不释放、cancel 后等待 callback、context exit 晚于 free transfer：`LibUSBTransferTests.swift:6-126`。
- 未覆盖且应成为 blocking tests：
  - context shutdown with open handle；
  - handle close during active transfer；
  - shutdown-before-submit 与 submit-state publication race；
  - shutdown from event queue；
  - event loop error/persistent failure 下 shutdown 是否可终止；
  - callback/submit exactly-once 的 concurrent stress；
  - device-list ref/unref 与 config descriptor free ordering。
- fake 的 `handleEventsTimeoutCompleted` 永远返回 0 且不会派发 callback：`FakeLibUSBFunctions.swift:121`；现有 shutdown test 用 `startsEventLoop: false` + 手动 `complete`，因此没有验证真实 event pump/callback/shutdown 协作。

### Files found

- `SwiftMTP/Services/MTP/Transport/LibUSBFunctionTable.swift` — libusb C boundary 与错误映射。
- `SwiftMTP/Services/MTP/Transport/LibUSBContext.swift` — context、event queue、active transfer registry、shutdown。
- `SwiftMTP/Services/MTP/Transport/LibUSBDeviceHandle.swift` — retained candidate、open/config/claim/release/close。
- `SwiftMTP/Services/MTP/Transport/LibUSBTransfer.swift` — async transfer、buffer、callback context、cancel/terminal wait。
- `SwiftMTP/Services/MTP/Transport/LibUSBTransport.swift` — handle 到 write/read transfer 的调用路径。
- `SwiftMTP/Services/MTP/Transport/USBDeviceEnumerator.swift` — device list/config descriptor/ref ownership。
- `SwiftMTPTests/MTP/Doubles/FakeLibUSBFunctions.swift` — lifecycle/transfer test double。
- `SwiftMTPTests/MTP/Transport/LibUSBLifecycleTests.swift` — context/handle happy-path 与 claim errors。
- `SwiftMTPTests/MTP/Transport/LibUSBTransferTests.swift` — transfer/cancel/shutdown ordering。
- `SwiftMTP/Support/CLibUSB/include/libusb.h` — bundled C ABI，smoke test 显示 1.0.29。
- `SwiftMTP.xcodeproj/project.pbxproj` — Swift 6 与 app default MainActor 配置。

### External references

- Bundled/runtime version：`CLibUSBSmokeTests.swift:5-13` 断言 libusb 1.0.29、nano 11953；当前线上文档页显示 libusb 1.0.30，因此 ABI 判断以仓库 bundled header 为准。
- libusb Asynchronous device I/O：<https://libusb.sourceforge.io/api-1.0/group__libusb__asyncio.html>
  - cancel 是异步的；取消完成仍必须等待 callback；
  - active transfer 在 callback 完成前不得 free；
  - callback 在 event-handling thread/context 执行。
- libusb Library initialization/deinitialization：<https://libusb.sourceforge.io/api-1.0/group__libusb__lib.html>
  - `libusb_exit` 应在关闭所有 open devices 后调用。
- libusb Caveats：<https://libusb.sourceforge.io/api-1.0/libusb_caveats.html>
  - 同一资源的 release/close 不得并发；
  - transfer 及其 buffer 在 submit 到 completion callback 之间不得由应用访问。
- libusb Polling and timing：<https://libusb.sourceforge.io/api-1.0/group__libusb__poll.html>
  - dedicated event thread shutdown 可使用 `libusb_interrupt_event_handler`；当前 function table 未暴露该函数，而是依赖 50ms timeout。

### Related specs

- `.trellis/tasks/07-26-swift-mtp-discovery-session/prd.md`：
  - 共享 context、最终退出；
  - 关闭必须等待 active async transfer completion callback；
  - AC 要求 cancel/close 时 transfer/buffer/handle 不在 completion 前释放。
- `.trellis/tasks/07-26-swift-mtp-discovery-session/design.md`：
  - shutdown 顺序：拒绝新 submit → cancel active → 等 terminal callbacks → exit context；
  - callback context 的 `Unmanaged` retain/release 恰好一次。
- `.trellis/tasks/07-26-swift-mtp-discovery-session/implement.md`：
  - review gate 明确要求 active transfer 不得 outlive buffer/context/handle。
- `.trellis/spec/backend/quality-guidelines.md`、`error-handling.md`、`.trellis/spec/frontend/type-safety.md`、`state-management.md` 当前均为占位模板，没有额外项目约束。

### Validation

- 命令：
  `xcodebuild test -project SwiftMTP.xcodeproj -scheme SwiftMTP -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:SwiftMTPTests/LibUSBLifecycleTests -only-testing:SwiftMTPTests/LibUSBTransferTests`
- 结果：
  - app 与 test target 均在 Swift 6 下编译、链接成功；
  - 编译参数确认 app target 含 `-default-isolation=MainActor`；
  - 测试未执行完成：xctest 在 bootstrap 阶段 `Early unexpected exit ... xctest at static xctest.main()`，命令 exit 65。
- 因此本报告能确认 “Swift 6/MainActor/C callback 边界可编译”，不能把 lifecycle tests 标记为本轮动态通过。

## Caveats / Not Found

- 本轮是只读审计，没有改业务或测试源码，也没有提交。
- Trellis research role 按角色隔离不读取 `implement.jsonl` / `check.jsonl`；任务要求来自已读取的 `prd.md`、`design.md`、`implement.md` 与 hook 注入的 curated context。
- 未连接真实 Android/MTP 硬件；没有硬件层 scan/open/close、物理拔插或 Darwin cancel fan-out 证据。
- 没有用 Thread Sanitizer 或可控 barrier fake 动态复现上述竞态；High 项来自明确的锁域/状态机缺口与 libusb 生命周期 contract。
- CodeGraph 对新建测试 double/lifecycle 文件的索引返回不完整，相关文件已从当前工作树直接按行核验；生产源码由 CodeGraph 当前磁盘内容与构建结果交叉确认。
