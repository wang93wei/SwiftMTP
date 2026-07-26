import CLibUSB
import XCTest

final class CLibUSBSmokeTests: XCTestCase {
    func testBundledLibUSBCompilesAndLinks() throws {
        XCTAssertEqual(LIBUSB_API_VERSION, 0x0100_010B)

        let version = try XCTUnwrap(libusb_get_version())
        XCTAssertEqual(version.pointee.major, 1)
        XCTAssertEqual(version.pointee.minor, 0)
        XCTAssertEqual(version.pointee.micro, 29)
        XCTAssertEqual(version.pointee.nano, 11_953)
        XCTAssertNotNil(version.pointee.rc)
    }
}
