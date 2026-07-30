import Foundation

nonisolated enum MTPDirectoryUploadPreflight {
    enum Outcome {
        case ready(MTPDirectoryUploadManifest)
        case terminal(MTPDirectoryUploadResult)
    }

    static func evaluate(_ request: MTPDirectoryUploadRequest) -> Outcome {
        let manifest: MTPDirectoryUploadManifest
        do {
            manifest = try MTPDirectoryUploadManifest.build(from: request.sourceURL)
        } catch {
            return .terminal(
                MTPDirectoryUploadSummary.failedBeforeManifest(error: coreError(error))
            )
        }
        guard manifest.totalSize <= request.availableSpace else {
            return .terminal(
                MTPDirectoryUploadSummary.allFailed(
                    manifest: manifest,
                    error: .invalidInput(
                        "directory upload exceeds available storage space"
                    ),
                    remoteMutationOccurred: false
                )
            )
        }
        return .ready(manifest)
    }

    private static func coreError(_ error: Error) -> MTPCoreError {
        error as? MTPCoreError
            ?? .protocolViolation("unexpected directory upload preflight failure")
    }
}
