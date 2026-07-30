# Current Transfer Evidence

## Provider boundary

- Typed requests/session methods already exist, but coordinator has no transfer forwarding: `SwiftMTP/Services/MTP/Backend/MTPBackend.swift:73-119`, `MTPConnectionCoordinator.swift:94-155`.
- Swift and Go backend sessions both return `unsupportedDevice`: `SwiftMTPBackend.swift:387-401`, `MTPProviderRuntime.swift:238-252`.
- Active registration/session already pins app UUID, provider and transport identity: `MTPConnectionCoordinator.swift:8-23,33-90,163-193`.

## Manager and UI

- Single-file manager directly calls `Kalam_Scan`, `Kalam_DownloadFile`, `Kalam_UploadFile`, `Kalam_CancelTask`, refresh and reset: `FileTransferManager.swift:110-135,224-259,331-389`.
- Download failure has an early return that can leave task state active: `FileTransferManager.swift:286-301`.
- `TransferTask` is `@MainActor`; manager currently updates it from the transfer queue in several paths: `TransferTask.swift:65-111,176-202`, `FileTransferManager.swift:185-303`.
- Directory upload uses a manager-global cancel bool, random per-file native task IDs, fake async blocking calls and partial-as-completed semantics: `FileTransferManager+DirectoryUpload.swift:5-21,57-90,100-197,306-351`.
- Existing Swift tests do not cover `FileTransferManager`, directory upload or `TransferTask`.

## Swift transport and session

- `LibUSBTransfer` is a safe one-submit blocking owner: it retains buffer/transfer/callback/context/handle until terminal callback: `LibUSBTransfer.swift:57-78,110-157,181-235`.
- context/handle shutdown cancel and wait for active transfers before close/exit: `LibUSBContext.swift:41-75,118-156`, `LibUSBDeviceHandle.swift:109-161`.
- `LibUSBTransport.transact` serializes command, one materialized outbound Data, then materialized inbound fragments: `LibUSBTransport.swift:24-101`.
- session has no GetObject/SendObject and creates an internal cancellation token that callers cannot cancel: `MTPDeviceSession.swift:101-181,239-310`.
- normal container/framer rejects `0xFFFFFFFF` streaming sentinel: `MTPContainer.swift:23-32,49-106`.
- ObjectInfo stores `UInt64` in memory but wire compressed size is `UInt32`; sentinel currently decodes as exact `UInt32.max`: `MTPDatasets.swift:33-38,130-159,201-205`.

## Native fallback

- Go transfer ABI returns only `1/0` and is not token-aware: `Native/kalam_bridge_transfer.go:31-48,241-243,283-305,410-415`.
- upload follows symlinks, accepts non-regular sources, ignores configured max size and narrows `int64` to `uint32`: `kalam_bridge_transfer.go:320-346`, `kalam_config.go:93-95`.
- cancellation uses a global `sync.Map` without terminal cleanup: `kalam_bridge_transfer.go:256-279,315-390`.
- SendObjectInfo success followed by cancel/SendObject failure has no orphan cleanup: `kalam_bridge_transfer.go:352-415`.
- legacy transfer may reuse only one active exact session; 0 or 2 sessions fail closed: `kalam_exact_session.go:465-490`, `kalam_exact_session_test.go:313-332`.
- Native transfer tests currently cover only cancellation map/no-op callback: `kalam_bridge_transfer_test.go:5-29`.

## Planning conclusions

- Preserve the terminal-callback ownership model and add sequential streaming above it.
- Route both providers through coordinator/session; do not add a Go special case to manager.
- Implement Native upload policy before provider integration.
- Treat directory upload, finalization and UI error mapping as dependent vertical slices, not unrelated cleanup.
- Never auto-replay a mutation or switch provider after submission.
