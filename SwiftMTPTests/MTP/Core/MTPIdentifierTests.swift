import XCTest
@testable import SwiftMTP

final class MTPIdentifierTests: XCTestCase {
    func testStorageIdentifierRejectsZero() {
        XCTAssertThrowsError(try MTPStorageID(validating: 0))
    }

    func testDistinctIdentifierTypesPreserveValues() throws {
        let storage = try MTPStorageID(validating: 7)
        let object = try MTPObjectID(validating: 7)
        let session = try MTPSessionID(validating: 7)
        let transaction = try MTPTransactionID(validating: 7)

        XCTAssertEqual(storage.rawValue, 7)
        XCTAssertEqual(object.rawValue, 7)
        XCTAssertEqual(session.rawValue, 7)
        XCTAssertEqual(transaction.rawValue, 7)
    }

    func testRootParentAndFullTransactionRangeAreExplicitlyValid() throws {
        XCTAssertEqual(MTPObjectID.root.rawValue, 0xFFFF_FFFF)
        XCTAssertEqual(try MTPTransactionID(validating: 0).rawValue, 0)
        XCTAssertEqual(try MTPTransactionID(validating: 0xFFFF_FFFF).rawValue, 0xFFFF_FFFF)
    }

    func testInvalidIdentifierSentinelsAreRejected() {
        XCTAssertThrowsError(try MTPObjectID(validating: 0))
        XCTAssertThrowsError(try MTPSessionID(validating: 0))
        XCTAssertThrowsError(try MTPSessionID(validating: 0xFFFF_FFFF))
        XCTAssertThrowsError(try MTPDeviceID(validating: ""))
    }
}
