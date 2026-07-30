# Native Swift MTP Discovery and Session Contract

## Scenario: Swift/libusb discovery foundation

### 1. Scope / Trigger

- Trigger: code under `Services/MTP/{Core,Transport,Backend}` talks directly to
  `libusb` and crosses the USB, MTP wire-protocol, backend-provider, and app-ID
  boundaries.
- Scope: device enumeration, endpoint selection, libusb lifecycle, MTP session
  transactions, discovery snapshots, and exact device routing.
- Current rollout boundary: `.swift` is the production default. The Go adapter
  remains compiled as a fallback boundary until its removal is explicitly
  approved; an active operation must never be replayed through another provider.
- Concurrency boundary: these blocking USB primitives use `DispatchQueue`,
  `NSLock`, and `NSCondition`. Do not migrate file-transfer code to Swift
  structured concurrency; that module has an explicit project exemption.

### 2. Signatures

```swift
protocol MTPBackend {
    func initialize() throws
    func scanDevices() throws -> MTPScanResult
    func openSession(for deviceID: MTPDeviceID) throws -> any MTPBackendSession
    func shutdown()
}

protocol MTPTransport {
    func transact(
        _ request: Data,
        cancellation: MTPCancellationToken
    ) throws -> [Data]
}

final class MTPConnectionCoordinator {
    func register(
        appDeviceID: UUID,
        snapshot: MTPDeviceSnapshot,
        providerKind: MTPProviderKind
    ) throws
    func selectDevice(_ appDeviceID: UUID) throws
    func refreshStorage(
        appDeviceID: UUID,
        deviceID: MTPDeviceID,
        storageID: MTPStorageID
    ) throws
    func close()
}
```

`SwiftMTPBackend` must keep injectable context, enumeration, and session
factories so lifecycle and multi-device routing can be tested without USB
hardware.

### 3. Contracts

- A native device ID is
  `swift:<bus>:<port-or-root>:<vendor-hex>:<product-hex>`, for example
  `swift:5:2.4:18d1:4ee1`. VID/PID alone is not a device identity.
- An accepted interface has exactly one bulk IN, one bulk OUT, and one
  interrupt IN endpoint. The normal class is Still Image (`0x06`);
  vendor-specific (`0xFF`) is temporarily accepted only with the same exact
  endpoint contract.
- USB endpoint shape creates only a PTP/MTP candidate. Before publishing a
  device snapshot, `DeviceInfo.OperationsSupported` must contain the operations
  used by the complete application path: `GetStorageIDs` (`0x1004`),
  `GetStorageInfo` (`0x1005`), `GetObjectHandles` (`0x1007`), `GetObjectInfo`
  (`0x1008`), `GetObject` (`0x1009`), `DeleteObject` (`0x100B`),
  `SendObjectInfo` (`0x100C`), and `SendObject` (`0x100D`). A PTP-only device is
  recorded as an isolated `unsupportedDevice` failure and scanning continues.
- `OpenSession` uses transaction ID `0`. The first ordinary operation uses
  transaction ID `1`. `CloseSession` uses the current transaction ID.
  Transaction IDs must never wrap into `0`.
- A transaction response must match the request transaction ID. A response
  before an expected data container, an invalid container size/type, or
  trailing/misaligned response data is a protocol violation.
- Bulk reads must support a header split across USB packets, short reads, and a
  zero-length packet. A short bulk OUT write is an error, never success.
- A retained `libusb_device` candidate is released exactly once. A transfer
  buffer and `libusb_transfer` stay alive until the terminal callback, including
  after cancellation.
- Shutdown order is:
  request transfer cancellation -> wait for terminal callbacks -> close claimed
  handles -> stop the event loop -> `libusb_exit`.
- `MTPConnectionCoordinator` owns at most one active session. Switching devices
  closes the old session and shuts down its backend before opening the new one.
  Every operation validates both the app UUID and immutable transport device ID.
- A terminal operation error (`noDevice`, disconnect, timeout, cancellation,
  USB/protocol failure, `sessionNotOpen`, or `invalidTransactionID`) invalidates
  and closes the active session/backend exactly once. Recoverable response codes
  and local file I/O failures keep the selected session active.
- Scanning may return healthy devices while recording per-device or per-storage
  failures in `MTPScanResult.failures`. Identity collisions fail closed.

### 4. Validation & Error Matrix

| Condition | Required result |
| --- | --- |
| Empty device ID or zero storage/object ID | `MTPCoreError.invalidInput` or `invalidIdentifier` |
| libusb access denied | `permissionDenied` |
| libusb busy | `busy` |
| device removed / terminal `NO_DEVICE` | `disconnected` |
| timeout / cancellation | `timeout` / `cancelled` |
| unsupported endpoint set | omit the candidate; do not leak a device reference |
| PTP candidate missing required file-transfer operations | record an isolated `unsupportedDevice` failure; continue scanning |
| duplicate native stable ID | fail closed with `protocolViolation` |
| wrong response transaction ID or container order | `protocolViolation` and invalidate the MTP session |
| failed `OpenSession` | permanently invalidate that session instance |
| unknown app UUID | `noDevice` |
| operation does not match active app UUID and device ID | `disconnected` |
| provider factory missing | `unsupportedDevice` |
| operation on a closed backend session | `disconnected` |

### 5. Good / Base / Bad Cases

- Good: two phones with the same VID/PID but different port paths are scanned,
  registered under different app UUIDs, and reopened by their exact native IDs.
- Good: an iPhone PTP session may open and return storage metadata, but it is
  omitted when it lacks `SendObjectInfo`/`SendObject`; a healthy Android MTP
  device from the same scan remains visible.
- Base: an empty USB bus yields an empty scan result and no retained candidates.
- Good partial failure: one storage query fails, the device and healthy storages
  remain visible, and the failure includes device ID, storage ID, stage, and
  typed error.
- Bad: reconnecting by array index, VID/PID only, or "first matching device".
- Bad: freeing a cancelled transfer immediately after `libusb_cancel_transfer`;
  cancellation is complete only when its terminal callback arrives.
- Bad: reusing an `MTPDeviceSession` after `OpenSession` or protocol validation
  fails.

### 6. Tests Required

- Dataset decoding: device info, storage IDs/info, malformed and truncated data,
  and `Data` slices whose `startIndex` is not zero.
- Interface selection and enumeration: exact endpoint set, unsupported class,
  unreadable descriptors/configurations, port overflow, reference cleanup, and
  two-device stable-ID uniqueness.
- Libusb lifecycle: initialize/exit idempotence, claim/alternate-setting cleanup,
  submit failure, cancel-before-submit, cancel-after-submit, callback-after-
  cancel, handle close, and context shutdown ordering.
- Transport: split header, short read, zero-length packet, short OUT, malformed
  length/type, wrong transaction ID, and response-before-data.
- Session: Open/Close transaction IDs, first ordinary ID, failed-open
  invalidation, response-code propagation, and overflow without wrapping to
  zero.
- Backend/coordinator: partial scan failures, storage failures, identity
  collision, inspection-session cleanup, exact re-enumeration, provider/device
  mismatch, PTP capability rejection, repeated selection, switching devices,
  and idempotent close.
- Before archive: focused tests, all `SwiftMTPTests`, arm64 Debug and Release
  builds, arm64 Analyze, and `git diff --check`.

### 7. Wrong vs Correct

#### Wrong

```swift
libusb_cancel_transfer(transfer)
libusb_free_transfer(transfer) // Callback may still access it.

let candidate = devices.first { $0.vendorID == vendor && $0.productID == product }
```

#### Correct

```swift
requestCancellation()
waitForTerminalCallback()
freeTransferAndBuffer()

let candidate = devices.singleMatch { $0.interface.deviceID == requestedDeviceID }
```

The exact-ID lookup must fail when there is no match or more than one match.

## Scenario: Provider-Bound File Transfers

### 1. Scope / Trigger

- Trigger: a single-file or directory upload/download crosses
  `FileTransferManager`, `MTPConnectionCoordinator`, a provider session, or the
  Go transfer ABI.
- `FileTransferManager` keeps the project-exempt traditional
  `DispatchQueue`/`NSLock` model. Transfer work must not be migrated to actors,
  `AsyncStream`, or an otherwise structured-concurrency state machine.
- The production provider defaults to `.swift`. The Go transfer adapter remains
  available only as a pinned fallback provider until explicit removal approval.

### 2. Signatures

```c
GoInt32 Kalam_PrepareTransferTask(char *taskID);
GoInt32 Kalam_AbortTransferTask(char *taskID);
void Kalam_CancelTask(char *taskID);

char *Kalam_DownloadFileSession(
    char *token,
    GoUint32 objectID,
    char *destinationPath,
    char *taskID,
    uintptr_t progressCallback,
    uintptr_t progressContext
);

char *Kalam_UploadFileSession(
    char *token,
    GoUint32 storageID,
    GoUint32 parentID,
    char *sourcePath,
    char *name,
    GoUint64 size,
    char *taskID,
    uintptr_t progressCallback,
    uintptr_t progressContext
);
```

The Swift Go adapter owns this lifecycle:

```text
prepare task -> install cancellation callback -> claim in session transfer
             -> terminal finish in Go -> invalidate callback -> abort if unclaimed
```

Legacy transfer exports remain linkable and atomically register plus claim their
task when the old transfer function starts. New session transfers require the
explicit prepare step.

### 3. Contracts

- Every transfer is pinned to one immutable app UUID, provider, transport
  device ID, storage/object identity, open session, and task-scoped
  cancellation token. A submitted operation is never replayed through another
  provider.
- The coordinator validates the complete identity before forwarding. Go
  transfer calls carry the exact native session token and fail closed for
  unknown, stale, missing, or ambiguous sessions.
- Each new Go session transfer uses a non-empty task ID and calls
  `Kalam_PrepareTransferTask` before installing its cancellation callback.
  Prepare creates exactly one `prepared` entry; duplicate prepare fails without
  replacing the existing entry.
- A session transfer atomically claims its prepared entry. A missing or already
  claimed entry fails closed before USB or file I/O starts. Cancellation may
  mark either a prepared or claimed entry, so cancellation delivered between
  callback registration and claim is not lost.
- `Kalam_CancelTask` never creates registry state. Cancelling an unknown,
  aborted, or terminal task is a strict no-op. Terminal completion removes the
  claimed entry exactly once, and the same task ID may later begin with clean
  state.
- `Kalam_AbortTransferTask` removes only an unclaimed prepared entry. The Swift
  adapter invalidates its callback and invokes abort on every prepared exit
  path; abort after claim or terminal completion is an idempotent no-op.
- Cancellation state must not rely on tombstones, TTLs, capacity limits, or
  timing windows. Registry state exists only for a prepared or claimed
  operation.
- libusb cancellation requests termination only. Transfer buffers, callback
  boxes, file resources, handle leases, and sessions remain alive until the
  terminal callback.
- Downloads write a sibling temporary file and replace the destination only
  after protocol success and byte-count validation. Empty files are valid;
  failed or cancelled downloads preserve any existing destination and remove
  the temporary file.
- Upload metadata uses `0xFFFFFFFF` as the non-exact ObjectInfo size sentinel.
  Streaming data containers use the streaming sentinel when their payload
  exceeds `0xFFFFFFF3`; neither sentinel is an exact file size.
- Once `SendObjectInfo` returns an object handle, cancellation, source-read
  failure, and `SendObject` failure attempt a best-effort delete. Cleanup
  failure is attached to diagnostics without replacing the primary typed
  failure, and the mutation is never retried automatically.
- Directory upload is serial and task-scoped. It uploads regular files only,
  owns an isolated cancellation token and folder cache, and reports explicit
  success, failure, cancellation, or partial outcome through one finalization
  boundary.
- Directory preflight/root routing and per-entry execution may live in
  separate collaborators, but they must share the same immutable request,
  cancellation token, folder router, mutation summary, and finalizer. A
  structural split must not create a second operation state machine.
- Kalam ABI/session adapter sources are grouped under `Backend/Go`; moving or
  splitting them relies on Xcode synchronized filesystem membership and must
  be verified with an executed test action after every structural change.
- Only an operation that may have mutated the remote device refreshes storage,
  invalidates the device-scoped cache, and emits the typed UI refresh event.
  Every task reaches exactly one terminal state.

### 4. Validation & Error Matrix

| Condition | Required result |
| --- | --- |
| Empty or nil task ID during prepare | return failure; create no registry state |
| Duplicate prepare | fail without replacing or cancelling the existing task |
| Session transfer without prepare | typed invalid-input response; no USB or file I/O |
| Cancel while prepared | retain the cancellation bit; claim observes cancellation |
| Cancel while claimed | request cancellation of that operation only |
| Cancel after abort or terminal finish | strict no-op; never recreate state |
| Abort while prepared | remove the entry and return success exactly once |
| Abort while claimed, absent, or terminal | idempotent no-op |
| Duplicate claim | fail closed; do not start a second transfer |
| Reuse task ID after abort or finish | create a fresh, uncancelled prepared entry |
| Nil or malformed Go response | throw a typed adapter error, free any returned C string, and clean up the prepared lifecycle |
| Transfer failure after remote mutation may have begun | preserve the provider and primary typed failure; never replay through another provider |

### 5. Good / Base / Bad Cases

- Good: cancellation fires after prepare but before the session ABI claims the
  task; the claimed operation observes cancellation and terminates normally.
- Base: prepare, claim, transfer, and terminal finish leave no registry entry;
  the Swift deferred abort is harmless.
- Good reuse: a task ID can be prepared again after abort or terminal finish
  without inheriting cancellation.
- Bad: registering the Swift callback before prepare, because an immediate
  cancellation could be lost.
- Bad: creating a cancelled entry for an unknown task ID, or retaining terminal
  tombstones to reject late cancellation.
- Bad: retrying an upload or download automatically through the other provider
  after an ambiguous or mutating failure.

### 6. Tests Required

- Provider/coordinator: exact identity and token forwarding, wrong or stale
  identity rejection, and no provider replay.
- Cancellation registry: prepare/claim, pre-claim and mid-operation cancel,
  duplicate prepare/claim, prepared abort, finish/cancel races, strict late
  cancel no-op, terminal cleanup, and clean task-ID reuse under `go test` and
  `go test -race`.
- Go adapter: prepare-before-registration ordering, cancellation in the
  prepare/registration window, prepare failure, nil response, callback
  invalidation, and exactly-once exit cleanup.
- Native upload: source policy, pre/mid cancellation, object allocation,
  compensation success/failure, and primary-error preservation under `go test`
  and `go test -race`.
- Swift transfer: framing sentinels, fragmented headers, empty/large files,
  source/sink errors, timeout/disconnect/cancel races, atomic download
  finalization, and orphan cleanup.
- Manager/directory: observable submission rejection, progress, queued/running
  cancellation, isolated concurrent operations, partial summary, single
  finalization, and mutation-sensitive refresh.
- Before archive: full Swift tests, arm64 Debug/Release/Analyze, Go
  test/race/vet, generated-header parity, dylib ABI checks, and
  `git diff --check`. Hardware parity remains a separate explicit gate when no
  Android device is available.

### 7. Wrong vs Correct

#### Wrong

```go
state := registry.states[taskID]
if state == nil {
    state = &transferCancellationState{}
    registry.states[taskID] = state // A late cancel recreates stale state.
}
state.cancelled.Store(true)
```

#### Correct

```go
state := registry.states[taskID]
if state == nil {
    return false
}
state.cancelled.Store(true)
return true
```

Prepare is the only operation that creates a new task entry. Claim changes its
phase, abort removes an unclaimed entry, and terminal finish removes the exact
claimed entry.

## Scenario: Filesystem Operations and Exact Go Fallback Sessions

### 1. Scope / Trigger

- Trigger: list/create/delete/refresh crosses SwiftUI, actor cache, provider
  coordination, the Go C ABI, or Swift MTP transactions.
- The production default remains `.go` until transfer migration is complete.
  A selected session never changes provider or transport identity in place.

### 2. Signatures

```swift
protocol MTPBackendSession: AnyObject {
    func listObjects(
        storageID: MTPStorageID,
        parentID: MTPObjectID
    ) throws -> MTPDirectoryListing
    func createFolder(
        storageID: MTPStorageID,
        parentID: MTPObjectID,
        name: String
    ) throws -> MTPObjectID
    func deleteObject(_ objectID: MTPObjectID) throws
    func refreshStorage(_ storageID: MTPStorageID) throws -> MTPStorage
}
```

The Go fallback exports `Kalam_ScanResult`, `Kalam_OpenSession`, token-bearing
`Kalam_*Session` filesystem calls, and `Kalam_CloseSession`. Managers and views
must not call these symbols directly. `Kalam_ScanResult` returns the typed
`devices` and `failures` envelope; the legacy array-returning `Kalam_Scan`
remains unchanged only for the un-migrated transfer compatibility path.

### 3. Contracts

- Go device identity is
  `go:<bus>:<complete-port-path>:<vendor-hex>:<product-hex>`. Missing topology
  fails closed; address, serial, enumeration index, and VID/PID alone are not
  reconnect keys.
- Exact open returns a random process-local token. List, create, delete,
  refresh, and close carry that immutable token.
- A successful list response contains `files` plus zero or more `failures`.
  Each failure contains `storageId`, `parentId`, `objectId`,
  `stage = "object_info"`, and `error = "invalid_object_handle"`.
- Only `InvalidObjectHandle` is a recoverable per-object response. Transport,
  protocol, session, and every other MTP response terminate the listing.
- Cache keys include app UUID, provider/device identity, storage, and parent.
  Only successful listings are cached; confirmed mutations invalidate after
  success, and a generation prevents late responses from repopulating cache.
  A submitted single-object delete that fails invalidates only the selected
  device cache before rethrowing the typed error, because the listed handle may
  already be stale. The mutation is never replayed automatically.
- `Scripts/build_kalam.sh` builds with vendored Go dependencies and the
  repository-pinned `SwiftMTP/libusb-1.0.dylib` and CLibUSB header. It must not
  replace them with a local Homebrew libusb.

### 4. Validation & Error Matrix

| Condition | Required result |
| --- | --- |
| Unknown or stale Go token | `disconnected` |
| Missing/ambiguous USB topology | fail exact scan/open; no fallback |
| `GetObjectInfo` returns `InvalidObjectHandle` | retain other objects and emit one typed warning |
| Any other object-info error | throw; do not cache a partial success |
| `sessionNotOpen` / `invalidTransactionID` during batch delete | stop the batch, invalidate the active session, and throw |
| Create/delete response is ambiguous or failed | throw; never replay mutation |
| Successful create/delete | invalidate the affected device cache once |
| Failed create | preserve current cache |
| Failed single-object delete | invalidate the selected device cache, rethrow the typed error, and never retry |
| Cleanup races an operation | wait for the operation lock; dispose once |

### 5. Good / Base / Bad Cases

- Good: two devices with identical VID/PID but different port paths keep
  separate tokens even when enumeration order changes.
- Base: an empty handles array is a successful empty directory.
- Good partial failure: one stale object handle produces one warning and the
  remaining objects.
- Bad: swallowing disconnect as a skipped file, routing through the old
  unkeyed pool, or retrying a mutation after an ambiguous response.

### 6. Tests Required

- Native: locator round-trip/order, exact open, A/B token isolation,
  unknown/stale/disconnected tokens, close/cleanup races, and legacy transfer
  fail-closed routing.
- Provider adapter: token forwarding, C-string free-once on every decode path,
  partial failure decoding, and mismatched warning metadata rejection.
- Filesystem: empty versus terminal failure, mutation invalidation, cache TTL,
  device isolation, and late-response generation.
- Artifact: Go normal/race tests, generated-header parity, arm64/minimum OS,
  `@rpath` dependencies, exported legacy/new symbols, and CLibUSB 1.0.29 smoke.

### 7. Wrong vs Correct

#### Wrong

```go
if err := device.GetObjectInfo(handle, &info); err != nil {
    continue // Disconnects and protocol failures become false success.
}
```

#### Correct

```go
if err := device.GetObjectInfo(handle, &info); err != nil {
    if isInvalidObjectHandleError(err) {
        failures = append(failures, warningFor(handle))
        continue
    }
    return nativeDirectoryListing{}, err
}
```
