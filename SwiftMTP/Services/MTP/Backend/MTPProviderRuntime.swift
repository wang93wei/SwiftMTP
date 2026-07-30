import Foundation

nonisolated protocol MTPProviderRuntimeProtocol: AnyObject, Sendable {
    var providerKind: MTPProviderKind { get }
    var coordinator: MTPConnectionCoordinator { get }
    func scanDevices() throws -> MTPScanResult
}

/// Owns the provider choice for newly opened app sessions. An active
/// coordinator session remains bound to its original provider and device.
nonisolated final class MTPProviderRuntime: MTPProviderRuntimeProtocol, @unchecked Sendable {
    static let shared = MTPProviderRuntime(providerKind: AppConfiguration.defaultMTPProvider)

    let providerKind: MTPProviderKind
    let coordinator: MTPConnectionCoordinator

    private let scanBackend: any MTPBackend
    private let scanLock = NSLock()
    private var scanBackendInitialized = false

    init(providerKind: MTPProviderKind) {
        self.providerKind = providerKind
        let kernel = KalamMTPKernelBoundary()
        let factories: [MTPProviderKind: MTPConnectionCoordinator.BackendFactory] = [
            .go: { GoMTPBackend(kernel: kernel) },
            .swift: { SwiftMTPBackend() },
        ]
        self.coordinator = MTPConnectionCoordinator(factories: factories)
        switch providerKind {
        case .go:
            self.scanBackend = GoMTPBackend(kernel: kernel)
        case .swift:
            self.scanBackend = SwiftMTPBackend()
        }
    }

    init(
        providerKind: MTPProviderKind,
        scanBackend: any MTPBackend,
        coordinator: MTPConnectionCoordinator
    ) {
        self.providerKind = providerKind
        self.scanBackend = scanBackend
        self.coordinator = coordinator
    }

    func scanDevices() throws -> MTPScanResult {
        try scanLock.withLock {
            if !scanBackendInitialized {
                try scanBackend.initialize()
                scanBackendInitialized = true
            }
            return try scanBackend.scanDevices()
        }
    }
}
