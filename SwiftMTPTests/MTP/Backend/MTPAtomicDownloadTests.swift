import XCTest
@testable import SwiftMTP

final class MTPAtomicDownloadTests: XCTestCase {
    func testWriteFailureAbortsAndRemovesTemporaryFile() throws {
        let fileSystem = FakeDownloadFileSystem()
        fileSystem.file.writeError = .localFileIO("write failed")
        let destination = try makeDestination(fileSystem: fileSystem)

        XCTAssertThrowsError(try destination.write(Data([1]))) {
            XCTAssertEqual($0 as? MTPCoreError, .localFileIO("write failed"))
        }
        destination.abort()

        XCTAssertEqual(fileSystem.removedURLs, [fileSystem.temporaryURL])
        XCTAssertEqual(fileSystem.finalizationEvents, [])
    }

    func testSyncFailureDoesNotMoveTemporaryFile() throws {
        let fileSystem = FakeDownloadFileSystem()
        fileSystem.file.synchronizeError = .localFileIO("sync failed")
        let destination = try makeDestination(fileSystem: fileSystem)

        XCTAssertThrowsError(
            try destination.finish(cancellation: MTPCancellationToken())
        ) {
            XCTAssertEqual($0 as? MTPCoreError, .localFileIO("sync failed"))
        }

        XCTAssertEqual(fileSystem.removedURLs, [fileSystem.temporaryURL])
        XCTAssertEqual(fileSystem.finalizationEvents, [])
    }

    func testCloseFailureDoesNotMoveTemporaryFile() throws {
        let fileSystem = FakeDownloadFileSystem()
        fileSystem.file.closeError = .localFileIO("close failed")
        let destination = try makeDestination(fileSystem: fileSystem)

        XCTAssertThrowsError(
            try destination.finish(cancellation: MTPCancellationToken())
        ) {
            XCTAssertEqual($0 as? MTPCoreError, .localFileIO("close failed"))
        }

        XCTAssertEqual(fileSystem.removedURLs, [fileSystem.temporaryURL])
        XCTAssertEqual(fileSystem.finalizationEvents, [])
    }

    func testRenameFailurePreservesExistingDestinationAndCleansTemporaryFile() throws {
        let fileSystem = FakeDownloadFileSystem()
        fileSystem.destinationExists = true
        fileSystem.replaceError = .localFileIO("replace failed")
        let destination = try makeDestination(fileSystem: fileSystem)

        XCTAssertThrowsError(
            try destination.finish(cancellation: MTPCancellationToken())
        ) {
            XCTAssertEqual($0 as? MTPCoreError, .localFileIO("replace failed"))
        }

        XCTAssertTrue(fileSystem.destinationExists)
        XCTAssertEqual(fileSystem.removedURLs, [fileSystem.temporaryURL])
        XCTAssertEqual(fileSystem.finalizationEvents, ["replace"])
    }

    func testCancellationAfterClosePreventsFinalMove() throws {
        let fileSystem = FakeDownloadFileSystem()
        let destination = try makeDestination(fileSystem: fileSystem)
        let cancellation = MTPCancellationToken()
        fileSystem.file.onClose = { cancellation.cancel() }

        XCTAssertThrowsError(try destination.finish(cancellation: cancellation)) {
            XCTAssertEqual($0 as? MTPCoreError, .cancelled)
        }

        XCTAssertEqual(fileSystem.removedURLs, [fileSystem.temporaryURL])
        XCTAssertEqual(fileSystem.finalizationEvents, [])
    }

    func testFailIfExistsDoesNotOverwriteDestinationCreatedDuringTransfer() throws {
        let fileSystem = FakeDownloadFileSystem()
        let destination = try MTPAtomicDownloadDestination(
            destinationURL: fileSystem.destinationURL,
            replacementPolicy: .failIfExists,
            fileSystem: fileSystem
        )
        fileSystem.destinationExists = true

        XCTAssertThrowsError(
            try destination.finish(cancellation: MTPCancellationToken())
        ) {
            guard case .localFileIO = $0 as? MTPCoreError else {
                return XCTFail("expected atomic no-replace failure, got \($0)")
            }
        }

        XCTAssertTrue(fileSystem.destinationExists)
        XCTAssertEqual(fileSystem.removedURLs, [fileSystem.temporaryURL])
        XCTAssertEqual(fileSystem.finalizationEvents, ["move"])
    }

    private func makeDestination(
        fileSystem: FakeDownloadFileSystem
    ) throws -> MTPAtomicDownloadDestination {
        try MTPAtomicDownloadDestination(
            destinationURL: fileSystem.destinationURL,
            replacementPolicy: .replaceExisting,
            fileSystem: fileSystem
        )
    }
}

private final class FakeDownloadFileSystem: MTPDownloadFileSystem {
    let destinationURL = URL(fileURLWithPath: "/fixtures/final.bin")
    let temporaryURL = URL(fileURLWithPath: "/fixtures/.download.tmp")
    let file = FakeDownloadWritableFile()
    var destinationExists = false
    var moveError: MTPCoreError?
    var replaceError: MTPCoreError?
    private(set) var removedURLs: [URL] = []
    private(set) var finalizationEvents: [String] = []

    func fileExists(at url: URL) -> Bool {
        url == destinationURL && destinationExists
    }

    func makeTemporaryFile(adjacentTo destinationURL: URL) throws
        -> (url: URL, file: any MTPDownloadWritableFile) {
        (temporaryURL, file)
    }

    func moveItemWithoutReplacing(at sourceURL: URL, to destinationURL: URL) throws {
        finalizationEvents.append("move")
        if let moveError {
            throw moveError
        }
        if destinationExists {
            throw MTPCoreError.localFileIO("destination appeared during transfer")
        }
        destinationExists = true
    }

    func replaceItem(at destinationURL: URL, with sourceURL: URL) throws {
        finalizationEvents.append("replace")
        if let replaceError {
            throw replaceError
        }
        destinationExists = true
    }

    func removeItemIfPresent(at url: URL) {
        removedURLs.append(url)
    }
}

private final class FakeDownloadWritableFile: MTPDownloadWritableFile {
    var writeError: MTPCoreError?
    var synchronizeError: MTPCoreError?
    var closeError: MTPCoreError?
    var onClose: (() -> Void)?

    func write(_ data: Data) throws {
        if let writeError {
            throw writeError
        }
    }

    func synchronize() throws {
        if let synchronizeError {
            throw synchronizeError
        }
    }

    func close() throws {
        onClose?()
        if let closeError {
            throw closeError
        }
    }
}
