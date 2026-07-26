import XCTest
@testable import SwiftMTP

final class SwiftMTPBackendTests: XCTestCase {
    func testScanKeepsDeviceIdentityWhenOneStorageFailsAndRecordsFailures() throws {
        let fakeUSB = FakeLibUSBFunctions()
        let context = try LibUSBContext(functions: fakeUSB.table, startsEventLoop: false)
        let firstID = try MTPDeviceID(validating: "swift:1:1:1111:0001")
        let secondID = try MTPDeviceID(validating: "swift:1:2:1111:0002")
        let firstStorage = try MTPStorageID(validating: 1)
        let failedStorage = try MTPStorageID(validating: 2)
        let first = FakeSwiftDiscoverySession(
            deviceID: firstID,
            storageIDs: [firstStorage, failedStorage]
        )
        first.storageInfo[firstStorage] = makeStorageInfo(description: "Internal")
        first.storageErrors[failedStorage] = .timeout
        let second = FakeSwiftDiscoverySession(deviceID: secondID)
        second.deviceInfoError = .permissionDenied
        let candidates = [
            makeCandidate(deviceID: firstID, raw: 0x401, functions: fakeUSB.table),
            makeCandidate(deviceID: secondID, raw: 0x402, functions: fakeUSB.table),
        ]
        let backend = SwiftMTPBackend(
            functions: fakeUSB.table,
            contextFactory: { context },
            enumerateCandidates: { _ in candidates },
            makeSession: { _, candidate in
                candidate.interface.deviceID == firstID ? first : second
            }
        )

        try backend.initialize()
        let snapshots = try backend.scanDevices()

        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.deviceID, firstID)
        XCTAssertEqual(snapshots.first?.manufacturer, "Acme")
        XCTAssertEqual(snapshots.first?.storages.map(\.id), [firstStorage])
        XCTAssertEqual(
            backend.lastScanFailures,
            [
                MTPScanFailure(
                    deviceID: firstID,
                    storageID: failedStorage,
                    stage: .storage,
                    error: .timeout
                ),
                MTPScanFailure(
                    deviceID: secondID,
                    storageID: nil,
                    stage: .device,
                    error: .permissionDenied
                ),
            ]
        )
        XCTAssertEqual(first.closeCount, 1)
        XCTAssertEqual(second.closeCount, 1)
        backend.shutdown()
    }

    func testOpenSessionReenumeratesAndOpensOnlyExactStableID() throws {
        let fakeUSB = FakeLibUSBFunctions()
        let context = try LibUSBContext(functions: fakeUSB.table, startsEventLoop: false)
        let firstID = try MTPDeviceID(validating: "swift:1:1:1111:0001")
        let secondID = try MTPDeviceID(validating: "swift:1:2:1111:0002")
        let storageID = try MTPStorageID(validating: 9)
        let candidates = [
            makeCandidate(deviceID: firstID, raw: 0x401, functions: fakeUSB.table),
            makeCandidate(deviceID: secondID, raw: 0x402, functions: fakeUSB.table),
        ]
        let opened = UncheckedResultBox<[MTPDeviceID]>()
        opened.store([])
        let selected = FakeSwiftDiscoverySession(
            deviceID: secondID,
            storageIDs: [storageID]
        )
        selected.storageInfo[storageID] = makeStorageInfo(description: "Selected")
        let backendWithSelectedSession = SwiftMTPBackend(
            functions: fakeUSB.table,
            contextFactory: { context },
            enumerateCandidates: { _ in candidates },
            makeSession: { _, candidate in
                var values = opened.value ?? []
                values.append(candidate.interface.deviceID)
                opened.store(values)
                return candidate.interface.deviceID == secondID
                    ? selected
                    : FakeSwiftDiscoverySession(deviceID: firstID)
            }
        )

        try backendWithSelectedSession.initialize()
        let session = try backendWithSelectedSession.openSession(for: secondID)
        try session.refreshStorage(storageID)

        XCTAssertEqual(opened.value, [secondID])
        XCTAssertEqual(session.deviceID, secondID)
        XCTAssertEqual(session.providerKind, .swift)
        session.close()
        XCTAssertEqual(selected.closeCount, 1)
        backendWithSelectedSession.shutdown()
    }

    func testTwoDeviceScanAndReopenIgnoreEnumerationOrder() throws {
        let fakeUSB = FakeLibUSBFunctions()
        let context = try LibUSBContext(functions: fakeUSB.table, startsEventLoop: false)
        let firstID = try MTPDeviceID(validating: "swift:1:1:18d1:4ee7")
        let secondID = try MTPDeviceID(validating: "swift:1:2:18d1:4ee7")
        let first = makeCandidate(deviceID: firstID, raw: 0x501, functions: fakeUSB.table)
        let second = makeCandidate(deviceID: secondID, raw: 0x502, functions: fakeUSB.table)
        var enumerationCount = 0
        let opened = UncheckedResultBox<[MTPDeviceID]>()
        opened.store([])
        let backend = SwiftMTPBackend(
            functions: fakeUSB.table,
            contextFactory: { context },
            enumerateCandidates: { _ in
                defer { enumerationCount += 1 }
                return enumerationCount == 0 ? [first, second] : [second, first]
            },
            makeSession: { _, candidate in
                var values = opened.value ?? []
                values.append(candidate.interface.deviceID)
                opened.store(values)
                return FakeSwiftDiscoverySession(deviceID: candidate.interface.deviceID)
            }
        )

        try backend.initialize()
        let snapshots = try backend.scanDevices()
        let session = try backend.openSession(for: secondID)

        XCTAssertEqual(snapshots.map(\.deviceID), [firstID, secondID])
        XCTAssertEqual(session.deviceID, secondID)
        XCTAssertEqual(opened.value, [firstID, secondID, secondID])
        session.close()
        backend.shutdown()
    }

    func testDuplicateStableIdentityFailsClosedInsteadOfOpeningFirstCandidate() throws {
        let fakeUSB = FakeLibUSBFunctions()
        let context = try LibUSBContext(functions: fakeUSB.table, startsEventLoop: false)
        let deviceID = try MTPDeviceID(validating: "swift:1:root:18d1:4ee7")
        let candidates = [
            makeCandidate(deviceID: deviceID, raw: 0x501, functions: fakeUSB.table),
            makeCandidate(deviceID: deviceID, raw: 0x502, functions: fakeUSB.table),
        ]
        let opened = UncheckedResultBox<[MTPDeviceID]>()
        opened.store([])
        let backend = SwiftMTPBackend(
            functions: fakeUSB.table,
            contextFactory: { context },
            enumerateCandidates: { _ in candidates },
            makeSession: { _, candidate in
                var values = opened.value ?? []
                values.append(candidate.interface.deviceID)
                opened.store(values)
                return FakeSwiftDiscoverySession(deviceID: candidate.interface.deviceID)
            }
        )

        try backend.initialize()
        XCTAssertThrowsError(try backend.openSession(for: deviceID)) {
            guard case .protocolViolation = $0 as? MTPCoreError else {
                return XCTFail("expected identity collision, got \($0)")
            }
        }
        XCTAssertEqual(opened.value, [])
        backend.shutdown()
    }
}

private final class FakeSwiftDiscoverySession: SwiftMTPDiscoverySession {
    let deviceID: MTPDeviceID
    var deviceInfoError: MTPCoreError?
    var storageIDs: [MTPStorageID]
    var storageInfo: [MTPStorageID: MTPStorageInfoDataset] = [:]
    var storageErrors: [MTPStorageID: MTPCoreError] = [:]
    private(set) var closeCount = 0

    init(deviceID: MTPDeviceID, storageIDs: [MTPStorageID] = []) {
        self.deviceID = deviceID
        self.storageIDs = storageIDs
    }

    func getDeviceInfo() throws -> MTPDeviceInfoDataset {
        if let deviceInfoError {
            throw deviceInfoError
        }
        return MTPDeviceInfoDataset(
            standardVersion: 100,
            vendorExtensionID: 6,
            vendorExtensionVersion: 101,
            vendorExtensionDescription: "MTP",
            functionalMode: 0,
            operationsSupported: [],
            eventsSupported: [],
            devicePropertiesSupported: [],
            captureFormats: [],
            imageFormats: [],
            manufacturer: "Acme",
            model: "Phone",
            deviceVersion: "1",
            serialNumber: "private"
        )
    }

    func getStorageIDs() throws -> [MTPStorageID] {
        storageIDs
    }

    func getStorageInfo(_ storageID: MTPStorageID) throws -> MTPStorageInfoDataset {
        if let error = storageErrors[storageID] {
            throw error
        }
        guard let info = storageInfo[storageID] else {
            throw MTPCoreError.noDevice
        }
        return info
    }

    func close() {
        closeCount += 1
    }
}

private func makeStorageInfo(description: String) -> MTPStorageInfoDataset {
    MTPStorageInfoDataset(
        storageType: 3,
        fileSystemType: 2,
        accessCapability: 0,
        maxCapacity: 1_000,
        freeSpaceInBytes: 500,
        freeSpaceInImages: 4,
        description: description,
        volumeLabel: "Phone"
    )
}

private func makeCandidate(
    deviceID: MTPDeviceID,
    raw: Int,
    functions: LibUSBFunctionTable
) -> LibUSBDeviceCandidate {
    makeTestLibUSBDeviceCandidate(
        deviceID: deviceID,
        rawDeviceValue: raw,
        functions: functions
    )
}
