import Darwin
import Foundation

extension FileTransferManager {
    struct UploadDestination {
        let storageID: MTPStorageID
        let parentID: MTPObjectID
        let availableSpace: UInt64
    }

    func makeDownloadRequest(
        device: Device,
        fileItem: FileItem,
        destinationURL: URL,
        shouldReplace: Bool
    ) throws -> MTPDownloadRequest {
        guard device.isConnected else {
            throw MTPCoreError.disconnected
        }
        guard !fileItem.isDirectory else {
            throw MTPCoreError.invalidInput("download source must be a file")
        }
        guard device.storageInfo.contains(where: { $0.storageID == fileItem.storageID }) else {
            throw MTPCoreError.invalidInput("download object storage does not belong to device")
        }
        guard destinationURL.isFileURL, !destinationURL.path.isEmpty else {
            throw MTPCoreError.invalidInput("download destination must be a file URL")
        }

        let destinationPath = destinationURL.path
        let parentURL = destinationURL.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(
            atPath: destinationPath,
            isDirectory: &isDirectory
        ) {
            guard !isDirectory.boolValue else {
                throw MTPCoreError.localFileIO("download destination is a directory")
            }
            guard shouldReplace else {
                throw MTPCoreError.localFileIO("download destination already exists")
            }
        }
        do {
            try FileManager.default.createDirectory(
                at: parentURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw MTPCoreError.localFileIO("download destination directory is unavailable")
        }

        return MTPDownloadRequest(
            objectID: fileItem.objectID,
            destinationURL: destinationURL,
            expectedSize: fileItem.size,
            replacementPolicy: shouldReplace ? .replaceExisting : .failIfExists
        )
    }

    func makeUploadRequest(
        device: Device,
        sourceURL: URL,
        parentID rawParentID: UInt32,
        storageID rawStorageID: UInt32
    ) throws -> MTPUploadRequest {
        let destination = try makeUploadDestination(
            device: device,
            parentID: rawParentID,
            storageID: rawStorageID
        )
        guard sourceURL.isFileURL, !sourceURL.path.isEmpty else {
            throw MTPCoreError.invalidInput("upload source must be a file URL")
        }

        var status = stat()
        guard sourceURL.path.withCString({ lstat($0, &status) }) == 0 else {
            throw MTPCoreError.localFileIO("upload source metadata could not be read")
        }
        guard status.st_size >= 0 else {
            throw MTPCoreError.localFileIO("upload source size is invalid")
        }
        let size = UInt64(status.st_size)
        guard size <= destination.availableSpace else {
            throw MTPCoreError.invalidInput("upload source exceeds available storage")
        }

        let request = MTPUploadRequest(
            storageID: destination.storageID,
            parentID: destination.parentID,
            sourceURL: sourceURL,
            name: sourceURL.lastPathComponent,
            size: size
        )
        let inspectedSource = try MTPUploadSourcePolicy.open(request: request)
        inspectedSource.close()
        return request
    }

    func makeDirectoryUploadRequest(
        device: Device,
        sourceURL: URL,
        parentID rawParentID: UInt32,
        storageID rawStorageID: UInt32,
        progressHandler: ((Int, Int) -> Void)?,
        completionHandler: ((MTPDirectoryUploadResult) -> Void)?
    ) throws -> MTPDirectoryUploadRequest {
        let destination = try makeUploadDestination(
            device: device,
            parentID: rawParentID,
            storageID: rawStorageID
        )
        _ = try MTPDirectoryUploadManifest.validateRoot(sourceURL)
        _ = try MTPObjectInfoDataset.folder(
            storageID: destination.storageID,
            parentObject: destination.parentID,
            name: sourceURL.lastPathComponent
        )
        return MTPDirectoryUploadRequest(
            appDeviceID: device.id,
            deviceIdentity: device.mtpIdentity,
            storageID: destination.storageID,
            parentID: destination.parentID,
            sourceURL: sourceURL,
            availableSpace: destination.availableSpace,
            progressHandler: progressHandler,
            completionHandler: completionHandler
        )
    }

    private func makeUploadDestination(
        device: Device,
        parentID rawParentID: UInt32,
        storageID rawStorageID: UInt32
    ) throws -> UploadDestination {
        guard device.isConnected else {
            throw MTPCoreError.disconnected
        }
        let storageID = try MTPStorageID(validating: rawStorageID)
        let parentID = try MTPObjectID(validating: rawParentID)
        guard let storage = device.storageInfo.first(where: {
            $0.storageID == storageID
        }) else {
            throw MTPCoreError.invalidInput("upload storage does not belong to device")
        }
        return UploadDestination(
            storageID: storageID,
            parentID: parentID,
            availableSpace: storage.freeSpace
        )
    }

    nonisolated static func coreError(_ error: Error) -> MTPCoreError {
        error as? MTPCoreError
            ?? .protocolViolation("unexpected transfer provider failure")
    }

    static func completionEvent(
        for execution: Execution,
        outcome: TerminalOutcome
    ) -> TransferCompletionEvent? {
        guard let route = uploadRoute(for: execution.request) else {
            return nil
        }

        let eventOutcome: TransferCompletionOutcome
        let remoteMutation: Bool
        switch outcome {
        case .completed:
            eventOutcome = .completed
            remoteMutation = true
        case .directory(let result):
            switch result.outcome {
            case .succeeded:
                eventOutcome = .completed
            case .failed:
                eventOutcome = .failed
            case .partial:
                eventOutcome = .partial
            case .cancelled:
                eventOutcome = .cancelled
            }
            remoteMutation = result.remoteMutationOccurred
        case .failed(let error):
            eventOutcome = .failed
            remoteMutation = {
                guard case .upload = execution.request else {
                    return false
                }
                return uploadMutationMayHaveOccurred(for: error)
            }()
        case .cancelled:
            eventOutcome = .cancelled
            if case .upload = execution.request {
                remoteMutation = execution.hasStarted
            } else {
                remoteMutation = false
            }
        }
        return TransferCompletionEvent(
            appDeviceID: execution.appDeviceID,
            storageID: route.storageID,
            parentID: route.parentID,
            outcome: eventOutcome,
            remoteMutation: remoteMutation
        )
    }

    private static func uploadRoute(
        for request: Request
    ) -> (storageID: MTPStorageID, parentID: MTPObjectID)? {
        switch request {
        case .download:
            return nil
        case .upload(let request):
            return (request.storageID, request.parentID)
        case .directory(let request):
            return (request.storageID, request.parentID)
        }
    }

    static func uploadMutationMayHaveOccurred(for error: MTPCoreError) -> Bool {
        switch error {
        case .invalidIdentifier, .invalidInput, .noDevice, .busy,
             .permissionDenied, .unsupportedDevice, .localFileIO:
            return false
        case .disconnected, .timeout, .cancelled, .usb, .response,
             .protocolViolation:
            return true
        }
    }

    static func diagnosticCategory(for error: MTPCoreError) -> String {
        switch error {
        case .invalidIdentifier(let kind, let value):
            return "invalid_identifier_\(kind.rawValue)_\(value)"
        case .invalidInput:
            return "invalid_input"
        case .noDevice:
            return "no_device"
        case .busy:
            return "busy"
        case .permissionDenied:
            return "permission_denied"
        case .disconnected:
            return "disconnected"
        case .timeout:
            return "timeout"
        case .cancelled:
            return "cancelled"
        case .usb(let code):
            return "usb_\(code)"
        case .response(let code):
            return "response_\(code.rawValue)"
        case .protocolViolation:
            return "protocol_violation"
        case .unsupportedDevice:
            return "unsupported_device"
        case .localFileIO:
            return "local_file_io"
        }
    }

    static func presentationOperation(
        for request: Request
    ) -> MTPTransferPresentationOperation {
        switch request {
        case .download:
            return .download
        case .upload:
            return .upload
        case .directory:
            return .directoryUpload
        }
    }
}
