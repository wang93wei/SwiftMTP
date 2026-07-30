# Transfer Migration Implementation Plan

## Execution Order

### 1. Native fallback upload policy

- [ ] 先写 Go RED tests：regular/zero/symlink/directory/non-regular、不存在、Unicode/`..` basename、配置上限、`UInt32.max` 两侧。
- [ ] 提取最窄 source inspection seam；在任何 SendObjectInfo 前执行 caller-independent policy。
- [ ] 补 cancellation registry lifecycle、pre/mid cancel、task ID reuse 和 legacy 0/1/2 exact-session admission tests。
- [ ] 保持旧 transfer ABI 可链接，不改变“唯一 active exact session，否则 fail closed”语义。

### 2. Provider-bound transfer contract

- [ ] 先写 coordinator RED tests：正确 active session forwarding、wrong app/device/provider、switch/close、terminal invalidation exactly once、unsupported 不切 provider。
- [ ] 增加 coordinator typed download/upload forwarding。
- [ ] 新增 token-aware Go transfer ABI 与 `KalamMTPBackendSession` adapter，覆盖 C string ownership、structured error、cancel 和 progress。
- [ ] 证明 manager 之外不存在新 direct Kalam transfer caller，且没有跨 provider replay。

### 3. Streaming libusb ownership primitive

- [ ] 扩展 fake 以脚本化多个 sequential transfer terminal callback；先写 buffer/callback/lease lifetime RED tests。
- [ ] 在保留现有 `LibUSBTransfer.execute` 行为的前提下实现同步 sequential streaming chunk primitive。
- [ ] 覆盖 cancel-before-submit、blocked submit、cancel-vs-complete、timeout、NO_DEVICE、shutdown/close、submit failure 和 duplicate callback。
- [ ] 每轮证明 terminal callback 先于 free/deallocate/release/close/exit。

### 4. MTP streaming framing and Swift download

- [ ] 写 streaming data header/sentinel、fragmented header、short/overrun、response order 和 TID/operation mismatch RED tests。
- [ ] 为 session/transport 增加 caller cancellation、stream sink 与 response result；现有 metadata transact tests 不回归。
- [ ] 实现 GetObject streaming、ObjectInfo sentinel 与 64-bit ObjectSize property 查询。
- [ ] 实现临时文件/原子 finalization，覆盖空文件、替换、write/sync/close error、取消与无残留。

### 5. Swift upload and compensation

- [ ] 写 ObjectInfo `0xFFFFFFFE`/`0xFFFFFFFF`/`0x1_0000_0000` 与 payload `0xFFFFFFF3` 两侧 exact-wire tests。
- [ ] 实现文件 SendObjectInfo 与 SendObject source streaming、short read/overrun 和实际字节进度。
- [ ] 写并实现 SendObjectInfo 后 cancel/timeout/disconnect/response failure 的 best-effort orphan cleanup；补偿失败进入 typed diagnostic。
- [ ] 断言 mutation 脚本只消费一次，不自动 reopen/replay。

### 6. FileTransferManager vertical integration

- [ ] 写 submission/task lifecycle RED tests：可观察拒绝、pending→transferring→terminal、progress、cancel、once-only completed move。
- [ ] 保持 `DispatchQueue + NSLock`，为 task 绑定 typed request、device identity、cancellation token 和 provider coordinator。
- [ ] 替换 download/upload 的 direct Kalam 调用，移除 `Thread.sleep`、二次 scan 推断和 active-task early-return 漏清理。
- [ ] 所有 `TransferTask` mutation 显式 hop 到 MainActor；不在 callback 线程直接更新 UI。

### 7. Directory upload state machine

- [ ] 写 manifest/preflight、nested file-bearing folders、policy、storage-space 与 package/hidden/empty-dir compatibility tests。
- [ ] 建立 operation-scoped token、folder cache、per-file outcome、summary 和 once finalizer。
- [ ] 覆盖 all-success/all-failed/partial/pre-cancel/mid-cancel/create-root failure，以及两个并发 operation 取消隔离。
- [ ] 删除 manager-wide directory cancel flag 和伪 async blocking helper。

### 8. Single completion and error presentation

- [ ] 写 remote mutation/no-mutation 的 refresh/cache/event RED tests。
- [ ] 建立唯一 typed finalizer，删除传输路径的全局 cache reset、延迟 magic notification 和重复 no-op branches。
- [ ] FileBrowser 只消费相关 device/storage/path 的 typed completion event。
- [ ] 建立窄 `MTPCoreError` presentation mapping，覆盖 submission、terminal、partial/cancel；保留 Logger 原始诊断。

### 9. Verification and handoff

- [ ] 拆分 `GoMTPBackendTests.swift` 的 scan/list/filesystem/transfer/C-string fixture，保持职责清晰且不降低测试覆盖。
- [ ] 运行所有 focused/full Swift、Debug/Release/Analyze、Go normal/race/vet、native build 与 ABI 检查。
- [ ] 运行静态架构检查与 `git diff --check`，确认 provider、Kalam 调用、refresh/cache、并发模型和重放边界。
- [ ] 写 `verification.md`，记录 AC、命令、测试数量、static audit、hardware 状态、默认 provider 与 fallback 边界。
- [ ] 独立 `trellis-check` 后再更新 spec、提交；不 push。

## Validation Commands

```bash
python3 ./.trellis/scripts/task.py validate .trellis/tasks/07-26-swift-mtp-transfer
xcodebuild test -project SwiftMTP.xcodeproj -scheme SwiftMTP -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
xcodebuild -project SwiftMTP.xcodeproj -scheme SwiftMTP -configuration Debug -arch arm64 build
xcodebuild -project SwiftMTP.xcodeproj -scheme SwiftMTP -configuration Release -arch arm64 build
xcodebuild -project SwiftMTP.xcodeproj -scheme SwiftMTP -configuration Debug -arch arm64 analyze
cd Native && go test ./...
cd Native && go test -race ./...
cd Native && go vet ./...
./Scripts/build_kalam.sh
cmp Native/libkalam.h SwiftMTP/libkalam.h
file SwiftMTP/libkalam.dylib
otool -L SwiftMTP/libkalam.dylib
nm -gU SwiftMTP/libkalam.dylib
git diff --check
```

Hardware gate when available:

1. 上传/下载空文件和小型确定性文件，比较 SHA-256。
2. 上传/下载嵌套目录并核对每个文件和目录结构。
3. 上传/下载多 GiB fixture，验证 sentinel、进度和最终字节数。
4. 中途取消 upload/download，确认无损坏最终文件和可见 orphan。
5. 两个并发目录任务只取消一个，另一个继续。
6. 每个方向中途拔线，重连后新 session 可用，旧 operation 不重放。
7. 在 Swift 与 Go 新会话分别运行矩阵；不得在同一 operation 中切 provider。

## Review Gates

- `FileTransferManager*.swift` 仍使用传统 queue/lock。
- manager/view 不直接引用 transfer Kalam symbols。
- 每个 libusb transfer terminal callback 先于资源释放。
- mutation 无自动 retry/replay；provider 只在提交前选择。
- `UInt64` size 不静默缩窄，空文件合法。
- task/outcome、cache/storage refresh 与 UI 展示一致。
- Go fallback 保留且 token-bound；生产默认仍由 cutover 决定。
- 本任务绝不删除 Go 或 libusb。

## Rollback

保持生产默认 Go，并为新会话显式选择 Go。若 Swift transfer 失败，关闭当前 Swift session 后重新选择 Go；不得重放已提交 operation。最终 Go 删除需用户未来再次明确授权。
