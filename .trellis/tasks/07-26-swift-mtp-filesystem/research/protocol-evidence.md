# MTP Filesystem Protocol Evidence

Checked on 2026-07-30.

## Go oracle

- `Kalam_ListFiles` sends `GetObjectHandles(storageID, 0, parentID)` and then `GetObjectInfo(handle)` sequentially.
- Root parent is `0xFFFFFFFF`; storage/object zero is invalid.
- A failed individual `GetObjectInfo` is skipped today, while a handle-list or connection failure terminates the whole bridge call.
- Folder creation sends `SendObjectInfo(storageID, parentID)` plus a complete ObjectInfo data phase with folder format `0x3001`.
- Successful `SendObjectInfo` returns response parameters `(storageID, parentID, newHandle)`.
- Delete sends `DeleteObject(handle, 0)`.
- `Kalam_RefreshStorage` only rereads storage info; `Kalam_ResetDeviceCache` does not reset a real device cache.

## Go behavior not adopted

- The vendored MTP string codec mishandles non-BMP Unicode by narrowing runes to UInt16 rather than encoding surrogate pairs.
- Folder name length is checked as UTF-8 bytes instead of MTP UTF-16 code units.
- `withDevice` classifies retryability by error strings and may replay mutating operations.
- A connection-probe error can be confused with success because one branch tests a stale error variable.
- Validation errors, nil and integer sentinels form inconsistent bridge error contracts.

## Swift gap

- Operation codes already exist and UInt32 array decoding is available.
- ObjectInfo currently has only a simplified value object; it lacks full wire encode/decode.
- Current transport writes one request then only reads; it cannot send ObjectInfo data after a command.
- Current session does not preserve response parameters and assumes all successful operations have inbound data.
- Current session invalidates on every MTP response error, which prevents safe partial listing after a recoverable stale-handle response.

## Primary sources

- AOSP client implementation of handles/info/send/delete:
  <https://android.googlesource.com/platform/frameworks/base/+/6215d3f/media/mtp/MtpDevice.cpp>
- AOSP server implementation of `SendObjectInfo`, response parameters and directory completion:
  <https://android.googlesource.com/platform/frameworks/base/+/ea1da3d/media/mtp/MtpServer.cpp>
- AOSP libmtp `ptp_sendobjectinfo` command/data/response contract:
  <https://android.googlesource.com/platform/external/libmtp/+/master/src/ptp.c>

## Required exact fixtures

1. `GetObjectHandles`: opcode `0x1007`, params `[storage, 0, parent]`.
2. `GetObjectInfo`: opcode `0x1008`, params `[handle]`, complete dataset.
3. `SendObjectInfo`: opcode `0x100C`, params `[storage, parent]`, outbound ObjectInfo data, response params `[storage, parent, handle]`.
4. `DeleteObject`: opcode `0x100B`, params `[handle, 0]`, response-only.
5. Legal empty handles, one recoverable object response, terminal transport/protocol error.
6. BMP and emoji names, timestamp variants, truncated/tail data and zero IDs.
