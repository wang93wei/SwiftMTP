import Foundation
import OSLog

nonisolated protocol SwiftMTPDiscoverySession: AnyObject {
    var deviceID: MTPDeviceID { get }
    func getDeviceInfo() throws -> MTPDeviceInfoDataset
    func getStorageIDs() throws -> [MTPStorageID]
    func getStorageInfo(_ storageID: MTPStorageID) throws -> MTPStorageInfoDataset
    func getObjectHandles(
        storageID: MTPStorageID,
        parentID: MTPObjectID
    ) throws -> [MTPObjectID]
    func getObjectInfo(_ objectID: MTPObjectID) throws -> MTPObjectInfoDataset
    func download(
        objectID: MTPObjectID,
        sink: any MTPStreamSink,
        progress: @escaping MTPTransferProgress,
        cancellation: MTPCancellationToken
    ) throws -> MTPDownloadResult
    func upload(
        storageID: MTPStorageID,
        parentID: MTPObjectID,
        name: String,
        size: UInt64,
        modificationDateString: String,
        source: any MTPStreamSource,
        progress: @escaping MTPTransferProgress,
        cancellation: MTPCancellationToken
    ) throws -> MTPUploadResult
    func createFolder(
        storageID: MTPStorageID,
        parentID: MTPObjectID,
        name: String
    ) throws -> MTPObjectID
    func deleteObject(_ objectID: MTPObjectID) throws
    func close()
}

nonisolated final class SwiftMTPBackend: MTPBackend {
    typealias ContextFactory = () throws -> LibUSBContext
    typealias Enumerator = (LibUSBContext) throws -> [LibUSBDeviceCandidate]
    typealias SessionFactory = (
        LibUSBContext,
        LibUSBDeviceCandidate
    ) throws -> any SwiftMTPDiscoverySession
    typealias DownloadDestinationFactory = (
        URL,
        MTPDownloadReplacementPolicy
    ) throws -> any MTPDownloadDestination
    typealias UploadSourceFactory = (
        MTPUploadRequest
    ) throws -> any MTPUploadSource

    private let stateLock = NSLock()
    private let contextFactory: ContextFactory
    private let enumerateCandidates: Enumerator
    private let makeSession: SessionFactory
    private let makeDownloadDestination: DownloadDestinationFactory
    private let makeUploadSource: UploadSourceFactory
    private var context: LibUSBContext?

    init(
        functions: LibUSBFunctionTable = LibUSBFunctionTable(),
        contextFactory: ContextFactory? = nil,
        enumerateCandidates: Enumerator? = nil,
        makeSession: SessionFactory? = nil,
        makeDownloadDestination: DownloadDestinationFactory? = nil,
        makeUploadSource: UploadSourceFactory? = nil
    ) {
        self.contextFactory = contextFactory ?? {
            try LibUSBContext(functions: functions)
        }
        self.enumerateCandidates = enumerateCandidates ?? { context in
            try USBDeviceEnumerator(context: context, functions: functions).enumerate()
        }
        self.makeSession = makeSession ?? { context, candidate in
            try LibUSBMTPDiscoverySession(
                context: context,
                candidate: candidate,
                functions: functions
            )
        }
        self.makeDownloadDestination = makeDownloadDestination ?? {
            try MTPAtomicDownloadDestination(
                destinationURL: $0,
                replacementPolicy: $1
            )
        }
        self.makeUploadSource = makeUploadSource ?? {
            try MTPUploadSourcePolicy.open(request: $0)
        }
    }

    func initialize() throws {
        if stateLock.withLock({ context != nil }) {
            return
        }
        let newContext = try contextFactory()
        let installed = stateLock.withLock {
            guard context == nil else {
                return false
            }
            context = newContext
            return true
        }
        if !installed {
            newContext.shutdown()
        }
    }

    func scanDevices() throws -> MTPScanResult {
        let context = try currentContext()
        let candidates = try enumerateCandidates(context)
        var snapshots: [MTPDeviceSnapshot] = []
        var failures: [MTPScanFailure] = []

        for candidate in candidates {
            let deviceID = candidate.interface.deviceID
            do {
                let session = try makeSession(context, candidate)
                defer { session.close() }
                guard session.deviceID == deviceID else {
                    throw MTPCoreError.protocolViolation(
                        "Swift scan opened a different device"
                    )
                }
                let deviceInfo = try session.getDeviceInfo()
                let storageIDs = try session.getStorageIDs()
                var storages: [MTPStorage] = []
                for storageID in storageIDs {
                    do {
                        let info = try session.getStorageInfo(storageID)
                        storages.append(
                            MTPStorage(
                                id: storageID,
                                description: info.description,
                                freeSpace: info.freeSpaceInBytes,
                                maxCapacity: info.maxCapacity
                            )
                        )
                    } catch {
                        let coreError = Self.coreError(error)
                        failures.append(
                            MTPScanFailure(
                                deviceID: deviceID,
                                storageID: storageID,
                                stage: .storage,
                                error: coreError
                            )
                        )
                        MTPLog.session.error(
                            "Storage scan failed for \(deviceID.rawValue, privacy: .private(mask: .hash))"
                        )
                        break
                    }
                }
                snapshots.append(
                    MTPDeviceSnapshot(
                        deviceID: deviceID,
                        name: deviceInfo.model,
                        manufacturer: deviceInfo.manufacturer,
                        model: deviceInfo.model,
                        storages: storages
                    )
                )
            } catch {
                failures.append(
                    MTPScanFailure(
                        deviceID: deviceID,
                        storageID: nil,
                        stage: .device,
                        error: Self.coreError(error)
                    )
                )
                MTPLog.session.error(
                    "Device scan failed for \(deviceID.rawValue, privacy: .private(mask: .hash))"
                )
            }
        }
        return MTPScanResult(snapshots: snapshots, failures: failures)
    }

    func openSession(for deviceID: MTPDeviceID) throws -> any MTPBackendSession {
        guard deviceID.rawValue.hasPrefix("swift:") else {
            throw MTPCoreError.invalidInput("device ID does not belong to Swift provider")
        }
        let context = try currentContext()
        let candidates = try enumerateCandidates(context)
        let matches = candidates.filter { $0.interface.deviceID == deviceID }
        guard !matches.isEmpty else {
            throw MTPCoreError.noDevice
        }
        guard matches.count == 1, let candidate = matches.first else {
            throw MTPCoreError.protocolViolation("duplicate Swift USB transport identity")
        }
        let session = try makeSession(context, candidate)
        guard session.deviceID == deviceID else {
            session.close()
            throw MTPCoreError.protocolViolation("Swift provider opened a different device")
        }
        return SwiftMTPBackendSession(
            discoverySession: session,
            makeDownloadDestination: makeDownloadDestination,
            makeUploadSource: makeUploadSource
        )
    }

    func shutdown() {
        let context = stateLock.withLock {
            let current = self.context
            self.context = nil
            return current
        }
        context?.shutdown()
    }

    private func currentContext() throws -> LibUSBContext {
        try stateLock.withLock {
            guard let context else {
                throw MTPCoreError.disconnected
            }
            return context
        }
    }

    private static func coreError(_ error: Error) -> MTPCoreError {
        error as? MTPCoreError
            ?? .protocolViolation("unexpected Swift MTP discovery failure")
    }
}
