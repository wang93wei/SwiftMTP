# Filesystem Migration Design

## 1. Dependency Gate

- Foundation verification shows codec/backend/test/build/Analyze and artifact
  blocking gates pass.
- Archived discovery/session verification shows libusb lifecycle, exact-ID reopen, transaction/session and scan gates pass; hardware is explicitly unavailable, not claimed.
- Go remains the production default in this child because upload/download still use the Go session. This child adds a typed production boundary and an explicit Swift development/test path; after the full Swift path is complete, the parent cutover makes Swift preferred and retains Go as fallback until the user separately authorizes removal.

## 2. Runtime Data Flow

```text
FileBrowserView / file actions
  → FileSystemManaging actor
    → MTPFileSystemCoordinating facade
      → MTPConnectionCoordinator
        → provider-fixed MTPBackendSession
          → Go session → Kalam_*                    (production default)
          → Swift session → MTPDeviceSession
            → LibUSBTransport → CLibUSB → libusb   (explicit dev/test)
```

```text
DeviceManager scan
  → configured provider runtime
    → MTPBackend.scanDevices()
      → [MTPDeviceSnapshot]
        → stable app UUID mapping
          → Device + MTPDeviceIdentity
          → coordinator.register(...)
```

Managers never receive raw libusb pointers and never open a backend session directly.

## 3. Typed Domain Contracts

### Device identity

```swift
struct MTPDeviceIdentity: Hashable, Sendable {
    let providerKind: MTPProviderKind
    let deviceID: MTPDeviceID
}
```

`Device.id` remains the app-facing UUID. `Device` also carries immutable transport identity for operation validation. `deviceIndex` remains a legacy display/compatibility field and is never a reconnect key.

### Directory result

```swift
struct MTPObjectFailure: Equatable, Sendable {
    let deviceID: MTPDeviceID
    let storageID: MTPStorageID
    let parentID: MTPObjectID
    let objectID: MTPObjectID
    let error: MTPCoreError
}

struct MTPDirectoryListing: Equatable, Sendable {
    let objects: [MTPObject]
    let failures: [MTPObjectFailure]
}
```

`MTPBackendSession.listObjects` returns `MTPDirectoryListing`, not a bare array. An empty `objects` and empty `failures` value is a successful empty directory. Terminal failure throws.

### ObjectInfo wire model

`MTPObjectInfoDataset` owns the full standard field sequence:

1. storage ID, object format, protection, compressed size;
2. thumbnail format/size/dimensions;
3. image dimensions/depth;
4. parent, association type/description, sequence number;
5. filename, capture date, modification date, keywords.

Folder encoding uses association format `0x3001`, size `0`, association type `1`, supplied storage/parent, and exact MTP UTF-16 strings. Date parsing accepts the standard UTC form and numeric offsets, returning `nil` only for an empty date string; malformed non-empty dates are typed decode failures.

## 4. Transaction Core Extension

The transaction engine models the data phase explicitly:

```swift
enum MTPDataPhase {
    case none
    case inbound
    case outbound(Data)
}

struct MTPTransactionResult {
    let data: Data?
    let responseCode: MTPResponseCode
    let responseParameters: [UInt32]
}
```

`MTPTransport` gains an outbound-metadata seam:

```swift
func transact(
    command: Data,
    outboundData: Data?,
    cancellation: MTPCancellationToken
) throws -> [Data]
```

`LibUSBTransport` writes the command container and, when supplied, the complete data container before reading response fragments. Each OUT write must report its exact byte count. This path is deliberately limited to materialized metadata; the transfer child may add a streaming source without changing filesystem operations.

`MTPDeviceSession`:

- allocates one TID per operation;
- encodes command parameters as little-endian UInt32;
- requires data container operation/TID to match the command;
- supports response-only, required inbound data, and outbound data;
- retains response parameters;
- rejects duplicate/missing/unexpected data and trailing containers.

### Session invalidation

| Error | Session state |
|---|---|
| transport disconnect/timeout/cancel after submission | invalid |
| malformed container, operation/TID/order mismatch | invalid |
| session-not-open or invalid-transaction response | invalid |
| transaction ID space exhausted before wrap to zero | invalid |
| ordinary object/storage MTP response | remains open |
| local input validation before submission | remains open |

This allows one stale object handle to be reported without making all later reads appear disconnected.

## 5. Filesystem Operations

### List

1. `GetObjectHandles(storageID, format: 0, parentID)`.
2. Decode its UInt32 array and validate every non-zero handle.
3. Sequentially call `GetObjectInfo(handle)` in the same session.
4. Map successful datasets to `MTPObject`.
5. Record and skip only recoverable object-level MTP responses.
6. Abort on transport, protocol, session, or malformed dataset errors.

### Create folder

1. Validate trimmed non-empty name, forbidden characters, embedded NUL and MTP UTF-16 unit limit.
2. Send `SendObjectInfo(storageID, parentID)` command.
3. Send ObjectInfo data container with the same operation/TID.
4. Require OK response parameters `(actualStorage, actualParent, newHandle)`.
5. Validate storage/parent consistency and non-zero new handle before returning.

AOSP confirms directories complete during `SendObjectInfo`; no `SendObject` follows.

### Delete

Send `DeleteObject(handle, format: 0)`. Only an OK response is success. Mutating operations are never automatically replayed based on error strings.

### Refresh

Call `GetStorageInfo(storageID)` and return the typed `MTPStorage`. “Refresh” means reread current storage metadata, not a device cache reset.

## 6. Provider Runtime and Go Adapter

`AppConfiguration` owns `defaultMTPProvider = .go`. A small runtime/factory owns:

- backend factories for `.go` and `.swift`;
- the shared `MTPConnectionCoordinator`;
- configured scan provider;
- orderly shutdown.

The production Kalam boundary implements typed Go session operations:

- Native USB discovery exposes full bus + port path + VID + PID and returns a canonical opaque locator in scan JSON;
- locator parsing rejects missing/empty port paths and never falls back to enumeration index, device address or serial;
- exact open returns an opaque process-local token bound to the selected physical candidate;
- list/create/delete/refresh and close accept that token; list JSON becomes `MTPDirectoryListing`;
- stale/unknown token, disconnect and structured Native failures become `MTPCoreError`;
- every non-nil Kalam string is paired with exactly one `Kalam_FreeString`;
- no manager or view parses Go JSON or calls `Kalam_*`.

Native session entries own the exact opened `*mtp.Device` and serialize operations.
Close is idempotent. Cleanup rejects new opens, waits for or rejects in-flight work,
disposes every session once and invalidates all old tokens. The legacy transfer
symbols remain exported in this child; they may reuse only the currently selected
exact session and must fail closed when no unambiguous active session exists. They
must not fall back to the old unkeyed pool.

Go and Swift contract tests share the same observable cases where the Go ABI can express them. Swift-specific diagnostics may be richer without changing UI semantics.

## 7. Manager Integration

### Scan result

`MTPBackend` and the provider runtime return
`MTPScanResult(snapshots: [MTPDeviceSnapshot], failures: [MTPScanFailure])`.
Operation-wide failure still throws `MTPCoreError`; partial failures are not hidden in
a concrete-backend side channel. `DeviceManager` treats successful absence and
explicit disconnect separately from transient scan errors. Transient errors retain
the selected device/session and only advance retry diagnostics.

### DeviceManager

- Remains `@MainActor` and keeps current scan interval/backoff/public state.
- Its initializer becomes internal and injectable; `shared` uses the production runtime.
- Background scan calls a typed scanning seam; all published mutation remains on MainActor.
- Stable app UUID cache is keyed by `MTPDeviceIdentity`, not serial, index, VID/PID, or enumeration order.
- Successful snapshots are registered with the coordinator before exposure to filesystem operations.
- Disconnect closes the selected coordinator session, clears only the disconnected device cache, cancels relevant operations, then posts the existing notification.

### FileSystemManager

- Remains an actor and conforms to an async `FileSystemManaging` contract.
- Its initializer injects coordinator facade, clock, TTL and logger seam; `shared` uses production defaults.
- Blocking backend work happens off MainActor, while actor state owns cache mutation and generations.
- `Device` requires `MTPDeviceIdentity`; `StorageInfo` and `FileItem` retain `MTPStorageID`/`MTPObjectID` rather than erasing them to `UInt32`.
- It maps `MTPObject` to existing `FileItem`: folder/file flag, name, typed IDs, size, modification date and ASCII-uppercase extension. Sorting remains in `FileBrowserView`.
- Batch delete returns a named result with successful object IDs and per-object typed failures. Missing device identity is an operation-wide throw, not “every object failed”.

### Views

- `loadFiles()` handles `throws`: success-empty shows the existing empty view; failure preserves the last successful listing when available and presents the existing error alert.
- Create, single-delete and batch-delete call `FileSystemManager`; no direct Kalam calls remain.
- Cache invalidation occurs only after confirmed success. Batch delete invalidates once if at least one item succeeded and reports failed names through the existing alert.

## 8. Cache Contract

```text
CacheKey = app UUID + provider + MTPDeviceID + storageID + parentID
```

- TTL comes from `AppConfiguration.cacheExpirationInterval` (60 seconds).
- Only successful listing results are cached.
- A per-device generation is captured before I/O; a late response cannot populate cache after disconnect or write invalidation.
- `clearCache(for:)` removes only that device's entries and increments its generation.
- Create/delete success invalidates the affected device after the response is validated.
- Failure leaves current cache untouched but is never stored as a successful empty listing.

## 9. Diagnostics and UI Error Mapping

- `MTPLog.fileSystem` records operation, opaque device ID, storage/object ID, count, duration and typed error.
- Per-object warnings include object ID and error category.
- Logs exclude file content, full local paths and raw serial numbers.
- Manager integration maps `MTPCoreError` to existing `MTPError`/FileBrowser alert text. Error localization additions belong in all existing language tables only when a new user-visible string is unavoidable.

## 10. Validation and Rollback

- Unit: ObjectInfo/date/name codec and exact wire fixtures.
- Scripted transport: all data phases, response parameters and session invalidation matrix.
- Backend: Swift, Go migration adapter and coordinator identity contract.
- Native fallback: fake enumerator/opener tests for topology identity, exact open, token pinning, close/cleanup races and legacy transfer-symbol compatibility.
- Runtime lifecycle: no package-load worker/config snapshot; init is idempotent, cleanup joins, and re-init creates a fresh generation.
- Manager: MainActor scan state, actor cache, mapping, mutation invalidation and UI-facing error distinction.
- Hardware: sequential Go then Swift comparison; never run writes through both providers concurrently.

Rollback before cutover is selecting `.go` for a new session and reverting this child commit. Foundation/discovery code, libusb and the isolated Go fallback remain.

`MTPConnectionCoordinator` is the only production session owner. The unused
foundation-era `MTPBackendRouter` and router-only tests are removed rather than kept
as a competing lifecycle abstraction.

## 11. Primary Protocol Evidence

- AOSP `MtpDevice::getObjectHandles/getObjectInfo/sendObjectInfo/deleteObject`:
  <https://android.googlesource.com/platform/frameworks/base/+/6215d3f/media/mtp/MtpDevice.cpp>
- AOSP `MtpServer::doSendObjectInfo` response parameters and directory completion:
  <https://android.googlesource.com/platform/frameworks/base/+/ea1da3d/media/mtp/MtpServer.cpp>
- AOSP libmtp `ptp_sendobjectinfo` command/data/response contract:
  <https://android.googlesource.com/platform/external/libmtp/+/master/src/ptp.c>
