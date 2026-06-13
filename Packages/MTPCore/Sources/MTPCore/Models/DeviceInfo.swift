import Foundation

/// MTP DeviceInfo。线序对应 Go types.go DeviceInfo。
/// 含多个 []uint16 数组字段(operationsSupported/eventsSupported/...),
/// 线序必须完整(任一字段错位即后续全错)。
/// 来源:vendor/github.com/ganeshrvel/go-mtpfs/mtp/types.go
public struct DeviceInfo: MTPDecodable, Equatable {
    public var standardVersion: UInt16
    public var mtpVendorExtensionID: UInt32
    public var mtpVersion: UInt16
    public var mtpExtension: String
    public var functionalMode: UInt16
    public var operationsSupported: [UInt16]
    public var eventsSupported: [UInt16]
    public var devicePropertiesSupported: [UInt16]
    public var captureFormats: [UInt16]
    public var playbackFormats: [UInt16]
    public var manufacturer: String
    public var model: String
    public var deviceVersion: String
    public var serialNumber: String

    public init(from reader: inout MTPReader) throws {
        standardVersion = try reader.readU16()
        mtpVendorExtensionID = try reader.readU32()
        mtpVersion = try reader.readU16()
        mtpExtension = try reader.readMTPString()
        functionalMode = try reader.readU16()
        operationsSupported = try reader.readU16Array()
        eventsSupported = try reader.readU16Array()
        devicePropertiesSupported = try reader.readU16Array()
        captureFormats = try reader.readU16Array()
        playbackFormats = try reader.readU16Array()
        manufacturer = try reader.readMTPString()
        model = try reader.readMTPString()
        deviceVersion = try reader.readMTPString()
        serialNumber = try reader.readMTPString()
    }

    public init() {
        standardVersion = 0; mtpVendorExtensionID = 0; mtpVersion = 0
        mtpExtension = ""; functionalMode = 0
        operationsSupported = []; eventsSupported = []
        devicePropertiesSupported = []; captureFormats = []; playbackFormats = []
        manufacturer = ""; model = ""; deviceVersion = ""; serialNumber = ""
    }
}
