import Foundation

/// MTP ObjectInfo。线序严格对应 Go types.go ObjectInfo(字段顺序即线序)。
/// 来源:vendor/github.com/ganeshrvel/go-mtpfs/mtp/types.go
public struct ObjectInfo: MTPDecodable, Equatable {
    public var storageID: UInt32
    public var objectFormat: UInt16
    public var protectionStatus: UInt16
    public var compressedSize: UInt32
    public var thumbFormat: UInt16
    public var thumbCompressedSize: UInt32
    public var thumbPixWidth: UInt32
    public var thumbPixHeight: UInt32
    public var imagePixWidth: UInt32
    public var imagePixHeight: UInt32
    public var imageBitDepth: UInt32
    public var parentObject: UInt32
    public var associationType: UInt16
    public var associationDesc: UInt32
    public var sequenceNumber: UInt32
    public var filename: String
    public var captureDate: Date?       // Go zero time → nil
    public var modificationDate: Date?  // Go zero time → nil
    public var keywords: String

    public init(from reader: inout MTPReader) throws {
        storageID = try reader.readU32()
        objectFormat = try reader.readU16()
        protectionStatus = try reader.readU16()
        compressedSize = try reader.readU32()
        thumbFormat = try reader.readU16()
        thumbCompressedSize = try reader.readU32()
        thumbPixWidth = try reader.readU32()
        thumbPixHeight = try reader.readU32()
        imagePixWidth = try reader.readU32()
        imagePixHeight = try reader.readU32()
        imageBitDepth = try reader.readU32()
        parentObject = try reader.readU32()
        associationType = try reader.readU16()
        associationDesc = try reader.readU32()
        sequenceNumber = try reader.readU32()
        filename = try reader.readMTPString()
        captureDate = try reader.readMTPTime()
        modificationDate = try reader.readMTPTime()
        keywords = try reader.readMTPString()
    }

    public init(storageID: UInt32 = 0, objectFormat: UInt16 = 0, protectionStatus: UInt16 = 0,
                compressedSize: UInt32 = 0, thumbFormat: UInt16 = 0, thumbCompressedSize: UInt32 = 0,
                thumbPixWidth: UInt32 = 0, thumbPixHeight: UInt32 = 0, imagePixWidth: UInt32 = 0,
                imagePixHeight: UInt32 = 0, imageBitDepth: UInt32 = 0, parentObject: UInt32 = 0,
                associationType: UInt16 = 0, associationDesc: UInt32 = 0, sequenceNumber: UInt32 = 0,
                filename: String = "", captureDate: Date? = nil, modificationDate: Date? = nil,
                keywords: String = "") {
        self.storageID = storageID; self.objectFormat = objectFormat
        self.protectionStatus = protectionStatus; self.compressedSize = compressedSize
        self.thumbFormat = thumbFormat; self.thumbCompressedSize = thumbCompressedSize
        self.thumbPixWidth = thumbPixWidth; self.thumbPixHeight = thumbPixHeight
        self.imagePixWidth = imagePixWidth; self.imagePixHeight = imagePixHeight
        self.imageBitDepth = imageBitDepth; self.parentObject = parentObject
        self.associationType = associationType; self.associationDesc = associationDesc
        self.sequenceNumber = sequenceNumber; self.filename = filename
        self.captureDate = captureDate; self.modificationDate = modificationDate
        self.keywords = keywords
    }
}
