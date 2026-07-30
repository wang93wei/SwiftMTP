# Exact Go Fallback Routing Evidence

## Blocking finding

Independent `trellis-check` found that the typed Swift coordinator validates an immutable
`(provider, MTPDeviceID)`, but the live Go fallback does not route native operations by
that identity:

- `Kalam_Scan` currently returns a single `DeviceJSON{ID: 1}`.
- Swift converts that legacy integer to `go:1`.
- `KalamMTPKernelBoundary.openSession(for:)` stores the Swift ID but does not pass a
  device selector to Native.
- `Kalam_ListFiles`, `Kalam_CreateFolder`, `Kalam_DeleteObject` and
  `Kalam_RefreshStorage` call an unkeyed global `withDevice`.
- `devicePoolEntry` has no physical identity and may return any idle connection.
- The vendored selector fails when more than one MTP candidate exists instead of
  opening a requested candidate.

Therefore the current Go session is only logically pinned in Swift. It cannot prove
that scan, open and later filesystem operations target the same physical device.

## Repository evidence

- Fixed scan ID and unkeyed scan: `Native/kalam_bridge.go:43-108`.
- Unkeyed pool entries and selection: `Native/kalam_pool.go:19-29,67-97,152-168,279-343`.
- Unkeyed filesystem ABI calls: `Native/kalam_bridge.go:130-206,222-350`.
- Vendored open-all selector and multi-device failure:
  `Native/vendor/github.com/ganeshrvel/go-mtpfs/mtp/select.go:73-133`.
- Vendored initialization passes an empty selector:
  `Native/vendor/github.com/ganeshrvel/go-mtpx/main.go:18-35`.
- Swift fallback ABI lacks a native selector/token:
  `SwiftMTP/Services/MTP/Backend/MTPProviderRuntime.swift:3-16,106-225`.
- Swift legacy-ID mapping: `SwiftMTP/Services/MTP/Backend/GoMTPBackend.swift:89-104`.
- Coordinator's typed checks are already correct:
  `SwiftMTP/Services/MTP/Backend/MTPConnectionCoordinator.swift:8-18,33-160`.

## Required contract

1. Native discovery exposes a canonical, non-secret locator derived from USB bus,
   complete port path, VID and PID. Enumeration ordinal and device address are not
   stable identity.
2. The vendored USB layer exposes `libusb_get_port_numbers`; empty/unavailable port
   path fails closed rather than falling back to ordinal, address or model.
3. Native exact-open matches the complete locator before configuring the MTP device.
4. Opening a Go backend session returns an opaque process-local token bound to that
   locator/device. Filesystem operations and close accept the token.
5. Token close is idempotent; stale/unknown tokens fail explicitly; cleanup prevents
   new opens and safely disposes all sessions.
6. Existing transfer ABI symbols remain available in this child. Compatibility must
   not create a second uncoordinated device claim or silently route a transfer to a
   different device. If safe reuse of the selected token cannot be proved without
   transfer migration, implementation must stop and report the boundary.
7. Manager/view code never receives the token and continues through the typed
   coordinator/session contract.

## Test requirements

- Two identical VID/PID devices with different port paths produce distinct IDs.
- Reversed enumeration preserves the same locator set.
- Exact open A never opens B; unknown/stale locator fails closed.
- Interleaved A/B list/create/delete/refresh operations keep their own token.
- Same numeric storage/object IDs on A and B cannot cross-mutate.
- Disconnect invalidates the old token; reconnect creates a new token for the same
  topology identity.
- Close/cleanup/operation races have no double dispose or use-after-close.
- Every non-nil C string is freed exactly once on success and all decode/validation
  failures.
- Old transfer symbols still link, and any compatibility routing uses only the active
  exact session.

## Mandatory verification after Native changes

```bash
cd Native && go test ./...
cd Native && go test -race ./...
./Scripts/build_kalam.sh
cmp -s Native/libkalam.h SwiftMTP/libkalam.h
file SwiftMTP/libkalam.dylib
lipo -archs SwiftMTP/libkalam.dylib
otool -L SwiftMTP/libkalam.dylib
nm -gU SwiftMTP/libkalam.dylib | rg ' _Kalam_'
```

Then repeat the focused/full Swift tests, arm64 Debug/Release/Analyze, app
linkage, Native normal/race/vet and `git diff --check` gates. Scripted tests do
not replace two-device Android hardware evidence.
