# Transfer Migration Design

## Dependency

Requires the verified foundation, discovery/session and filesystem children.

## Transfer Object Ownership

Each active transfer is represented by a reference object owned by the existing `FileTransferManager.transferQueue`. It owns:

- lock-backed cancellation state;
- local file handle and temporary URL;
- `libusb_transfer` pointer and transfer buffer;
- byte counters and progress callback;
- terminal result guarded against double completion.

The C callback only records terminal/chunk state and signals the owning queue/condition. UI mutation is dispatched to main. The transfer object is released only after libusb invokes the terminal callback.

## Download

1. Validate destination and replacement policy.
2. Open a sibling temporary file.
3. GetObjectInfo and verify expected metadata.
4. Receive data containers/chunks, stream payload to the temporary file and report byte progress.
5. Verify protocol completion and byte count.
6. Atomically replace/move to the final destination.
7. On failure/cancel, close and remove the temporary file.

No timed-out callback may continue writing after the operation returns.

## Upload

1. Validate a regular non-symlink source, configured size limit and storage free space.
2. Send ObjectInfo and capture the new handle.
3. Stream local bytes with SendObject and actual progress.
4. Confirm response and refresh storage/cache.
5. On failure/cancel after step 2, issue best-effort DeleteObject in a fresh valid session when safe.

ObjectInfo compressed size is exact through `0xFFFFFFFE` and uses `0xFFFFFFFF` for file sizes `>= 0xFFFFFFFF`. Data-container length includes the 12-byte header: payloads through `0xFFFFFFF3` encode `payload + 12`, while larger payloads use `0xFFFFFFFF`. Exact-wire fixtures cover both sides of each threshold. For large downloads, ObjectInfo sentinel triggers a 64-bit ObjectSize property query when supported; otherwise progress is indeterminate and the final byte count is measured. Unsupported/ObjectTooLarge responses are visible errors, never a truncated UInt32 size.

## Retry and Session Rules

- Retry only errors classified as transient/busy/timeout when no conflicting write commit is ambiguous.
- Any USB disconnect, sync error or transfer cancellation invalidates the current session before retry.
- Upload retry must account for whether ObjectInfo committed; cleanup occurs before another create.
- Backoff values live in `AppConfiguration.swift`.
- A timeout cancels and joins the libusb transfer before releasing the session.

## FileTransferManager Integration

- Preserve serial `transferQueue`, `taskLock`, directory-upload lock and main-queue UI updates.
- Replace direct `Kalam_*` calls with `MTPConnectionCoordinator` delegation keyed by the requested app `Device.id`; the coordinator alone resolves and verifies its internal `MTPBackendSession`.
- Native cancellation token and `TransferTask.isCancelled` remain coordinated; terminal transition is idempotent.
- Directory upload reuses backend folder creation/upload and checks cancellation between entries and during each file.
- Refresh is performed only after a confirmed operation or explicit recovery path.

## Observability

Logs include operation, opaque device ID, storage/object ID, bytes, duration, retry index and typed terminal error. Full local paths, file content and serial numbers are excluded.
