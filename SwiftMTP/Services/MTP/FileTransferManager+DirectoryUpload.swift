import Foundation

extension FileTransferManager {
    @discardableResult
    func uploadDirectory(
        to device: Device,
        sourceURL: URL,
        parentId rawParentID: UInt32,
        storageId rawStorageID: UInt32,
        progressHandler: ((Int, Int) -> Void)? = nil,
        completionHandler: ((MTPDirectoryUploadResult) -> Void)? = nil
    ) throws -> TransferTask {
        let request = try makeDirectoryUploadRequest(
            device: device,
            sourceURL: sourceURL,
            parentID: rawParentID,
            storageID: rawStorageID,
            progressHandler: progressHandler,
            completionHandler: completionHandler
        )
        let task = TransferTask(
            type: .upload,
            fileName: "📁 \(sourceURL.lastPathComponent)",
            sourceURL: sourceURL,
            destinationPath: "/device/\(request.parentID.rawValue)",
            totalSize: 0
        )
        submit(
            task: task,
            device: device,
            request: .directory(request)
        )
        return task
    }

    nonisolated func executeDirectory(
        execution: Execution,
        request: MTPDirectoryUploadRequest
    ) throws -> MTPDirectoryUploadResult {
        try MTPDirectoryUploadExecutor(coordinator: coordinator).execute(
            execution: execution,
            request: request
        )
    }
}
