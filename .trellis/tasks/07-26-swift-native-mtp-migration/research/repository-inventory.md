# Repository Inventory

## Current Runtime Boundary

The production path is SwiftUI → Swift managers → `Kalam_*` C ABI → Go MTP implementation → vendored go-mtpx/libusb.

- Swift imports only `libkalam.h`: `SwiftMTP/SwiftMTP-Bridging-Header.h:8-12`.
- Exported ABI is declared at `Native/libkalam.h:90-103`.
- Xcode embeds and signs `libkalam.dylib` and `libusb-1.0.dylib`: `SwiftMTP.xcodeproj/project.pbxproj:38-49,114-123`.

## Used Native Capabilities

| Capability | Go/CGO source | Swift consumer |
|---|---|---|
| Initialize/shutdown | `Native/kalam_bridge.go:37-41,401-421` | `DeviceManager.swift:118-134`, `SwiftMTPApp.swift:97-117` |
| Scan devices/storage | `Native/kalam_bridge.go:43-127` | `DeviceManager.swift:215-303` |
| List objects | `Native/kalam_bridge.go:130-205` | `FileSystemManager.swift:112-213` |
| Create folder | `Native/kalam_bridge.go:222-288` | `FileBrowserView+ToolbarDrop.swift:144-164`, `FileTransferManager+DirectoryUpload.swift:232-265` |
| Delete object | `Native/kalam_bridge.go:291-315` | `FileBrowserView+Actions.swift:280-353` |
| Download | `Native/kalam_bridge_transfer.go:31-267` | `FileTransferManager.swift:185-302` |
| Upload | `Native/kalam_bridge_transfer.go:305-439` | `FileTransferManager.swift:305-390`, `FileTransferManager+DirectoryUpload.swift:306-351` |
| Cancel task | `Native/kalam_bridge_transfer.go:288-303` | `FileTransferManager.swift:110-134` |
| Refresh/reset | `Native/kalam_bridge.go:317-375` | `FileTransferManager.swift:359-389`, `FileTransferManager+DirectoryUpload.swift:181-184` |

`Kalam_SetProgressCallback` is a no-op and has no Swift caller: `Native/kalam_bridge_transfer.go:25-29`.

## Protocol and State Responsibilities Hidden in Go

- All native operations are globally serialized by `deviceMu`: `Native/kalam_pool.go:15-18,170-179,279-287`.
- Pool maximum is 3, TTL is 2 minutes, cleanup interval is 1 minute: `Native/kalam_config.go:87-90`.
- Scan, ordinary operations, and download use different timeout/retry policies: `Native/kalam_config.go:68-80`.
- MTP session and transaction IDs are owned by the vendored device implementation: `Native/vendor/github.com/ganeshrvel/go-mtpfs/mtp/ops.go:16-41`.
- A transaction is command → optional data-out/data-in → response, with transaction-ID validation: `Native/vendor/github.com/ganeshrvel/go-mtpfs/mtp/mtp.go:371-510`.
- Upload is `SendObjectInfo` followed by `SendObject`: `Native/kalam_bridge_transfer.go:362-430`.
- Data transfer handles 16 KiB chunks, split headers, short packets, and zero-length packets: `Native/vendor/github.com/ganeshrvel/go-mtpfs/mtp/mtp.go:525-657`.

## Existing Risks That Must Not Become New Contracts

- Download timeout may return while its goroutine still uses the device/file: `Native/kalam_bridge_transfer.go:169-198`.
- Upload truncates `CompressedSize` above 4 GiB despite a 10 GiB app limit: `Native/kalam_bridge_transfer.go:355-370`.
- Cancel markers are never removed: `Native/kalam_bridge_transfer.go:269-303`.
- Successful transfer-side `Kalam_Scan` results are not freed by Swift: `FileTransferManager.swift:224-240,286-296,364-369`.
- `Kalam_ResetDeviceCache` only calls `GetDeviceInfo`; it does not reset a cache: `Native/kalam_bridge.go:352-375`.
- No real-time Swift progress callback exists today; UI progress effectively changes at start/end.

These are parity observations, not requirements to reproduce bugs.

## Test Baseline

- `SwiftMTPTests` target exists but has no source files: `SwiftMTP.xcodeproj/project.pbxproj:138-160,231-237`.
- Existing tests are five Go test files covering validation, IDs, C strings, empty pool behavior, and cancellation-map smoke tests.
- There is no injectable USB transport fake.
- Real-device verification is required for enumeration, interface claim, device quirks, disconnect behavior, and end-to-end transfer.

## Build Removal Surface

Final cutover must remove:

- `Native/`, `Scripts/build_kalam.sh`, generated `libkalam.h/.dylib/.a`.
- `SWIFT_OBJC_BRIDGING_HEADER` entries used only for `libkalam.h`.
- Xcode embed/sign membership for `libkalam.dylib`.
- Go execution from `Scripts/run_tests.sh`.
- Go/CGO/libkalam references in README/wiki/localizations.

The approved final architecture retains libusb and removes only Go/CGO/libkalam.
