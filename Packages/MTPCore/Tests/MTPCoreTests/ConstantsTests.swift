import XCTest
@testable import MTPCore

final class ConstantsTests: XCTestCase {
    func testOperationCodeValues() {
        // 对照 Go const.go(const.go:897-909)
        XCTAssertEqual(OperationCode.getDeviceInfo.rawValue,   0x1001)
        XCTAssertEqual(OperationCode.openSession.rawValue,     0x1002)
        XCTAssertEqual(OperationCode.closeSession.rawValue,    0x1003)
        XCTAssertEqual(OperationCode.getStorageIDs.rawValue,   0x1004)
        XCTAssertEqual(OperationCode.getStorageInfo.rawValue,  0x1005)
        XCTAssertEqual(OperationCode.getNumObjects.rawValue,   0x1006)
        XCTAssertEqual(OperationCode.getObjectHandles.rawValue, 0x1007)
        XCTAssertEqual(OperationCode.getObjectInfo.rawValue,   0x1008)
        XCTAssertEqual(OperationCode.getObject.rawValue,       0x1009)
    }

    func testReturnCodeValues() {
        // 对照 const.go:1790-1819。注意:RC_ObjectNotFound 不存在 → invalidObjectHandle
        XCTAssertEqual(ReturnCode.ok.rawValue,                   0x2001)
        XCTAssertEqual(ReturnCode.sessionAlreadyOpened.rawValue, 0x201E)
        XCTAssertEqual(ReturnCode.invalidObjectHandle.rawValue,  0x2009)
        XCTAssertEqual(ReturnCode.sessionNotOpen.rawValue,       0x2003)
        XCTAssertEqual(ReturnCode.deviceBusy.rawValue,           0x2019)
        XCTAssertEqual(ReturnCode.transactionCanceled.rawValue,  0x201F)
    }

    func testContainerTypeValues() {
        // USB container 类型(const.go:1930-1933)
        XCTAssertEqual(ContainerType.command.rawValue,  0x0001)
        XCTAssertEqual(ContainerType.data.rawValue,    0x0002)
        XCTAssertEqual(ContainerType.response.rawValue, 0x0003)
        XCTAssertEqual(ContainerType.event.rawValue,   0x0004)
    }

    func testMiscConstants() {
        // GOH(const.go)
        XCTAssertEqual(MTPConstants.gohAllStorage,  0xFFFFFFFF)
        XCTAssertEqual(MTPConstants.gohRootParent,  0xFFFFFFFF)
        // ObjectFormatCode:文件夹
        XCTAssertEqual(MTPConstants.ofcAssociation, 0x3001)
        // 线序长度(types.go:167-168)
        XCTAssertEqual(MTPConstants.usbHeaderLength, 12)        // 2*2 + 2*4
        XCTAssertEqual(MTPConstants.usbBulkContainerLength, 32) // 5*4 + 12
        // bulk 单次缓冲(mtp.go:526)
        XCTAssertEqual(MTPConstants.bulkTransferBufferSize, 0x4000) // 16KB
        // 端点拓扑(usb.go:282-289)—— libusb 宏在 Swift 不可见,自写等价常量
        XCTAssertEqual(MTPConstants.endpointIn, 0x80)
        XCTAssertEqual(MTPConstants.transferTypeBulk, 0x02)
        XCTAssertEqual(MTPConstants.transferTypeInterrupt, 0x03)
        // 默认超时(mtp.go:154)
        XCTAssertEqual(MTPConstants.defaultTimeoutMs, 2000)
    }
}
