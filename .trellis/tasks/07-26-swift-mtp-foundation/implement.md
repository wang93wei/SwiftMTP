# Foundation Implementation Plan

## TDD Checklist

- [x] Record baseline Debug build and existing test-target behavior.
- [x] Add the first failing Swift test and confirm the test target executes it.
- [x] Vendor libusb header/license/module map and add explicit module/link settings.
- [x] Add a compile/link smoke test for `CLibUSB`.
- [x] Write failing tests for typed IDs, root/zero validation and error values.
- [x] Implement minimal identifier and error types.
- [x] Write failing binary reader/writer tests for every integer width, UTF-16LE string, empty string, cursor bounds and malformed input.
- [x] Implement reader/writer without unsafe unaligned loads.
- [x] Write failing MTP container tests for command/data/response, exact bytes, length/type/code/transaction validation and fragmentation; assert data-length wire values at payload sizes `0xFFFFFFF2`, `0xFFFFFFF3`, `0xFFFFFFF4`, `0xFFFFFFFE`, `0xFFFFFFFF` and `0x1_0000_0000`.
- [x] Implement container and initial dataset codecs.
- [x] Write failing scripted-transport tests for request matching, response fragments, timeout, cancellation and unconsumed steps.
- [x] Implement `MTPTransport`, `ScriptedMTPTransport` and fixture builders.
- [x] Write failing provider-router tests proving provider selection is fixed for an open session.
- [x] Implement `MTPBackend`, migration-only `GoMTPBackend` adapter and router; leave Go as default.
- [x] Add focused comments for binary-layout and pointer-lifetime invariants plus safe structured logs.
- [x] Write `verification.md` with AC, command/test counts, hardware status, provider default and rollback commit.

## Validation

```bash
xcodebuild -project SwiftMTP.xcodeproj -scheme SwiftMTP -configuration Debug build
xcodebuild -project SwiftMTP.xcodeproj -scheme SwiftMTP -configuration Release build
xcodebuild test -project SwiftMTP.xcodeproj -scheme SwiftMTP -destination 'platform=macOS,arch=arm64' CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=
otool -L <built-app>/Contents/MacOS/SwiftMTP
codesign --verify --deep --strict --verbose=2 <built-app>
git diff --check
```

The child cannot commit unless focused/full tests, Debug/Release builds,
Analyze, linkage/signing checks, and `git diff --check` pass; record the exact
commands and results in `verification.md`.

## Review Gate

- No production provider switch.
- No Homebrew include/library path is needed.
- No unsafe buffer read lacks an explicit bound check.
- No C pointer is stored in a Sendable value or crosses an actor boundary.
- Existing Go path still builds and runs.

## Rollback

Remove the new CLibUSB/module settings, Swift core files and test sources. No production behavior depends on them.
