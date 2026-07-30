import XCTest
@testable import SwiftMTP

@MainActor
final class DeviceManagerBackendTests: XCTestCase {
    func testRepeatedLegacyIndicesAndReorderedSnapshotsKeepStableSeparateUUIDs() async throws {
        let firstID = try MTPDeviceID(validating: "go:bus1:0")
        let secondID = try MTPDeviceID(validating: "go:bus2:0")
        let first = snapshot(firstID, name: "First")
        let second = snapshot(secondID, name: "Second")
        let runtime = FakeProviderRuntime(scans: [[first, second], [second, first]])
        let manager = DeviceManager(runtime: runtime, startsScanning: false)

        await manager.scanDevicesAndWait()
        let initial = Dictionary(uniqueKeysWithValues: manager.devices.map {
            ($0.mtpIdentity.deviceID, $0.id)
        })
        XCTAssertEqual(Set(manager.devices.map(\.deviceIndex)), [0])

        await manager.scanDevicesAndWait()
        let reordered = Dictionary(uniqueKeysWithValues: manager.devices.map {
            ($0.mtpIdentity.deviceID, $0.id)
        })

        XCTAssertEqual(initial, reordered)
        XCTAssertNotEqual(initial[firstID], initial[secondID])
        manager.prepareForTermination()
    }

    func testSelectedDeviceDisconnectClosesCoordinatorAndClearsPublishedState() async throws {
        let deviceID = try MTPDeviceID(validating: "go:bus1:0")
        let runtime = FakeProviderRuntime(scans: [[snapshot(deviceID, name: "Phone")], []])
        let manager = DeviceManager(runtime: runtime, startsScanning: false)

        await manager.scanDevicesAndWait()
        XCTAssertNotNil(manager.selectedDevice)

        await manager.scanDevicesAndWait()

        XCTAssertEqual(manager.devices, [])
        XCTAssertNil(manager.selectedDevice)
        XCTAssertNotNil(manager.connectionError)
        manager.prepareForTermination()
    }

    func testPartialScanFailuresRemainVisibleWithHealthyDevices() async throws {
        let deviceID = try MTPDeviceID(validating: "go:bus1:0")
        let failedID = try MTPDeviceID(validating: "go:bus2:0")
        let failure = MTPScanFailure(
            deviceID: failedID,
            storageID: nil,
            stage: .device,
            error: .permissionDenied
        )
        let runtime = FakeProviderRuntime(
            results: [
                .success(
                    MTPScanResult(
                        snapshots: [snapshot(deviceID, name: "Phone")],
                        failures: [failure]
                    )
                ),
            ]
        )
        let manager = DeviceManager(runtime: runtime, startsScanning: false)

        await manager.scanDevicesAndWait()

        XCTAssertEqual(manager.devices.map(\.mtpIdentity.deviceID), [deviceID])
        XCTAssertEqual(manager.scanFailures, [failure])
        manager.prepareForTermination()
    }

    func testTransientScanFailuresPreserveSelectedDeviceAndSession() async throws {
        let deviceID = try MTPDeviceID(validating: "go:bus1:0")
        let runtime = FakeProviderRuntime(
            results: [
                .success(
                    MTPScanResult(
                        snapshots: [snapshot(deviceID, name: "Phone")],
                        failures: []
                    )
                ),
                .failure(.timeout),
                .failure(.protocolViolation("Go device JSON decode failed")),
            ]
        )
        let manager = DeviceManager(runtime: runtime, startsScanning: false)

        await manager.scanDevicesAndWait()
        let selectedID = manager.selectedDevice?.id
        await manager.scanDevicesAndWait()
        await manager.scanDevicesAndWait()

        XCTAssertEqual(manager.devices.map(\.mtpIdentity.deviceID), [deviceID])
        XCTAssertEqual(manager.selectedDevice?.id, selectedID)
        XCTAssertEqual(runtime.backend.sessions.first?.closeCount, 0)
        manager.prepareForTermination()
    }

    func testPartialFailureForSelectedIdentityDoesNotConfirmDisappearance() async throws {
        let deviceID = try MTPDeviceID(validating: "go:bus1:0")
        let failure = MTPScanFailure(
            deviceID: deviceID,
            storageID: nil,
            stage: .device,
            error: .timeout
        )
        let runtime = FakeProviderRuntime(
            results: [
                .success(
                    MTPScanResult(
                        snapshots: [snapshot(deviceID, name: "Phone")],
                        failures: []
                    )
                ),
                .success(MTPScanResult(snapshots: [], failures: [failure])),
            ]
        )
        let manager = DeviceManager(runtime: runtime, startsScanning: false)

        await manager.scanDevicesAndWait()
        let selectedID = manager.selectedDevice?.id
        await manager.scanDevicesAndWait()

        XCTAssertEqual(manager.devices.map(\.mtpIdentity.deviceID), [deviceID])
        XCTAssertEqual(manager.selectedDevice?.id, selectedID)
        XCTAssertEqual(manager.scanFailures, [failure])
        XCTAssertEqual(runtime.backend.sessions.first?.closeCount, 0)
        manager.prepareForTermination()
    }

    func testExplicitDisconnectClearsSelectedDeviceAndClosesSession() async throws {
        let deviceID = try MTPDeviceID(validating: "go:bus1:0")
        let runtime = FakeProviderRuntime(
            results: [
                .success(
                    MTPScanResult(
                        snapshots: [snapshot(deviceID, name: "Phone")],
                        failures: []
                    )
                ),
                .failure(.disconnected),
            ]
        )
        let manager = DeviceManager(runtime: runtime, startsScanning: false)

        await manager.scanDevicesAndWait()
        await manager.scanDevicesAndWait()

        XCTAssertTrue(manager.devices.isEmpty)
        XCTAssertNil(manager.selectedDevice)
        XCTAssertEqual(runtime.backend.sessions.first?.closeCount, 1)
        manager.prepareForTermination()
    }

    func testRepeatedScanFailuresReachManualRefreshState() async {
        let runtime = FakeProviderRuntime(
            results: [
                .failure(.timeout),
                .failure(.timeout),
                .failure(.timeout),
            ]
        )
        let manager = DeviceManager(runtime: runtime, startsScanning: false)

        for _ in 0..<3 {
            await manager.scanDevicesAndWait()
        }

        XCTAssertTrue(manager.hasScannedOnce)
        XCTAssertTrue(manager.showManualRefreshButton)
        manager.prepareForTermination()
    }
}

final class MTPProviderRuntimeTests: XCTestCase {
    func testScanCarriesBackendSnapshotsAndFailuresTogether() throws {
        let deviceID = try MTPDeviceID(validating: "swift:1:1:1111:0001")
        let failure = MTPScanFailure(
            deviceID: deviceID,
            storageID: nil,
            stage: .device,
            error: .permissionDenied
        )
        let backend = FakeMTPBackend(providerKind: .swift)
        backend.scanResult = MTPScanResult(
            snapshots: [snapshot(deviceID, name: "Phone")],
            failures: [failure]
        )
        let coordinator = MTPConnectionCoordinator(
            factories: [.swift: { backend }]
        )
        let runtime = MTPProviderRuntime(
            providerKind: .swift,
            scanBackend: backend,
            coordinator: coordinator
        )

        let result = try runtime.scanDevices()

        XCTAssertEqual(result, backend.scanResult)
        XCTAssertEqual(backend.initializeCount, 1)
    }
}

private final class FakeProviderRuntime: MTPProviderRuntimeProtocol, @unchecked Sendable {
    enum ScanResult {
        case success(MTPScanResult)
        case failure(MTPCoreError)
    }

    let providerKind = MTPProviderKind.go
    let coordinator: MTPConnectionCoordinator
    let backend: FakeMTPBackend
    private let lock = NSLock()
    private var results: [ScanResult]

    init(scans: [[MTPDeviceSnapshot]]) {
        results = scans.map {
            .success(MTPScanResult(snapshots: $0, failures: []))
        }
        let backend = FakeMTPBackend(providerKind: .go)
        self.backend = backend
        coordinator = MTPConnectionCoordinator(
            factories: [.go: { backend }]
        )
    }

    init(results: [ScanResult]) {
        self.results = results
        let backend = FakeMTPBackend(providerKind: .go)
        self.backend = backend
        coordinator = MTPConnectionCoordinator(
            factories: [.go: { backend }]
        )
    }

    func scanDevices() throws -> MTPScanResult {
        try lock.withLock {
            guard !results.isEmpty else {
                return MTPScanResult(snapshots: [], failures: [])
            }
            switch results.removeFirst() {
            case .success(let snapshots):
                return snapshots
            case .failure(let error):
                throw error
            }
        }
    }
}

private func snapshot(_ id: MTPDeviceID, name: String) -> MTPDeviceSnapshot {
    MTPDeviceSnapshot(
        deviceID: id,
        name: name,
        manufacturer: "Acme",
        model: "P",
        storages: [
            MTPStorage(
                id: try! MTPStorageID(validating: 1),
                description: "Internal",
                freeSpace: 1,
                maxCapacity: 2
            ),
        ]
    )
}
