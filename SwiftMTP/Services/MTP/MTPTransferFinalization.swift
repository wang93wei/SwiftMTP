import Combine
import Foundation
import OSLog

nonisolated enum TransferCompletionOutcome: Equatable, Sendable {
    case completed
    case failed
    case partial
    case cancelled
}

nonisolated struct TransferCompletionEvent: Equatable, Sendable {
    let appDeviceID: UUID
    let storageID: MTPStorageID
    let parentID: MTPObjectID
    let outcome: TransferCompletionOutcome
    let remoteMutation: Bool

    func matches(
        appDeviceID: UUID,
        storageID: MTPStorageID,
        parentID: MTPObjectID
    ) -> Bool {
        self.appDeviceID == appDeviceID
            && self.storageID == storageID
            && self.parentID == parentID
    }
}

@MainActor
final class MTPTransferCompletionCenter: ObservableObject {
    static let shared = MTPTransferCompletionCenter()

    @Published private(set) var latestEvent: TransferCompletionEvent?
    let events = PassthroughSubject<TransferCompletionEvent, Never>()

    func publish(_ event: TransferCompletionEvent) {
        latestEvent = event
        events.send(event)
    }
}

@MainActor
protocol MTPTransferFileSystemRefreshing: AnyObject {
    func refreshStorage(for device: Device, storageID: MTPStorageID) async throws
    func invalidateCache(for device: Device) async
}

@MainActor
private final class LiveMTPTransferFileSystemRefresh:
    MTPTransferFileSystemRefreshing
{
    private let manager: FileSystemManager

    init(manager: FileSystemManager = .shared) {
        self.manager = manager
    }

    func refreshStorage(for device: Device, storageID: MTPStorageID) async throws {
        _ = try await manager.refreshStorage(for: device, storageID: storageID)
    }

    func invalidateCache(for device: Device) async {
        await manager.clearCache(for: device)
    }
}

@MainActor
protocol MTPTransferCompletionFinalizing: AnyObject {
    func finalize(_ event: TransferCompletionEvent, for device: Device)
}

@MainActor
final class MTPTransferFinalizer: MTPTransferCompletionFinalizing {
    static let shared = MTPTransferFinalizer()

    private let fileSystem: any MTPTransferFileSystemRefreshing
    private let completionCenter: MTPTransferCompletionCenter

    init(
        fileSystem: any MTPTransferFileSystemRefreshing =
            LiveMTPTransferFileSystemRefresh(),
        completionCenter: MTPTransferCompletionCenter = .shared
    ) {
        self.fileSystem = fileSystem
        self.completionCenter = completionCenter
    }

    func finalize(_ event: TransferCompletionEvent, for device: Device) {
        guard event.remoteMutation else {
            return
        }
        Task { @MainActor [fileSystem, completionCenter] in
            do {
                try await fileSystem.refreshStorage(
                    for: device,
                    storageID: event.storageID
                )
            } catch {
                MTPLog.transfer.error(
                    "Transfer storage refresh failed for device \(device.mtpIdentity.deviceID.rawValue, privacy: .private(mask: .hash)), storage=\(event.storageID.rawValue, privacy: .public), category=\(String(reflecting: type(of: error)), privacy: .public)"
                )
            }
            await fileSystem.invalidateCache(for: device)
            completionCenter.publish(event)
        }
    }
}

enum MTPTransferPresentationOperation {
    case download
    case upload
    case directoryUpload
}

@MainActor
enum MTPTransferErrorPresentation {
    static func message(
        for error: MTPCoreError,
        operation: MTPTransferPresentationOperation
    ) -> String {
        switch error {
        case .disconnected, .noDevice:
            return L10n.FileTransfer.deviceDisconnectedReconnect
        case .busy:
            return L10n.DeviceError.deviceBusy
        case .permissionDenied:
            return L10n.FileSystemError.permissionDenied
        case .timeout:
            return L10n.DeviceError.deviceTimeout
        case .cancelled:
            return L10n.FileTransfer.statusCancelled
        case .unsupportedDevice:
            return L10n.DeviceError.deviceNotSupported
        case .invalidIdentifier, .invalidInput, .usb, .response,
             .protocolViolation, .localFileIO:
            return genericFailure(for: operation)
        }
    }

    static func directoryMessage(for result: MTPDirectoryUploadResult) -> String {
        switch result.outcome {
        case .succeeded:
            return ""
        case .failed:
            return L10n.FileBrowser.uploadDirectoryFailed.localized(
                result.failedFiles,
                L10n.FileTransfer.uploadFailed
            )
        case .partial:
            return L10n.FileBrowser.uploadDirectoryPartial.localized(
                result.uploadedFiles,
                result.totalFiles
            )
        case .cancelled:
            return L10n.FileTransfer.statusCancelled
        }
    }

    private static func genericFailure(
        for operation: MTPTransferPresentationOperation
    ) -> String {
        switch operation {
        case .download:
            return L10n.FileTransfer.downloadFailed
        case .upload, .directoryUpload:
            return L10n.FileTransfer.uploadFailed
        }
    }
}
