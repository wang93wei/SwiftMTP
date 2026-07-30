import Foundation

nonisolated func decodeKalamResponse<T: Decodable>(
    _ pointer: UnsafeMutablePointer<CChar>?,
    abi: KalamFileSystemABI
) throws -> T {
    guard let pointer else {
        throw MTPCoreError.disconnected
    }
    defer { abi.free(pointer) }
    let data = Data(String(cString: pointer).utf8)
    do {
        return try JSONDecoder().decode(T.self, from: data)
    } catch {
        throw MTPCoreError.protocolViolation("Go session JSON decode failed")
    }
}

nonisolated func validateKalamSuccess(
    _ ok: Bool,
    errorCode: String?
) throws {
    guard ok else {
        switch errorCode {
        case "stale_token", "unknown_token", "disconnected", "shutting_down":
            throw MTPCoreError.disconnected
        case "invalid_input":
            throw MTPCoreError.invalidInput("Go session rejected invalid input")
        default:
            throw MTPCoreError.response(code: .generalError)
        }
    }
}

nonisolated func validateKalamTransferSuccess(
    _ response: KalamTransferResponseDTO
) throws -> UInt64 {
    guard response.ok else {
        switch response.error {
        case "stale_token", "unknown_token", "disconnected", "shutting_down":
            throw MTPCoreError.disconnected
        case "invalid_input":
            throw MTPCoreError.invalidInput("Go transfer rejected invalid input")
        case "local_io":
            throw MTPCoreError.localFileIO("Go transfer local file I/O failed")
        case "timeout":
            throw MTPCoreError.timeout
        case "cancelled":
            throw MTPCoreError.cancelled
        case "permission_denied":
            throw MTPCoreError.permissionDenied
        case "mtp_response":
            guard let responseCode = response.responseCode else {
                throw MTPCoreError.protocolViolation(
                    "Go transfer response omitted its MTP response code"
                )
            }
            throw MTPCoreError.response(code: MTPResponseCode(rawValue: responseCode))
        default:
            throw MTPCoreError.response(code: .generalError)
        }
    }
    guard let bytes = response.bytes else {
        throw MTPCoreError.protocolViolation(
            "Go transfer success response omitted its byte count"
        )
    }
    return bytes
}

nonisolated struct KalamOpenSessionDTO: Decodable {
    let ok: Bool
    let token: String?
    let error: String?
}

nonisolated struct KalamListResponseDTO: Decodable {
    let ok: Bool
    let files: [KalamFileDTO]?
    let failures: [KalamObjectFailureDTO]?
    let error: String?
}

nonisolated struct KalamMutationResponseDTO: Decodable {
    let ok: Bool
    let objectId: UInt32?
    let storage: GoStorageDTO?
    let error: String?
}

nonisolated struct KalamTransferResponseDTO: Decodable {
    let ok: Bool
    let bytes: UInt64?
    let error: String?
    let responseCode: UInt16?
}

nonisolated struct KalamFileDTO: Decodable {
    let id: UInt32
    let parentId: UInt32
    let storageId: UInt32
    let name: String
    let size: UInt64
    let isFolder: Bool
    let modTime: Int64

    func object(expectedStorageID: MTPStorageID) throws -> MTPObject {
        guard !name.isEmpty else {
            throw MTPCoreError.protocolViolation("Go file JSON contains an empty name")
        }
        let parentID = try MTPObjectID(validating: parentId)
        let storageID = try MTPStorageID(validating: storageId)
        guard storageID == expectedStorageID else {
            throw MTPCoreError.protocolViolation(
                "Go file JSON does not match the listing storage"
            )
        }
        return MTPObject(
            id: try MTPObjectID(validating: id),
            parentID: parentID,
            storageID: storageID,
            name: name,
            size: size,
            isFolder: isFolder,
            modificationDate: modTime > 0
                ? Date(timeIntervalSince1970: TimeInterval(modTime))
                : nil
        )
    }
}

nonisolated struct KalamObjectFailureDTO: Decodable {
    let storageId: UInt32
    let parentId: UInt32
    let objectId: UInt32
    let stage: String
    let error: String

    func failure(
        deviceID: MTPDeviceID,
        expectedStorageID: MTPStorageID,
        expectedParentID: MTPObjectID
    ) throws -> MTPObjectFailure {
        let storageID = try MTPStorageID(validating: storageId)
        let parentID = try MTPObjectID(validating: parentId)
        guard storageID == expectedStorageID,
              parentID == expectedParentID,
              stage == "object_info",
              error == "invalid_object_handle" else {
            throw MTPCoreError.protocolViolation(
                "Go directory warning does not match the listing request"
            )
        }
        return MTPObjectFailure(
            deviceID: deviceID,
            storageID: storageID,
            parentID: parentID,
            objectID: try MTPObjectID(validating: objectId),
            stage: .objectInfo,
            error: .response(code: .invalidObjectHandle)
        )
    }
}
