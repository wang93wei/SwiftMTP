# 迁移 MTP 文件系统操作

## Goal

在已验证的 Swift libusb/MTP session 上实现当前生产使用的对象与目录操作，并让 `DeviceManager`、`FileSystemManager` 可以在会话固定的 Swift provider 下完成扫描、浏览、创建和删除。

## In Scope

- MTP 对象元数据、列表/建目录/删除/刷新及 DeviceManager/FileSystemManager 集成。

## Key Decisions

- **KD1:** 有效空目录与失败必须区分。
- **KD2:** 单个坏 ObjectInfo 保持当前跳过行为，但必须产生结构化诊断。
- **KD3:** 不实现 rename/move/copy，生产仍可在新会话回滚到 Go。

## Dependencies and Handoff

- foundation 与 discovery/session 的 `verification.md` 必须显示 blocking AC、build/tests 与 `Open: 0` 通过。
- 完成时生成本任务 `verification.md`，记录 manager/backend AC、硬件只读/写元数据状态、provider 默认和回滚 commit。

## Requirements

- 实现 GetObjectHandles、GetObjectInfo、SendObjectInfo(folder)、DeleteObject 和 storage refresh。
- 根 parent 保持 `0xFFFFFFFF`，storage/object zero ID 必须在边界拒绝。
- object info 映射保持名称、parent/storage/object ID、size、目录标志和修改时间语义。
- 单个 object info 读取失败可保持当前“跳过坏项”的可见行为，但必须产生带 object ID 的结构化诊断。
- 创建目录必须验证名称和 response 返回的新 object handle；失败不得返回伪成功 ID。
- 将 provider 注入 `DeviceManager`/`FileSystemManager`，会话开始后固定 provider。
- 保持 60 秒目录缓存、按设备失效和操作后刷新行为。
- 不再依赖 JSON 解码作为 Swift provider 的内部边界。

## Acceptance Criteria

- [ ] object handles/info、folder create response、delete response 与 storage refresh 均有 binary fixture/transport tests。
- [ ] root、多 storage、空目录、文件夹/文件、Unicode 名称、坏 object info、invalid ID 和 MTP error 有测试。
- [ ] `FileSystemManager` 在 Swift provider 下返回与现有 `FileItem` 一致的字段和排序输入。
- [ ] 创建/删除成功后只失效相关设备缓存并触发现有刷新链；失败不会伪装为空目录或成功。
- [ ] `DeviceManager` 和 `FileSystemManager` 的 Go/Swift provider contract tests 通过。
- [ ] 可用硬件时完成 scan→root list→nested list→create folder→delete 的顺序回归。
- [ ] 不实现或暴露当前生产未使用的 rename/move/copy。
- [ ] Xcode build 与全部 Swift tests 通过，生产默认仍可回滚到 Go。

## Out of Scope

- 文件内容上传、下载、进度或取消。
- rename、move、copy、thumbnail 和对象属性编辑。
- 删除 Go provider。

## Open Questions

无阻塞项。
