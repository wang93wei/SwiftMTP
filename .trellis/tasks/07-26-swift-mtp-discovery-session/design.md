# Discovery and Session Design

## Dependency

Requires the complete, verified `07-26-swift-mtp-foundation` artifacts and code.

## Components

- `LibUSBContext`: owns `libusb_context`, initialization, event queue/thread and shutdown state.
- `USBDeviceEnumerator`: converts descriptor/config/interface/endpoint data into stable Swift candidates.
- `LibUSBDeviceHandle`: owns open handle, selected configuration, claimed interface and endpoint metadata.
- `LibUSBTransfer`: owns one async transfer, buffer, callback context and terminal state.
- `MTPDeviceSession`: owns MTP session ID, next transaction ID and serial operation queue.
- `SwiftMTPBackend.scanDevices`: opens candidates sequentially, fetches device/storage information, returns snapshots containing `MTPDeviceID`, then closes temporary inspection sessions.
- `MTPConnectionCoordinator`: maps app `Device.id` to the selected snapshot identity and one open provider-fixed `MTPBackendSession`.

## Stable Identity

The transport identity uses bus number + port path + vendor/product ID and may include a serial only after successful open. Every snapshot carries this opaque `MTPDeviceID`. The UI-facing UUID cache maps it to a stable UUID; raw device index is not treated as a durable identity.

Selecting a device asks the coordinator to close any prior session and call the chosen backend's `openSession(for:)` with that exact snapshot identity. Filesystem/transfer calls resolve the session by app `Device.id` and verify the transport ID. Tests use two candidates with different scripted responses to prove no cross-device routing.

## Event Loop

The shared context runs `libusb_handle_events_timeout_completed` on a dedicated queue/thread. Each async transfer uses one `@convention(c)` callback with an `Unmanaged` context whose retain/release is paired exactly once. Shutdown first rejects new submissions, cancels active transfers and waits for terminal callbacks before exiting the context.

## Session State

```text
idle → opened → claimed → sessionOpen → closing → closed
                    ↘ disconnected / failed
```

- Session ID excludes 0 and `0xFFFFFFFF`.
- OpenSession command and response use transaction ID `0`.
- Only after OpenSession succeeds does the next transaction ID become `1`; CloseSession consumes the current in-session ID.
- Transaction IDs increment once per in-session command.
- Only the session serial queue reads or mutates session/transaction state.
- Transaction mismatch, malformed response, USB disconnect or unrecoverable I/O closes and invalidates the session.
- Retry creates a fresh session; it never overlaps or reuses an active/invalid transfer.

## Scan Semantics

Enumeration can return multiple MTP candidates because `DeviceManager` already models an array. Unsupported interfaces are ignored with debug diagnostics. A candidate that opens but fails device/storage queries produces a structured per-device failure; storage failures do not corrupt successfully decoded device identity. Inspection sessions are closed after scan; later operations reopen only the selected `MTPDeviceID`.

The production UI remains on Go by default. Swift scan is exercised through unit tests, a diagnostic entry point and optional developer provider selection that is fixed when a session begins.
