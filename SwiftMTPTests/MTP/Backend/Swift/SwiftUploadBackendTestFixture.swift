import Foundation
@testable import SwiftMTP

struct SwiftUploadFixture {
    let backend: SwiftMTPBackend
    let session: any MTPBackendSession
    let discovery: FakeSwiftDiscoverySession
    let storageID: MTPStorageID
    let source: RecordingUploadSource
    let sourceFactoryCallCount: () -> Int

    func close() {
        session.close()
        backend.shutdown()
    }
}

final class RecordingUploadSource: MTPUploadSource {
    let size: UInt64
    let modificationDateString = "20260730T000000Z"
    private(set) var closeCount = 0

    init(size: UInt64) {
        self.size = size
    }

    var length: UInt64? {
        size
    }

    func read(maximumLength: Int) throws -> Data {
        Data()
    }

    func close() {
        closeCount += 1
    }
}
