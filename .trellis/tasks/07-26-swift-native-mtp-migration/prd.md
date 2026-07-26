# 将 Go MTP 核心完整迁移到 Swift

## Goal

将当前由 Go、CGO 与 `libkalam.dylib` 承担的 Android MTP 核心能力迁移为 Swift 原生实现。最终应用保留 libusb 作为 USB transport，但设备发现、MTP/PTP 协议、文件系统和传输不再依赖 Go 工具链、Go 运行时或 CGO。

## Background

- 工作分支：`refactor/swift-native-mtp`；目标基线：`main`。
- 当前架构为 SwiftUI → Swift Services → C/CGO → Go MTP → libusb。
- 当前 Go 层还承担 MTP session/transaction、连接复用、全局串行化、超时重试、分块传输与取消，不是薄桥接。
- 当前没有 Swift 测试源码；已有 Go 测试只覆盖少量校验、ID、C 字符串和取消状态。

## In Scope

- 完成 Delivery Map 中五个阶段及其跨阶段验证。
- 将当前生产使用的 MTP 能力迁入 Swift，并在最终阶段清理 Go/CGO/libkalam。

## Key Decisions

- **KD1:** 保留 libusb、只移除 Go/CGO/libkalam（R2、R10）。
- **KD2:** 迁移期允许双 provider，但每个设备会话固定一个 provider（R8）。
- **KD3:** `FileTransferManager*.swift` 继续采用队列与锁（R6）。
- **KD4:** Go 只有在 Swift 自动化与真机门禁通过后才删除（R9、R10）。

## Requirements

- **R1 — Functional parity:** Swift provider 覆盖当前生产调用的初始化/清理、设备与存储扫描、对象列表、创建目录、删除对象、上传、下载、刷新、进度和取消。
- **R2 — Native boundary:** 保留 libusb 1.0 C 库；通过可复现的本地 header/module/link 配置供 Swift 使用，干净构建不得依赖 Homebrew 或 Go。
- **R3 — Swift protocol ownership:** MTP container 编解码、session/transaction ID、response 校验、storage/object 数据模型和传输状态机由 Swift 拥有。
- **R4 — Typed contracts:** 用 Swift 类型和结构化错误替代 `Kalam_*` 的 JSON/C 字符串、`nil` 和整数错误码；服务层负责映射为现有 UI 状态。
- **R5 — Concurrency invariants:** 同一设备的完整 MTP transaction 必须串行；活动 I/O 完成或取消回调到达前不得释放 buffer、handle 或 session。
- **R6 — Project concurrency exemption:** `FileTransferManager*.swift` 保持 `DispatchQueue + NSLock`，不得迁移为 Actor/Sendable 模型；UI 状态只在主线程更新。
- **R7 — Diagnostics:** USB、MTP、文件 I/O、超时、取消和断连必须产生可诊断的 typed error 与适量结构化日志，不记录文件内容或设备敏感标识。
- **R8 — Staged migration:** Go 与 Swift provider 可在迁移期共存，但 provider 与选中 `MTPDeviceID` 必须在设备会话开始时固定；生产会话不得混用 provider 或串设备。
- **R9 — TDD and evidence:** 每个阶段先补失败测试，再实现；纯逻辑用单元/契约测试，USB 与设备差异用真实 Android 设备回归。
- **R10 — Final cleanup:** Swift provider 全量验收后删除 Go/CGO/libkalam 代码、二进制、脚本、构建项和文档引用，同时保留并正确签名/打包 libusb。
- **R11 — UI scope:** 保持现有 SwiftUI 信息架构和用户操作，不借迁移新增无关功能或改版界面。

## Acceptance Criteria

- [ ] **AC1:** 最终生产源码、构建、测试、打包和用户文档不存在 `Kalam_*`、libkalam、CGO 构建或 Go 工具链要求；`.trellis` 仅允许历史/研究证据命中。
- [ ] **AC2:** Swift provider 完成设备/存储扫描、对象列表、创建目录、删除、单文件与目录上传、下载、刷新、进度和取消。
- [ ] **AC3:** 空设备、设备占用、权限、断连、USB 错误、MTP response、协议不同步、超时、取消和本地文件错误均有测试覆盖的结构化错误。
- [ ] **AC4:** session/transaction 串行化、transaction ID 校验、short packet、split header、zero-length packet 与资源关闭顺序均有协议级测试。
- [ ] **AC5:** `DeviceManager`、`FileSystemManager`、`FileTransferManager` 的可见状态、缓存失效、断连处理和任务终态无回归。
- [ ] **AC6:** 迁移期 provider 与 selected snapshot identity 在会话创建时固定，多设备不会串路由；Swift 验收失败时可在新会话切回 Go，最终切换后 Go provider 被删除。
- [ ] **AC7:** Debug/Release clean build、Swift tests、DMG 打包及 `desloppify` 强制检查通过。
- [ ] **AC8:** 在可用 Android 硬件上完成扫描→浏览→创建→上传→下载校验→取消→删除→断连回归，并明确记录真机与模拟测试证据。
- [ ] **AC9:** 最终 `.app` 仍正确嵌入、签名并链接 libusb，但不包含 `libkalam.dylib`。
- [ ] **AC10:** 从不安装 Go/Homebrew libusb 的干净环境，使用仓库自带依赖即可构建和测试。

## Out of Scope

- 移除 libusb、改用 IOKit 或新增内核/DriverKit 驱动。
- SwiftUI 改版或新增与 MTP 迁移无关的产品功能。
- 将 `FileTransferManager*.swift` 改造成 Swift 6 Actor 并发。
- 实现当前生产路径未使用的 MTP move/copy、thumbnail、event endpoint 或任意设备属性编辑能力。

## Delivery Map

1. `07-26-swift-mtp-foundation`：CLibUSB、Swift MTP 类型/codec、fake transport 与契约测试底座。
2. `07-26-swift-mtp-discovery-session`：libusb 生命周期、设备枚举、MTP session/transaction、设备和存储扫描。
3. `07-26-swift-mtp-filesystem`：对象列表、创建目录、删除对象和文件系统服务集成。
4. `07-26-swift-mtp-transfer`：上传下载、进度、取消、超时、断连和目录上传。
5. `07-26-swift-mtp-cutover`：全量验证、默认切换、删除 Go/CGO/libkalam、清理构建打包文档。

## Open Questions

无阻塞项。
