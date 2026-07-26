# Native Swift MTP Discovery and Session Contract

## Scenario: Swift/libusb discovery foundation

### 1. Scope / Trigger

- Trigger: code under `Services/MTP/{Core,Transport,Backend}` talks directly to
  `libusb` and crosses the USB, MTP wire-protocol, backend-provider, and app-ID
  boundaries.
- Scope: device enumeration, endpoint selection, libusb lifecycle, MTP session
  transactions, discovery snapshots, and exact device routing.
- Current rollout boundary: `.go` remains the production provider until a later
  cutover task. Do not wire `SwiftMTPBackend` into production managers merely
  because this foundation exists.
- Concurrency boundary: these blocking USB primitives use `DispatchQueue`,
  `NSLock`, and `NSCondition`. Do not migrate file-transfer code to Swift
  structured concurrency; that module has an explicit project exemption.

### 2. Signatures

```swift
protocol MTPBackend {
    func initialize() throws
    func scanDevices() throws -> [MTPDeviceSnapshot]
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
- Scanning may return healthy devices while recording per-device or per-storage
  failures in `lastScanFailures`. Identity collisions fail closed.

### 4. Validation & Error Matrix

| Condition | Required result |
| --- | --- |
| Empty device ID or zero storage/object ID | `MTPCoreError.invalidInput` or `invalidIdentifier` |
| libusb access denied | `permissionDenied` |
| libusb busy | `busy` |
| device removed / terminal `NO_DEVICE` | `disconnected` |
| timeout / cancellation | `timeout` / `cancelled` |
| unsupported endpoint set | omit the candidate; do not leak a device reference |
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
  mismatch, repeated selection, switching devices, and idempotent close.
- Before archive: focused tests, all `SwiftMTPTests`, arm64 Debug and Release
  builds, arm64 Analyze, `git diff --check`, and `desloppify scan --path .` with
  `Open: 0`.

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
