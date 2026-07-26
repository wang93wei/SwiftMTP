import Darwin
import XCTest
@testable import SwiftMTP

final class GoMTPBackendTests: XCTestCase {
    func testScanDecodesJSONAndAlwaysFreesKernelString() throws {
        let kernel = FakeGoKernel(
            json: """
            [{"id":1,"name":"Pixel","manufacturer":"Google","model":"Pixel 9",
              "serialNumber":"secret","storage":[{"id":65537,"description":"Internal",
              "freeSpace":20,"maxCapacity":100}],"mtpSupport":{"mtpVersion":"1.0",
              "deviceVersion":"1","vendorExtension":"Google"}}]
            """
        )
        let backend = GoMTPBackend(kernel: kernel)

        let devices = try backend.scanDevices()

        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(devices[0].deviceID.rawValue, "go:1")
        XCTAssertEqual(devices[0].storages[0].id.rawValue, 65537)
        XCTAssertEqual(kernel.freeCount, 1)
        XCTAssertEqual(kernel.initializeCount, 0)
    }

    func testScanAlwaysFreesKernelStringForMalformedJSON() {
        let kernel = FakeGoKernel(json: "{")
        let backend = GoMTPBackend(kernel: kernel)

        XCTAssertThrowsError(try backend.scanDevices())
        XCTAssertEqual(kernel.freeCount, 1)
    }

    func testScanAlwaysFreesKernelStringForTypedValidationFailure() {
        let kernel = FakeGoKernel(
            json: """
            [{"id":1,"name":"Pixel","manufacturer":"Google","model":"Pixel 9",
              "storage":[{"id":0,"description":"Invalid","freeSpace":20,"maxCapacity":100}]}]
            """
        )
        let backend = GoMTPBackend(kernel: kernel)

        XCTAssertThrowsError(try backend.scanDevices()) {
            XCTAssertEqual(
                $0 as? MTPCoreError,
                .invalidIdentifier(kind: .storage, value: 0)
            )
        }
        XCTAssertEqual(kernel.freeCount, 1)
    }
}

private final class FakeGoKernel: GoMTPKernelBoundary {
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
