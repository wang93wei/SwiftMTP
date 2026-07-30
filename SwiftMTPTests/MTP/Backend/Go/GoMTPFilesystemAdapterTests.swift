import XCTest
@testable import SwiftMTP

final class GoMTPFilesystemAdapterTests: XCTestCase {
    func testListFreesCStringAndDecodesPartialObjectFailure() throws {
        let fixture = try GoMTPFilesystemAdapterFixture()
        defer { fixture.session.close() }

        let listing = try fixture.session.listObjects(
            storageID: fixture.storageID,
            parentID: .root
        )

        XCTAssertEqual(listing.objects.count, 1)
        XCTAssertEqual(
            listing.failures,
            [
                MTPObjectFailure(
                    deviceID: fixture.deviceID,
                    storageID: fixture.storageID,
                    parentID: .root,
                    objectID: try MTPObjectID(validating: 3),
                    stage: .objectInfo,
                    error: .response(code: .invalidObjectHandle)
                ),
            ]
        )
        XCTAssertEqual(fixture.state.openedDeviceIDs, [fixture.deviceID.rawValue])
        XCTAssertEqual(fixture.state.receivedTokens, ["token-a"])
        XCTAssertEqual(fixture.state.freeCount, 2)
    }

    func testListRejectsMalformedOrMismatchedPayloadsAndFreesEveryCString() throws {
        let fixture = try GoMTPFilesystemAdapterFixture()
        defer { fixture.session.close() }

        fixture.state.payload = """
        {"ok":true,"failures":[{"storageId":2,"parentId":4294967295,"objectId":3,
                               "stage":"object_info","error":"invalid_object_handle"}]}
        """
        XCTAssertThrowsError(
            try fixture.session.listObjects(storageID: fixture.storageID, parentID: .root)
        ) {
            guard case .protocolViolation = $0 as? MTPCoreError else {
                return XCTFail("Expected protocol violation, got \($0)")
            }
        }

        fixture.state.payload = """
        {"ok":true,
         "files":[{"id":2,"parentId":4294967295,"storageId":2,"name":"a.txt",
                   "size":4,"isFolder":false,"modTime":0}]}
        """
        XCTAssertThrowsError(
            try fixture.session.listObjects(storageID: fixture.storageID, parentID: .root)
        ) {
            guard case .protocolViolation = $0 as? MTPCoreError else {
                return XCTFail("Expected protocol violation, got \($0)")
            }
        }

        fixture.state.payload = "{invalid"
        XCTAssertThrowsError(
            try fixture.session.listObjects(storageID: fixture.storageID, parentID: .root)
        )

        fixture.state.payload = """
        {"ok":true,"files":[{"id":0,"parentId":4294967295,"storageId":1,
                             "name":"bad","size":0,"isFolder":false,"modTime":0}]}
        """
        XCTAssertThrowsError(
            try fixture.session.listObjects(storageID: fixture.storageID, parentID: .root)
        )

        XCTAssertEqual(fixture.state.receivedTokens, Array(repeating: "token-a", count: 4))
        XCTAssertEqual(fixture.state.freeCount, 5)
    }

    func testMutationsUseExactTokenAndCloseSessionOnce() throws {
        let fixture = try GoMTPFilesystemAdapterFixture()

        XCTAssertEqual(
            try fixture.session.createFolder(
                storageID: fixture.storageID,
                parentID: .root,
                name: "new"
            ).rawValue,
            9
        )
        XCTAssertNoThrow(
            try fixture.session.deleteObject(try MTPObjectID(validating: 9))
        )
        XCTAssertEqual(
            try fixture.session.refreshStorage(fixture.storageID).id,
            fixture.storageID
        )
        fixture.session.close()
        fixture.session.close()

        XCTAssertEqual(fixture.state.receivedTokens, Array(repeating: "token-a", count: 4))
        XCTAssertEqual(fixture.state.freeCount, 5)
    }
}
