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

    /// Plan 2c Minor 盲点:12 字节但 type 非法(0xFFFF)→ ContainerType(rawValue:) nil → throw endOfData。
    func testParseBulkHeaderInvalidTypeThrows() {
        // length=12,type=0xFFFF(非法),code=0,tid=0 —— 12 字节齐全,但 type 无对应枚举
        let bytes: [UInt8] = [0x0C,0x00,0x00,0x00, 0xFF,0xFF, 0x00,0x00, 0x00,0x00,0x00,0x00]
        XCTAssertThrowsError(try parseBulkHeader(bytes)) { error in
            guard case MTPDecodeError.endOfData = error else {
                XCTFail("非法 type 应抛 endOfData,实际 \(error)"); return
            }
        }
    }

    /// 各合法 container type 值经 parseBulkHeader 正确映射(此前只测 .response)。
    /// command(0x0001)/data(0x0002)/event(0x0004)。
    func testParseBulkHeaderAllValidTypes() throws {
        func parse(type: UInt16) throws -> ContainerType {
            // length=12,type=入参,code=0,tid=0
            let bytes: [UInt8] = [0x0C,0x00,0x00,0x00,
                                  UInt8(type & 0xFF), UInt8((type >> 8) & 0xFF),
                                  0x00,0x00, 0x00,0x00,0x00,0x00]
            return try parseBulkHeader(bytes).type
        }
        XCTAssertEqual(try parse(type: 0x0001), .command)
        XCTAssertEqual(try parse(type: 0x0002), .data)
        XCTAssertEqual(try parse(type: 0x0003), .response)
        XCTAssertEqual(try parse(type: 0x0004), .event)
    }

    /// parseBulkHeader:字节不足于读取 type/tid(介于 4-12 之间)也应抛错。
    func testParseBulkHeaderPartialThrows() {
        // 8 字节:够 length+type 但不够 code+tid
        let bytes: [UInt8] = [0x0C,0x00,0x00,0x00, 0x03,0x00, 0x01,0x20]
        XCTAssertThrowsError(try parseBulkHeader(bytes))
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

    /// declaredLength < 12(无 payload 区,restLen 负)→ throw endOfData(对照 mtp.go:348)。
    /// 此前只测 declaredLength==12 和 >rest,负 restLen 分支未覆盖。
    func testDecodeResponseParamsLengthBelowHeaderThrows() {
        // declaredLength=8 → restLen = 8-12 = -4 < 0
        XCTAssertThrowsError(try decodeResponseParams(declaredLength: 8, rest: [])) { error in
            guard case MTPDecodeError.endOfData = error else {
                XCTFail("declaredLength<12 应抛 endOfData,实际 \(error)"); return
            }
        }
        // 极端:declaredLength=0
        XCTAssertThrowsError(try decodeResponseParams(declaredLength: 0, rest: []))
    }

    /// rest 非整除 4(restLen/4 整数除法截断):declaredLength=14 → restLen=2 → nParam=0。
    /// 验证截断语义:丢弃不足一个 u32 的尾部字节,返回空数组(协议边界契约)。
    func testDecodeResponseParamsTruncatesNonMultipleOf4() throws {
        // declaredLength=14 → restLen=2 → nParam=2/4=0,rest 含 2 字节(被截断)
        let params = try decodeResponseParams(declaredLength: 14, rest: [0x01, 0x02])
        XCTAssertEqual(params, [], "restLen=2 非 4 整数倍,nParam 应截断为 0")
        // declaredLength=16 → restLen=4 → nParam=1(恰好整除,正常)
        let p2 = try decodeResponseParams(declaredLength: 16, rest: [0x01, 0, 0, 0])
        XCTAssertEqual(p2, [1])
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

    /// needsZeroLengthPacket 边界:lastTransferBytes==0(空尾包)→ false;
    /// packetSize==0(除零保护)→ false。此前只测 512/100 两值。
    func testNeedsZeroLengthPacketBoundaries() {
        // lastTransferBytes==0:无数据传输,不需 ZLP(对照 Go mtp.go:597 n>0 守卫)
        XCTAssertFalse(needsZeroLengthPacket(lastTransferBytes: 0, packetSize: 512),
                       "空尾包不应触发 ZLP")
        // packetSize==0:除零保护,避免 % 0 崩溃
        XCTAssertFalse(needsZeroLengthPacket(lastTransferBytes: 512, packetSize: 0),
                       "packetSize==0 不应触发 ZLP(除零保护)")
        // 两者皆 0
        XCTAssertFalse(needsZeroLengthPacket(lastTransferBytes: 0, packetSize: 0))
        // 大包:4096 是 512 的整数倍 → true(验证多倍数关系)
        XCTAssertTrue(needsZeroLengthPacket(lastTransferBytes: 4096, packetSize: 512))
    }
}
