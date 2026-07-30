import Combine
import XCTest
@testable import SwiftMTP

@MainActor
final class MTPTransferFinalizationTests: XCTestCase {
    func testRemoteMutationRefreshesInvalidatesAndPublishesTypedEvent() async throws {
        let fileSystem = TransferFileSystemRefreshDouble()
        let center = MTPTransferCompletionCenter()
        let finalizer = MTPTransferFinalizer(
            fileSystem: fileSystem,
            completionCenter: center
        )
        let device = try makeFinalizationDevice()
        let event = TransferCompletionEvent(
            appDeviceID: device.id,
            storageID: device.storageInfo[0].storageID,
            parentID: .root,
            outcome: .completed,
            remoteMutation: true
        )

        finalizer.finalize(event, for: device)
        await waitUntil { center.latestEvent == event }

        XCTAssertEqual(fileSystem.refreshCalls, [event.storageID])
        XCTAssertEqual(fileSystem.invalidatedDeviceIDs, [device.id])
        XCTAssertEqual(center.latestEvent, event)
    }

    func testNoRemoteMutationPerformsNoRefreshInvalidationOrEvent() async throws {
        let fileSystem = TransferFileSystemRefreshDouble()
        let center = MTPTransferCompletionCenter()
        let finalizer = MTPTransferFinalizer(
            fileSystem: fileSystem,
            completionCenter: center
        )
        let device = try makeFinalizationDevice()

        finalizer.finalize(
            TransferCompletionEvent(
                appDeviceID: device.id,
                storageID: device.storageInfo[0].storageID,
                parentID: .root,
                outcome: .cancelled,
                remoteMutation: false
            ),
            for: device
        )
        await Task.yield()

        XCTAssertTrue(fileSystem.refreshCalls.isEmpty)
        XCTAssertTrue(fileSystem.invalidatedDeviceIDs.isEmpty)
        XCTAssertNil(center.latestEvent)
    }

    func testCompletionEventMatchesOnlyExactDeviceStorageAndParent() throws {
        let device = try makeFinalizationDevice()
        let storageID = device.storageInfo[0].storageID
        let event = TransferCompletionEvent(
            appDeviceID: device.id,
            storageID: storageID,
            parentID: .root,
            outcome: .partial,
            remoteMutation: true
        )

        XCTAssertTrue(
            event.matches(
                appDeviceID: device.id,
                storageID: storageID,
                parentID: .root
            )
        )
        XCTAssertFalse(
            event.matches(
                appDeviceID: UUID(),
                storageID: storageID,
                parentID: .root
            )
        )
        XCTAssertFalse(
            event.matches(
                appDeviceID: device.id,
                storageID: try MTPStorageID(validating: 2),
                parentID: .root
            )
        )
        XCTAssertFalse(
            event.matches(
                appDeviceID: device.id,
                storageID: storageID,
                parentID: try MTPObjectID(validating: 8)
            )
        )
    }

    func testPresentationMapperCoversStableTransferCategoriesWithoutTechnicalDetails() {
        XCTAssertEqual(
            MTPTransferErrorPresentation.message(for: .busy, operation: .upload),
            L10n.DeviceError.deviceBusy
        )
        XCTAssertEqual(
            MTPTransferErrorPresentation.message(
                for: .permissionDenied,
                operation: .download
            ),
            L10n.FileSystemError.permissionDenied
        )
        XCTAssertEqual(
            MTPTransferErrorPresentation.message(for: .timeout, operation: .upload),
            L10n.DeviceError.deviceTimeout
        )
        XCTAssertEqual(
            MTPTransferErrorPresentation.message(for: .cancelled, operation: .upload),
            L10n.FileTransfer.statusCancelled
        )
        XCTAssertEqual(
            MTPTransferErrorPresentation.message(
                for: .unsupportedDevice,
                operation: .download
            ),
            L10n.DeviceError.deviceNotSupported
        )
        XCTAssertEqual(
            MTPTransferErrorPresentation.message(
                for: .localFileIO("/private/path/secret.txt"),
                operation: .upload
            ),
            L10n.FileTransfer.uploadFailed
        )
        XCTAssertEqual(
            MTPTransferErrorPresentation.message(
                for: .response(code: .generalError),
                operation: .download
            ),
            L10n.FileTransfer.downloadFailed
        )
    }

    func testDirectoryPresentationCoversPartialFailureAndCancellation() {
        let partial = MTPDirectoryUploadResult(
            outcome: .partial,
            totalFiles: 3,
            uploadedFiles: 2,
            failedFiles: 1,
            skippedFiles: 0,
            fileResults: [],
            errors: ["sensitive diagnostic"],
            remoteMutationOccurred: true
        )
        let failed = MTPDirectoryUploadResult(
            outcome: .failed,
            totalFiles: 1,
            uploadedFiles: 0,
            failedFiles: 1,
            skippedFiles: 0,
            fileResults: [],
            errors: ["/private/path/secret.txt"],
            remoteMutationOccurred: false
        )

        XCTAssertEqual(
            MTPTransferErrorPresentation.directoryMessage(for: partial),
            L10n.FileBrowser.uploadDirectoryPartial.localized(2, 3)
        )
        XCTAssertEqual(
            MTPTransferErrorPresentation.directoryMessage(for: failed),
            L10n.FileBrowser.uploadDirectoryFailed.localized(
                1,
                L10n.FileTransfer.uploadFailed
            )
        )
        XCTAssertEqual(
            MTPTransferErrorPresentation.directoryMessage(
                for: MTPDirectoryUploadResult(
                    outcome: .cancelled,
                    totalFiles: 1,
                    uploadedFiles: 0,
                    failedFiles: 0,
                    skippedFiles: 1,
                    fileResults: [],
                    errors: [],
                    remoteMutationOccurred: false
                )
            ),
            L10n.FileTransfer.statusCancelled
        )
    }

    func testTransferUIUsesTypedScopedEventsWithoutLegacyRefreshNotification() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let relativePaths = [
            "SwiftMTP/Services/MTP/FileTransferManager.swift",
            "SwiftMTP/Views/FileBrowserView.swift",
            "SwiftMTP/Views/FileBrowserView+ToolbarDrop.swift",
        ]
        let sources = try relativePaths.map {
            try String(
                contentsOf: repositoryRoot.appendingPathComponent($0),
                encoding: .utf8
            )
        }

        XCTAssertFalse(sources.joined().contains("RefreshFileList"))
        XCTAssertTrue(sources[1].contains("event.matches("))
        XCTAssertFalse(sources[0].contains("FileSystemManager.shared"))
    }

}

private final class TransferFileSystemRefreshDouble:
    MTPTransferFileSystemRefreshing,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var storedRefreshCalls: [MTPStorageID] = []
    private var storedInvalidatedDeviceIDs: [UUID] = []

    var refreshCalls: [MTPStorageID] {
        lock.withLock { storedRefreshCalls }
    }

    var invalidatedDeviceIDs: [UUID] {
        lock.withLock { storedInvalidatedDeviceIDs }
    }

    func refreshStorage(for device: Device, storageID: MTPStorageID) async throws {
        lock.withLock { storedRefreshCalls.append(storageID) }
    }

    func invalidateCache(for device: Device) async {
        lock.withLock { storedInvalidatedDeviceIDs.append(device.id) }
    }
}

@MainActor
private func makeFinalizationDevice() throws -> Device {
    Device(
        deviceIndex: 0,
        mtpIdentity: MTPDeviceIdentity(
            providerKind: .go,
            deviceID: try MTPDeviceID(validating: "go:finalization-tests")
        ),
        name: "Finalization Test",
        manufacturer: "Test",
        model: "Test",
        serialNumber: "",
        batteryLevel: nil,
        storageInfo: [
            StorageInfo(
                storageID: try MTPStorageID(validating: 1),
                maxCapacity: 100,
                freeSpace: 100,
                description: "Test"
            ),
        ]
    )
}
