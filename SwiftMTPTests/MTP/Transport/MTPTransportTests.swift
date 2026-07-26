import XCTest
@testable import SwiftMTP

final class MTPTransportTests: XCTestCase {
    func testScriptMatchesExactRequestAndReturnsFragments() throws {
        let request = Data([0x01, 0x02])
        let transport = ScriptedMTPTransport(
            steps: [
                .init(
                    expectedRequest: request,
                    result: .success([Data([0x0C, 0x00]), Data([0x00, 0x00])])
                ),
            ]
        )

        XCTAssertEqual(
            try transport.transact(request, cancellation: MTPCancellationToken()),
            [Data([0x0C, 0x00]), Data([0x00, 0x00])]
        )
        XCTAssertNoThrow(try transport.verifyConsumed())
    }

    func testScriptPropagatesUSBTimeoutAndMTPResponseErrors() {
        for error in [
            MTPCoreError.usb(code: -4),
            .timeout,
            .response(code: .init(rawValue: 0x2005)),
        ] {
            let transport = ScriptedMTPTransport(
                steps: [.init(expectedRequest: Data([0x01]), result: .failure(error))]
            )
            XCTAssertThrowsError(
                try transport.transact(Data([0x01]), cancellation: MTPCancellationToken())
            ) { XCTAssertEqual($0 as? MTPCoreError, error) }
        }
    }

    func testCancellationIsIdempotentAndPreventsTransaction() {
        let token = MTPCancellationToken()
        var callbackCount = 0
        token.onCancel { callbackCount += 1 }
        token.cancel()
        token.cancel()

        let transport = ScriptedMTPTransport(
            steps: [.init(expectedRequest: Data([0x01]), result: .success([]))]
        )
        XCTAssertEqual(callbackCount, 1)
        XCTAssertThrowsError(try transport.transact(Data([0x01]), cancellation: token)) {
            XCTAssertEqual($0 as? MTPCoreError, .cancelled)
        }
        XCTAssertThrowsError(try transport.verifyConsumed())
    }

    func testUnconsumedAndMismatchedStepsFail() {
        let transport = ScriptedMTPTransport(
            steps: [.init(expectedRequest: Data([0x01]), result: .success([]))]
        )
        XCTAssertThrowsError(try transport.transact(
            Data([0x02]),
            cancellation: MTPCancellationToken()
        ))
        XCTAssertThrowsError(try transport.verifyConsumed())

        XCTAssertNoThrow(try transport.transact(
            Data([0x01]),
            cancellation: MTPCancellationToken()
        ))
        XCTAssertNoThrow(try transport.verifyConsumed())
    }
}
