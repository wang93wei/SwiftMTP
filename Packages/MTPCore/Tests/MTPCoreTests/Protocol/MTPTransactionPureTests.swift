import XCTest
@testable import MTPCore

/// 事务纯函数单测(对照 Plan 2c Task 2)。覆盖 Go mtp.go:333/347-355/464/669/597。
final class MTPTransactionPureTests: XCTestCase {

    // MARK: - parseBulkHeader(12 字节小端 → length/type/code/tid)

    func testParseBulkHeaderResponse() throws {
        // length=0x2001,type=0x0003(response),code=0x2001(ok),tid=1
        let bytes: [UInt8] = [0x01,0x20,0x00,0x00, 0x03,0x00, 0x01,0x20, 0x01,0x00,0x00,0x00]
        let h = try parseBulkHeader(bytes)
        XCTAssertEqual(h.length, 0x2001)
        XCTAssertEqual(h.type, .response)
        XCTAssertEqual(h.code, 0x2001)
        XCTAssertEqual(h.transactionID, 1)
    }

    func testParseBulkHeaderTooShortThrows() {
        XCTAssertThrowsError(try parseBulkHeader([0x01, 0x02]))  // <12 字节
    }

    // MARK: - decodeResponseParams(声明的 payload → [UInt32])

    func testDecodeResponseParams() throws {
        // length=24(12 header + 12 payload = 3 params),rest=12 字节
        let rest: [UInt8] = [0x01,0,0,0, 0x02,0,0,0, 0x03,0,0,0]
        let params = try decodeResponseParams(declaredLength: 24, rest: rest)
        XCTAssertEqual(params, [1, 2, 3])
    }

    func testDecodeResponseParamsDeclaredExceedsRestThrows() {
        // length 声明 24(payload 12)但 rest 只 4 字节 → throw(对照 mtp.go:348)
        XCTAssertThrowsError(try decodeResponseParams(declaredLength: 24, rest: [1,2,3,4]))
    }

    func testDecodeResponseParamsNoPayload() throws {
        XCTAssertEqual(try decodeResponseParams(declaredLength: 12, rest: []), [])  // 0 参数
    }

    // MARK: - shouldEnableSeparateHeader(P1 探测)

    func testShouldEnableSeparateHeader() {
        XCTAssertTrue(shouldEnableSeparateHeader(firstPacketBytes: 12, restLength: 0, declaredContainerLength: 100))
        XCTAssertFalse(shouldEnableSeparateHeader(firstPacketBytes: 512, restLength: 500, declaredContainerLength: 600))  // 正常包
        XCTAssertFalse(shouldEnableSeparateHeader(firstPacketBytes: 12, restLength: 0, declaredContainerLength: 12))  // length==n,无后续
    }

    // MARK: - isSessionAlreadyOpened(P5 判定)

    func testIsSessionAlreadyOpened() {
        XCTAssertTrue(isSessionAlreadyOpened(MTPError.rcError(.sessionAlreadyOpened)))
        XCTAssertFalse(isSessionAlreadyOpened(MTPError.rcError(.deviceBusy)))
        XCTAssertFalse(isSessionAlreadyOpened(MTPError.libusb(MTPUSBError(code: -7))))
    }

    // MARK: - needsZeroLengthPacket(bulkWrite ZLP 判定)

    func testNeedsZeroLengthPacket() {
        XCTAssertTrue(needsZeroLengthPacket(lastTransferBytes: 512, packetSize: 512))
        XCTAssertFalse(needsZeroLengthPacket(lastTransferBytes: 100, packetSize: 512))
    }
}
