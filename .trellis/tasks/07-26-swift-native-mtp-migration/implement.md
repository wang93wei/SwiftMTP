# Parent Implementation Plan

The parent task owns requirements, integration gates and the child map. It is not an implementation target.

## Ordered Child Tasks

- [ ] **1. `07-26-swift-mtp-foundation`**
  - Establish CLibUSB linking/module packaging.
  - Add Swift test sources and TDD infrastructure.
  - Implement typed MTP contracts, codecs, cancellation and scripted transport.
  - Add migration-only backend abstraction without changing the production default.
  - Gate: clean build and deterministic protocol tests pass.

- [ ] **2. `07-26-swift-mtp-discovery-session`**
  - Depends on child 1.
  - Implement libusb context/event loop, discovery, claim/release and session/transaction state.
  - Implement device info and storage scan.
  - Gate: fake-transport tests pass; optional hardware scan evidence is recorded.

- [ ] **3. `07-26-swift-mtp-filesystem`**
  - Depends on children 1–2.
  - Implement object handles/info, directory listing, folder creation, deletion and refresh.
  - Integrate Swift provider with `DeviceManager`/`FileSystemManager` behind session-fixed provider selection.
  - Gate: backend/manager contract tests pass and read-only hardware parity is recorded when hardware is available.

- [ ] **4. `07-26-swift-mtp-transfer`**
  - Depends on children 1–3.
  - Implement streaming download/upload, progress, cancellation, timeout, retry, compensation and directory upload.
  - Integrate without changing the `FileTransferManager` concurrency model.
  - Gate: transfer tests and hardware hash/cancel/disconnect matrix pass.

- [ ] **5. `07-26-swift-mtp-cutover`**
  - Depends on children 1–4.
  - Run final cross-provider and hardware acceptance.
  - Make Swift the sole provider; remove Go/CGO/libkalam and stale build/test/docs configuration.
  - Verify clean Debug/Release builds, tests, DMG and dylib signing/linkage.
  - Run mandatory `desloppify` scans and require `Open: 0`.

## Cross-Child Review Gates

- Every child uses RED → GREEN → REFACTOR and leaves the branch buildable.
- Each child must run focused tests plus the full Swift test suite and Xcode build.
- Before every child commit, run `desloppify scan --path .` and require `Open: 0`; record all required scores.
- Go source changes, if any are required only for an oracle fixture, must also run `./Scripts/build_kalam.sh` and `cd Native && go test ./...`.
- No child may delete the Go path before child 5.
- No provider switch may occur during an open device session.
- High-risk libusb pointer/callback code receives an independent Trellis check before commit.
- Git commits are performed by the dedicated commit agent; no push is planned unless separately requested.

## Required Child Evidence Package

Before a child is marked complete, create `<child-task>/verification.md` containing:

- every child AC with pass/fail status;
- exact focused/full test and build commands with exit status and test counts;
- `desloppify` lenient/strict, five mechanical and seven subjective scores plus `Open: 0`;
- hardware evidence marked passed, failed, unavailable or not applicable;
- current production provider default and rollback commit.

Each downstream child may start only when every predecessor `verification.md` shows all blocking AC passed. Child 5 additionally requires real-device gates from children 2–4 to be passed, not merely unavailable.

## Final Validation Commands

```bash
MIGRATION_PATH="/usr/bin:/bin:/usr/sbin:/sbin"
MIGRATION_DERIVED_DATA="$(mktemp -d)"
MIGRATION_BUILD_SETTINGS="$(mktemp)"
! env PATH="$MIGRATION_PATH" /usr/bin/which go
env PATH="$MIGRATION_PATH" xcodebuild -project SwiftMTP.xcodeproj -scheme SwiftMTP -configuration Debug -derivedDataPath "$MIGRATION_DERIVED_DATA" clean build
env PATH="$MIGRATION_PATH" xcodebuild -project SwiftMTP.xcodeproj -scheme SwiftMTP -configuration Release -derivedDataPath "$MIGRATION_DERIVED_DATA" clean build
env PATH="$MIGRATION_PATH" xcodebuild test -project SwiftMTP.xcodeproj -scheme SwiftMTP -destination 'platform=macOS' -derivedDataPath "$MIGRATION_DERIVED_DATA" CODE_SIGNING_ALLOWED=NO
env PATH="$MIGRATION_PATH" ./Scripts/create_dmg_simple.sh
env PATH="$MIGRATION_PATH" xcodebuild -project SwiftMTP.xcodeproj -scheme SwiftMTP -showBuildSettings > "$MIGRATION_BUILD_SETTINGS"
! rg '/opt/homebrew|pkg-config' "$MIGRATION_BUILD_SETTINGS"
otool -L <built-app>/Contents/MacOS/SwiftMTP
codesign --verify --deep --strict --verbose=2 <built-app>
desloppify scan --path .
! git grep -nE 'Kalam_|libkalam|CGO|go-mtpx|build_kalam|go build|go test' -- SwiftMTP SwiftMTPTests SwiftMTP.xcodeproj Scripts docs README.md CLAUDE.md AGENTS.md
```

The build-settings command must succeed, then the negated `rg` and scoped final grep must succeed by finding no matches; a separate full-repository audit may only find approved `.trellis` planning/research history.

## Rollback Points

- Child 1: remove the CLibUSB/codec/test additions; production remains Go.
- Child 2: disable the Swift provider and close its libusb context; production remains Go.
- Child 3: select Go for a new session; no write path has switched.
- Child 4: select Go for a new session; Swift transfer code remains isolated.
- Child 5: revert to the verified pre-cutover commit if final packaging or hardware regression fails.
