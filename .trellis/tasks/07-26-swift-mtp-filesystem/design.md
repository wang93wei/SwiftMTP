# Filesystem Migration Design

## Dependency

Requires verified foundation and discovery/session children.

## Dataset and Operation Ownership

- `MTPObjectInfoCodec` decodes/encodes the standard ObjectInfo dataset with checked field lengths.
- The selected `MTPBackendSession.listObjects` executes GetObjectHandles then GetObjectInfo sequentially within that device session's transaction queue.
- A failed handle list fails the operation. A failed individual object info is skipped for current parity but recorded as a structured warning.
- Folder creation encodes ObjectInfo with folder format `0x3001`, zero size, supplied storage/parent and UTF-16LE name, then validates response parameter 3 as a non-zero handle.
- Delete uses DeleteObject(handle, format 0).
- Refresh calls GetStorageInfo and returns the updated typed storage rather than simulating a cache reset.

## Service Integration

`DeviceManager` and `FileSystemManager` receive an `MTPBackend` dependency with the shared production default. Existing singletons remain, but tests construct isolated instances/factories.

`FileSystemManager` remains an actor. It calls the synchronous backend from an appropriate background boundary and never blocks `MainActor`. Its cache keys continue to include device, storage and parent IDs; invalidation is scoped to the affected device.

Swift provider results map directly to `Device`, `StorageInfo` and `FileItem`. The Go adapter continues decoding its legacy JSON during migration, but that JSON never enters the Swift provider.

## Failure Semantics

- Transport/protocol failures are errors, not empty successful directories.
- Empty list is returned only for a valid successful directory with zero handles.
- Skipped corrupt/unreadable object metadata is logged with object ID and surfaced in backend diagnostics.
- Create/delete update caches only after confirmed MTP success.
- Physical disconnect invalidates the session and follows the existing manager disconnect path.

## Differential Validation

Read-only snapshots normalize device/storage/object IDs, names, sizes, types and modification times for sequential Go/Swift comparison. Write comparison uses a dedicated test folder and cleans it before switching providers.
