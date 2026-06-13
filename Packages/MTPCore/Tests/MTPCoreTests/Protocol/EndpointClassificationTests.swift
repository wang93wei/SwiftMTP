import XCTest
@testable import MTPCore

final class EndpointClassificationTests: XCTestCase {
    // 端点构造辅助:address(b7方向/b3:0端点号)+ attributes(b1:0传输类型)
    private func ep(_ addr: UInt8, _ attrs: UInt8) -> EndpointSnapshot {
        EndpointSnapshot(address: addr, attributes: attrs, maxPacketSize: 512)
    }

    func testClassifyValidMTPEndpoints() {
        // OUT-BULK(0x02) + IN-INT(0x81) + IN-BULK(0x83)
        let eps = [ep(0x02, 0x02), ep(0x81, 0x03), ep(0x83, 0x02)]
        let r = classifyEndpoints(eps)
        XCTAssertEqual(r.sendEP, 0x02)
        XCTAssertEqual(r.eventEP, 0x81)
        XCTAssertEqual(r.fetchEP, 0x83)
    }

    func testClassifyIgnoresIsochronous() {
        // 含一个同步端点(传输类型 1),3 端点里只有 2 个有效 → 不齐备
        let eps = [ep(0x02, 0x02), ep(0x81, 0x03), ep(0x83, 0x01)]  // 0x83 是 ISOCHRONOUS
        let r = classifyEndpoints(eps)
        XCTAssertNil(r.fetchEP, "ISOCHRONOUS 端点不应被当 bulk IN")
    }

    func testIsMTPCandidateRequiresExactly3Endpoints() {
        XCTAssertTrue(isMTPCandidate([ep(0x02, 0x02), ep(0x81, 0x03), ep(0x83, 0x02)]))
        XCTAssertFalse(isMTPCandidate([ep(0x02, 0x02), ep(0x81, 0x03)]), "2 端点不算")
        XCTAssertFalse(isMTPCandidate(Array(repeating: ep(0, 0), count: 4)), "4 端点不算")
    }

    func testIsMTPCandidateRequiresAllThreeTypes() {
        // 缺中断端点(只有 2 个 bulk)
        XCTAssertFalse(isMTPCandidate([ep(0x02, 0x02), ep(0x81, 0x02), ep(0x83, 0x02)]))
    }

    // MARK: - 空输入边界(此前未覆盖)

    /// classifyEndpoints 空列表 → 全 nil(无端点可分派)。
    func testClassifyEmptyListReturnsAllNil() {
        let r = classifyEndpoints([])
        XCTAssertNil(r.sendEP)
        XCTAssertNil(r.fetchEP)
        XCTAssertNil(r.eventEP)
    }

    /// isMTPCandidate([]) → false(count != 3 的 0 分支)。
    func testIsMTPCandidateEmptyListIsFalse() {
        XCTAssertFalse(isMTPCandidate([]), "空端点列表不应是 MTP 候选")
    }

    // MARK: - 同向同类型重复:后者覆盖前者(注释明说的顺序赋值契约)

    /// 两个 OUT-BULK 端点 → sendEP 取后者(对照 Go select.go switch 顺序赋值)。
    /// 此前只有单一端点,从未验证"后出现覆盖前者"语义。
    func testClassifyDuplicateSameTypeLastWins() {
        // 两个 OUT-BULK(0x02, 0x05),一个 IN-INT(0x81),一个 IN-BULK(0x83)
        let eps = [ep(0x02, 0x02), ep(0x05, 0x02), ep(0x81, 0x03), ep(0x83, 0x02)]
        let r = classifyEndpoints(eps)
        XCTAssertEqual(r.sendEP, 0x05, "重复 OUT-BULK 应取后者(0x05)")
        XCTAssertEqual(r.eventEP, 0x81)
        XCTAssertEqual(r.fetchEP, 0x83)
    }
}
