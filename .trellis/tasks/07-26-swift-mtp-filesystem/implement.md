# Filesystem Migration Implementation Plan

## TDD Checklist

- [ ] Add failing ObjectInfo codec tests for file/folder, Unicode, timestamps, large sizes and truncated/malformed datasets.
- [ ] Implement checked ObjectInfo codec and typed mapping.
- [ ] Add failing GetObjectHandles/list tests for root, storage, empty list, bad handle info, transport error and disconnect.
- [ ] Implement sequential list operation with structured skipped-item diagnostics.
- [ ] Add failing folder creation tests for exact ObjectInfo bytes, Unicode/invalid names, missing response params and zero handle.
- [ ] Implement folder creation.
- [ ] Add failing delete and refresh tests for success and MTP/USB errors.
- [ ] Implement delete and typed storage refresh.
- [ ] Add failing backend contract tests shared by Go adapter, Swift backend and fake backend where applicable.
- [ ] Refactor `DeviceManager` for backend injection without changing MainActor behavior or scan backoff.
- [ ] Refactor `FileSystemManager` for backend injection while preserving actor/cache semantics.
- [ ] Add manager tests for empty vs error, mapping, cache hit/expiry/invalidation, create/delete refresh and disconnect.
- [ ] Add sequential provider differential fixture tooling for device/storage/object snapshots.
- [ ] Add focused logs/comments for partial-list diagnostics and cache invalidation boundaries.
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

1. Compare normalized Go and Swift scan/root/nested listings sequentially.
2. Create a uniquely named test folder with Swift.
3. Refresh/list and verify the returned handle.
4. Delete the folder and verify it disappears.

## Review Gate

- Valid empty directory and operation failure remain distinguishable.
- Provider selection cannot change while a session is open.
- No filesystem operation overlaps an active transaction on the same session.
- No cache is invalidated before confirmed write success.
- Production can still select Go until the final cutover.

## Rollback

Select Go for a new session and revert manager injection/filesystem implementation. Foundation and discovery code remain independently testable.
