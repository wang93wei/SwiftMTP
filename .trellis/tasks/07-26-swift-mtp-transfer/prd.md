# 迁移 MTP 上传下载与取消

## Goal

在 Swift provider 上实现可取消、可诊断且不会并发破坏 session 的单文件与目录传输，替代 Go 的 GetObject/SendObjectInfo/SendObject 路径，并保持现有传输 UI 与传统并发模型。

## In Scope

- GetObject、SendObjectInfo/SendObject、进度、取消、超时/重试、目录上传和 FileTransferManager 集成。

## Key Decisions

- **KD1:** `FileTransferManager*.swift` 保持 `DispatchQueue + NSLock`。
- **KD2:** 超时/取消必须等待 libusb terminal callback 后才释放资源。
- **KD3:** ObjectInfo size `>= 0xFFFFFFFF` 与 data payload `> 0xFFFFFFF3` 使用 `0xFFFFFFFF` sentinel；大文件下载优先读取 64 位 ObjectSize 属性，绝不截断。
- **KD4:** 本阶段不删除 Go，生产可在新会话回滚。

## Dependencies and Handoff

- foundation、discovery/session、filesystem 的 `verification.md` 必须显示 blocking AC、build/tests 与 `Open: 0` 通过。
- 完成时生成本任务 `verification.md`；真实上传/下载/hash/取消/断连状态是 cutover 的 blocking handoff。

## Requirements

- 实现 GetObject 下载、SendObjectInfo + SendObject 上传、实际字节进度和任务取消。
- `FileTransferManager*.swift` 保持 `DispatchQueue + NSLock`，不得改成 Actor/Sendable。
- libusb transfer 采用可取消异步接口；超时/取消返回前必须等到 terminal callback，禁止悬挂 I/O 与后续 transaction 重叠。
- 下载使用临时文件并在成功校验后原子落位；失败/取消删除临时文件。
- 上传在 SendObjectInfo 成功而 SendObject 失败时 best-effort 删除已创建对象，并记录补偿失败。
- 结构化错误区分本地路径/空间、USB、MTP response、超时、取消和断连。
- 保持单文件和目录上传的现有入口、任务终态、缓存刷新与用户提示。
- 文件大小上限迁入 `AppConfiguration.swift`；不得发生 UInt64→UInt32 静默截断。
- 进度回调只携带安全字节计数，不跨线程直接修改 UI。

## Acceptance Criteria

- [ ] download/upload exact byte stream、空文件、fragmentation、short/ZLP、ObjectInfo/data-container 各自 sentinel 边界与 64 位 ObjectSize 路径均有协议测试。
- [ ] cancel-before-start、mid-transfer cancel、timeout、disconnect 和 callback race 有确定性测试。
- [ ] operation 返回后不存在仍访问 buffer/file/handle/session 的 transfer。
- [ ] 下载失败不留下最终路径的损坏文件；上传失败尽力清除 orphan object。
- [ ] `TransferTask` 的 pending/transferring/completed/failed/cancelled、progress 与 active/completed 列表迁移有测试。
- [ ] 目录上传保持递归目录结构、空间预检、部分失败汇总和取消语义。
- [ ] 传输完成后 storage/cache/文件列表刷新链无回归。
- [ ] 可用硬件时完成小文件、空文件、嵌套目录、大文件、取消、拔线和 hash 校验。
- [ ] Xcode build 与全部 Swift tests 通过，可在新会话回滚到 Go provider。

## Out of Scope

- 并行多文件传输或多设备并行传输优化。
- 暂停/恢复、断点续传和 MTP CancelTransaction event 支持。
- SwiftUI 传输界面改版。
- 删除 Go provider。

## Open Questions

无阻塞项。
