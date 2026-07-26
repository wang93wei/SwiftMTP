# Swift Native MTP Migration Design

## 1. Architecture

```text
SwiftUI Views
  → DeviceManager / FileSystemManager / FileTransferManager
    → MTPBackend (typed, blocking contract; never called on main thread)
      → GoMTPBackend (migration only) → Kalam_* → Go
      → SwiftMTPBackend
        → MTPDeviceSession
          → MTP codec + transaction state machine
            → LibUSBTransport
              → CLibUSB → bundled libusb-1.0.dylib → Android device
```

The final state removes `GoMTPBackend`, `Kalam_*`, CGO and `libkalam`, while preserving `MTPBackend`, `SwiftMTPBackend`, CLibUSB and libusb.

## 2. Module Boundaries

| Layer | Responsibility | Must not own |
|---|---|---|
| `CLibUSB` | Official libusb header/module map and dynamic linking | MTP semantics or app state |
| `LibUSBContext` | `libusb_init/exit`, enumeration, event loop, transfer lifetime | Device/session business rules |
| `LibUSBTransport` | Open/configure/claim/release, endpoint I/O, cancellation | MTP object/storage decoding |
| `MTPCodec` | Little-endian container and dataset encode/decode | USB handles or UI state |
| `MTPDeviceSession` | Session ID, transaction ID, transaction ordering and response validation | View/cache/transfer-task state |
| `SwiftMTPBackend` | Device/storage/object/transfer operations | SwiftUI rendering |
| `MTPBackendRouter` | Choose a provider and open the requested snapshot identity for a new device session | Mixing providers or device identities inside a session |
| Existing managers | Cache, UI state, task presentation and user-facing error mapping | Raw libusb pointers |

The bundled libusb runtime self-reports `1.0.29.11953` and is currently arm64. Its vendored header/license must therefore come from official v1.0.29. External latest API documentation may describe 1.0.30, but that is not the bundled binary. This migration preserves the current architecture baseline; adding a universal libusb artifact is a separate distribution task unless the existing Xcode target already requires it.

## 3. C Interop and Packaging

- Vendor the matching official `libusb.h`, license/notice and a small `module.modulemap` in the repository.
- Import libusb through a named Clang module rather than exposing its declarations through the app-wide `libkalam` bridging header.
- Keep the tracked `libusb-1.0.dylib`, its `@rpath` install name and Embed Libraries signing.
- Add explicit link/search/module settings required by direct Swift calls.
- Do not require `/opt/homebrew`, `pkg-config`, Go or CGO for a clean build.
- Validate the built app with `otool -L`, `codesign --verify` and inspection of `Contents/Frameworks`.

## 4. Core Contracts

The production-facing backend uses typed Swift models and synchronous throwing operations. Callers already provide background execution (`Task.detached`, actor methods, or `transferQueue`), so raw C pointers never cross actor boundaries.

```swift
protocol MTPBackend {
    func initialize() throws
    func scanDevices() throws -> [MTPDeviceSnapshot]
    func openSession(for deviceID: MTPDeviceID) throws -> any MTPBackendSession
    func shutdown()
}

protocol MTPBackendSession {
    var deviceID: MTPDeviceID { get }
    var providerKind: MTPProviderKind { get }
    func listObjects(storageID: MTPStorageID, parentID: MTPObjectID) throws -> [MTPObject]
    func createFolder(storageID: MTPStorageID, parentID: MTPObjectID, name: String) throws -> MTPObjectID
    func deleteObject(_ objectID: MTPObjectID) throws
    func download(_ request: MTPDownloadRequest,
                  progress: @escaping (UInt64) -> Void,
                  cancellation: MTPCancellationToken) throws
    func upload(_ request: MTPUploadRequest,
                progress: @escaping (UInt64) -> Void,
                cancellation: MTPCancellationToken) throws
    func refreshStorage(_ storageID: MTPStorageID) throws
    func close()
}
```

Every `MTPDeviceSnapshot` carries the opaque `MTPDeviceID` needed to reopen that physical candidate. `DeviceManager` maps this transport identity to the app-facing stable `Device.id`. `MTPConnectionCoordinator` maps `Device.id` to exactly one open `MTPBackendSession`; selecting a different device closes the prior session and opens the selected snapshot through the provider chosen for that new session. `FileSystemManager` and `FileTransferManager` resolve operations through this coordinator and verify that the session device ID matches the requested device.

IDs are distinct Swift value types. Root parent remains `0xFFFFFFFF`;
storage/object zero is invalid, session excludes zero and `0xFFFFFFFF`, while
transaction IDs preserve the full UInt32 range because OpenSession uses zero
and normal increment may wrap through `0xFFFFFFFF`. `MTPDeviceSnapshot`,
`MTPStorage`, and `MTPObject` replace JSON DTOs.

`MTPBackendSession` is internal to `MTPConnectionCoordinator` and never escapes to an actor or manager. The coordinator is a traditional serial-queue/lock protected class that exposes typed blocking delegation keyed by app `Device.id`; it may use one narrowly audited `@unchecked Sendable` conformance so `FileSystemManager` can retain it. No concurrency annotation is added to `FileTransferManager*.swift`, and raw libusb pointers stay on the coordinator/session queues.

## 5. USB and MTP State

### USB lifecycle

1. Create one shared libusb context.
2. Enumerate configurations/interfaces and select MTP-compatible interfaces with bulk IN, bulk OUT and interrupt IN endpoints.
3. Open the device, set configuration when required, and fail if interface claim fails.
4. Run async transfer event handling on a dedicated queue/thread.
5. On close: reject new work → cancel active transfers → wait for completion callback → close MTP session → release interface → close handle.
6. Stop the event loop and call `libusb_exit` only after all handles are closed.

### MTP transaction

1. Allocate a non-zero/non-`0xFFFFFFFF` session ID.
2. Send OpenSession command and receive its response with transaction ID `0`.
3. Only after OpenSession succeeds, set the next transaction ID to `1`; CloseSession uses the current in-session transaction ID.
4. Serialize command → optional data-out/data-in → response as one indivisible operation.
5. Validate container type, operation code, payload length and transaction ID.
6. Map non-OK response codes into typed `MTPError.response`.
7. A USB error or protocol sync error invalidates the session; it is never returned to a reusable pool.

The pure Swift codec owns container headers, strings, device info, storage info, object info and response parameter decoding. Split headers, short packets and zero-length packets are transport concerns with deterministic fake-transport tests.

## 6. Concurrency and Cancellation

- Each `MTPDeviceSession` owns a serial `DispatchQueue`; no two transactions for the same device overlap.
- A coordinator prevents scan/read operations from claiming a handle already used by an active transfer.
- `FileTransferManager*.swift` keeps its existing `transferQueue` and locks.
- `MTPCancellationToken` is lock-backed and idempotent. Cancelling submits `libusb_cancel_transfer`; the operation returns only after the libusb completion callback confirms cancellation or terminal failure.
- Buffer, file handle, `libusb_transfer`, device handle and continuation lifetimes are owned by an explicit transfer object.
- UI mutations stay on `MainActor`/main queue.

## 7. File Transfer Semantics

- Download streams into a sibling temporary file, checks byte count, then atomically replaces/moves to the destination. Failure and cancellation remove the temporary file.
- Upload performs `SendObjectInfo` then `SendObject`. If data transfer fails after object creation, best-effort `DeleteObject` compensates the orphan and logs any cleanup failure.
- Progress reports actual transferred bytes without changing the existing UI structure.
- Timeout/retry decisions use structured USB/MTP error categories, not string matching.
- Retries never reuse an invalidated session and never overlap a timed-out transfer.
- ObjectInfo compressed size is exact through `0xFFFFFFFE`; file sizes `>= 0xFFFFFFFF` use the `0xFFFFFFFF` sentinel.
- The data-container length includes the 12-byte header. Payloads through `0xFFFFFFF3` encode `payload + 12`; larger payloads use the `0xFFFFFFFF` sentinel. Exact-wire fixtures cover `0xFFFFFFF2`, `0xFFFFFFF3`, `0xFFFFFFF4`, `0xFFFFFFFE`, `0xFFFFFFFF` and `0x1_0000_0000`.
- Device ObjectTooLarge/unsupported responses fail visibly.
- For downloads whose ObjectInfo size is `0xFFFFFFFF`, query the 64-bit ObjectSize property when supported; otherwise stream safely with indeterminate progress. No UInt64→UInt32 truncation is allowed.

## 8. Error and Logging Model

The protocol/backend layer names this error `MTPCoreError` to avoid colliding with the existing UI-facing `MTPError`. `MTPCoreError` covers invalid input, no device, busy/permission, disconnected, timeout, cancelled, USB error code, MTP response code, protocol violation, unsupported device and local file I/O.

- Service managers map `MTPCoreError` to the existing UI-facing `MTPError`, alerts and task states at the manager integration boundary.
- No failure becomes an empty list unless the existing UI contract explicitly requires an empty successful directory.
- Use `Logger` categories for USB lifecycle, MTP session, filesystem and transfer.
- Log operation, device-safe opaque ID, object/storage ID, byte count, duration and structured error.
- Do not log file content, full local paths or raw device serial numbers.

## 9. Provider Migration and Rollback

- `GoMTPBackend` wraps the existing ABI only during migration.
- Provider choice is a developer/test configuration stored centrally in `AppConfiguration.swift`.
- The router fixes both provider kind and selected `MTPDeviceID` when a device session is created; switching provider or device requires closing the current session.
- Differential tests run providers sequentially against the same fixture/device. They never issue write operations to both providers concurrently.
- Go remains the default until Swift discovery, filesystem and transfer acceptance gates all pass.
- Final cutover changes the default to Swift, runs the complete matrix, then deletes Go/CGO/libkalam in the same child task.
- Before deletion, rollback is provider selection; after deletion, rollback is the prior verified Git commit.

## 10. Verification Strategy

1. Pure unit tests: binary codec, bounds checks, IDs, datasets and error mapping.
2. Scripted transport tests: transaction order, IDs, response errors, fragmented headers, short/ZLP behavior, cancellation and disconnect.
3. Backend contract tests: device/storage/object/upload/download observable results and local file side effects.
4. Manager integration tests: state, cache invalidation, task progress/terminal status and main-thread updates.
5. Hardware regression: scan, browse, create, upload, hash-verified download, cancellation, delete and disconnect.
6. Build/package verification: Debug, Release, test, DMG, dylib linkage/signature and absence of Go/libkalam.

## 11. Known Risks

- MTP devices vary in header/data packet behavior and response quirks; keep device-specific handling isolated in transport/session policy.
- The current libusb artifact is arm64-only; do not imply universal support without a separately verified binary.
- Hardware-free CI cannot prove USB ownership, Android interop or physical disconnect behavior.
- The existing Go implementation contains bugs (unjoined timeout goroutine, leaked scan strings, stale cancellation flags and >4 GiB truncation). Golden tests capture intended observable behavior, not those unsafe mechanisms.
