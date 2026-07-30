# 建立 Swift MTP 协议与测试底座

## Goal

在不切换现有生产 Go provider 的前提下，建立可直接调用已捆绑 libusb 的 Swift 编译边界、纯 Swift MTP 类型/编解码器和可注入测试 seam，为后续 USB session 与业务操作提供稳定契约。

## In Scope

- CLibUSB 编译/链接边界、Swift MTP core、backend/transport contracts 和 Swift 测试底座。

## Key Decisions

- **KD1:** 使用仓库内 header/module/dylib，不依赖 Homebrew。
- **KD2:** 本阶段不打开真实设备，生产默认保持 Go。
- **KD3:** binary codec 显式处理 32 位字段、`0xFFFFFFFF` sentinel 和 UInt64 窄化风险。

## Dependencies and Handoff

- 无实现前置子任务；以父任务 PRD/design/research 为输入。
- 完成时生成本任务 `verification.md`，列出全部 AC、测试/构建/Analyze/链接/签名证据、硬件状态、Go 默认 provider 和回滚 commit。

## Requirements

- 将匹配仓库当前 runtime `1.0.29.11953` 的官方 v1.0.29 header、许可证和 Clang module map 纳入仓库；外部最新 API 文档为 1.0.30，二者不得混淆；干净编译不得读取 Homebrew 路径。
- 保留并显式链接现有 `libusb-1.0.dylib`，本阶段不得移除 `libkalam` 或 Go。
- 定义不同类型的 device/storage/object/session/transaction ID、operation/response/container code、typed `MTPCoreError`；后续 manager 集成时显式映射到现有 UI-facing `MTPError`。
- 实现边界检查完备的 little-endian reader/writer、MTP container、字符串及基础 dataset codec。
- 定义 `MTPBackend`、低层 transport seam、lock-backed cancellation token 与 migration-only provider router。
- 建立真实可运行的 Swift 测试源码、scripted fake transport、fixture builder 和 backend contract test 基类。
- 保持现有生产默认路径为 Go，不改变用户可见行为。

## Acceptance Criteria

- [x] `import CLibUSB` 可编译；新 Swift 层的 Debug/Release 编译不调用 `/opt/homebrew`、Go 或 CGO，应用仍按本阶段要求保留运行时 `libkalam`。
- [x] container command/data/response、字符串、边界值和 malformed/truncated input 均有先红后绿的测试。
- [x] ID 类型阻止 storage/object/session/transaction 参数误用；root parent `0xFFFFFFFF`、storage/object zero invalid、session 排除 `0`/`0xFFFFFFFF`、transaction 允许完整 UInt32 范围均有测试。
- [x] scripted transport 可以断言 exact request bytes，并脚本化 fragmented response、USB/MTP error、timeout 与 cancellation。
- [x] `MTPBackend` 可由 Go migration adapter、Swift implementation 与 test fake 实现。
- [x] 应用仍默认使用 Go provider，现有行为和构建不变。
- [x] Swift 全量测试与 Xcode build 通过。

## Out of Scope

- 打开或 claim 真实 USB 设备。
- 实现 MTP session、设备扫描、对象操作或文件传输。
- 删除任何 Go/CGO/libkalam 生产路径。

## Open Questions

无阻塞项。
