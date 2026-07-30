import Foundation

nonisolated final class MTPDirectoryUploadExecutor {
    private let coordinator: any MTPTransferCoordinating

    init(coordinator: any MTPTransferCoordinating) {
        self.coordinator = coordinator
    }

    func execute(
        execution: FileTransferManager.Execution,
        request: MTPDirectoryUploadRequest
    ) throws -> MTPDirectoryUploadResult {
        let manifest: MTPDirectoryUploadManifest
        switch MTPDirectoryUploadPreflight.evaluate(request) {
        case .ready(let readyManifest):
            manifest = readyManifest
        case .terminal(let result):
            return result
        }

        if execution.cancellation.isCancelled || execution.isTerminal {
            return MTPDirectoryUploadSummary.cancelled(
                entries: manifest.entries,
                remoteMutationOccurred: false
            )
        }
        updateTaskTotalSize(manifest.totalSize, execution: execution)
        guard !manifest.entries.isEmpty else {
            return MTPDirectoryUploadSummary().result(forcedOutcome: .succeeded)
        }

        var summary = MTPDirectoryUploadSummary()
        let folderRouter = MTPDirectoryUploadFolderRouter(
            coordinator: coordinator,
            request: request,
            cancellation: execution.cancellation
        )
        let rootID: MTPObjectID
        do {
            rootID = try folderRouter.resolveRoot(
                named: manifest.rootURL.lastPathComponent
            )
        } catch {
            let coreError = Self.coreError(error)
            if coreError == .cancelled || execution.cancellation.isCancelled {
                return MTPDirectoryUploadSummary.cancelled(
                    entries: manifest.entries,
                    remoteMutationOccurred: folderRouter.remoteMutationOccurred
                )
            }
            return MTPDirectoryUploadSummary.allFailed(
                manifest: manifest,
                error: coreError,
                remoteMutationOccurred: folderRouter.remoteMutationOccurred
            )
        }
        if folderRouter.remoteMutationOccurred {
            summary.markRemoteMutation()
        }

        let entryExecutor = MTPDirectoryUploadEntryExecutor(
            coordinator: coordinator,
            execution: execution,
            request: request,
            manifest: manifest,
            folderRouter: folderRouter,
            rootID: rootID,
            initialSummary: summary
        )
        return entryExecutor.execute()
    }

    private func updateTaskTotalSize(
        _ totalSize: UInt64,
        execution: FileTransferManager.Execution
    ) {
        DispatchQueue.main.async {
            guard !execution.isTerminal else {
                return
            }
            execution.task.updateTotalSize(totalSize)
        }
    }

    private static func coreError(_ error: Error) -> MTPCoreError {
        error as? MTPCoreError
            ?? .protocolViolation("unexpected directory upload failure")
    }
}
