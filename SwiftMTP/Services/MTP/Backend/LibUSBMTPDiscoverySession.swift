import Foundation

nonisolated final class LibUSBMTPDiscoverySession: SwiftMTPDiscoverySession {
    let deviceID: MTPDeviceID

    private let handle: LibUSBDeviceHandle
    private let session: MTPDeviceSession
    private let closeLock = NSLock()
    private var closed = false

    init(
        context: LibUSBContext,
        candidate: LibUSBDeviceCandidate,
        functions: LibUSBFunctionTable
    ) throws {
        let handle = try LibUSBDeviceHandle(
            context: context,
            candidate: candidate,
            functions: functions
        )
        let transport = LibUSBTransport(handle: handle, functions: functions)
        let session = MTPDeviceSession(transport: transport)
        do {
            try session.open()
        } catch {
            handle.close()
            throw error
        }
        self.deviceID = candidate.interface.deviceID
        self.handle = handle
        self.session = session
    }

    deinit {
        close()
    }

    func getDeviceInfo() throws -> MTPDeviceInfoDataset {
        try withOpenSession { try session.getDeviceInfo() }
    }

    func getStorageIDs() throws -> [MTPStorageID] {
        try withOpenSession { try session.getStorageIDs() }
    }

    func getStorageInfo(_ storageID: MTPStorageID) throws -> MTPStorageInfoDataset {
        try withOpenSession { try session.getStorageInfo(storageID) }
    }

    func getObjectHandles(
        storageID: MTPStorageID,
        parentID: MTPObjectID
    ) throws -> [MTPObjectID] {
        try withOpenSession {
            try session.getObjectHandles(storageID: storageID, parentID: parentID)
        }
    }

    func getObjectInfo(_ objectID: MTPObjectID) throws -> MTPObjectInfoDataset {
        try withOpenSession { try session.getObjectInfo(objectID) }
    }

    func download(
        objectID: MTPObjectID,
        sink: any MTPStreamSink,
        progress: @escaping MTPTransferProgress,
        cancellation: MTPCancellationToken
    ) throws -> MTPDownloadResult {
        try withOpenSession {
            try session.download(
                objectID: objectID,
                sink: sink,
                progress: progress,
                cancellation: cancellation
            )
        }
    }

    func upload(
        storageID: MTPStorageID,
        parentID: MTPObjectID,
        name: String,
        size: UInt64,
        modificationDateString: String,
        source: any MTPStreamSource,
        progress: @escaping MTPTransferProgress,
        cancellation: MTPCancellationToken
    ) throws -> MTPUploadResult {
        try withOpenSession {
            try session.upload(
                storageID: storageID,
                parentID: parentID,
                name: name,
                size: size,
                modificationDateString: modificationDateString,
                source: source,
                progress: progress,
                cancellation: cancellation
            )
        }
    }

    func createFolder(
        storageID: MTPStorageID,
        parentID: MTPObjectID,
        name: String
    ) throws -> MTPObjectID {
        try withOpenSession {
            try session.createFolder(storageID: storageID, parentID: parentID, name: name)
        }
    }

    func deleteObject(_ objectID: MTPObjectID) throws {
        try withOpenSession { try session.deleteObject(objectID) }
    }

    func close() {
        closeLock.withLock {
            guard !closed else {
                return
            }
            closed = true
            session.close()
            handle.close()
        }
    }

    private func withOpenSession<T>(_ operation: () throws -> T) throws -> T {
        try closeLock.withLock {
            guard !closed else {
                throw MTPCoreError.disconnected
            }
            return try operation()
        }
    }
}
