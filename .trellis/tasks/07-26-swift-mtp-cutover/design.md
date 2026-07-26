# Cutover Design

## Dependency

Requires all four implementation children to be complete and independently verified.

## Pre-Deletion Gate

Go remains intact until all of the following are true:

1. Swift protocol/backend/manager tests pass.
2. Debug and Release builds pass with Swift provider selected.
3. Real-device matrix passes, including write/cancel/disconnect operations.
4. Sequential Go/Swift normalized snapshots show no unexplained functional mismatch.
5. Rollback commit is recorded.

If hardware is unavailable, deletion is blocked because the parent acceptance criteria require real Android interoperability evidence.

## Removal Surface

- Entire `Native/` Go module, vendor tree, tests and generated library/header.
- `SwiftMTP/libkalam.dylib`, `SwiftMTP/libkalam.h` and the old bridging header if CLibUSB no longer needs it.
- Xcode libkalam Embed Libraries membership, CGO-related search/link settings and obsolete rpath entries.
- `Scripts/build_kalam.sh`, Go branches in `Scripts/run_tests.sh` and Go/bridge checks in setup scripts.
- Go/CGO/libkalam documentation, diagrams and localized credits.
- Migration-only `GoMTPBackend`, provider flag and differential code that has no lasting test value.

CLibUSB module/header/license, `libusb-1.0.dylib`, explicit link/embed/sign settings and relevant sandbox/library-validation settings remain.

## Clean-Build Proof

Use a fresh `mktemp` DerivedData directory and restrict PATH to `/usr/bin:/bin:/usr/sbin:/sbin`; prove `go` is unavailable in that environment. Inspect Xcode build settings for `/opt/homebrew`/`pkg-config` references, then build and test using only Xcode/toolchain plus tracked repository files. Inspect the built executable and Frameworks directory rather than relying on project-text searches alone.

## Rollback

The last verified commit before removal is the rollback point. If build/package/hardware validation fails after deletion, revert the cutover commit rather than reconstructing generated Go artifacts manually.

## Documentation Contract

Architecture and setup docs describe Swift MTP/PTP + libusb, the CLibUSB module, Swift test commands, USB access constraints and the distinction between simulated protocol tests and real-device evidence.
