import Darwin
import Foundation

nonisolated protocol MTPUploadSource: MTPStreamSource {
    var size: UInt64 { get }
    var modificationDateString: String { get }
    func close()
}

nonisolated enum MTPUploadSourcePolicy {
    static func open(
        request: MTPUploadRequest,
        maximumSize: UInt64 = AppConfiguration.maxFileSize
    ) throws -> any MTPUploadSource {
        try validateRequest(request, maximumSize: maximumSize)

        let path = request.sourceURL.path
        var linkStatus = stat()
        guard path.withCString({ lstat($0, &linkStatus) }) == 0 else {
            throw MTPCoreError.localFileIO("upload source metadata could not be read")
        }
        let linkType = linkStatus.st_mode & S_IFMT
        guard linkType != S_IFLNK else {
            throw MTPCoreError.invalidInput("upload source must not be a symbolic link")
        }
        guard linkType == S_IFREG else {
            throw MTPCoreError.invalidInput("upload source must be a regular file")
        }

        let descriptor = path.withCString {
            Darwin.open($0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else {
            throw MTPCoreError.localFileIO("upload source could not be opened")
        }

        do {
            var openedStatus = stat()
            guard fstat(descriptor, &openedStatus) == 0 else {
                throw MTPCoreError.localFileIO("opened upload source metadata could not be read")
            }
            guard openedStatus.st_mode & S_IFMT == S_IFREG,
                  openedStatus.st_dev == linkStatus.st_dev,
                  openedStatus.st_ino == linkStatus.st_ino,
                  openedStatus.st_size >= 0 else {
                throw MTPCoreError.invalidInput("upload source changed during validation")
            }
            let openedSize = UInt64(openedStatus.st_size)
            guard openedSize == request.size else {
                throw MTPCoreError.invalidInput(
                    "upload source size does not match the typed request"
                )
            }
            return MTPFileUploadSource(
                descriptor: descriptor,
                size: openedSize,
                modificationDate: Date(
                    timeIntervalSince1970: TimeInterval(openedStatus.st_mtimespec.tv_sec)
                )
            )
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    private static func validateRequest(
        _ request: MTPUploadRequest,
        maximumSize: UInt64
    ) throws {
        guard request.sourceURL.isFileURL else {
            throw MTPCoreError.invalidInput("upload source must be a file URL")
        }
        let path = request.sourceURL.path
        guard path.hasPrefix("/") else {
            throw MTPCoreError.invalidInput("upload source path must be absolute")
        }
        guard URL(fileURLWithPath: path).standardizedFileURL.path == path else {
            throw MTPCoreError.invalidInput("upload source path must be standardized")
        }
        guard AppConfiguration.isValidPathLength(path) else {
            throw MTPCoreError.invalidInput("upload source path is too long")
        }
        guard request.size <= maximumSize else {
            throw MTPCoreError.invalidInput("upload source exceeds the configured size limit")
        }
        _ = try MTPObjectInfoDataset.file(
            storageID: request.storageID,
            parentObject: request.parentID,
            name: request.name,
            size: request.size
        )
    }
}

private nonisolated final class MTPFileUploadSource: MTPUploadSource {
    let size: UInt64
    let modificationDateString: String

    private let lock = NSLock()
    private var handle: FileHandle?

    init(descriptor: Int32, size: UInt64, modificationDate: Date) {
        self.size = size
        self.modificationDateString = Self.mtpTimestamp(for: modificationDate)
        self.handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    deinit {
        close()
    }

    var length: UInt64? {
        size
    }

    func read(maximumLength: Int) throws -> Data {
        guard maximumLength > 0 else {
            throw MTPCoreError.invalidInput("upload source read length must be positive")
        }
        let current = try lock.withLock {
            guard let handle else {
                throw MTPCoreError.localFileIO("upload source is closed")
            }
            return handle
        }
        do {
            return try current.read(upToCount: maximumLength) ?? Data()
        } catch let error as MTPCoreError {
            throw error
        } catch {
            throw MTPCoreError.localFileIO("upload source read failed")
        }
    }

    func close() {
        let current = lock.withLock {
            defer { handle = nil }
            return handle
        }
        try? current?.close()
    }

    private static func mtpTimestamp(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }
}
