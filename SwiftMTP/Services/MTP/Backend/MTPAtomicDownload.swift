import Darwin
import Foundation

nonisolated protocol MTPDownloadDestination: MTPStreamSink {
    func finish(cancellation: MTPCancellationToken) throws
    func abort()
}

nonisolated protocol MTPDownloadWritableFile: MTPStreamSink {
    func synchronize() throws
    func close() throws
}

nonisolated protocol MTPDownloadFileSystem {
    func fileExists(at url: URL) -> Bool
    func makeTemporaryFile(adjacentTo destinationURL: URL) throws
        -> (url: URL, file: any MTPDownloadWritableFile)
    func moveItemWithoutReplacing(at sourceURL: URL, to destinationURL: URL) throws
    func replaceItem(at destinationURL: URL, with sourceURL: URL) throws
    func removeItemIfPresent(at url: URL)
}

nonisolated final class MTPAtomicDownloadDestination: MTPDownloadDestination {
    private enum State {
        case open
        case finished
        case aborted
    }

    private let destinationURL: URL
    private let replacementPolicy: MTPDownloadReplacementPolicy
    private let fileSystem: any MTPDownloadFileSystem
    private let temporaryURL: URL
    private let file: any MTPDownloadWritableFile
    private var state = State.open
    private var fileClosed = false

    convenience init(
        destinationURL: URL,
        replacementPolicy: MTPDownloadReplacementPolicy
    ) throws {
        try self.init(
            destinationURL: destinationURL,
            replacementPolicy: replacementPolicy,
            fileSystem: MTPFoundationDownloadFileSystem()
        )
    }

    init(
        destinationURL: URL,
        replacementPolicy: MTPDownloadReplacementPolicy,
        fileSystem: any MTPDownloadFileSystem
    ) throws {
        guard destinationURL.isFileURL else {
            throw MTPCoreError.invalidInput("download destination must be a file URL")
        }
        if replacementPolicy == .failIfExists,
           fileSystem.fileExists(at: destinationURL) {
            throw MTPCoreError.invalidInput("download destination already exists")
        }
        self.destinationURL = destinationURL
        self.replacementPolicy = replacementPolicy
        self.fileSystem = fileSystem
        let temporary = try fileSystem.makeTemporaryFile(adjacentTo: destinationURL)
        self.temporaryURL = temporary.url
        self.file = temporary.file
    }

    deinit {
        abort()
    }

    func write(_ data: Data) throws {
        guard state == .open else {
            throw MTPCoreError.localFileIO("download destination is not writable")
        }
        try file.write(data)
    }

    func finish(cancellation: MTPCancellationToken) throws {
        guard state == .open else {
            throw MTPCoreError.localFileIO("download destination already finalized")
        }
        do {
            try cancellation.throwIfCancelled()
            try file.synchronize()
            try file.close()
            fileClosed = true
            try cancellation.throwIfCancelled()
            switch replacementPolicy {
            case .failIfExists:
                try fileSystem.moveItemWithoutReplacing(
                    at: temporaryURL,
                    to: destinationURL
                )
            case .replaceExisting:
                if fileSystem.fileExists(at: destinationURL) {
                    try fileSystem.replaceItem(
                        at: destinationURL,
                        with: temporaryURL
                    )
                } else {
                    try fileSystem.moveItemWithoutReplacing(
                        at: temporaryURL,
                        to: destinationURL
                    )
                }
            }
            state = .finished
        } catch {
            cleanupAfterFailure()
            throw Self.coreError(error, phase: "finalize")
        }
    }

    func abort() {
        guard state == .open else {
            return
        }
        cleanupAfterFailure()
    }

    private func cleanupAfterFailure() {
        if !fileClosed {
            try? file.close()
            fileClosed = true
        }
        fileSystem.removeItemIfPresent(at: temporaryURL)
        state = .aborted
    }

    private static func coreError(_ error: Error, phase: String) -> MTPCoreError {
        if let error = error as? MTPCoreError {
            return error
        }
        return .localFileIO("download \(phase) failed")
    }
}

private nonisolated final class MTPFoundationDownloadFileSystem: MTPDownloadFileSystem {
    private let fileManager = FileManager.default

    func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    func makeTemporaryFile(adjacentTo destinationURL: URL) throws
        -> (url: URL, file: any MTPDownloadWritableFile) {
        let directoryURL = destinationURL.deletingLastPathComponent()
        for _ in 0..<8 {
            let temporaryURL = directoryURL.appendingPathComponent(
                ".swiftmtp-download-\(UUID().uuidString).tmp",
                isDirectory: false
            )
            let descriptor = temporaryURL.path.withCString {
                Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
            }
            if descriptor == -1, errno == EEXIST {
                continue
            }
            guard descriptor >= 0 else {
                throw MTPCoreError.localFileIO("download temporary file creation failed")
            }
            return (
                temporaryURL,
                MTPFoundationDownloadFile(descriptor: descriptor)
            )
        }
        throw MTPCoreError.localFileIO("download temporary file creation failed")
    }

    func moveItemWithoutReplacing(at sourceURL: URL, to destinationURL: URL) throws {
        do {
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
        } catch {
            throw MTPCoreError.localFileIO("download atomic move failed")
        }
    }

    func replaceItem(at destinationURL: URL, with sourceURL: URL) throws {
        do {
            _ = try fileManager.replaceItemAt(
                destinationURL,
                withItemAt: sourceURL,
                backupItemName: nil,
                options: []
            )
        } catch {
            throw MTPCoreError.localFileIO("download atomic replacement failed")
        }
    }

    func removeItemIfPresent(at url: URL) {
        try? fileManager.removeItem(at: url)
    }
}

private nonisolated final class MTPFoundationDownloadFile: MTPDownloadWritableFile {
    private let handle: FileHandle

    init(descriptor: Int32) {
        self.handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    func write(_ data: Data) throws {
        do {
            try handle.write(contentsOf: data)
        } catch {
            throw MTPCoreError.localFileIO("download temporary file write failed")
        }
    }

    func synchronize() throws {
        do {
            try handle.synchronize()
        } catch {
            throw MTPCoreError.localFileIO("download temporary file sync failed")
        }
    }

    func close() throws {
        do {
            try handle.close()
        } catch {
            throw MTPCoreError.localFileIO("download temporary file close failed")
        }
    }
}
