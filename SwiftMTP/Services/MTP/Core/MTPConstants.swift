import Foundation

nonisolated struct MTPOperationCode: RawRepresentable, Hashable, Sendable {
    let rawValue: UInt16

    init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    static let getDeviceInfo = Self(rawValue: 0x1001)
    static let openSession = Self(rawValue: 0x1002)
    static let closeSession = Self(rawValue: 0x1003)
    static let getStorageIDs = Self(rawValue: 0x1004)
    static let getStorageInfo = Self(rawValue: 0x1005)
    static let getObjectHandles = Self(rawValue: 0x1007)
    static let getObjectInfo = Self(rawValue: 0x1008)
    static let getObject = Self(rawValue: 0x1009)
    static let deleteObject = Self(rawValue: 0x100B)
    static let sendObjectInfo = Self(rawValue: 0x100C)
    static let sendObject = Self(rawValue: 0x100D)
}

nonisolated struct MTPResponseCode: RawRepresentable, Hashable, Sendable {
    let rawValue: UInt16

    init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    static let ok = Self(rawValue: 0x2001)
    static let generalError = Self(rawValue: 0x2002)
    static let sessionNotOpen = Self(rawValue: 0x2003)
    static let operationNotSupported = Self(rawValue: 0x2005)
    static let invalidObjectHandle = Self(rawValue: 0x2009)
    static let deviceBusy = Self(rawValue: 0x2019)
}

nonisolated enum MTPContainerType: UInt16, Sendable {
    case command = 1
    case data = 2
    case response = 3
    case event = 4
}
