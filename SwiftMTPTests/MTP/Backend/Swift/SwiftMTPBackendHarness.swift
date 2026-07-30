import Foundation
@testable import SwiftMTP

struct SwiftMTPBackendHarness {
    let backend: SwiftMTPBackend
    let discovery: FakeSwiftDiscoverySession
    let deviceID: MTPDeviceID
}

func makeSwiftMTPBackendHarness(
    rawDeviceValue: Int,
    storageIDs: [MTPStorageID] = [],
    makeUploadSource: SwiftMTPBackend.UploadSourceFactory? = nil
) throws -> SwiftMTPBackendHarness {
    let fakeUSB = FakeLibUSBFunctions()
    let context = try LibUSBContext(functions: fakeUSB.table, startsEventLoop: false)
    let deviceID = try MTPDeviceID(validating: "swift:1:1:1111:0001")
    let discovery = FakeSwiftDiscoverySession(
        deviceID: deviceID,
        storageIDs: storageIDs
    )
    let candidate = makeCandidate(
        deviceID: deviceID,
        raw: rawDeviceValue,
        functions: fakeUSB.table
    )
    let backend = SwiftMTPBackend(
        functions: fakeUSB.table,
        contextFactory: { context },
        enumerateCandidates: { _ in [candidate] },
        makeSession: { _, _ in discovery },
        makeUploadSource: makeUploadSource
    )
    return SwiftMTPBackendHarness(
        backend: backend,
        discovery: discovery,
        deviceID: deviceID
    )
}

func makeStorageInfo(description: String) -> MTPStorageInfoDataset {
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

func makeCandidate(
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
