import Foundation

nonisolated extension MTPDeviceSession {
    func compensateUploadLocked(
        objectID: MTPObjectID,
        primaryError: MTPCoreError
    ) {
        guard !shouldInvalidate(primaryError), state == .open else {
            state = .invalid
            reportUploadDiagnostic(
                MTPUploadCompensationDiagnostic(
                    objectID: objectID,
                    primaryError: primaryError,
                    outcome: .skippedOrphanRisk
                )
            )
            return
        }
        do {
            _ = try executeLocked(
                operation: .deleteObject,
                parameters: [objectID.rawValue, 0],
                phase: .none,
                cancellation: MTPCancellationToken()
            )
            reportUploadDiagnostic(
                MTPUploadCompensationDiagnostic(
                    objectID: objectID,
                    primaryError: primaryError,
                    outcome: .removed
                )
            )
        } catch {
            let cleanupError = uploadCoreError(error)
            if shouldInvalidate(cleanupError) {
                state = .invalid
            }
            reportUploadDiagnostic(
                MTPUploadCompensationDiagnostic(
                    objectID: objectID,
                    primaryError: primaryError,
                    outcome: .failed(cleanupError)
                )
            )
        }
    }

    func uploadCoreError(_ error: Error) -> MTPCoreError {
        error as? MTPCoreError
            ?? .localFileIO("upload source read failed")
    }
}
