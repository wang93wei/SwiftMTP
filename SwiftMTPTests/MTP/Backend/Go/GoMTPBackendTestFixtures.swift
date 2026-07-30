import Darwin
@testable import SwiftMTP

final class FakeGoKernel: GoMTPKernelBoundary {
    private let json: String
    private(set) var freeCount = 0
    private(set) var initializeCount = 0

    init(json: String) {
        self.json = json
    }

    func initialize() { initializeCount += 1 }
    func shutdown() {}
    func scanDevicesJSON() -> UnsafeMutablePointer<CChar>? { strdup(json) }
    func freeString(_ pointer: UnsafeMutablePointer<CChar>) {
        freeCount += 1
        free(pointer)
    }
    func openSession(for deviceID: MTPDeviceID) throws -> any MTPBackendSession {
        FakeMTPBackendSession(deviceID: deviceID, providerKind: .go)
    }
}
