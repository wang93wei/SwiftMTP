# Foundation Design

## Dependency

This is the first implementation child. It follows the parent `prd.md` and `design.md`.

## Source Layout

```text
SwiftMTP/Services/MTP/Core/
  MTPIdentifiers.swift
  MTPConstants.swift
  MTPError.swift
  MTPBinaryReader.swift
  MTPBinaryWriter.swift
  MTPContainer.swift
  MTPDatasets.swift
SwiftMTP/Services/MTP/Backend/
  MTPBackend.swift
  MTPBackendRouter.swift
  GoMTPBackend.swift
SwiftMTP/Services/MTP/Transport/
  MTPTransport.swift
SwiftMTP/Support/CLibUSB/
  include/libusb.h
  module.modulemap
  LICENSE
SwiftMTPTests/MTP/
  Core/
  Doubles/
```

Exact grouping may adapt to the synchronized Xcode project, but responsibilities stay separated and production files remain small.

## Binary Codec

- Reader owns immutable `Data` plus cursor and checks every read before advancing.
- Writer emits explicit little-endian integers and length-prefixed UTF-16LE MTP strings.
- Container header is 12 bytes: length, type, code and transaction ID.
- Decode rejects lengths below the header, lengths above available bytes, unknown required container types and trailing/short payload where the dataset contract forbids it.
- Encoders never silently narrow UInt64 to UInt32.

## Test Seams

`MTPTransport` represents one serialized raw transaction and has no libusb dependency. `ScriptedMTPTransport` stores expected outbound containers and queued inbound fragments/errors. Tests compare exact bytes and verify that all scripted steps are consumed.

`MTPBackend` is synchronous and throwing so existing callers decide execution context. This avoids raw C pointers and non-Sendable state crossing actors.

`MTPBackendRouter` receives a provider factory and binds the provider to a session token. Switching providers requires closing the token. The production configuration remains Go until final cutover.

The routed session holds its traditional lock across each blocking delegation so
`close()` waits for an in-flight operation before closing the underlying session.
Explicit close and deinitialization are idempotent.

Each factory product is owned for one routed session: the router calls
`initialize()` before `openSession`, and calls `shutdown()` after close or a
failed open. Routed sessions close idempotently, close on deinitialization,
reject operations after close, and release the router's busy state exactly
once.

The foundation error is named `MTPCoreError` so it does not collide with the
existing UI-facing `MTPError`. Managers map between them only in later
integration children.

## C Module

The module map exports the official header and links `usb-1.0`. Xcode search/link settings point to repository paths and the already tracked dylib. No runtime libusb call is required for the foundation tests; a compile/link smoke test is sufficient.

## Logging

Define `Logger` categories centrally for core/USB/session/filesystem/transfer. Foundation errors carry safe structured fields; raw serial numbers, file contents and full local paths are excluded.
