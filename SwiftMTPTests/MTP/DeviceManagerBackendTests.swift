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
    func testProductionRuntimeUsesSwiftNativeProvider() {
        XCTAssertEqual(MTPProviderRuntime.shared.providerKind, .swift)
    }

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

    func testScanWaitsForActiveUploadBeforeEnteringScanBackend() throws {
        let deviceID = try MTPDeviceID(validating: "swift:1:1:2717:ff48")
        let selectedSnapshot = snapshot(deviceID, name: "Xiaomi")
        let appDeviceID = UUID()
        let activeBackend = FakeMTPBackend(providerKind: .swift)
        let coordinator = MTPConnectionCoordinator(
            factories: [.swift: { activeBackend }]
        )
        try coordinator.register(
            appDeviceID: appDeviceID,
            snapshot: selectedSnapshot,
            providerKind: .swift
        )
        try coordinator.selectDevice(appDeviceID)
        let session = try XCTUnwrap(activeBackend.sessions.first)
        let uploadStarted = DispatchSemaphore(value: 0)
        let releaseUpload = DispatchSemaphore(value: 0)
        session.uploadHandler = { _, _, _ in
            uploadStarted.signal()
            releaseUpload.wait()
        }

        let scanBackend = FakeMTPBackend(providerKind: .swift)
        let scanEntered = DispatchSemaphore(value: 0)
        scanBackend.scanResult = MTPScanResult(
            snapshots: [selectedSnapshot],
            failures: []
        )
        scanBackend.scanHandler = {
            scanEntered.signal()
            return scanBackend.scanResult
        }
        let runtime = MTPProviderRuntime(
            providerKind: .swift,
            scanBackend: scanBackend,
            coordinator: coordinator
        )
        let uploadResult = UncheckedResultBox<Result<Void, Error>>()
        let scanResult = UncheckedResultBox<Result<MTPScanResult, Error>>()
        let operations = DispatchGroup()

        operations.enter()
        DispatchQueue.global().async {
            defer { operations.leave() }
            uploadResult.store(
                Result {
                    try coordinator.upload(
                        appDeviceID: appDeviceID,
                        deviceID: deviceID,
                        request: MTPUploadRequest(
                            storageID: try MTPStorageID(validating: 1),
                            parentID: .root,
                            sourceURL: URL(fileURLWithPath: "/tmp/source"),
                            name: "source",
                            size: 1
                        ),
                        progress: { _ in },
                        cancellation: MTPCancellationToken()
                    )
                }
            )
        }
        XCTAssertEqual(uploadStarted.wait(timeout: .now() + 1), .success)

        operations.enter()
        DispatchQueue.global().async {
            defer { operations.leave() }
            scanResult.store(Result { try runtime.scanDevices() })
        }

        XCTAssertEqual(scanEntered.wait(timeout: .now() + 0.1), .timedOut)
        releaseUpload.signal()
        XCTAssertEqual(operations.wait(timeout: .now() + 2), .success)
        XCTAssertNoThrow(try uploadResult.value?.get())
        XCTAssertEqual(try scanResult.value?.get(), scanBackend.scanResult)
    }

    func testScanReusesSelectedSwiftSnapshotWithoutOpeningSecondSession() throws {
        let deviceID = try MTPDeviceID(validating: "swift:2:1.3:2717:ff48")
        let selectedSnapshot = snapshot(deviceID, name: "Xiaomi")
        let appDeviceID = UUID()
        let activeBackend = FakeMTPBackend(providerKind: .swift)
        let coordinator = MTPConnectionCoordinator(
            factories: [.swift: { activeBackend }]
        )
        try coordinator.register(
            appDeviceID: appDeviceID,
            snapshot: selectedSnapshot,
            providerKind: .swift
        )
        try coordinator.selectDevice(appDeviceID)

        let fakeUSB = FakeLibUSBFunctions()
        let context = try LibUSBContext(functions: fakeUSB.table, startsEventLoop: false)
        let candidate = makeCandidate(
            deviceID: deviceID,
            raw: 0x401,
            functions: fakeUSB.table
        )
        let scanSession = FakeSwiftDiscoverySession(deviceID: deviceID)
        let opened = UncheckedResultBox<[MTPDeviceID]>()
        opened.store([])
        let scanBackend = SwiftMTPBackend(
            functions: fakeUSB.table,
            contextFactory: { context },
            enumerateCandidates: { _ in [candidate] },
            makeSession: { _, candidate in
                var values = opened.value ?? []
                values.append(candidate.interface.deviceID)
                opened.store(values)
                return scanSession
            }
        )
        let runtime = MTPProviderRuntime(
            providerKind: .swift,
            scanBackend: scanBackend,
            coordinator: coordinator
        )

        let result = try runtime.scanDevices()

        XCTAssertEqual(result.snapshots, [selectedSnapshot])
        XCTAssertEqual(opened.value, [])
        XCTAssertEqual(scanSession.closeCount, 0)
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
