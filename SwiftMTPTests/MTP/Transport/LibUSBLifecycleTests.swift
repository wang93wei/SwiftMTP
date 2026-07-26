import CLibUSB
import XCTest
@testable import SwiftMTP

final class LibUSBLifecycleTests: XCTestCase {
    func testContextInitializesAndExitsExactlyOnce() throws {
        let fake = FakeLibUSBFunctions()
        let context = try LibUSBContext(
            functions: fake.table,
            startsEventLoop: false
        )

        context.shutdown()
        context.shutdown()

        XCTAssertEqual(fake.events, ["init", "exit"])
    }

    func testHandleConfiguresClaimsAlternateAndCleansUpInReverseOrder() throws {
        let fake = FakeLibUSBFunctions()
        let context = try LibUSBContext(
            functions: fake.table,
            startsEventLoop: false
        )
        let candidate = makeCandidate(functions: fake.table)

        let handle = try LibUSBDeviceHandle(
            context: context,
            candidate: candidate,
            functions: fake.table
        )
        handle.close()
        context.shutdown()

        XCTAssertEqual(
            fake.events,
            [
                "init",
                "open",
                "getConfiguration",
                "setConfiguration:1",
                "claim:3",
                "alternate:3:1",
                "release:3",
                "close",
                "exit",
            ]
        )
    }

    func testClaimErrorsAreTypedAndAlwaysCloseTheHandle() throws {
        for (code, expected) in [
            (Int32(LIBUSB_ERROR_BUSY.rawValue), MTPCoreError.busy),
            (Int32(LIBUSB_ERROR_ACCESS.rawValue), .permissionDenied),
            (Int32(LIBUSB_ERROR_NO_DEVICE.rawValue), .disconnected),
        ] {
            let fake = FakeLibUSBFunctions()
            fake.claimCode = code
            let context = try LibUSBContext(
                functions: fake.table,
                startsEventLoop: false
            )
            let candidate = makeCandidate(functions: fake.table)

            XCTAssertThrowsError(
                try LibUSBDeviceHandle(
                    context: context,
                    candidate: candidate,
                    functions: fake.table
                )
            ) {
                XCTAssertEqual($0 as? MTPCoreError, expected)
            }
            context.shutdown()

            XCTAssertEqual(
                fake.events,
                [
                    "init",
                    "open",
                    "getConfiguration",
                    "setConfiguration:1",
                    "claim:3",
                    "close",
                    "exit",
                ]
            )
        }
    }

    func testAlternateSettingFailureReleasesClaimAndClosesHandle() throws {
        let fake = FakeLibUSBFunctions()
        fake.alternateSettingCode = Int32(LIBUSB_ERROR_NOT_FOUND.rawValue)
        let context = try LibUSBContext(
            functions: fake.table,
            startsEventLoop: false
        )

        XCTAssertThrowsError(
            try LibUSBDeviceHandle(
                context: context,
                candidate: makeCandidate(functions: fake.table),
                functions: fake.table
            )
        ) {
            XCTAssertEqual(
                $0 as? MTPCoreError,
                .usb(code: Int32(LIBUSB_ERROR_NOT_FOUND.rawValue))
            )
        }
        context.shutdown()

        XCTAssertEqual(
            fake.events,
            [
                "init", "open", "getConfiguration", "setConfiguration:1",
                "claim:3", "alternate:3:1", "release:3", "close", "exit",
            ]
        )
    }

    func testContextShutdownClosesOpenHandleBeforeExit() throws {
        let fake = FakeLibUSBFunctions()
        let context = try LibUSBContext(
            functions: fake.table,
            startsEventLoop: false
        )
        let handle = try LibUSBDeviceHandle(
            context: context,
            candidate: makeCandidate(functions: fake.table),
            functions: fake.table
        )

        context.shutdown()

        XCTAssertEqual(
            Array(fake.events.suffix(3)),
            ["release:3", "close", "exit"]
        )
        XCTAssertThrowsError(try handle.rawHandleForTransfer()) {
            XCTAssertEqual($0 as? MTPCoreError, .disconnected)
        }
    }

    private func makeCandidate(functions: LibUSBFunctionTable) -> LibUSBDeviceCandidate {
        makeTestLibUSBDeviceCandidate(
            deviceID: try! MTPDeviceID(validating: "swift:1:1:0001:0002"),
            alternateSetting: 1,
            functions: functions
        )
    }
}
