# Filesystem Repository Evidence

Checked on 2026-07-30.

## Current production flow

- `DeviceManager.scanDevices` calls `Kalam_Scan` directly and publishes decoded JSON on MainActor.
- `FileSystemManager.getFileList` calls `Kalam_ListFiles` directly, frees the returned string, decodes JSON and collapses every failure into `[]`.
- FileBrowser create, single delete and batch delete call `Kalam_CreateFolder` / `Kalam_DeleteObject` directly.
- `MTPConnectionCoordinator` already owns app UUID → snapshot/provider registration and one active session, but has no production caller and only delegates refresh.
- `SwiftMTPBackendSession` still throws `unsupportedDevice` for list/create/delete.

## Identity and cache evidence

- App `Device.id` is a UUID; legacy `deviceIndex` comes from Go JSON and the current Go scanner emits a constant ID.
- Native Swift identity is `swift:<bus>:<port path>:<vid>:<pid>`. The Go migration adapter uses `go:<id>`.
- Current disconnect detection uses serial numbers, while the coordinator expects immutable `MTPDeviceID`.
- File cache key is app UUID + storage + parent. TTL is hard-coded to 60 seconds even though `AppConfiguration.cacheExpirationInterval` exists.
- Failed/decode-null reads are not cached, but callers cannot distinguish them from successful empty directories.
- Current cache has no generation/version, so a late request can repopulate data after invalidation.

## Current behavior to preserve

- FileItem mapping keeps object/parent/storage IDs, filename, size, folder flag and optional Unix modification date.
- Folder file type is `"folder"`; file extension is ASCII-uppercase.
- Sorting is UI-owned and folders-first.
- Single delete uses the existing error alert; batch delete reports failed names.
- DeviceManager scan work stays off MainActor; published mutations stay on MainActor.
- FileSystemManager remains an actor and device cache invalidation does not affect other devices.

## Behaviors to correct

- Empty directory and failure must no longer share one `[]` result.
- Create failure must not be silent.
- Batch delete must not invalidate/refresh when every delete failed.
- Manager/view code must not parse Go JSON or call filesystem Kalam functions after integration.
- App UUID mapping must not depend on legacy index, serial availability, VID/PID alone or enumeration order.
- Cache TTL must use centralized configuration and a test clock.

## Primary code anchors

- `SwiftMTP/Services/MTP/DeviceManager.swift`
- `SwiftMTP/Services/MTP/FileSystemManager.swift`
- `SwiftMTP/Services/MTP/Backend/MTPConnectionCoordinator.swift`
- `SwiftMTP/Services/MTP/Backend/SwiftMTPBackend.swift`
- `SwiftMTP/Views/FileBrowserView.swift`
- `SwiftMTP/Views/FileBrowserView+ToolbarDrop.swift`
- `SwiftMTP/Views/FileBrowserView+Actions.swift`
- `Native/kalam_bridge.go`
- `Native/kalam_pool.go`
