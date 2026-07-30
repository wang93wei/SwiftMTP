import XCTest
@testable import SwiftMTP

final class SwiftMTPUploadBackendTests: XCTestCase {
    func testProviderValidatesStorageAndUsesOneOpenedSource() throws {
        let fixture = try makeUploadFixture(freeSpace: 10)
        defer { fixture.close() }
        let request = MTPUploadRequest(
            storageID: fixture.storageID,
            parentID: .root,
            sourceURL: URL(fileURLWithPath: "/tmp/source.bin"),
            name: "source.bin",
            size: 3
        )

        try fixture.session.upload(
            request,
            progress: { _ in },
            cancellation: MTPCancellationToken()
        )

        XCTAssertEqual(fixture.discovery.uploadCount, 1)
        XCTAssertEqual(fixture.source.closeCount, 1)
    }

    func testInsufficientStorageClosesSourceBeforeDeviceMutation() throws {
        let fixture = try makeUploadFixture(freeSpace: 2)
        defer { fixture.close() }
        let request = MTPUploadRequest(
            storageID: fixture.storageID,
            parentID: .root,
            sourceURL: URL(fileURLWithPath: "/tmp/source.bin"),
            name: "source.bin",
            size: 3
        )

        XCTAssertThrowsError(
            try fixture.session.upload(
                request,
                progress: { _ in },
                cancellation: MTPCancellationToken()
            )
        ) {
            guard case .invalidInput = $0 as? MTPCoreError else {
                return XCTFail("expected storage preflight rejection, got \($0)")
            }
        }

        XCTAssertEqual(fixture.discovery.uploadCount, 0)
        XCTAssertEqual(fixture.source.closeCount, 1)
    }

    func testPreCancelledUploadDoesNotOpenSourceOrTouchDevice() throws {
        let fixture = try makeUploadFixture(freeSpace: 10)
        defer { fixture.close() }
        let cancellation = MTPCancellationToken()
        cancellation.cancel()

        XCTAssertThrowsError(
            try fixture.session.upload(
                MTPUploadRequest(
                    storageID: fixture.storageID,
                    parentID: .root,
                    sourceURL: URL(fileURLWithPath: "/tmp/source.bin"),
                    name: "source.bin",
                    size: 3
                ),
                progress: { _ in },
                cancellation: cancellation
            )
        ) {
            XCTAssertEqual($0 as? MTPCoreError, .cancelled)
        }

        XCTAssertEqual(fixture.sourceFactoryCallCount(), 0)
        XCTAssertEqual(fixture.discovery.uploadCount, 0)
    }

    private func makeUploadFixture(freeSpace: UInt64) throws -> SwiftUploadFixture {
        let storageID = try MTPStorageID(validating: 1)
        let source = RecordingUploadSource(size: 3)
        let factoryCallCount = UncheckedResultBox<Int>()
        factoryCallCount.store(0)
        let harness = try makeSwiftMTPBackendHarness(
            rawDeviceValue: 0x701,
            storageIDs: [storageID],
            makeUploadSource: { _ in
                factoryCallCount.store((factoryCallCount.value ?? 0) + 1)
                return source
            }
        )
        harness.discovery.storageInfo[storageID] = MTPStorageInfoDataset(
            storageType: 3,
            fileSystemType: 2,
            accessCapability: 0,
            maxCapacity: 100,
            freeSpaceInBytes: freeSpace,
            freeSpaceInImages: 0,
            description: "Phone",
            volumeLabel: "Phone"
        )
        try harness.backend.initialize()
        return SwiftUploadFixture(
            backend: harness.backend,
            session: try harness.backend.openSession(for: harness.deviceID),
            discovery: harness.discovery,
            storageID: storageID,
            source: source,
            sourceFactoryCallCount: { factoryCallCount.value ?? 0 }
        )
    }
}
