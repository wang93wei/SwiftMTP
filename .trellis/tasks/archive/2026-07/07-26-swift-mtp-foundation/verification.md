# Foundation Verification

Date: 2026-07-26
Branch: `refactor/swift-native-mtp`
Rollback baseline: `f2c87263ecc2955c3e72942f9f484d056065ffce`

## Acceptance Criteria

| AC | Result | Evidence |
|---|---|---|
| `import CLibUSB` compiles and links without Homebrew | PASS | `CLibUSBSmokeTests`; module map uses repository header and `-lusb-1.0`; scoped search found no `/opt/homebrew`, `pkg-config`, Go build or CGO setting |
| Official header/license match the bundled binary | PASS, corrected baseline | Existing dylib self-reports `1.0.29.11953`; official `v1.0.29` `libusb.h` and upstream `COPYING` (vendored as `LICENSE`) are present. The earlier 1.0.30 planning assumption was incorrect |
| Container, string, boundaries and malformed input are tested | PASS | Exact literal command/data/response bytes, UTF-16LE strings, truncation, unknown type, trailing bytes and fragmented input |
| Distinct typed IDs and sentinel rules | PASS | storage/object/session/transaction types are distinct; transaction IDs allow the complete UInt32 range including OpenSession `0` and natural wrap value `0xFFFFFFFF`; only session `0`/`0xFFFFFFFF` are rejected; root parent is explicit `0xFFFFFFFF` |
| Exact 4 GiB wire boundaries without large allocations | PASS | Header-length seam accepts `UInt64`; fixtures cover `0xFFFFFFF2`, `0xFFFFFFF3`, `0xFFFFFFF4`, `0xFFFFFFFE`, `0xFFFFFFFF`, `0x1_0000_0000` |
| ObjectInfo and data-container sentinels stay distinct | PASS | Separate `compressedSizeField(for:)` and `dataWireLength(payloadLength:)` tests |
| Scripted transport supports exact request, fragments and errors | PASS | Exact request matching, fragments, USB error, MTP response, timeout, cancellation, mismatch and unconsumed step coverage; a mismatch no longer consumes the expected step |
| Backend, Go adapter and provider-fixed router | PASS | Typed synchronous protocols; router owns initialize/shutdown for each factory product, rejects provider/device switches while open, closes on deinit, closes idempotently and rejects post-close delegation; Go JSON C string is freed with `defer` on success, malformed JSON and typed validation failure |
| Production provider remains Go | PASS | No manager, view, Go/Native, bridging-header or provider configuration file was changed |
| Swift tests and builds pass | PASS for supported arm64 baseline | 31 tests pass; Debug arm64 and Release arm64 pass; static analyze passes |
| Static and artifact checks | PASS | `git diff --check`, linkage, and ad-hoc codesign checks pass |

## TDD Evidence

- Baseline Debug build: exit 0.
- Baseline empty test target: exit 65, app-host XCTest injection exited before bootstrapping.
- First RED: `MTPIdentifierTests.testStorageIdentifierRejectsZero`, exit 65 with `Cannot find 'MTPStorageID' in scope`.
- First GREEN: the same focused test passed, 1 test / 0 failures.
- Later vertical RED evidence included missing reader/writer, container/framer, dataset, transport/cancellation, backend/router, Go boundary and operation-code symbols before each minimal implementation.
- Review RED: 19 focused tests executed with 8 assertion failures covering full-range transaction IDs, retained mismatch steps, router close/deinit/lifecycle behavior.
- Concurrency RED: `testCloseWaitsForInFlightDelegation` failed because `close()` completed while a delegated operation was still running.
- Concurrency GREEN: the routed-session lock now spans validation and delegation; the focused test passes.
- Final GREEN: 31 tests / 0 failures.

## Commands

| Command | Exit | Result |
|---|---:|---|
| `xcodebuild test ... CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=` | 0 | 31 tests, 0 failures |
| `xcodebuild ... -configuration Debug -destination 'platform=macOS,arch=arm64' build CODE_SIGNING_ALLOWED=NO` | 0 | Debug build succeeded |
| `xcodebuild ... -configuration Release -destination 'platform=macOS,arch=arm64' ONLY_ACTIVE_ARCH=YES build CODE_SIGNING_ALLOWED=NO` | 0 | Release arm64 build succeeded |
| Release without `ONLY_ACTIVE_ARCH=YES` | 65 | Existing arm64-only bundled dylibs cause the x86_64 link slice to fail; universal binary work remains out of scope |
| `xcodebuild analyze ... Debug ... CODE_SIGNING_ALLOWED=NO` | 0 | Analyze succeeded |
| Required test command with `CODE_SIGNING_ALLOWED=NO` | 65 | Current macOS 27/Xcode beta terminates unsigned hostless `xctest` before bootstrap; disabling signing cannot be repaired by an unsigned project setting |
| Test with `CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=` | 0 | Repository-safe ad-hoc signing passes 31/31 without a developer certificate |
| Release `build-for-testing` audit | 65, expected unsupported configuration | The optimized app module has `ENABLE_TESTABILITY=NO`; the stale Release test-target link to nonexistent `SwiftMTP.debug.dylib` was removed. The shared scheme intentionally tests Debug |
| `otool -L` on ad-hoc Debug product | 0 | `SwiftMTP.debug.dylib` links both `@rpath/libusb-1.0.dylib` and existing `@rpath/libkalam.dylib` |
| `codesign --verify --deep --strict --verbose=2` | 0 | Ad-hoc Debug app and embedded libusb are valid on disk; libusb reports `Signature=adhoc` |
| `git diff --check` | 0 | No whitespace errors |

The hostless logic-test target links the app's Debug dylib and does not launch
`SwiftMTPApp`, `DeviceManager`, or hardware scans.

## libusb Source

- Upstream tag: `libusb/libusb` `v1.0.29`
- Header SHA-256: `8c77e192d53960966c42d5f6ef204e3be88c9ff3ca431acdd5c6039689b3fe0b`
- License SHA-256: `5df07007198989c622f5d41de8d703e7bef3d0e79d62e24332ee739a452af62a`
- Header API macro: `LIBUSB_API_VERSION == 0x0100010B`
- Runtime: major 1, minor 0, micro 29, nano 11953, non-null RC string

## Hardware

Not applicable for this foundation child. No interface was opened or claimed.
Enumeration, Android interoperability, disconnect and transfer behavior belong
to later hardware-gated children.

## Rollback

No commit was created by this child. The pre-task Git rollback point is
`f2c87263ecc2955c3e72942f9f484d056065ffce`. Rollback removes the new
Core/Backend/Transport, CLibUSB and test files plus the scoped Xcode module,
link and test-target settings; existing Go/libkalam production behavior does
not depend on the new foundation.
