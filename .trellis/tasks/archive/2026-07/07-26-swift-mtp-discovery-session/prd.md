# 实现 libusb 设备会话与扫描

## Goal

基于 foundation 提供的 Swift codec 与 CLibUSB，完整实现可测试的 libusb 生命周期、MTP 设备识别、session/transaction 状态机以及设备/存储扫描，但仍不迁移文件系统或写操作。

## In Scope

- libusb context/handle/transfer 生命周期、MTP interface discovery、session/transaction 和设备/存储扫描。

## Key Decisions

- **KD1:** OpenSession command/response transaction ID 固定为 `0`；成功后首条 session command 使用 `1`。
- **KD2:** 每个设备 session 串行执行完整 transaction，错误后不复用无效 session。
- **KD3:** 本阶段生产默认仍为 Go，Swift 仅在测试或新开发会话启用。

## Dependencies and Handoff

- 前置 `07-26-swift-mtp-foundation/verification.md` 必须显示全部 blocking AC、build/tests、Analyze 与 artifact checks 通过。
- 完成时生成本任务 `verification.md`；硬件 scan/open/close 状态必须明确，供 filesystem 阶段判定。

## Requirements

- 一个共享 libusb context 负责初始化、事件处理和最终退出。
- 枚举所有 configuration/interface/alternate setting，识别具备 bulk IN、bulk OUT、interrupt IN 的 MTP/PTP 接口。
- 对选定设备执行 open、必要的 configuration 设置、interface claim；任何 claim 错误都必须失败并清理。
- 实现 MTP OpenSession/CloseSession、单调 transaction ID、完整 transaction 顺序与 response transaction ID 校验。
- USB、MTP 或 sync 错误必须使 session 失效；无效 session 不得复用。
- 实现 GetDeviceInfo、GetStorageIDs、GetStorageInfo 并映射为 typed Swift snapshot。
- 每个 snapshot 必须携带可重新打开对应物理设备的 `MTPDeviceID`；选择设备后只能用该 ID 创建对应 session。
- 资源关闭顺序必须等待 active async transfer 的 completion callback。
- Swift provider 只通过开发/测试配置在新会话启用；Go 仍是生产默认。

## Acceptance Criteria

- [ ] scripted transport 覆盖设备枚举结果、端点选择、claim busy/no-device/permission 和清理顺序。
- [ ] OpenSession command/response TID `0`、首条 session command TID `1`、CloseSession 当前 TID、response mismatch、unexpected container 与 reconnect 有测试。
- [ ] GetDeviceInfo/StorageIDs/StorageInfo 的 binary fixture 解码和 typed mapping 有测试。
- [ ] 取消或关闭时，transfer/buffer/handle 不会在 completion 前释放。
- [ ] Swift scan 对无设备、单设备、多设备、unsupported interface 与单个 storage 失败提供可诊断结果。
- [ ] 两个 scripted 设备的 snapshot→选择→session 路由不会串设备，且切换设备会关闭旧 session。
- [ ] 可用硬件时记录至少一次真实 Android 设备 scan/open/close 证据；无硬件时明确标记未验证。
- [ ] Xcode build 与全部 Swift tests 通过，Go 默认路径无回归。

## Out of Scope

- 对象列表、创建、删除、上传或下载。
- 启用 interrupt event endpoint 的 MTP event 消费。
- 将 Swift provider 设为生产默认。

## Open Questions

无阻塞项。
