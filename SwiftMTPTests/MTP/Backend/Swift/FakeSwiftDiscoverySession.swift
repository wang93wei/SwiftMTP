import Foundation
@testable import SwiftMTP

final class FakeSwiftDiscoverySession: SwiftMTPDiscoverySession {
    let deviceID: MTPDeviceID
    var deviceInfo: MTPDeviceInfoDataset
    var deviceInfoError: MTPCoreError?
    var storageIDs: [MTPStorageID]
    var storageInfo: [MTPStorageID: MTPStorageInfoDataset] = [:]
    var storageErrors: [MTPStorageID: MTPCoreError] = [:]
    var objectHandles: [MTPObjectID] = []
    var objectHandlesError: MTPCoreError?
    var objectInfo: [MTPObjectID: MTPObjectInfoDataset] = [:]
    var objectInfoErrors: [MTPObjectID: MTPCoreError] = [:]
    var downloadData = Data()
    var downloadResult = MTPDownloadResult(
        expectedByteCount: 0,
        transferredByteCount: 0
    )
    var downloadError: MTPCoreError?
    var beforeDownload: (() -> Void)?
    private(set) var downloadCount = 0
    var uploadResult: MTPUploadResult?
    var uploadError: MTPCoreError?
    private(set) var uploadCount = 0
    private(set) var closeCount = 0

    init(
        deviceID: MTPDeviceID,
        storageIDs: [MTPStorageID] = [],
        deviceInfo: MTPDeviceInfoDataset? = nil
    ) {
        self.deviceID = deviceID
        self.storageIDs = storageIDs
        self.deviceInfo = deviceInfo ?? MTPDeviceInfoDataset(
            standardVersion: 100,
            vendorExtensionID: 6,
            vendorExtensionVersion: 101,
            vendorExtensionDescription: "MTP",
            functionalMode: 0,
            operationsSupported: [
                MTPOperationCode.getStorageIDs.rawValue,
                MTPOperationCode.getStorageInfo.rawValue,
                MTPOperationCode.getObjectHandles.rawValue,
                MTPOperationCode.getObjectInfo.rawValue,
                MTPOperationCode.getObject.rawValue,
                MTPOperationCode.deleteObject.rawValue,
                MTPOperationCode.sendObjectInfo.rawValue,
                MTPOperationCode.sendObject.rawValue,
            ],
            eventsSupported: [],
            devicePropertiesSupported: [],
            captureFormats: [],
            imageFormats: [],
            manufacturer: "Acme",
            model: "Phone",
            deviceVersion: "1",
            serialNumber: "private"
        )
    }

    func getDeviceInfo() throws -> MTPDeviceInfoDataset {
        if let deviceInfoError {
            throw deviceInfoError
        }
        return deviceInfo
    }

    func getStorageIDs() throws -> [MTPStorageID] {
        storageIDs
    }

    func getStorageInfo(_ storageID: MTPStorageID) throws -> MTPStorageInfoDataset {
        if let error = storageErrors[storageID] {
            throw error
        }
        guard let info = storageInfo[storageID] else {
            throw MTPCoreError.noDevice
        }
        return info
    }

    func getObjectHandles(
        storageID: MTPStorageID,
        parentID: MTPObjectID
    ) throws -> [MTPObjectID] {
        if let objectHandlesError {
            throw objectHandlesError
        }
        return objectHandles
    }

    func getObjectInfo(_ objectID: MTPObjectID) throws -> MTPObjectInfoDataset {
        if let error = objectInfoErrors[objectID] {
            throw error
        }
        guard let info = objectInfo[objectID] else {
            throw MTPCoreError.response(code: .invalidObjectHandle)
        }
        return info
    }

    func download(
        objectID: MTPObjectID,
        sink: any MTPStreamSink,
        progress: @escaping MTPTransferProgress,
        cancellation: MTPCancellationToken
    ) throws -> MTPDownloadResult {
        downloadCount += 1
        beforeDownload?()
        try cancellation.throwIfCancelled()
        if !downloadData.isEmpty {
            try sink.write(downloadData)
            progress(UInt64(downloadData.count))
        }
        if let downloadError {
            throw downloadError
        }
        return downloadResult
    }

    func upload(
        storageID: MTPStorageID,
        parentID: MTPObjectID,
        name: String,
        size: UInt64,
        modificationDateString: String,
        source: any MTPStreamSource,
        progress: @escaping MTPTransferProgress,
        cancellation: MTPCancellationToken
    ) throws -> MTPUploadResult {
        uploadCount += 1
        try cancellation.throwIfCancelled()
        if let uploadError {
            throw uploadError
        }
        if let uploadResult {
            return uploadResult
        }
        return MTPUploadResult(
            objectID: try MTPObjectID(validating: 1),
            transferredByteCount: size
        )
    }

    func createFolder(
        storageID: MTPStorageID,
        parentID: MTPObjectID,
        name: String
    ) throws -> MTPObjectID {
        try MTPObjectID(validating: 1)
    }

    func deleteObject(_ objectID: MTPObjectID) throws {}

    func close() {
        closeCount += 1
    }
}
