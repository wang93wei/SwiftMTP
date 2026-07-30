import XCTest
@testable import SwiftMTP

final class SwiftMTPFilesystemBackendTests: XCTestCase {
    func testListKeepsObjectsAndReportsRecoverableObjectFailure() throws {
        let harness = try makeSwiftMTPBackendHarness(rawDeviceValue: 0x501)
        let storageID = try MTPStorageID(validating: 1)
        let goodID = try MTPObjectID(validating: 2)
        let missingID = try MTPObjectID(validating: 3)
        harness.discovery.objectHandles = [goodID, missingID]
        harness.discovery.objectInfo[goodID] = try MTPObjectInfoDataset(
            storageID: storageID,
            objectFormat: 0x3000,
            objectSize: 12,
            parentObject: .root,
            filename: "readme.txt"
        )

        try harness.backend.initialize()
        let session = try harness.backend.openSession(for: harness.deviceID)
        let listing = try session.listObjects(storageID: storageID, parentID: .root)

        XCTAssertEqual(listing.objects.map(\.id), [goodID])
        XCTAssertEqual(listing.failures.map(\.objectID), [missingID])
        session.close()
        harness.backend.shutdown()
    }

    func testLegalEmptyListingDiffersFromTerminalFailure() throws {
        let harness = try makeSwiftMTPBackendHarness(rawDeviceValue: 0x502)
        let storageID = try MTPStorageID(validating: 1)
        try harness.backend.initialize()
        let session = try harness.backend.openSession(for: harness.deviceID)

        XCTAssertEqual(
            try session.listObjects(storageID: storageID, parentID: .root),
            MTPDirectoryListing(objects: [], failures: [])
        )
        harness.discovery.objectHandlesError = .timeout
        XCTAssertThrowsError(try session.listObjects(storageID: storageID, parentID: .root)) {
            XCTAssertEqual($0 as? MTPCoreError, .timeout)
        }
        session.close()
        harness.backend.shutdown()
    }

    func testListOnlySkipsInvalidObjectHandleResponses() throws {
        let harness = try makeSwiftMTPBackendHarness(rawDeviceValue: 0x503)
        let storageID = try MTPStorageID(validating: 1)
        let objectID = try MTPObjectID(validating: 3)
        harness.discovery.objectHandles = [objectID]
        harness.discovery.objectInfoErrors[objectID] = .response(code: .generalError)
        try harness.backend.initialize()
        let session = try harness.backend.openSession(for: harness.deviceID)

        XCTAssertThrowsError(
            try session.listObjects(storageID: storageID, parentID: .root)
        ) {
            XCTAssertEqual($0 as? MTPCoreError, .response(code: .generalError))
        }
        session.close()
        harness.backend.shutdown()
    }
}
