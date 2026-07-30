import XCTest
@testable import SwiftMTP

final class SwiftMTPDownloadBackendTests: XCTestCase {
    func testEmptyDownloadAtomicallyCreatesDestinationWithoutTemporaryResidue() throws {
        let fixture = try makeDownloadFixture()
        defer { fixture.cleanup() }
        fixture.discovery.downloadData = Data()
        fixture.discovery.downloadResult = MTPDownloadResult(
            expectedByteCount: 0,
            transferredByteCount: 0
        )
        let destinationURL = fixture.directoryURL.appendingPathComponent("empty.bin")

        try fixture.session.download(
            MTPDownloadRequest(
                objectID: fixture.objectID,
                destinationURL: destinationURL,
                expectedSize: 0
            ),
            progress: { _ in },
            cancellation: MTPCancellationToken()
        )

        XCTAssertEqual(try Data(contentsOf: destinationURL), Data())
        XCTAssertEqual(try fixture.temporaryFiles(), [])
        fixture.close()
    }

    func testReplaceExistingKeepsOldDestinationUntilTransferSucceeds() throws {
        let fixture = try makeDownloadFixture()
        defer { fixture.cleanup() }
        let destinationURL = fixture.directoryURL.appendingPathComponent("replace.bin")
        try Data("old".utf8).write(to: destinationURL)
        fixture.discovery.downloadData = Data("new".utf8)
        fixture.discovery.downloadResult = MTPDownloadResult(
            expectedByteCount: 3,
            transferredByteCount: 3
        )
        fixture.discovery.beforeDownload = {
            XCTAssertEqual(try? Data(contentsOf: destinationURL), Data("old".utf8))
        }

        try fixture.session.download(
            MTPDownloadRequest(
                objectID: fixture.objectID,
                destinationURL: destinationURL,
                expectedSize: 3,
                replacementPolicy: .replaceExisting
            ),
            progress: { _ in },
            cancellation: MTPCancellationToken()
        )

        XCTAssertEqual(try Data(contentsOf: destinationURL), Data("new".utf8))
        XCTAssertEqual(try fixture.temporaryFiles(), [])
        fixture.close()
    }

    func testFailedDownloadPreservesExistingDestinationAndRemovesTemporaryFile() throws {
        let fixture = try makeDownloadFixture()
        defer { fixture.cleanup() }
        let destinationURL = fixture.directoryURL.appendingPathComponent("preserve.bin")
        try Data("old".utf8).write(to: destinationURL)
        fixture.discovery.downloadData = Data("partial".utf8)
        fixture.discovery.downloadError = .timeout

        XCTAssertThrowsError(
            try fixture.session.download(
                MTPDownloadRequest(
                    objectID: fixture.objectID,
                    destinationURL: destinationURL,
                    expectedSize: 7,
                    replacementPolicy: .replaceExisting
                ),
                progress: { _ in },
                cancellation: MTPCancellationToken()
            )
        ) {
            XCTAssertEqual($0 as? MTPCoreError, .timeout)
        }

        XCTAssertEqual(try Data(contentsOf: destinationURL), Data("old".utf8))
        XCTAssertEqual(try fixture.temporaryFiles(), [])
        fixture.close()
    }

    func testFailIfExistsRejectsBeforeStartingDeviceTransfer() throws {
        let fixture = try makeDownloadFixture()
        defer { fixture.cleanup() }
        let destinationURL = fixture.directoryURL.appendingPathComponent("existing.bin")
        try Data("old".utf8).write(to: destinationURL)

        XCTAssertThrowsError(
            try fixture.session.download(
                MTPDownloadRequest(
                    objectID: fixture.objectID,
                    destinationURL: destinationURL,
                    expectedSize: 0,
                    replacementPolicy: .failIfExists
                ),
                progress: { _ in },
                cancellation: MTPCancellationToken()
            )
        ) {
            guard case .invalidInput = $0 as? MTPCoreError else {
                return XCTFail("expected invalid destination rejection, got \($0)")
            }
        }

        XCTAssertEqual(fixture.discovery.downloadCount, 0)
        XCTAssertEqual(try Data(contentsOf: destinationURL), Data("old".utf8))
        XCTAssertEqual(try fixture.temporaryFiles(), [])
        fixture.close()
    }

    func testCancelledDownloadPreservesExistingDestinationAndRemovesTemporaryFile() throws {
        let fixture = try makeDownloadFixture()
        defer { fixture.cleanup() }
        let destinationURL = fixture.directoryURL.appendingPathComponent("cancel.bin")
        try Data("old".utf8).write(to: destinationURL)
        let cancellation = MTPCancellationToken()
        fixture.discovery.beforeDownload = { cancellation.cancel() }

        XCTAssertThrowsError(
            try fixture.session.download(
                MTPDownloadRequest(
                    objectID: fixture.objectID,
                    destinationURL: destinationURL,
                    expectedSize: 3
                ),
                progress: { _ in },
                cancellation: cancellation
            )
        ) {
            XCTAssertEqual($0 as? MTPCoreError, .cancelled)
        }

        XCTAssertEqual(try Data(contentsOf: destinationURL), Data("old".utf8))
        XCTAssertEqual(try fixture.temporaryFiles(), [])
        fixture.close()
    }

    private func makeDownloadFixture() throws -> SwiftDownloadFixture {
        let harness = try makeSwiftMTPBackendHarness(rawDeviceValue: 0x601)
        let objectID = try MTPObjectID(validating: 9)
        try harness.backend.initialize()
        let session = try harness.backend.openSession(for: harness.deviceID)
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "swiftmtp-download-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: false
        )
        return SwiftDownloadFixture(
            backend: harness.backend,
            session: session,
            discovery: harness.discovery,
            objectID: objectID,
            directoryURL: directoryURL
        )
    }
}
