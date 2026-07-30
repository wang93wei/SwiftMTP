import Foundation

nonisolated final class SwiftMTPBackendSession: MTPBackendSession {
    let deviceID: MTPDeviceID
    let providerKind = MTPProviderKind.swift

    let discoverySession: any SwiftMTPDiscoverySession
    let makeDownloadDestination: SwiftMTPBackend.DownloadDestinationFactory
    let makeUploadSource: SwiftMTPBackend.UploadSourceFactory
    private let closeLock = NSLock()
    private var closed = false

    init(
        discoverySession: any SwiftMTPDiscoverySession,
        makeDownloadDestination: @escaping SwiftMTPBackend.DownloadDestinationFactory,
        makeUploadSource: @escaping SwiftMTPBackend.UploadSourceFactory
    ) {
        self.discoverySession = discoverySession
        self.deviceID = discoverySession.deviceID
        self.makeDownloadDestination = makeDownloadDestination
        self.makeUploadSource = makeUploadSource
    }

    deinit {
        close()
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

    func withOpenSession<T>(_ operation: () throws -> T) throws -> T {
        try closeLock.withLock {
            guard !closed else {
                throw MTPCoreError.disconnected
            }
            return try operation()
        }
    }
}
