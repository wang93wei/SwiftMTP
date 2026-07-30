import Foundation

nonisolated extension MTPDeviceSession {
    func resolvedObjectSizeLocked(
        objectID: MTPObjectID,
        objectInfo: MTPObjectInfoDataset,
        cancellation: MTPCancellationToken
    ) throws -> UInt64? {
        guard objectInfo.hasObjectSizeSentinel else {
            return objectInfo.objectSize
        }
        do {
            return try executeInboundLocked(
                operation: .getObjectPropValue,
                parameters: [
                    objectID.rawValue,
                    UInt32(MTPObjectPropertyCode.objectSize.rawValue),
                ],
                cancellation: cancellation
            ) { data in
                var reader = MTPBinaryReader(data: data)
                let value = try reader.readUInt64()
                guard reader.remainingCount == 0 else {
                    throw MTPCoreError.protocolViolation(
                        "ObjectSize property contained trailing bytes"
                    )
                }
                return value
            }
        } catch let error as MTPCoreError {
            guard case .response(let code) = error,
                  code == .operationNotSupported || code == .invalidObjectPropCode else {
                throw error
            }
            return nil
        }
    }
}
