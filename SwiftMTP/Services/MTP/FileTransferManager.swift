import Combine
import Darwin
import Foundation
import OSLog

class FileTransferManager: ObservableObject {
    static let shared = FileTransferManager(
        coordinator: LiveMTPTransferCoordinator(
            coordinator: MTPProviderRuntime.shared.coordinator
        )
    )

    @Published var activeTasks: [TransferTask] = []
    @Published var completedTasks: [TransferTask] = []

    enum Request: @unchecked Sendable {
        case download(MTPDownloadRequest)
        case upload(MTPUploadRequest)
        case directory(MTPDirectoryUploadRequest)
    }

    nonisolated final class Execution: @unchecked Sendable {
        let task: TransferTask
        let device: Device
        let appDeviceID: UUID
        let deviceIdentity: MTPDeviceIdentity
        let request: Request
        let cancellation: MTPCancellationToken

        private let lock = NSLock()
        private var terminalClaimed = false
        private var started = false

        init(
            task: TransferTask,
            device: Device,
            appDeviceID: UUID,
            deviceIdentity: MTPDeviceIdentity,
            request: Request,
            cancellation: MTPCancellationToken
        ) {
            self.task = task
            self.device = device
            self.appDeviceID = appDeviceID
            self.deviceIdentity = deviceIdentity
            self.request = request
            self.cancellation = cancellation
        }

        var isTerminal: Bool {
            lock.withLock { terminalClaimed }
        }

        var hasStarted: Bool {
            lock.withLock { started }
        }

        func beginIfPending() -> Bool {
            lock.withLock {
                guard !terminalClaimed else {
                    return false
                }
                started = true
                return true
            }
        }

        func claimTerminal() -> Bool {
            lock.withLock {
                guard !terminalClaimed else {
                    return false
                }
                terminalClaimed = true
                return true
            }
        }
    }

    enum TerminalOutcome: Sendable {
        case completed
        case directory(MTPDirectoryUploadResult)
        case failed(MTPCoreError)
        case cancelled
    }

    let coordinator: any MTPTransferCoordinating
    private let transferQueue: DispatchQueue
    private let completionFinalizer: any MTPTransferCompletionFinalizing
    private let taskLock = NSLock()
    nonisolated(unsafe) private var executions: [UUID: Execution] = [:]

    init(
        coordinator: any MTPTransferCoordinating,
        completionFinalizer: any MTPTransferCompletionFinalizing =
            MTPTransferFinalizer.shared,
        transferQueue: DispatchQueue = DispatchQueue(
            label: "com.swiftmtp.transfer",
            qos: .userInitiated
        )
    ) {
        self.coordinator = coordinator
        self.completionFinalizer = completionFinalizer
        self.transferQueue = transferQueue
    }

    @discardableResult
    func downloadFile(
        from device: Device,
        fileItem: FileItem,
        to destinationURL: URL,
        shouldReplace: Bool = false
    ) throws -> TransferTask {
        let request = try makeDownloadRequest(
            device: device,
            fileItem: fileItem,
            destinationURL: destinationURL,
            shouldReplace: shouldReplace
        )
        let task = TransferTask(
            type: .download,
            fileName: fileItem.name,
            sourceURL: URL(fileURLWithPath: "/device/\(fileItem.objectID.rawValue)"),
            destinationPath: destinationURL.path,
            totalSize: fileItem.size
        )
        submit(
            task: task,
            device: device,
            request: .download(request)
        )
        return task
    }

    @discardableResult
    func uploadFile(
        to device: Device,
        sourceURL: URL,
        parentId: UInt32,
        storageId: UInt32
    ) throws -> TransferTask {
        let request = try makeUploadRequest(
            device: device,
            sourceURL: sourceURL,
            parentID: parentId,
            storageID: storageId
        )
        let task = TransferTask(
            type: .upload,
            fileName: request.name,
            sourceURL: request.sourceURL,
            destinationPath: "/device/\(request.parentID.rawValue)",
            totalSize: request.size
        )
        submit(
            task: task,
            device: device,
            request: .upload(request)
        )
        return task
    }

    func cancelTask(_ task: TransferTask) {
        guard let execution = execution(for: task.id) else {
            return
        }
        execution.cancellation.cancel()
        if execution.hasStarted {
            return
        }
        finish(execution, outcome: .cancelled)
    }

    func cancelAllTasks() {
        for task in activeTasks {
            cancelTask(task)
        }
    }

    func clearCompletedTasks() {
        completedTasks.removeAll()
    }

    func moveTaskToCompleted(_ task: TransferTask) {
        guard !completedTasks.contains(where: { $0.id == task.id }) else {
            return
        }
        activeTasks.removeAll { $0.id == task.id }
        completedTasks.insert(task, at: 0)
    }

    func submit(task: TransferTask, device: Device, request: Request) {
        let execution = Execution(
            task: task,
            device: device,
            appDeviceID: device.id,
            deviceIdentity: device.mtpIdentity,
            request: request,
            cancellation: MTPCancellationToken()
        )
        taskLock.withLock {
            executions[task.id] = execution
        }
        activeTasks.append(task)
        transferQueue.async { [weak self] in
            self?.execute(execution)
        }
    }

    private nonisolated func execute(_ execution: Execution) {
        guard execution.beginIfPending() else {
            return
        }
        DispatchQueue.main.async {
            guard !execution.isTerminal else {
                return
            }
            execution.task.updateStatus(.transferring)
        }

        do {
            switch execution.request {
            case .download(let request):
                try coordinator.download(
                    appDeviceID: execution.appDeviceID,
                    deviceID: execution.deviceIdentity.deviceID,
                    request: request,
                    progress: progressHandler(for: execution),
                    cancellation: execution.cancellation
                )
            case .upload(let request):
                try coordinator.upload(
                    appDeviceID: execution.appDeviceID,
                    deviceID: execution.deviceIdentity.deviceID,
                    request: request,
                    progress: progressHandler(for: execution),
                    cancellation: execution.cancellation
                )
            case .directory(let request):
                let result = try executeDirectory(
                    execution: execution,
                    request: request
                )
                finish(execution, outcome: .directory(result))
                return
            }
            finish(execution, outcome: .completed)
        } catch {
            let coreError = Self.coreError(error)
            if coreError == .cancelled || execution.cancellation.isCancelled {
                finish(execution, outcome: .cancelled)
            } else {
                finish(execution, outcome: .failed(coreError))
            }
        }
    }

    private nonisolated func progressHandler(
        for execution: Execution
    ) -> MTPTransferProgress {
        { transferredBytes in
            DispatchQueue.main.async {
                guard !execution.isTerminal else {
                    return
                }
                execution.task.updateProgress(
                    transferred: transferredBytes,
                    speed: 0
                )
            }
        }
    }

    private nonisolated func finish(
        _ execution: Execution,
        outcome: TerminalOutcome
    ) {
        guard execution.claimTerminal() else {
            return
        }
        _ = taskLock.withLock {
            executions.removeValue(forKey: execution.task.id)
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            switch outcome {
            case .completed:
                execution.task.updateProgress(
                    transferred: execution.task.totalSize,
                    speed: 0
                )
                execution.task.updateStatus(.completed)
            case .directory(let result):
                execution.task.updateDirectoryUploadResult(result)
                execution.task.updateProgress(
                    transferred: result.fileResults
                        .filter { $0.outcome == .uploaded }
                        .reduce(0) { $0 + $1.size },
                    speed: 0
                )
                switch result.outcome {
                case .succeeded:
                    execution.task.updateStatus(.completed)
                case .failed:
                    execution.task.updateStatus(
                        .failed(MTPTransferErrorPresentation.directoryMessage(for: result))
                    )
                case .partial:
                    execution.task.updateStatus(
                        .partial(MTPTransferErrorPresentation.directoryMessage(for: result))
                    )
                case .cancelled:
                    execution.task.isCancelled = true
                    execution.task.updateStatus(.cancelled)
                }
                if case .directory(let request) = execution.request {
                    request.completionHandler?(result)
                }
            case .failed(let error):
                execution.task.updateStatus(
                    .failed(
                        MTPTransferErrorPresentation.message(
                            for: error,
                            operation: Self.presentationOperation(for: execution.request)
                        )
                    )
                )
                MTPLog.transfer.error(
                    "Transfer \(execution.task.id.uuidString, privacy: .public) failed for device \(execution.deviceIdentity.deviceID.rawValue, privacy: .private(mask: .hash)), category=\(Self.diagnosticCategory(for: error), privacy: .public)"
                )
            case .cancelled:
                execution.task.isCancelled = true
                execution.task.updateStatus(.cancelled)
                if case .directory(let request) = execution.request {
                    let result = MTPDirectoryUploadResult(
                        outcome: .cancelled,
                        totalFiles: 0,
                        uploadedFiles: 0,
                        failedFiles: 0,
                        skippedFiles: 0,
                        fileResults: [],
                        errors: [],
                        remoteMutationOccurred: false
                    )
                    execution.task.updateDirectoryUploadResult(result)
                    request.completionHandler?(result)
                }
            }
            self.moveTaskToCompleted(execution.task)
            if let event = Self.completionEvent(for: execution, outcome: outcome) {
                self.completionFinalizer.finalize(event, for: execution.device)
            }
        }
    }

    private func execution(for taskID: UUID) -> Execution? {
        taskLock.withLock { executions[taskID] }
    }

    typealias DirectoryUploadResult = MTPDirectoryUploadResult
}
