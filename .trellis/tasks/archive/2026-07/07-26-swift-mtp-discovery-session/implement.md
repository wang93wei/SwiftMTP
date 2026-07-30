# Discovery and Session Implementation Plan

## TDD Checklist

- [ ] Add failing tests for descriptor/config/interface/endpoint selection, including alternate settings and unsupported interfaces.
- [ ] Implement pure descriptor mapping and MTP candidate detection.
- [ ] Add failing tests for context init/exit, device open/configuration/claim errors and reverse-order cleanup using a libusb function table/test double.
- [ ] Implement `LibUSBContext`, `USBDeviceEnumerator` and RAII-style handle ownership.
- [ ] Add failing async-transfer lifetime tests: submit, complete, cancel, disconnect and shutdown while active.
- [ ] Implement event loop, callback trampoline and `LibUSBTransfer` ownership.
- [ ] Add failing MTP session tests proving OpenSession command/response TID `0`, first in-session command TID `1`, CloseSession current TID, already-open recovery and invalidation.
- [ ] Implement the serial `MTPDeviceSession`.
- [ ] Add failing transaction tests for command/data/response ordering, response codes, transaction mismatch, split header, short read and zero-length packet.
- [ ] Implement transaction execution over `LibUSBTransport`.
- [ ] Add failing dataset tests for DeviceInfo, StorageIDs and StorageInfo.
- [ ] Implement scan and typed snapshots in `SwiftMTPBackend`.
- [ ] Add failing two-device snapshot→selection→session tests proving the selected transport ID is reopened, the previous session closes and operations never route to the other candidate.
- [ ] Implement `MTPConnectionCoordinator` and explicit `openSession(for:)`.
- [ ] Add provider/session tests proving Go and Swift cannot mix within one open session.
- [ ] Add lifecycle and failure logs with safe opaque device identifiers.
- [ ] Write `verification.md` with AC, command/test counts, hardware state, provider default and rollback commit.

## Validation

```bash
xcodebuild test -project SwiftMTP.xcodeproj -scheme SwiftMTP -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
xcodebuild -project SwiftMTP.xcodeproj -scheme SwiftMTP -configuration Debug build
xcodebuild -project SwiftMTP.xcodeproj -scheme SwiftMTP -configuration Release build
git diff --check
```

The child cannot commit unless focused/full tests, Debug/Release builds,
Analyze, and `git diff --check` pass; record exact commands and results in
`verification.md`.

Hardware gate when available:

1. Scan an unlocked Android device in MTP mode.
2. Verify model/manufacturer/storage values.
3. Close and reconnect repeatedly.
4. Confirm busy/claimed and physical disconnect errors are diagnosable.

## Review Gate

- No active transfer can outlive its buffer/context/handle.
- No claim error is ignored.
- No transaction can overlap another on the same session.
- Hardware evidence is labeled separately from fake-transport evidence.
- Production default remains Go.

## Rollback

Disable Swift provider selection and remove the discovery/session implementation. Foundation code and Go production behavior remain intact.
