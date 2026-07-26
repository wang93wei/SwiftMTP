# 切换 Swift Provider 并移除 Go

## Goal

在 Swift provider 通过完整自动化与真机验收后，将其设为唯一生产实现，删除 Go、CGO、`libkalam` 及所有残留配置，同时继续正确嵌入、签名和分发 libusb。

## In Scope

- 最终真机/构建/打包门禁、Swift-only 切换、Go/CGO/libkalam 清理和文档更新。

## Key Decisions

- **KD1:** libusb、USB 访问相关 sandbox/library-validation 设置继续保留。
- **KD2:** children 2–4 的真实设备 blocking gate 未通过时，不得删除 Go。
- **KD3:** 删除后的回滚单位是 pre-cutover Git commit，不手工重建 Go 产物。
- **KD4:** 本任务不 push、发布或 notarize。

## Dependencies and Handoff

- 前四个 child 的 `verification.md` 必须显示全部 blocking AC 与 `Open: 0` 通过。
- discovery、filesystem、transfer 的真实设备 blocking 项必须为 passed，不能仅为 unavailable。
- 完成时生成本任务 `verification.md`，汇总最终 AC、clean build/tests、DMG/link/sign、desloppify 全分数、硬件矩阵与回滚 commit。

## Requirements

- 在删除前执行 Go/Swift 顺序差分、完整 Swift tests、Debug/Release build 和真实设备矩阵。
- Swift provider 成为唯一默认；移除 migration router 的 Go factory 与全部 `Kalam_*` 调用。
- 删除 `Native/`、`libkalam.h/.dylib/.a`、CGO build script 和 Go tests/vendor/module。
- 从 Xcode 移除 libkalam embed/link、旧 bridging header 和无用 search path；保留 CLibUSB 与 libusb embed/sign/rpath。
- 将测试/环境脚本改为纯 Swift + bundled libusb，不要求 Go 或 Homebrew。
- 更新 README、wiki、架构/时序图、本地化“built with”文案和测试说明。
- 验证 `.app`/DMG 中只有所需 libusb，不含 libkalam 或 Go 产物。
- 执行强制 `desloppify` 扫描并确保 `Open: 0`；涉及残余 Go 修改时执行 Go 专项扫描。
- 不 push，除非用户另行要求。

## Acceptance Criteria

- [ ] `git grep` 在生产、构建、测试、打包和用户文档中找不到 `Kalam_`、libkalam、CGO、go-mtpx、build_kalam、go build/test 残留。
- [ ] `Native/`、Go module/vendor/tests 和全部 libkalam 生成物已删除。
- [ ] Debug/Release clean build 与全部 Swift tests 在无 Go、无 Homebrew libusb 环境通过。
- [ ] `.app/Contents/Frameworks` 含正确签名的 libusb，不含 libkalam；主二进制 `otool -L` 解析成功。
- [ ] DMG 创建、挂载检查和 codesign 验证通过。
- [ ] 真机扫描、浏览、创建、上传、hash 下载、取消、删除、断连/重连全部通过，或明确列出无法取得硬件导致的未完成阻塞。
- [ ] 文档与 8 个本地化资源准确描述 Swift + libusb 架构。
- [ ] `desloppify scan --path .` 显示 `Open: 0`，并报告全部强制分数。
- [ ] 最终提交由 commit agent 完成，工作树只包含授权迁移变更。

## Out of Scope

- 移除 libusb、改变 sandbox 策略或新增 universal binary 支持。
- 发布、notarize、push 或创建 PR，除非用户另行授权。
- 与迁移无关的 UI/功能修改。

## Open Questions

无阻塞项。
