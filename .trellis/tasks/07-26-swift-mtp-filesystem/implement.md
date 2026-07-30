# Filesystem Migration Implementation Plan

## Preconditions

- [x] Confirm foundation and archived discovery/session verification satisfy blocking gates.
- [x] Confirm branch remains `refactor/swift-native-mtp` and production default remains Go.
- [x] Load `karpathy-guidelines`, `trellis-before-dev`, `project-exemption`, `moai-lang-swift`, and `build-macos-apps` before product-code edits.
- [x] Dispatch the exact-routing remediation through `trellis-implement`. Exact routing is implemented and verified; the main session still owns the repeat independent `trellis-check`.

## TDD Execution

### 1. ObjectInfo and operation contracts

- [x] RED: add exact literal ObjectInfo fixtures for file/folder, BMP/emoji Unicode, UTC/offset timestamps, sentinel size, empty optional strings, truncation, trailing bytes and malformed strings.
- [x] GREEN: complete `MTPObjectInfoDataset` encode/decode and map to `MTPObject`.
- [x] RED: add `GetObjectHandles` and `GetObjectInfo` exact command/data/response tests, including root, zero IDs, empty handles and invalid handles.
- [x] GREEN: implement typed read operations in `MTPDeviceSession`.
- [x] REFACTOR: keep wire schema separate from app/backend models.

### 2. Transaction data phases

- [x] RED: response-only command succeeds without a data container; required inbound data rejects response-first; outbound metadata writes command then data before response.
- [x] RED: preserve response parameters and reject wrong operation/TID/order, duplicate data/response, trailing containers and short OUT.
- [x] GREEN: add explicit `.none/.inbound/.outbound(Data)` phase and transport outbound metadata seam.
- [x] RED/GREEN: ordinary object response leaves session usable; transport/protocol/session errors invalidate it.
- [x] REFACTOR: document that large streaming payloads remain a separate transfer-child seam.

### 3. Swift filesystem session

- [x] RED: list root/multiple objects/empty directory and one recoverable object response failure.
- [x] RED: terminal handles, transport, protocol and malformed ObjectInfo failures abort the listing.
- [x] GREEN: implement `MTPDirectoryListing` and structured `MTPObjectFailure`.
- [x] RED/GREEN: implement folder creation exact ObjectInfo bytes and three response parameters.
- [x] RED/GREEN: implement delete and typed storage refresh.
- [x] Replace `SwiftMTPBackendSession` filesystem placeholders with open-session delegation.

### 4. Coordinator and provider runtime

- [x] RED: coordinator list/create/delete/refresh require active matching app UUID + transport ID + provider.
- [x] GREEN: add typed filesystem facade methods without exposing sessions to managers.
- [x] RED: Go Kalam boundary frees every non-nil string exactly once and maps success/error/invalid JSON without silent empty results.
- [x] GREEN: implement migration Go session adapter and centralized provider runtime.
- [x] Add `AppConfiguration.defaultMTPProvider = .go`; prove active session cannot switch provider.

### 4b. Exact Go fallback routing

- [x] RED: fake Native enumeration of two same-VID/PID devices with different port paths stays distinct across reversed order; missing port path fails closed.
- [x] GREEN: expose libusb port path through the vendored Go USB layer and add exact locator enumeration/open.
- [x] RED: exact open A never opens B; unknown/stale locator and disconnect fail explicitly.
- [x] GREEN: add opaque Native session registry/token and session-aware list/create/delete/refresh/close exports.
- [x] RED: interleaved A/B operations with colliding storage/object IDs cannot cross-read or cross-mutate; close is idempotent and cleanup/operation races are safe.
- [x] GREEN: bind `KalamMTPBackendSession` to the Native token and map structured errors/C-string ownership without retries.
- [x] Preserve legacy upload/download symbols and route them only through an unambiguous active exact session; do not migrate transfer algorithms or concurrency.
- [x] Run `cd Native && go test ./...`, `cd Native && go test -race ./...`, `./Scripts/build_kalam.sh`, header parity, dylib arch/link and symbol checks.

### 4c. Typed scan outcomes

- [x] RED: backend/runtime partial failures travel with successful snapshots; Go malformed JSON keeps a stable public error plus diagnostic context.
- [x] GREEN: replace concrete-backend side channel with `MTPScanResult`.
- [x] RED: transient timeout/decode/protocol failure preserves current device/session; successful disappearance or explicit disconnect performs cleanup.
- [x] GREEN: split DeviceManager successful scan, transient failure and explicit disconnect state transitions.
- [x] Replace real-time polling in DeviceManager tests with an awaitable completion seam.

### 5. DeviceManager integration

- [x] RED: two snapshots with repeated/reordered legacy indices keep separate stable app UUIDs via `MTPDeviceIdentity`.
- [x] RED: scan identity/reorder, selection, disconnect and coordinator registration preserve MainActor state rules; existing manager behavior retains failure/backoff coverage.
- [x] GREEN: inject typed scanner/runtime while preserving `shared`, public API, intervals and notifications.
- [x] Remove direct DeviceManager `Kalam_Init/Kalam_Scan` usage; keep Kalam implementation behind Go boundary.

### 6. FileSystemManager and cache

- [x] RED: mapping fields, legal empty vs thrown failure, failed listing not cached, cache hit, TTL with fake clock, device isolation and first-storage root behavior.
- [x] RED: generation prevents late list response from repopulating cache after invalidation.
- [x] RED: create/delete success invalidates affected device; failure leaves cache; batch partial success invalidates once.
- [x] GREEN: make `FileSystemManager` an injectable actor conforming to async `FileSystemManaging`.
- [x] Use centralized 60-second cache configuration and structured logging.

### 6b. Typed app filesystem IDs and batch result

- [x] RED/GREEN: operational `Device` requires `MTPDeviceIdentity`; preview uses an explicit valid fixture.
- [x] Carry `MTPStorageID`/`MTPObjectID` through `StorageInfo`, `FileItem`, filesystem protocol/manager and view actions without changing SwiftUI row UUID identity.
- [x] RED/GREEN: root/child destination uses a real typed storage ID; no root-object sentinel may be used as storage fallback.
- [x] Replace bare failed-ID array with a named batch-delete result containing successful IDs and per-object typed errors.
- [x] Cover device-scoped cache isolation and late-list suppression after scoped invalidation.

### 7. View action integration

- [x] Route `loadFiles`, create folder, single delete and batch delete through `FileSystemManaging`.
- [x] Reuse existing loading, empty, error alert and batch partial-failure UX.
- [x] Verify manager/FileBrowser production sources contain no direct `Kalam_ListFiles`, `Kalam_CreateFolder` or `Kalam_DeleteObject`.
- [x] Do not migrate upload/download paths in this child.

### 8. Differential and regression evidence

- [x] Add normalized provider fixtures for device/storage/object identity, names, sizes, types and modification dates.
- [ ] Run sequential Go/Swift read-only comparison when hardware is available.
- [ ] Create and delete one uniquely named Swift test folder only when hardware is available; record cleanup result.
- [x] Write `verification.md` with every AC, exact commands/counts, hardware state, default provider, libusb/Go retention and rollback state.

### 9. Quality-blocking ownership cleanup

- [x] Delete unused `MTPBackendRouter` and its dedicated tests; keep coordinator as the only production session owner.
- [x] Keep `FileSystemManaging` and the active narrow `MTPFileSystemCoordinating` injection seam; do not delete them as “dead protocols”.
- [x] Move Native live config and pool cleanup worker from package load into idempotent `Kalam_Init/Cleanup`; cleanup cancels and joins before disposing sessions/pool, and re-init creates fresh state.
- [x] Add Native lifecycle/race tests and repeat Go/Swift/build/artifact gates.

## Validation Commands

Focused tests use repository-safe ad-hoc signing:

```bash
xcodebuild test -project SwiftMTP.xcodeproj -scheme SwiftMTP \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:SwiftMTPTests/MTPObjectInfoDatasetTests \
  -only-testing:SwiftMTPTests/MTPFilesystemSessionTests \
  -only-testing:SwiftMTPTests/SwiftMTPFilesystemBackendTests \
  -only-testing:SwiftMTPTests/MTPConnectionCoordinatorFilesystemTests \
  -only-testing:SwiftMTPTests/DeviceManagerBackendTests \
  -only-testing:SwiftMTPTests/FileSystemManagerTests \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=

xcodebuild test -project SwiftMTP.xcodeproj -scheme SwiftMTP \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:SwiftMTPTests \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=
```

Build and static checks:

```bash
xcodebuild -project SwiftMTP.xcodeproj -scheme SwiftMTP \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project SwiftMTP.xcodeproj -scheme SwiftMTP \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build

xcodebuild analyze -project SwiftMTP.xcodeproj -scheme SwiftMTP \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO

git diff --check
```

Native/ABI checks required by exact routing:

```bash
(cd Native && go test ./...)
(cd Native && go test -race ./...)
./Scripts/build_kalam.sh
cmp -s Native/libkalam.h SwiftMTP/libkalam.h
file SwiftMTP/libkalam.dylib
lipo -archs SwiftMTP/libkalam.dylib
otool -L SwiftMTP/libkalam.dylib
nm -gU SwiftMTP/libkalam.dylib | rg ' _Kalam_'
```

Record the known default-universal Release failure caused by thin arm64 libusb/libkalam; do not expand this child to change distribution architecture.

## Review Gates

- Valid empty directory and terminal failure are observably distinct.
- Partial listing skips only recoverable object-level responses.
- All transactions remain serialized within one provider/device-fixed session.
- Go fallback scan/open/filesystem operations use stable topology locator + immutable native token; no unkeyed pool routing remains.
- Legacy transfer symbols never choose an arbitrary device and remain link-compatible.
- No stale in-flight response repopulates an invalidated cache.
- No mutation retries automatically after an ambiguous response.
- No cache invalidation happens before confirmed write success.
- Manager/view production code no longer calls filesystem `Kalam_*` directly.
- Default remains Go; libusb and Go/CGO/libkalam remain present.
- Focused/full tests, Debug/Release/Analyze, Go normal/race, native/ABI checks,
  and `git diff --check` pass with exact results recorded.

## Rollback Points

1. Codec/transaction: revert the phase/result types and new fixtures together.
2. Swift backend: keep filesystem methods unsupported while foundation/discovery remain usable.
3. Manager integration: restore the typed Go runtime as default; never switch an active session in place.
4. Full child: revert the child commit. Go/CGO/libkalam and libusb are still present, so rollback does not require rebuilding the native layer.
