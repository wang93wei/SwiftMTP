import Darwin
import XCTest
@testable import SwiftMTP

final class GoMTPTransferAdapterTests: XCTestCase {
    func testTransferAdapterForwardsExactTokenRequestProgressAndFreesResponses() throws {
        let fixture = try TransferFixture()
        var freeCount = 0
        var receivedTasks: [String] = []
        var preparedTasks: [String] = []
        var abortedTasks: [String] = []
        var downloadArguments: (String, UInt32, String)?
        var uploadArguments: (String, UInt32, UInt32, String, String, UInt64)?
        let transferABI = KalamTransferABI(
            download: { token, objectID, path, taskID, progress in
                downloadArguments = (
                    String(cString: token),
                    objectID,
                    String(cString: path)
                )
                receivedTasks.append(String(cString: taskID))
                progress(2)
                progress(4)
                return strdup(#"{"ok":true,"bytes":4}"#)
            },
            upload: { token, storageID, parentID, path, name, size, taskID, progress in
                uploadArguments = (
                    String(cString: token),
                    storageID,
                    parentID,
                    String(cString: path),
                    String(cString: name),
                    size
                )
                receivedTasks.append(String(cString: taskID))
                progress(5)
                return strdup(#"{"ok":true,"bytes":5}"#)
            },
            prepare: {
                preparedTasks.append(String(cString: $0))
                return 1
            },
            cancel: { _ in XCTFail("successful transfer must not cancel") },
            abort: {
                abortedTasks.append(String(cString: $0))
                return 0
            }
        )
        let session = try fixture.session(
            transferABI: transferABI,
            free: {
                freeCount += 1
                Darwin.free($0)
            }
        )
        var progress: [UInt64] = []

        try session.download(
            MTPDownloadRequest(
                objectID: fixture.objectID,
                destinationURL: URL(fileURLWithPath: "/tmp/download.bin"),
                expectedSize: 4
            ),
            progress: { progress.append($0) },
            cancellation: MTPCancellationToken()
        )
        try session.upload(
            MTPUploadRequest(
                storageID: fixture.storageID,
                parentID: .root,
                sourceURL: URL(fileURLWithPath: "/tmp/upload.bin"),
                name: "remote.bin",
                size: 5
            ),
            progress: { progress.append($0) },
            cancellation: MTPCancellationToken()
        )

        XCTAssertEqual(downloadArguments?.0, "token-a")
        XCTAssertEqual(downloadArguments?.1, fixture.objectID.rawValue)
        XCTAssertEqual(downloadArguments?.2, "/tmp/download.bin")
        XCTAssertEqual(uploadArguments?.0, "token-a")
        XCTAssertEqual(uploadArguments?.1, fixture.storageID.rawValue)
        XCTAssertEqual(uploadArguments?.2, MTPObjectID.root.rawValue)
        XCTAssertEqual(uploadArguments?.3, "/tmp/upload.bin")
        XCTAssertEqual(uploadArguments?.4, "remote.bin")
        XCTAssertEqual(uploadArguments?.5, 5)
        XCTAssertEqual(progress, [2, 4, 5])
        XCTAssertEqual(receivedTasks.count, 2)
        XCTAssertTrue(receivedTasks.allSatisfy { !$0.isEmpty })
        XCTAssertNotEqual(receivedTasks[0], receivedTasks[1])
        XCTAssertEqual(preparedTasks, receivedTasks)
        XCTAssertEqual(abortedTasks, receivedTasks)
        XCTAssertEqual(freeCount, 3)
        session.close()
        XCTAssertEqual(freeCount, 4)
    }

    func testTransferCancellationMapsPreAndMidFlightWithoutRetry() throws {
        let fixture = try TransferFixture()
        let cancellation = MTPCancellationToken()
        var downloadCount = 0
        var cancelledTask: String?
        var events: [String] = []
        let transferABI = KalamTransferABI(
            download: { _, _, _, _, _ in
                downloadCount += 1
                events.append("download")
                cancellation.cancel()
                return strdup(#"{"ok":false,"error":"cancelled"}"#)
            },
            upload: { _, _, _, _, _, _, _, _ in
                XCTFail("unexpected upload")
                return nil
            },
            prepare: { _ in
                events.append("prepare")
                return 1
            },
            cancel: {
                cancelledTask = String(cString: $0)
                events.append("cancel")
            },
            abort: { _ in
                events.append("abort")
                return 0
            }
        )
        let session = try fixture.session(transferABI: transferABI)

        XCTAssertThrowsError(
            try session.download(
                MTPDownloadRequest(
                    objectID: fixture.objectID,
                    destinationURL: URL(fileURLWithPath: "/tmp/download.bin"),
                    expectedSize: nil
                ),
                progress: { _ in },
                cancellation: cancellation
            )
        ) {
            XCTAssertEqual($0 as? MTPCoreError, .cancelled)
        }
        XCTAssertEqual(downloadCount, 1)
        XCTAssertFalse(cancelledTask?.isEmpty ?? true)
        XCTAssertEqual(events, ["prepare", "download", "cancel", "abort"])

        let preCancelled = MTPCancellationToken()
        preCancelled.cancel()
        XCTAssertThrowsError(
            try session.download(
                MTPDownloadRequest(
                    objectID: fixture.objectID,
                    destinationURL: URL(fileURLWithPath: "/tmp/download.bin"),
                    expectedSize: nil
                ),
                progress: { _ in },
                cancellation: preCancelled
            )
        ) {
            XCTAssertEqual($0 as? MTPCoreError, .cancelled)
        }
        XCTAssertEqual(downloadCount, 1)
        XCTAssertEqual(
            events,
            ["prepare", "download", "cancel", "abort", "prepare", "cancel", "abort"]
        )
        session.close()
    }

    func testCancellationAfterTerminalTransferDoesNotReachNativeRegistry() throws {
        let fixture = try TransferFixture()
        let cancellation = MTPCancellationToken()
        var cancelCount = 0
        var abortCount = 0
        let transferABI = KalamTransferABI(
            download: { _, _, _, _, _ in
                strdup(#"{"ok":true,"bytes":4}"#)
            },
            upload: { _, _, _, _, _, _, _, _ in
                XCTFail("unexpected upload")
                return nil
            },
            prepare: { _ in 1 },
            cancel: { _ in cancelCount += 1 },
            abort: { _ in
                abortCount += 1
                return 0
            }
        )
        let session = try fixture.session(transferABI: transferABI)

        try session.download(
            MTPDownloadRequest(
                objectID: fixture.objectID,
                destinationURL: URL(fileURLWithPath: "/tmp/download.bin"),
                expectedSize: 4
            ),
            progress: { _ in },
            cancellation: cancellation
        )
        cancellation.cancel()

        XCTAssertEqual(cancelCount, 0)
        XCTAssertEqual(abortCount, 1)
        session.close()
    }

    func testTransferErrorsAreStructuredAndEveryNonNilCStringIsFreedOnce() throws {
        let fixture = try TransferFixture()
        var payload = #"{"ok":false,"error":"disconnected"}"#
        var freeCount = 0
        var callCount = 0
        var abortCount = 0
        let transferABI = KalamTransferABI(
            download: { _, _, _, _, _ in
                callCount += 1
                return strdup(payload)
            },
            upload: { _, _, _, _, _, _, _, _ in
                callCount += 1
                return strdup(payload)
            },
            prepare: { _ in 1 },
            cancel: { _ in },
            abort: { _ in
                abortCount += 1
                return 0
            }
        )
        let session = try fixture.session(
            transferABI: transferABI,
            free: {
                freeCount += 1
                Darwin.free($0)
            }
        )
        let download = MTPDownloadRequest(
            objectID: fixture.objectID,
            destinationURL: URL(fileURLWithPath: "/tmp/download.bin"),
            expectedSize: nil
        )

        for entry in [
            (#"{"ok":false,"error":"disconnected"}"#, MTPCoreError.disconnected),
            (#"{"ok":false,"error":"stale_token"}"#, .disconnected),
            (#"{"ok":false,"error":"invalid_input"}"#, .invalidInput("Go transfer rejected invalid input")),
            (#"{"ok":false,"error":"local_io"}"#, .localFileIO("Go transfer local file I/O failed")),
            (#"{"ok":false,"error":"timeout"}"#, .timeout),
            (#"{"ok":false,"error":"mtp_response","responseCode":8217}"#, .response(code: .deviceBusy)),
        ] {
            payload = entry.0
            XCTAssertThrowsError(
                try session.download(
                    download,
                    progress: { _ in },
                    cancellation: MTPCancellationToken()
                )
            ) {
                XCTAssertEqual($0 as? MTPCoreError, entry.1)
            }
        }
        payload = "{"
        XCTAssertThrowsError(
            try session.download(
                download,
                progress: { _ in },
                cancellation: MTPCancellationToken()
            )
        ) {
            guard case .protocolViolation = $0 as? MTPCoreError else {
                return XCTFail("expected protocol violation, got \($0)")
            }
        }
        XCTAssertEqual(callCount, 7)
        XCTAssertEqual(abortCount, 7)
        XCTAssertEqual(freeCount, 8)
        session.close()
        XCTAssertEqual(freeCount, 9)
    }

    func testPreparationFailureDoesNotInstallCancellationOrInvokeTransferCleanup() throws {
        let fixture = try TransferFixture()
        let cancellation = MTPCancellationToken()
        var downloadCount = 0
        var cancelCount = 0
        var abortCount = 0
        let transferABI = KalamTransferABI(
            download: { _, _, _, _, _ in
                downloadCount += 1
                return nil
            },
            upload: { _, _, _, _, _, _, _, _ in nil },
            prepare: { _ in 0 },
            cancel: { _ in cancelCount += 1 },
            abort: { _ in
                abortCount += 1
                return 0
            }
        )
        let session = try fixture.session(transferABI: transferABI)

        XCTAssertThrowsError(
            try session.download(
                MTPDownloadRequest(
                    objectID: fixture.objectID,
                    destinationURL: URL(fileURLWithPath: "/tmp/download.bin"),
                    expectedSize: nil
                ),
                progress: { _ in },
                cancellation: cancellation
            )
        ) {
            XCTAssertEqual(
                $0 as? MTPCoreError,
                .invalidInput("Go transfer task preparation failed")
            )
        }
        cancellation.cancel()

        XCTAssertEqual(downloadCount, 0)
        XCTAssertEqual(cancelCount, 0)
        XCTAssertEqual(abortCount, 0)
        session.close()
    }

    func testCancellationDuringPreparationIsDeliveredBeforeTransferClaim() throws {
        let fixture = try TransferFixture()
        let cancellation = MTPCancellationToken()
        var events: [String] = []
        let transferABI = KalamTransferABI(
            download: { _, _, _, _, _ in
                XCTFail("pre-claim cancellation must not invoke the transfer")
                return nil
            },
            upload: { _, _, _, _, _, _, _, _ in nil },
            prepare: { _ in
                events.append("prepare")
                cancellation.cancel()
                return 1
            },
            cancel: { _ in events.append("cancel") },
            abort: { _ in
                events.append("abort")
                return 1
            }
        )
        let session = try fixture.session(transferABI: transferABI)

        XCTAssertThrowsError(
            try session.download(
                MTPDownloadRequest(
                    objectID: fixture.objectID,
                    destinationURL: URL(fileURLWithPath: "/tmp/download.bin"),
                    expectedSize: nil
                ),
                progress: { _ in },
                cancellation: cancellation
            )
        ) {
            XCTAssertEqual($0 as? MTPCoreError, .cancelled)
        }
        XCTAssertEqual(events, ["prepare", "cancel", "abort"])
        XCTAssertEqual(cancellation.registeredCallbackCount, 0)
        session.close()
    }

    func testNilTransferResponseAbortsPreparedTaskExactlyOnce() throws {
        let fixture = try TransferFixture()
        var abortCount = 0
        let transferABI = KalamTransferABI(
            download: { _, _, _, _, _ in nil },
            upload: { _, _, _, _, _, _, _, _ in nil },
            prepare: { _ in 1 },
            cancel: { _ in XCTFail("nil response must not synthesize cancellation") },
            abort: { _ in
                abortCount += 1
                return 0
            }
        )
        let session = try fixture.session(transferABI: transferABI)

        XCTAssertThrowsError(
            try session.download(
                MTPDownloadRequest(
                    objectID: fixture.objectID,
                    destinationURL: URL(fileURLWithPath: "/tmp/download.bin"),
                    expectedSize: nil
                ),
                progress: { _ in },
                cancellation: MTPCancellationToken()
            )
        )
        XCTAssertEqual(abortCount, 1)
        session.close()
    }
}

private struct TransferFixture {
    let deviceID = try! MTPDeviceID(validating: "go:5:2.4:18d1:4ee1")
    let storageID = try! MTPStorageID(validating: 1)
    let objectID = try! MTPObjectID(validating: 9)

    init() throws {}

    func session(
        transferABI: KalamTransferABI,
        free: @escaping (UnsafeMutablePointer<CChar>) -> Void = { pointer in
            Darwin.free(pointer)
        }
    ) throws -> any MTPBackendSession {
        let fileSystemABI = KalamFileSystemABI(
            open: { _ in strdup(#"{"ok":true,"token":"token-a"}"#) },
            close: { _ in strdup(#"{"ok":true}"#) },
            list: { _, _, _ in strdup(#"{"ok":true}"#) },
            free: free,
            create: { _, _, _, _ in strdup(#"{"ok":true,"objectId":9}"#) },
            delete: { _, _ in strdup(#"{"ok":true}"#) },
            refresh: { _, _ in
                strdup(
                    #"{"ok":true,"storage":{"id":1,"description":"","freeSpace":1,"maxCapacity":2}}"#
                )
            }
        )
        let kernel = KalamMTPKernelBoundary(
            fileSystemABI: fileSystemABI,
            transferABI: transferABI
        )
        kernel.recordSnapshots([
            MTPDeviceSnapshot(
                deviceID: deviceID,
                name: "Phone",
                manufacturer: "Acme",
                model: "P",
                storages: []
            ),
        ])
        return try kernel.openSession(for: deviceID)
    }
}
