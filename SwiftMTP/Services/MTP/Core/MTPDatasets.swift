import Foundation

nonisolated struct MTPUInt32Array: Equatable, Sendable {
    let values: [UInt32]

    func encoded() -> Data {
        var writer = MTPBinaryWriter()
        writer.write(UInt32(values.count))
        for value in values {
            writer.write(value)
        }
        return writer.data
    }

    static func decode(_ data: Data) throws -> Self {
        var reader = MTPBinaryReader(data: data)
        let count = try reader.readUInt32()
        guard UInt64(count) * 4 <= UInt64(reader.remainingCount) else {
            throw MTPCoreError.protocolViolation("UInt32 array dataset is truncated")
        }
        var values: [UInt32] = []
        values.reserveCapacity(Int(count))
        for _ in 0..<count {
            values.append(try reader.readUInt32())
        }
        guard reader.remainingCount == 0 else {
            throw MTPCoreError.protocolViolation("UInt32 array dataset has trailing bytes")
        }
        return Self(values: values)
    }
}

nonisolated struct MTPObjectInfoDataset: Equatable, Sendable {
    let storageID: MTPStorageID
    let objectFormat: UInt16
    let protectionStatus: UInt16
    let objectSize: UInt64
    let thumbFormat: UInt16
    let thumbCompressedSize: UInt32
    let thumbPixelWidth: UInt32
    let thumbPixelHeight: UInt32
    let imagePixelWidth: UInt32
    let imagePixelHeight: UInt32
    let imageBitDepth: UInt32
    let parentObject: MTPObjectID
    let associationType: UInt16
    let associationDescription: UInt32
    let sequenceNumber: UInt32
    let filename: String
    let captureDateString: String
    let modificationDateString: String
    let keywords: String

    var modificationDate: Date? {
        try? Self.parseDate(modificationDateString)
    }

    var hasObjectSizeSentinel: Bool {
        objectSize == UInt64(UInt32.max)
    }

    init(
        storageID: MTPStorageID,
        objectFormat: UInt16,
        objectSize: UInt64,
        parentObject: MTPObjectID,
        filename: String,
        modificationDateString: String = "",
        protectionStatus: UInt16 = 0,
        thumbFormat: UInt16 = 0,
        thumbCompressedSize: UInt32 = 0,
        thumbPixelWidth: UInt32 = 0,
        thumbPixelHeight: UInt32 = 0,
        imagePixelWidth: UInt32 = 0,
        imagePixelHeight: UInt32 = 0,
        imageBitDepth: UInt32 = 0,
        associationType: UInt16 = 0,
        associationDescription: UInt32 = 0,
        sequenceNumber: UInt32 = 0,
        captureDateString: String = "",
        keywords: String = ""
    ) throws {
        var validator = MTPBinaryWriter()
        try validator.writeMTPString(filename)
        try validator.writeMTPString(captureDateString)
        try validator.writeMTPString(modificationDateString)
        try validator.writeMTPString(keywords)
        _ = try Self.parseDate(captureDateString)
        _ = try Self.parseDate(modificationDateString)

        self.storageID = storageID
        self.objectFormat = objectFormat
        self.protectionStatus = protectionStatus
        self.objectSize = objectSize
        self.thumbFormat = thumbFormat
        self.thumbCompressedSize = thumbCompressedSize
        self.thumbPixelWidth = thumbPixelWidth
        self.thumbPixelHeight = thumbPixelHeight
        self.imagePixelWidth = imagePixelWidth
        self.imagePixelHeight = imagePixelHeight
        self.imageBitDepth = imageBitDepth
        self.parentObject = parentObject
        self.associationType = associationType
        self.associationDescription = associationDescription
        self.sequenceNumber = sequenceNumber
        self.filename = filename
        self.captureDateString = captureDateString
        self.modificationDateString = modificationDateString
        self.keywords = keywords
    }

    static func folder(
        storageID: MTPStorageID,
        parentObject: MTPObjectID,
        name: String
    ) throws -> Self {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MTPCoreError.invalidInput("folder name must not be empty")
        }
        guard !trimmed.contains(where: { "/\\:*?\"<>|".contains($0) }) else {
            throw MTPCoreError.invalidInput("folder name contains a forbidden character")
        }
        return try Self(
            storageID: storageID,
            objectFormat: 0x3001,
            objectSize: 0,
            parentObject: parentObject,
            filename: trimmed,
            associationType: 1
        )
    }

    static func file(
        storageID: MTPStorageID,
        parentObject: MTPObjectID,
        name: String,
        size: UInt64,
        modificationDateString: String = ""
    ) throws -> Self {
        guard !name.isEmpty else {
            throw MTPCoreError.invalidInput("file name must not be empty")
        }
        guard !name.contains(where: { "/\\:*?\"<>|".contains($0) }) else {
            throw MTPCoreError.invalidInput("file name contains a forbidden character")
        }
        guard !name.unicodeScalars.contains(where: {
            $0.value < 0x20 || $0.value == 0x7F
        }) else {
            throw MTPCoreError.invalidInput("file name contains a control character")
        }
        return try Self(
            storageID: storageID,
            objectFormat: 0x3000,
            objectSize: size,
            parentObject: parentObject,
            filename: name,
            modificationDateString: modificationDateString
        )
    }

    func encoded() throws -> Data {
        var writer = MTPBinaryWriter()
        writer.write(storageID.rawValue)
        writer.write(objectFormat)
        writer.write(protectionStatus)
        writer.write(Self.compressedSizeField(for: objectSize))
        writer.write(thumbFormat)
        writer.write(thumbCompressedSize)
        writer.write(thumbPixelWidth)
        writer.write(thumbPixelHeight)
        writer.write(imagePixelWidth)
        writer.write(imagePixelHeight)
        writer.write(imageBitDepth)
        writer.write(parentObject.rawValue)
        writer.write(associationType)
        writer.write(associationDescription)
        writer.write(sequenceNumber)
        try writer.writeMTPString(filename)
        try writer.writeMTPString(captureDateString)
        try writer.writeMTPString(modificationDateString)
        try writer.writeMTPString(keywords)
        return writer.data
    }

    static func decode(_ data: Data) throws -> Self {
        var reader = MTPBinaryReader(data: data)
        let storageID = try MTPStorageID(validating: reader.readUInt32())
        let objectFormat = try reader.readUInt16()
        let protectionStatus = try reader.readUInt16()
        let objectSize = UInt64(try reader.readUInt32())
        let thumbFormat = try reader.readUInt16()
        let thumbCompressedSize = try reader.readUInt32()
        let thumbPixelWidth = try reader.readUInt32()
        let thumbPixelHeight = try reader.readUInt32()
        let imagePixelWidth = try reader.readUInt32()
        let imagePixelHeight = try reader.readUInt32()
        let imageBitDepth = try reader.readUInt32()
        let rawParentObject = try reader.readUInt32()
        // ObjectInfo uses zero for a root-level object's absent parent.
        // Normalize that wire value to the root selector used by the domain layer.
        let parentObject = rawParentObject == 0
            ? MTPObjectID.root
            : try MTPObjectID(validating: rawParentObject)
        let associationType = try reader.readUInt16()
        let associationDescription = try reader.readUInt32()
        let sequenceNumber = try reader.readUInt32()
        let filename = try reader.readMTPString()
        let captureDateString = try reader.readMTPString()
        let modificationDateString = try reader.readMTPString()
        let keywords = try reader.readMTPString()
        guard reader.remainingCount == 0 else {
            throw MTPCoreError.protocolViolation("ObjectInfo dataset has trailing bytes")
        }
        return try Self(
            storageID: storageID,
            objectFormat: objectFormat,
            objectSize: objectSize,
            parentObject: parentObject,
            filename: filename,
            modificationDateString: modificationDateString,
            protectionStatus: protectionStatus,
            thumbFormat: thumbFormat,
            thumbCompressedSize: thumbCompressedSize,
            thumbPixelWidth: thumbPixelWidth,
            thumbPixelHeight: thumbPixelHeight,
            imagePixelWidth: imagePixelWidth,
            imagePixelHeight: imagePixelHeight,
            imageBitDepth: imageBitDepth,
            associationType: associationType,
            associationDescription: associationDescription,
            sequenceNumber: sequenceNumber,
            captureDateString: captureDateString,
            keywords: keywords
        )
    }

    /// ObjectInfo has a separate UInt32 size field: values through
    /// `0xFFFFFFFE` are exact, while larger values use its sentinel.
    static func compressedSizeField(for byteCount: UInt64) -> UInt32 {
        byteCount >= UInt64(UInt32.max) ? UInt32.max : UInt32(byteCount)
    }

    private static func parseDate(_ value: String) throws -> Date? {
        guard !value.isEmpty else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.isLenient = false
        let normalized = value.hasSuffix("Z") ? String(value.dropLast()) + "+0000" : value
        for format in ["yyyyMMdd'T'HHmmssZ", "yyyyMMdd'T'HHmmss"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: normalized) {
                return date
            }
        }
        throw MTPCoreError.protocolViolation("ObjectInfo contains a malformed MTP timestamp")
    }
}

nonisolated struct MTPDeviceInfoDataset: Equatable, Sendable {
    let standardVersion: UInt16
    let vendorExtensionID: UInt32
    let vendorExtensionVersion: UInt16
    let vendorExtensionDescription: String
    let functionalMode: UInt16
    let operationsSupported: [UInt16]
    let eventsSupported: [UInt16]
    let devicePropertiesSupported: [UInt16]
    let captureFormats: [UInt16]
    let imageFormats: [UInt16]
    let manufacturer: String
    let model: String
    let deviceVersion: String
    let serialNumber: String

    static func decode(_ data: Data) throws -> Self {
        var reader = MTPBinaryReader(data: data)
        let result = Self(
            standardVersion: try reader.readUInt16(),
            vendorExtensionID: try reader.readUInt32(),
            vendorExtensionVersion: try reader.readUInt16(),
            vendorExtensionDescription: try reader.readMTPString(),
            functionalMode: try reader.readUInt16(),
            operationsSupported: try reader.readUInt16Array(),
            eventsSupported: try reader.readUInt16Array(),
            devicePropertiesSupported: try reader.readUInt16Array(),
            captureFormats: try reader.readUInt16Array(),
            imageFormats: try reader.readUInt16Array(),
            manufacturer: try reader.readMTPString(),
            model: try reader.readMTPString(),
            deviceVersion: try reader.readMTPString(),
            serialNumber: try reader.readMTPString()
        )
        guard reader.remainingCount == 0 else {
            throw MTPCoreError.protocolViolation("DeviceInfo dataset has trailing bytes")
        }
        return result
    }
}

nonisolated struct MTPStorageInfoDataset: Equatable, Sendable {
    let storageType: UInt16
    let fileSystemType: UInt16
    let accessCapability: UInt16
    let maxCapacity: UInt64
    let freeSpaceInBytes: UInt64
    let freeSpaceInImages: UInt32
    let description: String
    let volumeLabel: String

    static func decode(_ data: Data) throws -> Self {
        var reader = MTPBinaryReader(data: data)
        let result = Self(
            storageType: try reader.readUInt16(),
            fileSystemType: try reader.readUInt16(),
            accessCapability: try reader.readUInt16(),
            maxCapacity: try reader.readUInt64(),
            freeSpaceInBytes: try reader.readUInt64(),
            freeSpaceInImages: try reader.readUInt32(),
            description: try reader.readMTPString(),
            volumeLabel: try reader.readMTPString()
        )
        guard reader.remainingCount == 0 else {
            throw MTPCoreError.protocolViolation("StorageInfo dataset has trailing bytes")
        }
        return result
    }
}

private extension MTPBinaryReader {
    nonisolated mutating func readUInt16Array() throws -> [UInt16] {
        let count = try readUInt32()
        guard UInt64(count) * 2 <= UInt64(remainingCount) else {
            throw MTPCoreError.protocolViolation("UInt16 array dataset is truncated")
        }
        var values: [UInt16] = []
        values.reserveCapacity(Int(count))
        for _ in 0..<count {
            values.append(try readUInt16())
        }
        return values
    }
}
