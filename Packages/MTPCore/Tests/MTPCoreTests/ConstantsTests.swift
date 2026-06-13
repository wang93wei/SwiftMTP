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
}
