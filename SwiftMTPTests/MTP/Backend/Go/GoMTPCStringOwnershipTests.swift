import XCTest
@testable import SwiftMTP

final class GoMTPCStringOwnershipTests: XCTestCase {
    func testScanAlwaysFreesKernelStringForMalformedJSON() {
        let kernel = FakeGoKernel(json: "{")
        let diagnostic = UncheckedResultBox<String>()
        let backend = GoMTPBackend(
            kernel: kernel,
            reportDiagnostic: { diagnostic.store($0) }
        )

        XCTAssertThrowsError(try backend.scanDevices()) {
            XCTAssertEqual(
                $0 as? MTPCoreError,
                .protocolViolation("Go device JSON decode failed")
            )
        }
        XCTAssertTrue(diagnostic.value?.contains("byteCount=1") == true)
        XCTAssertTrue(diagnostic.value?.contains("DecodingError") == true)
        XCTAssertFalse(diagnostic.value?.contains("{") == true)
        XCTAssertEqual(kernel.freeCount, 1)
    }

    func testScanAlwaysFreesKernelStringForTypedValidationFailure() {
        let kernel = FakeGoKernel(
            json: """
            {"ok":true,"devices":[{"id":"go:5:2.4:18d1:4ee1","name":"Pixel",
              "manufacturer":"Google","model":"Pixel 9",
              "storage":[{"id":0,"description":"Invalid","freeSpace":20,"maxCapacity":100}]}]}
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
