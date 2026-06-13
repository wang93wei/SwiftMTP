import Foundation

/// MTP StorageInfo。线序对应 Go types.go StorageInfo。
/// 来源:vendor/github.com/ganeshrvel/go-mtpfs/mtp/types.go
public struct StorageInfo: MTPDecodable, Equatable {
    public var storageType: UInt16
    public var filesystemType: UInt16
    public var accessCapability: UInt16
    public var maxCapability: UInt64
    public var freeSpaceInBytes: UInt64
    public var freeSpaceInImages: UInt32
    public var storageDescription: String
    public var volumeLabel: String

    public init(from reader: inout MTPReader) throws {
        storageType = try reader.readU16()
        filesystemType = try reader.readU16()
        accessCapability = try reader.readU16()
        maxCapability = try reader.readU64()
        freeSpaceInBytes = try reader.readU64()
        freeSpaceInImages = try reader.readU32()
        storageDescription = try reader.readMTPString()
        volumeLabel = try reader.readMTPString()
    }

    public init() {
        storageType = 0; filesystemType = 0; accessCapability = 0
        maxCapability = 0; freeSpaceInBytes = 0; freeSpaceInImages = 0
        storageDescription = ""; volumeLabel = ""
    }
}
