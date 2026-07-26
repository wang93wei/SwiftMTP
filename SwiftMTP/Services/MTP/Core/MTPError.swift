import Foundation

/// Protocol/backend error. Manager integration maps this into the existing UI-facing errors.
nonisolated enum MTPCoreError: Error, Equatable, Sendable {
    case invalidIdentifier(kind: MTPIdentifierKind, value: UInt32)
    case invalidInput(String)
    case noDevice
    case busy
    case permissionDenied
    case disconnected
    case timeout
    case cancelled
    case usb(code: Int32)
    case response(code: MTPResponseCode)
    case protocolViolation(String)
    case unsupportedDevice
    case localFileIO(String)
}

nonisolated enum MTPIdentifierKind: String, Equatable, Sendable {
    case device
    case storage
    case object
    case session
    case transaction
}
