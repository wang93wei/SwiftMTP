# Discovery and Session Verification

Date: 2026-07-27

## Outcome

- Implemented libusb context, handle and asynchronous transfer ownership.
- Implemented C descriptor enumeration, MTP interface selection and stable transport identity.
- Implemented bulk transaction framing, MTP session state, discovery scan, exact-ID reopen and app UUID connection coordination.
- Production managers and the default Go path remain unchanged.

## Acceptance Criteria Matrix

| PRD acceptance criterion | Result | Evidence |
|---|---|---|
| Enumeration, endpoint selection, claim errors and cleanup | PASS | Interface-selector, enumerator and lifecycle suites cover supported/unsupported descriptors, busy/no-device/permission, candidate references and cleanup order |
| Open/CloseSession transaction IDs and protocol validation | PASS | Session tests cover OpenSession TID 0, first ordinary TID 1, CloseSession current TID, mismatch, unexpected order and invalidation |
| Device/storage dataset decoding and typed mapping | PASS | DeviceInfo, StorageIDs and StorageInfo binary fixtures plus scan mapping tests pass |
| Transfer/buffer/handle lifetime through terminal callback | PASS | Cancel/shutdown race tests prove terminal callback precedes free/release/exit |
| No/single/multiple device scan and partial storage failure diagnostics | PASS | Swift backend tests cover empty, exact-ID devices, unsupported interfaces, per-device and per-storage failures |
| Two-device snapshot selection cannot cross-route | PASS | Exact stable-ID reopen and coordinator switch tests close the old session and open only the requested candidate |
| Android scan/open/close evidence | PASS (status recorded as unavailable) | No hardware was available; the Hardware section explicitly records NOT RUN and no interoperability claim |
| Xcode build, all Swift tests and Go default path | PASS | 67/67 tests, arm64 Debug/Release and Analyze pass; production managers/default remain Go |

## Acceptance Evidence

- Context shutdown rejects new work, cancels active transfers, waits for terminal callbacks, closes open handles, then calls `libusb_exit`.
- Handle close waits for owned transfers before release-interface/close.
- Enumeration covers configuration/interface/alternate/endpoint mapping, unsupported interfaces, descriptor failures, retained candidate references and port-path overflow.
- OpenSession uses TID 0; the first production in-session TID is 1; TIDs never wrap back to 0.
- Split headers, short reads and ZLP are framed by declared MTP container length; short bulk OUT fails before an IN submission.
- Failed open/protocol/USB transactions invalidate the session and require a fresh instance.
- Scan keeps successful device/storage data and records typed per-device/per-storage failures.
- Re-enumeration matches exactly one stable ID; missing IDs and identity collisions fail closed.
- Two-device tests prove enumeration order does not affect exact reopen and coordinator switching closes the old session first.

## Commands Run

Focused discovery/session suite:

```bash
xcodebuild test -project SwiftMTP.xcodeproj -scheme SwiftMTP \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:SwiftMTPTests/LibUSBLifecycleTests \
  -only-testing:SwiftMTPTests/LibUSBTransferTests \
  -only-testing:SwiftMTPTests/USBDeviceEnumeratorTests \
  -only-testing:SwiftMTPTests/LibUSBTransportTests \
  -only-testing:SwiftMTPTests/MTPDeviceSessionTests \
  -only-testing:SwiftMTPTests/SwiftMTPBackendTests \
  -only-testing:SwiftMTPTests/MTPConnectionCoordinatorTests \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=
```

Result: PASS, 30 tests, 0 failures.

All Swift tests:

```bash
xcodebuild test -project SwiftMTP.xcodeproj -scheme SwiftMTP \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:SwiftMTPTests \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=
```

Result: PASS, 67 tests, 0 failures.

arm64 Debug build:

```bash
xcodebuild -project SwiftMTP.xcodeproj -scheme SwiftMTP \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO build
```

Result: BUILD SUCCEEDED.

Source hygiene:

```bash
git diff --check
```

Result: PASS.

## Hardware and Packaging State

- Android hardware scan/open/close: NOT RUN; no hardware evidence is claimed.
- Production provider: Go remains the default through the existing managers.
- Swift provider: available only through the new test/development backend seam.
- Default universal Release/DMG remains outside this child scope: tracked
  `libusb-1.0.dylib` and `libkalam.dylib` are arm64-only, so the existing
  default `arm64 x86_64` Release link is a known packaging conflict.

## Final Trellis Check

- Independent focused suite: PASS, 30 tests, 0 failures.
- Independent full Swift suite: PASS, 67 tests, 0 failures.
- arm64 Debug build: PASS.
- arm64 Release build with `ARCHS=arm64 ONLY_ACTIVE_ARCH=YES`: PASS.
- arm64 Debug `xcodebuild analyze`: PASS.
- Default universal Release: expected existing failure, exit 65; both tracked
  dylibs are arm64-only and the x86_64 link reports missing `Kalam_*`/libusb
  symbols. No packaging architecture change was made in this task.
- `git diff --check`: PASS.

The check consolidated repeated libusb candidate/handle setup into
`SwiftMTPTests/MTP/Doubles/MTPUSBFixtures.swift`; focused and full tests stayed
green after the change.

## Rollback

Rollback to the verified foundation baseline commit `e4a019b`, or remove the
Swift discovery/session provider seam. The unchanged Go manager path remains
the production fallback.
