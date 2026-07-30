import Darwin
import Foundation

nonisolated struct MTPDirectoryUploadManifest: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        let sourceURL: URL
        let relativePath: String
        let folderPath: String
        let name: String
        let size: UInt64
    }

    let rootURL: URL
    let entries: [Entry]
    let totalSize: UInt64
    let requiredFolderPaths: [String]

    static func validateRoot(_ sourceURL: URL) throws -> URL {
        guard sourceURL.isFileURL, !sourceURL.path.isEmpty else {
            throw MTPCoreError.invalidInput("directory upload source must be a file URL")
        }
        let standardizedRoot = sourceURL.standardizedFileURL
        guard standardizedRoot.path == sourceURL.path else {
            throw MTPCoreError.invalidInput("directory upload source path must be standardized")
        }
        var status = stat()
        guard standardizedRoot.path.withCString({ lstat($0, &status) }) == 0 else {
            throw MTPCoreError.localFileIO("directory upload source metadata could not be read")
        }
        guard status.st_mode & S_IFMT == S_IFDIR else {
            throw MTPCoreError.invalidInput("directory upload source must be a directory")
        }
        return standardizedRoot
    }

    static func build(from sourceURL: URL) throws -> Self {
        let rootURL = try validateRoot(sourceURL)
        let rootValues = try rootURL.resourceValues(forKeys: [.isPackageKey])
        guard rootValues.isPackage != true else {
            return Self(rootURL: rootURL, entries: [], totalSize: 0, requiredFolderPaths: [])
        }

        var enumerationError: Error?
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .isPackageKey,
            ],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw MTPCoreError.localFileIO("directory upload source could not be enumerated")
        }

        var entries: [Entry] = []
        var totalSize: UInt64 = 0
        for case let candidate as URL in enumerator {
            guard let entry = try makeEntry(candidate: candidate, rootURL: rootURL) else {
                continue
            }
            let (newTotal, overflow) = totalSize.addingReportingOverflow(entry.size)
            guard !overflow else {
                throw MTPCoreError.invalidInput("directory upload total size overflow")
            }
            totalSize = newTotal
            entries.append(entry)
        }
        guard enumerationError == nil else {
            throw MTPCoreError.localFileIO("directory upload source enumeration failed")
        }

        entries.sort { $0.relativePath < $1.relativePath }
        let folderPaths = Set(entries.compactMap { entry in
            entry.folderPath.isEmpty ? nil : entry.folderPath
        })
        return Self(
            rootURL: rootURL,
            entries: entries,
            totalSize: totalSize,
            requiredFolderPaths: folderPaths.sorted()
        )
    }

    private static func makeEntry(candidate: URL, rootURL: URL) throws -> Entry? {
        let values = try candidate.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        )
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            return nil
        }
        let sourceURL = candidate.standardizedFileURL
        let relativePath = try safeRelativePath(root: rootURL, candidate: sourceURL)
        var status = stat()
        guard sourceURL.path.withCString({ lstat($0, &status) }) == 0,
              status.st_mode & S_IFMT == S_IFREG,
              status.st_size >= 0 else {
            throw MTPCoreError.localFileIO(
                "directory upload file metadata could not be read"
            )
        }
        let size = UInt64(status.st_size)
        guard size <= AppConfiguration.maxFileSize else {
            throw MTPCoreError.invalidInput(
                "directory upload file exceeds the configured size limit"
            )
        }
        guard AppConfiguration.isValidPathLength(sourceURL.path) else {
            throw MTPCoreError.invalidInput("directory upload file path is too long")
        }
        _ = try MTPObjectInfoDataset.file(
            storageID: MTPStorageID(validating: 1),
            parentObject: .root,
            name: sourceURL.lastPathComponent,
            size: size
        )
        let folderPath = sourceURL
            .deletingLastPathComponent()
            .path
            .dropFirst(rootURL.path.count)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return Entry(
            sourceURL: sourceURL,
            relativePath: relativePath,
            folderPath: folderPath,
            name: sourceURL.lastPathComponent,
            size: size
        )
    }

    private static func safeRelativePath(root: URL, candidate: URL) throws -> String {
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path.hasPrefix(prefix) else {
            throw MTPCoreError.invalidInput("directory upload file escaped the source root")
        }
        let relativePath = String(candidate.path.dropFirst(prefix.count))
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !relativePath.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw MTPCoreError.invalidInput("directory upload relative path is invalid")
        }
        return relativePath
    }
}
