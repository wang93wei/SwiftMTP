import Darwin
import XCTest
@testable import SwiftMTP

final class GoMTPFilesystemAdapterErrorTests: XCTestCase {
    func testNilAndFailedKalamResultsMapToTypedErrorsWithoutRetry() throws {
        let deviceID = try MTPDeviceID(validating: "go:5:2.5:18d1:4ee1")
        let storageID = try MTPStorageID(validating: 1)
        var listCount = 0
        var createCount = 0
        var deleteCount = 0
        var freeCount = 0
        let abi = KalamFileSystemABI(
            open: { _ in strdup(#"{"ok":true,"token":"token-b"}"#) },
            close: { _ in strdup(#"{"ok":true}"#) },
            list: { _, _, _ in
                listCount += 1
                return nil
            },
            free: { pointer in
                freeCount += 1
                Darwin.free(pointer)
            },
            create: { _, _, _, _ in
                createCount += 1
                return strdup(#"{"ok":false,"error":"operation_failed"}"#)
            },
            delete: { _, _ in
                deleteCount += 1
                return strdup(#"{"ok":false,"error":"stale_token"}"#)
            },
            refresh: { _, _ in strdup(#"{"ok":false,"error":"disconnected"}"#) }
        )
        let kernel = KalamMTPKernelBoundary(fileSystemABI: abi)
        kernel.recordSnapshots([
            makeGoMTPTestSnapshot(deviceID: deviceID, storageID: storageID),
        ])
        let session = try kernel.openSession(for: deviceID)

        XCTAssertThrowsError(try session.listObjects(storageID: storageID, parentID: .root))
        XCTAssertThrowsError(
            try session.createFolder(storageID: storageID, parentID: .root, name: "new")
        )
        XCTAssertThrowsError(try session.deleteObject(try MTPObjectID(validating: 9)))
        XCTAssertThrowsError(try session.refreshStorage(storageID))
        XCTAssertEqual(listCount, 1)
        XCTAssertEqual(createCount, 1)
        XCTAssertEqual(deleteCount, 1)
        XCTAssertEqual(freeCount, 4)
    }
}
