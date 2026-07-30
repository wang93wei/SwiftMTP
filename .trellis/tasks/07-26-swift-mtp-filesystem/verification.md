# Filesystem Migration Verification

Date: 2026-07-30
Branch: `refactor/swift-native-mtp`
Commit/push: not performed; rollback is the uncommitted child diff until the main session creates a commit.

## Outcome

- Production default remains `AppConfiguration.defaultMTPProvider = .go`.
- Swift filesystem operations are available only through an explicitly selected Swift runtime for a new session.
- Coordinator facade sessions and the live Go fallback are fixed to app UUID,
  provider, canonical topology `MTPDeviceID` and an opaque Native session token.
- `DeviceManager`, `FileSystemManager` and FileBrowser list/create/delete paths use typed runtime/coordinator boundaries.
- Upload/download/cancel were not migrated. `FileTransferManager` keeps its project-exempt traditional concurrency model.
- CLibUSB, `LibUSBTransport`, Go/CGO and `libkalam` remain present. No IOKit replacement was introduced.

## Acceptance Criteria

| AC | Result | Evidence |
|---|---|---|
| AC1 | PASS | ObjectInfo literal wire, file/folder, BMP/emoji, UTC/offset, sentinel, empty strings and malformed inputs pass in `MTPObjectInfoDatasetTests`. |
| AC2 | PASS | Existing transaction tests plus filesystem session and short outbound metadata transport tests cover all three phases, response parameters, ordering/TID/operation failures and invalidation behavior. |
| AC3 | PASS | Swift backend tests distinguish legal empty listings, partial object response failures and terminal listing failures. |
| AC4 | PASS | Folder metadata bytes and missing/mismatched/zero response parameter cases pass. |
| AC5 | PASS | Exact delete, invalid identifiers, response/transport errors and typed storage refresh are covered by session/backend suites. |
| AC6 | PASS | Go, Swift and fake contracts pass. Native covers same-VID/PID paths, reversed enumeration, exact open, colliding IDs, stale/unknown tokens, disconnect/reconnect, idempotent close, cleanup races and legacy transfer fail-closed routing. Swift proves token forwarding and free-once ownership. |
| AC7 | PASS | Live-shaped Go snapshots use canonical bus + complete port path + VID + PID identities; repeated/reordered candidates retain distinct app UUIDs and published manager state is `@MainActor`. |
| AC8 | PASS | Mapping, empty/failure, cache hit, TTL, device isolation, root-without-storage, mutation invalidation and late-response generation tests pass. |
| AC9 | PASS | `rg` finds no filesystem `Kalam_*` calls in `DeviceManager`, `FileSystemManager` or `SwiftMTP/Views`; UI errors remain on existing alert paths. |
| AC10 | PASS | Default and shared runtime remain Go. Exact open produces a process-local token; filesystem and legacy transfer operations cannot route through the old unkeyed pool. |
| AC11 | PASS | libusb/CLibUSB/LibUSBTransport and Go/CGO/libkalam remain; no IOKit path was added. |
| AC12 | PASS | Focused/full tests, Debug/Release/Analyze, Go normal/race/vet, native/ABI checks, and `git diff --check` pass. |
| AC13 | UNAVAILABLE | No Android hardware was available. No real-device parity, create/delete interoperability or cutover claim is made. |
| AC14 | PASS | Duplicate router and dead service seams were removed; Native init/cleanup/re-init owns worker lifecycle and passes normal/race tests. |

## Automated Evidence

1. Focused filesystem suites:

   `xcodebuild test ...` with the six task suites and repository-safe ad-hoc signing.

   Result: **36 tests, 0 failures** across the six task suites plus
   `GoMTPBackendTests`, including typed partial scan failures, token forwarding,
   free-once ownership and mismatched metadata rejection.

2. Full unit suite:

   `xcodebuild test -project SwiftMTP.xcodeproj -scheme SwiftMTP -destination 'platform=macOS,arch=arm64' -only-testing:SwiftMTPTests CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=`

   Result: **98 tests, 0 failures**.

3. Debug build:

   `xcodebuild -project SwiftMTP.xcodeproj -scheme SwiftMTP -configuration Debug -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build`

   Result: **BUILD SUCCEEDED**.

4. arm64 Release build:

   `xcodebuild -project SwiftMTP.xcodeproj -scheme SwiftMTP -configuration Release -destination 'platform=macOS,arch=arm64' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build`

   Result: **BUILD SUCCEEDED**.

5. Analyze:

   `xcodebuild analyze -project SwiftMTP.xcodeproj -scheme SwiftMTP -configuration Debug -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO`

   Result: **ANALYZE SUCCEEDED**.

6. Static source checks:

   - `git diff --check`: PASS.
   - `go vet ./...` and `gofmt -d` on changed Native Go files: PASS. The
     independent check also removed an `atomic.Bool` by-value copy reported by
     `go vet`.
   - SwiftLint: UNAVAILABLE (`swiftlint` is not installed); no lint result is
     claimed.
   - Branch: `refactor/swift-native-mtp`.
   - Manager/FileBrowser filesystem `Kalam_*` search: zero matches.
   - DeviceManager `Kalam_Init/Kalam_Scan` search: zero matches.

7. Native exact-routing suites:

   - `cd Native && go test -count=1 ./...`: **30 tests, 0 failures**.
   - `cd Native && go test -race -count=1 ./...`: **30 tests, 0 failures; race detector clean**.
   - `./Scripts/build_kalam.sh`: PASS; generated headers synchronized.
   - `file` / `lipo -archs`: arm64 Mach-O dylib.
   - `otool -L`: `@rpath/libkalam.dylib` and repository-pinned
     `@rpath/libusb-1.0.dylib` compatibility/current `6.0.0`.
   - `vtool -show-build`: `libkalam.dylib` minimum macOS `26.0`, SDK `27.0`.
   - `nm -gU`: new session-aware exports and legacy download/upload/cancel exports present.
   - The build script uses only repository-pinned libusb/header and vendored Go
     dependencies; it performs no Homebrew copy and no network dependency mutation.
   - Repository libusb worktree and `HEAD` SHA-256 both equal
     `613323821e70b4c7f22268535707706ef4ccc18c6777215e42a8bca8bc02cec1`.
   - `CLibUSBSmokeTests`: **1 test, 0 failures**.

## Independent Fixes

- Made MTP timestamp parsing strict so impossible calendar dates are rejected.
- Restricted partial ObjectInfo listing recovery to `invalidObjectHandle`; other MTP
  responses now terminate the listing.
- Preserved recoverable Go ObjectInfo failures as typed `MTPObjectFailure` values,
  rejected warning metadata that does not match the requested storage/parent, and
  rejected listed objects whose storage does not match the request.
- Added the missing typed storage refresh requirement to `FileSystemManaging`.
- Added per-object error category logging without file content, local paths or serials.
- Removed duplicate session invalidation logic and rejected create-folder UI requests
  that have no storage instead of using the root object ID as a storage ID.
- Removed duplicate Go storage DTOs and kept one canonical definition.
- Made native builds deterministic by requiring repository libusb/header and vendored
  Go dependencies, and by pinning the dylib deployment target to macOS 26.
- Added regressions for impossible dates, non-recoverable ObjectInfo responses and
  mismatched Go partial-failure metadata.
- Added a typed `Kalam_ScanResult` envelope so healthy Go snapshots retain
  per-device/per-storage failures while the legacy `Kalam_Scan` array ABI remains
  available to the un-migrated transfer path.
- Invalidated coordinator sessions exactly once for terminal filesystem errors,
  and stopped batch deletion immediately for terminal MTP response codes.
- Removed unused broad service protocols and the duplicate `forceClearCache`
  alias while preserving the active filesystem injection seams.
- Fixed the Native shutdown flag to avoid copying `atomic.Bool` after first use.

## Exact Go Routing Result

- Scan identity is `go:<bus>:<complete-port-path>:<vid>:<pid>`; missing port paths
  fail closed.
- Exact open re-enumerates and opens only the requested physical candidate.
- Native list/create/delete/refresh/close require the immutable opaque token.
- Unknown, stale, disconnected and shutdown token states return structured errors.
- Close/cleanup dispose once and wait for in-flight operations; reconnect creates a
  fresh token for the same topology.
- Legacy transfer algorithms and symbols remain unchanged at the C boundary, but
  may reuse only one unambiguous active exact session. The detached download timeout
  goroutine was removed so it cannot outlive and reuse a disposed libusb handle.

## Hardware Matrix

Android device: **unavailable**.

The required Go → Swift read-only comparison and uniquely named Swift folder
create → refresh → delete sequence were not run. This verification does not establish
real-device parity and does not authorize changing the production default or removing
the Go fallback.
