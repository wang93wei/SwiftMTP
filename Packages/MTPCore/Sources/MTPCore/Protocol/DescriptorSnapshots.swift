import Foundation

/// USB 端点描述符快照(值类型,从 libusb_endpoint_descriptor 拷贝)。
public struct EndpointSnapshot: Equatable {
    public let address: UInt8       // bEndpointAddress:b7=方向(0x80=IN),b3:0=端点号
    public let attributes: UInt8    // bmAttributes:b1:0=传输类型(2=BULK,3=INTERRUPT)
    public let maxPacketSize: UInt16
    public init(address: UInt8, attributes: UInt8, maxPacketSize: UInt16) {
        self.address = address; self.attributes = attributes; self.maxPacketSize = maxPacketSize
    }
    public var isIn: Bool { (address & 0x80) != 0 }
    public var transferType: UInt8 { attributes & 0x03 }
}

/// USB 接口描述符快照。
public struct InterfaceDescriptorSnapshot: Equatable {
    public let interfaceNumber: UInt8
    public let interfaceStringIndex: UInt8   // iInterface(0=无字符串)
    public let endpoints: [EndpointSnapshot]
    public init(interfaceNumber: UInt8, interfaceStringIndex: UInt8, endpoints: [EndpointSnapshot]) {
        self.interfaceNumber = interfaceNumber
        self.interfaceStringIndex = interfaceStringIndex
        self.endpoints = endpoints
    }
}

/// USB 设备描述符快照。
public struct DeviceDescriptorSnapshot: Equatable {
    public let idVendor: UInt16
    public let idProduct: UInt16
    public let iManufacturer: UInt8
    public let iProduct: UInt8
    public let iSerialNumber: UInt8
    public let numConfigurations: UInt8
    public init(idVendor: UInt16, idProduct: UInt16, iManufacturer: UInt8,
                iProduct: UInt8, iSerialNumber: UInt8, numConfigurations: UInt8) {
        self.idVendor = idVendor; self.idProduct = idProduct
        self.iManufacturer = iManufacturer; self.iProduct = iProduct
        self.iSerialNumber = iSerialNumber; self.numConfigurations = numConfigurations
    }
}
