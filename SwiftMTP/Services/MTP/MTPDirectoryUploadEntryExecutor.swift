import Foundation
import OSLog

nonisolated final class MTPDirectoryUploadEntryExecutor {
    private let execution: FileTransferManager.Execution
    private let request: MTPDirectoryUploadRequest
    private let manifest: MTPDirectoryUploadManifest
    private let folderRouter: MTPDirectoryUploadFolderRouter
    private let rootID: MTPObjectID
    private let fileExecutor: MTPDirectoryUploadFileExecutor
    private var summary: MTPDirectoryUploadSummary

    init(
        coordinator: any MTPTransferCoordinating,
        execution: FileTransferManager.Execution,
        request: MTPDirectoryUploadRequest,
        manifest: MTPDirectoryUploadManifest,
        folderRouter: MTPDirectoryUploadFolderRouter,
        rootID: MTPObjectID,
        initialSummary: MTPDirectoryUploadSummary
    ) {
        self.execution = execution
        self.request = request
        self.manifest = manifest
        self.folderRouter = folderRouter
        self.rootID = rootID
        self.fileExecutor = MTPDirectoryUploadFileExecutor(
            coordinator: coordinator,
            execution: execution,
            request: request
        )
        self.summary = initialSummary
    }

    func execute() -> MTPDirectoryUploadResult {
        for (index, entry) in manifest.entries.enumerated() {
            if execution.cancellation.isCancelled || execution.isTerminal {
                summary.recordCancelled(manifest.entries[index...])
                return summary.result(forcedOutcome: .cancelled)
            }
            if let terminalResult = upload(entry, index: index) {
                return terminalResult
            }
            request.progressHandler?(index + 1, manifest.entries.count)
        }
        return summary.result()
    }

    private func upload(
        _ entry: MTPDirectoryUploadManifest.Entry,
        index: Int
    ) -> MTPDirectoryUploadResult? {
        do {
            let parentID = try folderRouter.resolveParent(for: entry, rootID: rootID)
            recordFolderMutationIfNeeded()
            // A provider upload is mutation-ambiguous once submitted.
            summary.markRemoteMutation()
            try fileExecutor.upload(
                entry,
                parentID: parentID,
                completedBytes: summary.uploadedByteCount
            )
            summary.recordUploaded(entry)
            return nil
        } catch {
            return handleFailure(error, entry: entry, index: index)
        }
    }

    private func handleFailure(
        _ error: Error,
        entry: MTPDirectoryUploadManifest.Entry,
        index: Int
    ) -> MTPDirectoryUploadResult? {
        let coreError = Self.coreError(error)
        recordFolderMutationIfNeeded()
        if coreError == .cancelled || execution.cancellation.isCancelled {
            summary.recordCancelled(manifest.entries[index...])
            return summary.result(forcedOutcome: .cancelled)
        }
        summary.recordFailed(entry, error: coreError)
        MTPLog.transfer.error(
            "Directory file upload failed for device \(self.request.deviceIdentity.deviceID.rawValue, privacy: .private(mask: .hash)), relativePath=\(entry.relativePath, privacy: .private(mask: .hash)), error=\(String(describing: coreError), privacy: .public)"
        )
        return nil
    }

    private func recordFolderMutationIfNeeded() {
        if folderRouter.remoteMutationOccurred {
            summary.markRemoteMutation()
        }
    }

    private static func coreError(_ error: Error) -> MTPCoreError {
        error as? MTPCoreError
            ?? .protocolViolation("unexpected directory upload failure")
    }
}
