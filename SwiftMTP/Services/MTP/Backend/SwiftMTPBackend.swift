import Foundation
import OSLog

nonisolated struct MTPScanFailure: Equatable, Sendable {
    enum Stage: String, Equatable, Sendable {
        case device
        case storage
    }

    let deviceID: MTPDeviceID
    let storageID: MTPStorageID?
    let stage: Stage
    let error: MTPCoreError
}

nonisolated protocol SwiftMTPDiscoverySession: AnyObject {
    var deviceID: MTPDeviceID { get }
    func getDeviceInfo() throws -> MTPDeviceInfoDataset
    func getStorageIDs() throws -> [MTPStorageID]
    func getStorageInfo(_ storageID: MTPStorageID) throws -> MTPStorageInfoDataset
    func close()
}

nonisolated final class SwiftMTPBackend: MTPBackend {
    typealias ContextFactory = () throws -> LibUSBContext
    typealias Enumerator = (LibUSBContext) throws -> [LibUSBDeviceCandidate]
    typealias SessionFactory = (
        LibUSBContext,
        LibUSBDeviceCandidate
    ) throws -> any SwiftMTPDiscoverySession

    private let stateLock = NSLock()
    private let contextFactory: ContextFactory
    private let enumerateCandidates: Enumerator
    private let makeSession: SessionFactory
    private var context: LibUSBContext?
    private var scanFailures: [MTPScanFailure] = []

    var lastScanFailures: [MTPScanFailure] {
        stateLock.withLock { scanFailures }
    }

    init(
        functions: LibUSBFunctionTable = LibUSBFunctionTable(),
        contextFactory: ContextFactory? = nil,
        enumerateCandidates: Enumerator? = nil,
        makeSession: SessionFactory? = nil
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

    func scanDevices() throws -> [MTPDeviceSnapshot] {
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
        stateLock.withLock {
            scanFailures = failures
        }
        return snapshots
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
        return SwiftMTPBackendSession(discoverySession: session)
    }

    func shutdown() {
        let context = stateLock.withLock {
            let current = self.context
            self.context = nil
            scanFailures.removeAll()
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

private nonisolated final class LibUSBMTPDiscoverySession: SwiftMTPDiscoverySession {
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

private nonisolated final class SwiftMTPBackendSession: MTPBackendSession {
    let deviceID: MTPDeviceID
    let providerKind = MTPProviderKind.swift

    private let discoverySession: any SwiftMTPDiscoverySession
    private let closeLock = NSLock()
    private var closed = false

    init(discoverySession: any SwiftMTPDiscoverySession) {
        self.discoverySession = discoverySession
        self.deviceID = discoverySession.deviceID
    }

    deinit {
        close()
    }

    func listObjects(
        storageID: MTPStorageID,
        parentID: MTPObjectID
    ) throws -> [MTPObject] {
        throw try unsupported()
    }

    func createFolder(
        storageID: MTPStorageID,
        parentID: MTPObjectID,
        name: String
    ) throws -> MTPObjectID {
        throw try unsupported()
    }

    func deleteObject(_ objectID: MTPObjectID) throws {
        throw try unsupported()
    }

    func download(
        _ request: MTPDownloadRequest,
        progress: @escaping (UInt64) -> Void,
        cancellation: MTPCancellationToken
    ) throws {
        throw try unsupported()
    }

    func upload(
        _ request: MTPUploadRequest,
        progress: @escaping (UInt64) -> Void,
        cancellation: MTPCancellationToken
    ) throws {
        throw try unsupported()
    }

    func refreshStorage(_ storageID: MTPStorageID) throws {
        _ = try closeLock.withLock {
            guard !closed else {
                throw MTPCoreError.disconnected
            }
            return try discoverySession.getStorageInfo(storageID)
        }
    }

    func close() {
        closeLock.withLock {
            guard !closed else {
                return
            }
            closed = true
            discoverySession.close()
        }
    }

    private func unsupported() throws -> MTPCoreError {
        try closeLock.withLock {
            guard !closed else {
                throw MTPCoreError.disconnected
            }
            return .unsupportedDevice
        }
    }
}
