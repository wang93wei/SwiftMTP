import Foundation
@testable import SwiftMTP

struct SwiftDownloadFixture {
    let backend: SwiftMTPBackend
    let session: any MTPBackendSession
    let discovery: FakeSwiftDiscoverySession
    let objectID: MTPObjectID
    let directoryURL: URL

    func temporaryFiles() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directoryURL.path)
            .filter { $0.hasPrefix(".swiftmtp-download-") }
    }

    func close() {
        session.close()
        backend.shutdown()
    }

    func cleanup() {
        close()
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
