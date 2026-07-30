import Foundation

nonisolated struct MTPDirectoryUploadSummary {
    private(set) var fileResults: [MTPDirectoryUploadFileResult] = []
    private(set) var remoteMutationOccurred = false

    var uploadedByteCount: UInt64 {
        fileResults
            .filter { $0.outcome == .uploaded }
            .reduce(0) { $0 + $1.size }
    }

    mutating func markRemoteMutation() {
        remoteMutationOccurred = true
    }

    mutating func recordUploaded(_ entry: MTPDirectoryUploadManifest.Entry) {
        fileResults.append(Self.result(for: entry, outcome: .uploaded, error: nil))
    }

    mutating func recordFailed(
        _ entry: MTPDirectoryUploadManifest.Entry,
        error: MTPCoreError
    ) {
        fileResults.append(Self.result(for: entry, outcome: .failed, error: error))
    }

    mutating func recordCancelled(_ entries: ArraySlice<MTPDirectoryUploadManifest.Entry>) {
        fileResults.append(contentsOf: Self.cancelledResults(for: Array(entries)))
    }

    func result(
        forcedOutcome: MTPDirectoryUploadTerminalOutcome? = nil
    ) -> MTPDirectoryUploadResult {
        Self.makeResult(
            fileResults: fileResults,
            forcedOutcome: forcedOutcome,
            remoteMutationOccurred: remoteMutationOccurred
        )
    }

    static func failedBeforeManifest(error: MTPCoreError) -> MTPDirectoryUploadResult {
        MTPDirectoryUploadResult(
            outcome: .failed,
            totalFiles: 0,
            uploadedFiles: 0,
            failedFiles: 0,
            skippedFiles: 0,
            fileResults: [],
            errors: [String(describing: error)],
            remoteMutationOccurred: false
        )
    }

    static func allFailed(
        manifest: MTPDirectoryUploadManifest,
        error: MTPCoreError,
        remoteMutationOccurred: Bool
    ) -> MTPDirectoryUploadResult {
        makeResult(
            fileResults: manifest.entries.map {
                result(for: $0, outcome: .failed, error: error)
            },
            forcedOutcome: .failed,
            remoteMutationOccurred: remoteMutationOccurred
        )
    }

    static func cancelled(
        entries: [MTPDirectoryUploadManifest.Entry],
        remoteMutationOccurred: Bool
    ) -> MTPDirectoryUploadResult {
        makeResult(
            fileResults: cancelledResults(for: entries),
            forcedOutcome: .cancelled,
            remoteMutationOccurred: remoteMutationOccurred
        )
    }

    private static func cancelledResults(
        for entries: [MTPDirectoryUploadManifest.Entry]
    ) -> [MTPDirectoryUploadFileResult] {
        entries.map { result(for: $0, outcome: .skipped, error: .cancelled) }
    }

    private static func result(
        for entry: MTPDirectoryUploadManifest.Entry,
        outcome: MTPDirectoryUploadFileOutcome,
        error: MTPCoreError?
    ) -> MTPDirectoryUploadFileResult {
        MTPDirectoryUploadFileResult(
            relativePath: entry.relativePath,
            size: entry.size,
            outcome: outcome,
            error: error
        )
    }

    private static func makeResult(
        fileResults: [MTPDirectoryUploadFileResult],
        forcedOutcome: MTPDirectoryUploadTerminalOutcome?,
        remoteMutationOccurred: Bool
    ) -> MTPDirectoryUploadResult {
        let uploaded = fileResults.filter { $0.outcome == .uploaded }.count
        let failed = fileResults.filter { $0.outcome == .failed }.count
        let skipped = fileResults.filter { $0.outcome == .skipped }.count
        let outcome = forcedOutcome ?? inferredOutcome(
            uploaded: uploaded,
            failed: failed
        )
        return MTPDirectoryUploadResult(
            outcome: outcome,
            totalFiles: fileResults.count,
            uploadedFiles: uploaded,
            failedFiles: failed,
            skippedFiles: skipped,
            fileResults: fileResults,
            errors: fileResults.compactMap { result in
                result.error.map {
                    "\(result.relativePath): \(String(describing: $0))"
                }
            },
            remoteMutationOccurred: remoteMutationOccurred
        )
    }

    private static func inferredOutcome(
        uploaded: Int,
        failed: Int
    ) -> MTPDirectoryUploadTerminalOutcome {
        guard failed > 0 else {
            return .succeeded
        }
        return uploaded == 0 ? .failed : .partial
    }
}
