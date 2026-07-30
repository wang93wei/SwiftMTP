import Darwin
import XCTest
@testable import SwiftMTP

final class MTPUploadSourcePolicyTests: XCTestCase {
    func testRegularUnicodeAndEmptyFilesOpenWithMeasuredMetadata() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        for (name, contents) in [
            ("空文件.bin", Data()),
            ("文档😀.bin", Data([1, 2, 3])),
        ] {
            let url = directory.appendingPathComponent(name)
            try contents.write(to: url)
            let source = try MTPUploadSourcePolicy.open(
                request: try request(url: url, name: name, size: UInt64(contents.count))
            )

            XCTAssertEqual(source.size, UInt64(contents.count))
            XCTAssertEqual(source.length, UInt64(contents.count))
            XCTAssertFalse(source.modificationDateString.isEmpty)
            XCTAssertEqual(try source.read(maximumLength: 16), contents)
            XCTAssertEqual(try source.read(maximumLength: 16), Data())
            source.close()
        }
    }

    func testOpenHandleKeepsValidatedFileWhenPathIsReplaced() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("source.bin")
        let replacement = directory.appendingPathComponent("replacement.bin")
        try Data("original".utf8).write(to: url)
        try Data("replacement".utf8).write(to: replacement)
        let source = try MTPUploadSourcePolicy.open(
            request: try request(url: url, name: "source.bin", size: 8)
        )

        try FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: replacement, to: url)

        XCTAssertEqual(try source.read(maximumLength: 32), Data("original".utf8))
        source.close()
    }

    func testModificationDateUsesBasicMTPTimestampWithoutTimezoneSuffix() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("dated.bin")
        try Data([1]).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_700_000_000)],
            ofItemAtPath: url.path
        )

        let source = try MTPUploadSourcePolicy.open(
            request: try request(url: url, name: "dated.bin", size: 1)
        )

        XCTAssertEqual(source.modificationDateString, "20231114T221320")
        source.close()
    }

    func testRejectsMissingDirectorySymlinkFIFOAndSizeMismatch() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let regular = directory.appendingPathComponent("regular.bin")
        try Data([1]).write(to: regular)
        let symlink = directory.appendingPathComponent("link.bin")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: regular)
        let fifo = directory.appendingPathComponent("pipe")
        XCTAssertEqual(fifo.path.withCString { mkfifo($0, S_IRUSR | S_IWUSR) }, 0)

        let cases: [(URL, UInt64)] = [
            (directory.appendingPathComponent("missing.bin"), 0),
            (directory, 0),
            (symlink, 1),
            (fifo, 0),
            (regular, 2),
        ]
        for (url, size) in cases {
            XCTAssertThrowsError(
                try MTPUploadSourcePolicy.open(
                    request: try request(url: url, name: "source.bin", size: size)
                )
            )
        }
    }

    func testRejectsConfiguredSizeLimitWithoutAllocatingPayload() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("sparse.bin")
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data()))
        let oversized = AppConfiguration.maxFileSize + 1
        XCTAssertEqual(url.path.withCString { truncate($0, off_t(oversized)) }, 0)

        XCTAssertThrowsError(
            try MTPUploadSourcePolicy.open(
                request: try request(url: url, name: "sparse.bin", size: oversized)
            )
        ) {
            guard case .invalidInput = $0 as? MTPCoreError else {
                return XCTFail("expected configured-size rejection, got \($0)")
            }
        }
    }

    private func request(
        url: URL,
        name: String,
        size: UInt64
    ) throws -> MTPUploadRequest {
        MTPUploadRequest(
            storageID: try MTPStorageID(validating: 1),
            parentID: .root,
            sourceURL: url,
            name: name,
            size: size
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "swiftmtp-upload-source-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: false
        )
        return url
    }
}
