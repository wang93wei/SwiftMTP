# Transfer Migration Verification

Date: 2026-07-30

## Outcome

The provider-bound Swift and Go transfer paths, streaming lifecycle,
single-file transfer, directory upload, cancellation, once-only finalization,
and filesystem late-response protection are implemented and covered by
automated tests.

The final Phase 2.2 full-scope integration check is green:

- prior focused transfer suites: 98 passed, 0 failed, 0 skipped;
- latest full Swift suite after late-cancel review: 191 passed, 0 failed,
  0 skipped;
- arm64 Debug, Release, and Analyze pass;
- Go normal, race, and vet pass;
- native build, ABI/header, dependency, symbol, minimum-OS, and ad-hoc
  codesign checks pass;
- static architecture audits and `git diff --check` pass.

The task is ready for final spec review and commit. It is not evidence for
production cutover: Android hardware was unavailable, the default provider
remains `.go`, and no Go/libusb removal, commit, push, or release action was
performed.

## Implementation Changes Covered by Final Check

- Split directory entry execution from directory preflight/root routing while
  preserving operation-scoped cancellation, mutation ambiguity, partial
  outcomes, progress, and once-only finalization.
- Grouped Kalam/Go backend implementation and Go adapter tests into focused
  synchronized subdirectories; Xcode automatically discovered the moved and
  newly split sources.
- Consolidated exact SendObjectInfo scripts, Go exact-session snapshots, and
  Swift backend harnesses so tests share contract fixtures rather than repeat
  wire/setup blocks.
- Split Swift backend fixtures by discovery, harness, download, and upload
  responsibility.

## Acceptance Review

| Criterion | Status | Evidence |
| --- | --- | --- |
| AC1 Go upload policy | Pass | Native policy/cancellation tests; Go normal/race/vet pass |
| AC2 provider pinning | Pass | Coordinator and exact-token adapter tests; no automatic provider replay |
| AC3 streaming ownership | Pass | libusb transfer/transport lifecycle and cancellation-race tests |
| AC4 Swift download | Pass | download session and atomic-download tests |
| AC5 Swift upload | Pass | sentinel, source failure, response, cancellation, and compensation tests |
| AC6 manager state | Pass | submission/progress/cancel/terminal tests; manager has no transfer Kalam calls |
| AC7 directory state | Pass | manifest, partial, cancellation isolation, and single finalization tests |
| AC8 refresh/cache/UI | Pass | mutation-sensitive finalization and cache-generation tests; no magic refresh notification |
| AC9 error boundary | Pass | typed submission, terminal, partial, and cancellation presentation paths |
| AC10 automated gates | Pass | Swift tests/builds/analyze, Go gates, native/ABI, and diff checks below |
| AC11 static architecture | Pass | default Go provider; no manager/view transfer Kalam calls, magic refresh, global cache reset, actor migration, or provider replay |
| AC12 Android hardware | Unavailable | no attached device; default provider unchanged |

## Swift Test Evidence

The test action used an independent DerivedData directory and local ad-hoc
signing:

```text
xcodebuild test ... \
  -derivedDataPath /tmp/SwiftMTP-final-check.dTCzOZ \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO
```

- Latest full suite: **191 passed, 0 failed, 0 skipped**.
- Full result bundle:
  `/tmp/SwiftMTP-final-check.dTCzOZ/FullTests.xcresult`.
- Focused transfer/backend/session/directory/libusb/Go-adapter suites:
  **98 passed, 0 failed, 0 skipped**.
- Focused result bundle:
  `/tmp/SwiftMTP-final-check.dTCzOZ/FocusedTransfer.xcresult`.
- `xcrun xcresulttool get test-results summary` reported `result: Passed` for
  both bundles.

This is executed XCTest evidence, not `build-for-testing`.

## Build, Native, and Static Gates

- `python3 ./.trellis/scripts/task.py validate
  .trellis/tasks/07-26-swift-mtp-transfer` — pass.
- `python3 ./.trellis/scripts/task.py validate
  .trellis/tasks/07-26-swift-mtp-filesystem` — pass.
- `python3 ./.trellis/scripts/task.py validate
  .trellis/tasks/07-26-swift-mtp-foundation` — pass.
- `python3 ./.trellis/scripts/task.py validate
  .trellis/tasks/07-26-swift-native-mtp-migration` — pass.
- `python3 ./.trellis/scripts/task.py validate
  .trellis/tasks/07-26-swift-mtp-cutover` — pass (planning context only).
- arm64 Debug build — pass.
- arm64 Release build — pass.
- arm64 Debug Analyze — pass.
- `cd Native && go test ./...` — pass.
- `cd Native && go test -race ./...` — pass.
- `cd Native && go vet ./...` — pass.
- `./Scripts/build_kalam.sh` — pass.
- `cmp Native/libkalam.h SwiftMTP/libkalam.h` — pass.
- `file SwiftMTP/libkalam.dylib` — thin arm64 Mach-O dylib.
- `otool -l` — minimum macOS 26.0, SDK 27.0.
- `otool -L` — expected `@rpath/libkalam.dylib` and
  `@rpath/libusb-1.0.dylib`.
- `nm -gU` — exact-session download/upload, cancel, open/close, and free
  symbols exported; all six transfer ABI symbols and exact-session open/close
  ABI are present.
- `go list` — the split exact-transfer, cancellation, download, upload,
  upload-policy, and legacy CGO transfer files all participate in the package
  build.
- `codesign --verify --verbose=4` — valid ad-hoc signature and designated
  requirement.
- `git diff --check` — pass.
- Static audits — production default is `.go`; manager/view code has no
  transfer Kalam calls, `RefreshFileList`, global cache reset, `Thread.sleep`,
  actor migration, or automatic provider replay.
- Repository audit — Go sources and the repository-pinned libusb dylib remain.

Xcode emitted the existing missing `AccentColor` asset warning and an
Xcode-beta `IDELaunchSession` diagnostic warning. Neither produced compiler,
test, analyzer, or runtime-test failures. `swiftlint` and `golangci-lint` are
unavailable in this environment; no lint result is claimed.

## Hardware and Rollout Boundary

An `SPUSBDataType` probe found no attached Android/MTP device.
Empty/small/nested/multi-GiB fixtures, SHA-256 parity, mid-transfer cancel,
cable removal, reconnect, and Swift-vs-Go new-session matrices remain
unverified on device.

This evidence does not authorize cutover, automatic fallback, provider replay,
Go deletion, libusb removal, commit, push, or release.

## Late-Cancel Registry Follow-up

Date: 2026-07-30

- Replaced implicit cancel-created state with an explicit
  `prepared -> claimed -> terminal` registry lifecycle. Unknown, aborted, and
  terminal task IDs now make `cancel` a strict no-op; no tombstone, TTL, time
  window, or retained terminal state is used.
- Added `Kalam_PrepareTransferTask` and `Kalam_AbortTransferTask`. The Swift Go
  adapter prepares before installing its cancellation callback, claims through
  the existing session transfer ABI, and invokes abort cleanup exactly once on
  every post-prepare exit. Legacy `Kalam_DownloadFile`,
  `Kalam_UploadFile`, and `Kalam_CancelTask` symbols remain exported.
- RED evidence:
  - focused Go tests failed to compile because `prepare`/`claim` and the
    non-creating `cancel` result did not exist;
  - focused Swift tests failed to compile because the transfer ABI did not yet
    expose prepare/abort lifecycle hooks.
- GREEN evidence:
  - focused Go cancellation/bridge tests — pass;
  - focused Go race tests — pass;
  - `cd Native && go test ./...` — pass;
  - `cd Native && go test -race ./...` — pass;
  - `cd Native && go vet ./...` — pass;
  - focused `GoMTPTransferAdapterTests` — 7 passed, 0 failed, using
    `CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO`;
  - `./Scripts/build_kalam.sh` — pass;
  - generated header parity — pass;
  - ABI symbol audit — new prepare/abort plus old download/upload/cancel and
    session transfer symbols present;
  - `git diff --check` and Trellis task validation — pass.

The focused Swift command with `CODE_SIGNING_ALLOWED=NO` compiled and linked
but the macOS 27 test runner was killed while loading an unsigned test bundle.
The project-standard local ad-hoc signing command above executed all seven
focused tests successfully.

Android hardware remains unavailable. Real pre-submit/mid-transfer cancellation,
disconnect, reconnect, large-file, and device-specific behavior are not claimed;
the default provider remains Go and libusb remains unchanged.

## Independent Late-Cancel Review

Date: 2026-07-30

The independent `trellis-check` found no production lifecycle defect. The
registry's mutex linearizes prepare/claim/abort/cancel/finish, terminal cleanup
deletes the exact state pointer, and cancel never creates unknown or terminal
state. Duplicate prepare/claim fail, duplicate abort/finish are no-ops, and
task-ID reuse starts with a fresh uncancelled state. The legacy ABI still uses
atomic begin+claim, so active cancellation remains observable without retaining
terminal tombstones.

One test-evidence gap was fixed:

- added a deterministic Swift adapter test that cancels inside successful
  prepare, before callback registration, and proves the already-cancelled token
  immediately reaches native cancel, never invokes transfer, then aborts the
  prepared state once;
- added a nil C-response regression proving the exceptional post-prepare path
  invokes abort cleanup exactly once.

Fresh evidence:

- focused `GoMTPTransferAdapterTests`: **7 passed, 0 failed, 0 skipped**;
- full Swift XCTest: **191 passed, 0 failed, 0 skipped**;
- `cd Native && go test ./...`: 74 passed test events across 50 top-level
  tests;
- `cd Native && go test -race ./...`: the same 74 test events pass with the
  race detector;
- `cd Native && go vet ./...`: pass;
- arm64 Debug build, arm64 Release build, and arm64 Debug Analyze: pass;
- `./Scripts/build_kalam.sh`: pass;
- generated headers match; thin arm64 dylib, minimum macOS 26.0, SDK 27.0,
  expected `@rpath/libusb-1.0.dylib` dependency, and valid ad-hoc signature;
- new prepare/abort symbols plus legacy/session download/upload/cancel,
  open/close, and free symbols are exported;
- transfer/filesystem/foundation/parent/cutover Trellis validations and
  `git diff --check`: pass;
- production default remains `.go`; Go Native sources and repository-pinned
  libusb remain present; coordinator forwarding performs no provider switch or
  mutation replay.

No Android/MTP device was found. Hardware cancellation, disconnect/reconnect,
large-file sentinels, SHA-256 parity, and device-specific behavior remain
unverified and no cutover claim is made.
