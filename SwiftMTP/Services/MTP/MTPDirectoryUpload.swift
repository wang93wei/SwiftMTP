import Foundation

nonisolated enum MTPDirectoryUploadTerminalOutcome: Equatable, Sendable {
    case succeeded
    case failed
    case partial
    case cancelled
}

nonisolated enum MTPDirectoryUploadFileOutcome: Equatable, Sendable {
    case uploaded
    case failed
    case skipped
}

nonisolated struct MTPDirectoryUploadFileResult: Equatable, Sendable {
    let relativePath: String
    let size: UInt64
    let outcome: MTPDirectoryUploadFileOutcome
    let error: MTPCoreError?
}

nonisolated struct MTPDirectoryUploadResult: Equatable, Sendable {
    let outcome: MTPDirectoryUploadTerminalOutcome
    let totalFiles: Int
    let uploadedFiles: Int
    let failedFiles: Int
    let skippedFiles: Int
    let fileResults: [MTPDirectoryUploadFileResult]
    let errors: [String]
    let remoteMutationOccurred: Bool
}

nonisolated struct MTPDirectoryUploadRequest: @unchecked Sendable {
    let appDeviceID: UUID
    let deviceIdentity: MTPDeviceIdentity
    let storageID: MTPStorageID
    let parentID: MTPObjectID
    let sourceURL: URL
    let availableSpace: UInt64
    let progressHandler: ((Int, Int) -> Void)?
    let completionHandler: ((MTPDirectoryUploadResult) -> Void)?
}
