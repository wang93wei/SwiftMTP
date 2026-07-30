import XCTest
@testable import SwiftMTP

final class GoMTPScanTests: XCTestCase {
    func testScanDecodesJSONAndAlwaysFreesKernelString() throws {
        let kernel = FakeGoKernel(
            json: """
            {"ok":true,"devices":[{"id":"go:5:2.4:18d1:4ee1","name":"Pixel","manufacturer":"Google","model":"Pixel 9",
              "serialNumber":"secret","storage":[{"id":65537,"description":"Internal",
              "freeSpace":20,"maxCapacity":100}],"mtpSupport":{"mtpVersion":"1.0",
              "deviceVersion":"1","vendorExtension":"Google"}}],"failures":[]}
            """
        )
        let backend = GoMTPBackend(kernel: kernel)

        let result = try backend.scanDevices()

        XCTAssertEqual(result.snapshots.count, 1)
        XCTAssertEqual(result.snapshots[0].deviceID.rawValue, "go:5:2.4:18d1:4ee1")
        XCTAssertEqual(result.snapshots[0].storages[0].id.rawValue, 65537)
        XCTAssertEqual(kernel.freeCount, 1)
        XCTAssertEqual(kernel.initializeCount, 0)
    }

    func testScanPreservesTypedPartialFailuresAlongsideHealthyDevices() throws {
        let kernel = FakeGoKernel(
            json: """
            {"ok":true,
             "devices":[{"id":"go:5:2.4:18d1:4ee1","name":"Pixel","manufacturer":"Google",
                         "model":"Pixel 9","storage":[]}],
             "failures":[{"deviceId":"go:5:2.5:18d1:4ee1","stage":"device",
                          "error":"disconnected"},
                         {"deviceId":"go:5:2.4:18d1:4ee1","stage":"storage",
                          "error":"operation_failed"}]}
            """
        )
        let backend = GoMTPBackend(kernel: kernel)

        let result = try backend.scanDevices()

        XCTAssertEqual(result.snapshots.count, 1)
        XCTAssertEqual(
            result.failures,
            [
                MTPScanFailure(
                    deviceID: try MTPDeviceID(validating: "go:5:2.5:18d1:4ee1"),
                    storageID: nil,
                    stage: .device,
                    error: .disconnected
                ),
                MTPScanFailure(
                    deviceID: try MTPDeviceID(validating: "go:5:2.4:18d1:4ee1"),
                    storageID: nil,
                    stage: .storage,
                    error: .response(code: .generalError)
                ),
            ]
        )
        XCTAssertEqual(kernel.freeCount, 1)
    }
}
