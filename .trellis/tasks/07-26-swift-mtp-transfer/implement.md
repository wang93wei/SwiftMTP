# Transfer Migration Implementation Plan

## TDD Checklist

- [ ] Add failing transfer-owner lifetime tests for submit, chunk completion, terminal callback, cancellation and double completion.
- [ ] Implement lock-backed cancellation and transfer ownership around libusb async API.
- [ ] Add failing download codec/stream tests for empty, small, fragmented, split header, exact packet, ZLP, short read, oversized/malformed length and local write error.
- [ ] Implement GetObject streaming into a temporary file with atomic finalization.
- [ ] Add failing timeout/cancel/disconnect tests proving no callback touches resources after return.
- [ ] Implement cancel-and-join session invalidation.
- [ ] Add failing upload tests for ObjectInfo sizes `0xFFFFFFFE`, `0xFFFFFFFF`, `0x1_0000_0000`; data-container payload sizes `0xFFFFFFF2`, `0xFFFFFFF3`, `0xFFFFFFF4`, `0xFFFFFFFF`, `0x1_0000_0000`; plus local read failure and MTP response errors.
- [ ] Implement SendObjectInfo + SendObject streaming.
- [ ] Add failing compensation tests for cancel/failure after ObjectInfo and cleanup failure diagnostics.
- [ ] Implement orphan-object cleanup policy.
- [ ] Move transfer size/timeout/backoff constants into `AppConfiguration.swift` with tests.
- [ ] Refactor `FileTransferManager` to use `MTPBackend` while preserving `transferQueue + NSLock`.
- [ ] Add manager tests for all task states, idempotent completion, progress, cancellation and disconnect.
- [ ] Refactor directory upload to use the backend and add nested/partial/cancel/cache-refresh tests.
- [ ] Add structured transfer logs and comments at callback/pointer ownership boundaries.
- [ ] Write `verification.md` with AC, command/test counts, hardware state, provider default and rollback commit.

## Validation

```bash
xcodebuild test -project SwiftMTP.xcodeproj -scheme SwiftMTP -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
xcodebuild -project SwiftMTP.xcodeproj -scheme SwiftMTP -configuration Debug build
xcodebuild -project SwiftMTP.xcodeproj -scheme SwiftMTP -configuration Release build
desloppify scan --path .
```

The child cannot commit unless desloppify reports `Open: 0`; record all required scores in `verification.md`.

Hardware gate when available:

1. Upload/download empty and small deterministic files.
2. Compare SHA-256 after download.
3. Upload/download a multi-gigabyte fixture when storage/time allows.
4. Cancel mid-upload and mid-download; verify no partial final file/orphan object.
5. Disconnect during each direction; reconnect and verify a fresh session works.
6. Upload a nested directory and verify structure/content.

## Review Gate

- `FileTransferManager*.swift` still uses traditional queues/locks.
- Every libusb transfer reaches a terminal callback before resource release.
- Retry cannot duplicate an ambiguous upload.
- UInt64 sizes are never silently narrowed.
- All UI state changes occur on main.
- Go remains selectable for a new session until cutover.

## Rollback

Select Go for a new session and revert transfer integration. Swift read-only functionality remains available for continued diagnosis.
