import Foundation

nonisolated final class MTPDirectoryUploadFileExecutor {
    private let coordinator: any MTPTransferCoordinating
    private let execution: FileTransferManager.Execution
    private let request: MTPDirectoryUploadRequest

    init(
        coordinator: any MTPTransferCoordinating,
        execution: FileTransferManager.Execution,
        request: MTPDirectoryUploadRequest
    ) {
        self.coordinator = coordinator
        self.execution = execution
        self.request = request
    }

    func upload(
        _ entry: MTPDirectoryUploadManifest.Entry,
        parentID: MTPObjectID,
        completedBytes: UInt64
    ) throws {
        let uploadRequest = MTPUploadRequest(
            storageID: request.storageID,
            parentID: parentID,
            sourceURL: entry.sourceURL,
            name: entry.name,
            size: entry.size
        )
        let source = try MTPUploadSourcePolicy.open(request: uploadRequest)
        source.close()
        try coordinator.upload(
            appDeviceID: request.appDeviceID,
            deviceID: request.deviceIdentity.deviceID,
            request: uploadRequest,
            progress: { [execution] transferred in
                DispatchQueue.main.async {
                    guard !execution.isTerminal else {
                        return
                    }
                    execution.task.updateProgress(
                        transferred: completedBytes + transferred,
                        speed: 0
                    )
                }
            },
            cancellation: execution.cancellation
        )
    }
}
