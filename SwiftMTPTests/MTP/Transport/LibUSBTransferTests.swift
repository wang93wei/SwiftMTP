import CLibUSB
import XCTest
@testable import SwiftMTP

final class LibUSBTransferTests: XCTestCase {
    func testPreCancelledTransferDoesNotAllocateOrSubmit() throws {
        let fake = FakeLibUSBFunctions()
        let context = try LibUSBContext(functions: fake.table, startsEventLoop: false)
        let token = MTPCancellationToken()
        token.cancel()
        let transfer = LibUSBTransfer(
            context: context,
            deviceHandle: OpaquePointer(bitPattern: 0x200)!,
            endpoint: 0x81,
            buffer: .input(capacity: 64),
            timeoutMilliseconds: 1_000,
            functions: fake.table
        )

        XCTAssertThrowsError(try transfer.execute(cancellation: token)) {
            XCTAssertEqual($0 as? MTPCoreError, .cancelled)
        }
        XCTAssertFalse(fake.events.contains("allocateTransfer"))
        XCTAssertFalse(fake.events.contains("submitTransfer"))
        context.shutdown()
    }

    func testReadBufferIsFreedOnlyAfterCompletionCallback() throws {
        let fake = FakeLibUSBFunctions()
        let context = try LibUSBContext(
            functions: fake.table,
            startsEventLoop: false
        )
        let transfer = LibUSBTransfer(
            context: context,
            deviceHandle: OpaquePointer(bitPattern: 0x200)!,
            endpoint: 0x81,
            buffer: .input(capacity: 64),
            timeoutMilliseconds: 1_000,
            functions: fake.table
        )
        let result = UncheckedResultBox<Result<Data, Error>>()
        let completed = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            result.store(Result {
                try transfer.execute(cancellation: MTPCancellationToken())
            })
            completed.signal()
        }

        XCTAssertTrue(fake.waitForEvent("submitTransfer"))
        XCTAssertEqual(completed.wait(timeout: .now() + 0.05), .timedOut)
        XCTAssertFalse(fake.events.contains("freeTransfer"))

        fake.complete(data: Data([1, 2, 3]))

        XCTAssertEqual(completed.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(try result.value?.get(), Data([1, 2, 3]))
        XCTAssertEqual(
            fake.events,
            ["init", "allocateTransfer", "submitTransfer", "freeTransfer"]
        )
        context.shutdown()
    }

    func testCancellationWaitsForTerminalCallbackBeforeReturning() throws {
        let fake = FakeLibUSBFunctions()
        let context = try LibUSBContext(
            functions: fake.table,
            startsEventLoop: false
        )
        let token = MTPCancellationToken()
        let transfer = LibUSBTransfer(
            context: context,
            deviceHandle: OpaquePointer(bitPattern: 0x200)!,
            endpoint: 0x81,
            buffer: .input(capacity: 64),
            timeoutMilliseconds: 1_000,
            functions: fake.table
        )
        let result = UncheckedResultBox<Result<Data, Error>>()
        let completed = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            result.store(Result {
                try transfer.execute(cancellation: token)
            })
            completed.signal()
        }

        XCTAssertTrue(fake.waitForEvent("submitTransfer"))
        token.cancel()
        XCTAssertTrue(fake.waitForEvent("cancelTransfer"))
        XCTAssertEqual(completed.wait(timeout: .now() + 0.05), .timedOut)
        XCTAssertFalse(fake.events.contains("freeTransfer"))

        fake.complete(status: LIBUSB_TRANSFER_CANCELLED)

        XCTAssertEqual(completed.wait(timeout: .now() + 1), .success)
        XCTAssertThrowsError(try result.value?.get()) {
            XCTAssertEqual($0 as? MTPCoreError, .cancelled)
        }
        XCTAssertEqual(fake.events.last, "freeTransfer")
        context.shutdown()
    }

    func testCompletionWinningCancellationRaceReturnsCompletedBytesOnce() throws {
        let fake = FakeLibUSBFunctions()
        let context = try LibUSBContext(functions: fake.table, startsEventLoop: false)
        let token = MTPCancellationToken()
        let transfer = LibUSBTransfer(
            context: context,
            deviceHandle: OpaquePointer(bitPattern: 0x200)!,
            endpoint: 0x81,
            buffer: .input(capacity: 64),
            timeoutMilliseconds: 1_000,
            functions: fake.table
        )
        let result = UncheckedResultBox<Result<Data, Error>>()
        let completed = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            result.store(Result {
                try transfer.execute(cancellation: token)
            })
            completed.signal()
        }

        XCTAssertTrue(fake.waitForEvent("submitTransfer"))
        token.cancel()
        XCTAssertTrue(fake.waitForEvent("cancelTransfer"))
        fake.completeNext(status: LIBUSB_TRANSFER_COMPLETED, data: Data([9]))

        XCTAssertEqual(completed.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(try result.value?.get(), Data([9]))
        XCTAssertEqual(fake.events.filter { $0 == "freeTransfer" }.count, 1)
        context.shutdown()
    }

    func testContextShutdownCancelsAndWaitsBeforeExit() throws {
        let fake = FakeLibUSBFunctions()
        let context = try LibUSBContext(
            functions: fake.table,
            startsEventLoop: false
        )
        let transfer = LibUSBTransfer(
            context: context,
            deviceHandle: OpaquePointer(bitPattern: 0x200)!,
            endpoint: 0x81,
            buffer: .input(capacity: 64),
            timeoutMilliseconds: 1_000,
            functions: fake.table
        )
        let transferFinished = DispatchSemaphore(value: 0)
        let shutdownFinished = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            _ = try? transfer.execute(cancellation: MTPCancellationToken())
            transferFinished.signal()
        }
        XCTAssertTrue(fake.waitForEvent("submitTransfer"))

        DispatchQueue.global().async {
            context.shutdown()
            shutdownFinished.signal()
        }

        XCTAssertTrue(fake.waitForEvent("cancelTransfer"))
        XCTAssertEqual(shutdownFinished.wait(timeout: .now() + 0.05), .timedOut)

        fake.complete(status: LIBUSB_TRANSFER_CANCELLED)

        XCTAssertEqual(transferFinished.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(shutdownFinished.wait(timeout: .now() + 1), .success)
        let events = fake.events
        XCTAssertLessThan(
            try XCTUnwrap(events.firstIndex(of: "freeTransfer")),
            try XCTUnwrap(events.firstIndex(of: "exit"))
        )
    }

    func testShutdownRacingSubmissionCancelsImmediatelyAfterSubmitReturns() throws {
        let fake = FakeLibUSBFunctions()
        fake.blockSubmit = true
        let context = try LibUSBContext(
            functions: fake.table,
            startsEventLoop: false
        )
        let transfer = LibUSBTransfer(
            context: context,
            deviceHandle: OpaquePointer(bitPattern: 0x200)!,
            endpoint: 0x81,
            buffer: .input(capacity: 64),
            timeoutMilliseconds: 1_000,
            functions: fake.table
        )
        let transferFinished = DispatchSemaphore(value: 0)
        let shutdownFinished = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            _ = try? transfer.execute(cancellation: MTPCancellationToken())
            transferFinished.signal()
        }
        XCTAssertTrue(fake.waitForEvent("submitTransfer"))

        DispatchQueue.global().async {
            context.shutdown()
            shutdownFinished.signal()
        }
        XCTAssertEqual(shutdownFinished.wait(timeout: .now() + 0.05), .timedOut)

        fake.allowSubmit.signal()
        XCTAssertTrue(fake.waitForEvent("cancelTransfer"))
        fake.complete(status: LIBUSB_TRANSFER_CANCELLED)

        XCTAssertEqual(transferFinished.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(shutdownFinished.wait(timeout: .now() + 1), .success)
        XCTAssertLessThan(
            try XCTUnwrap(fake.events.firstIndex(of: "freeTransfer")),
            try XCTUnwrap(fake.events.firstIndex(of: "exit"))
        )
    }

    func testSubmitFailureFreesTransferAndDoesNotBlockShutdown() throws {
        let fake = FakeLibUSBFunctions()
        fake.submitCode = Int32(LIBUSB_ERROR_NO_DEVICE.rawValue)
        let context = try LibUSBContext(
            functions: fake.table,
            startsEventLoop: false
        )
        let transfer = LibUSBTransfer(
            context: context,
            deviceHandle: OpaquePointer(bitPattern: 0x200)!,
            endpoint: 0x81,
            buffer: .input(capacity: 64),
            timeoutMilliseconds: 1_000,
            functions: fake.table
        )

        XCTAssertThrowsError(
            try transfer.execute(cancellation: MTPCancellationToken())
        ) {
            XCTAssertEqual($0 as? MTPCoreError, .disconnected)
        }
        context.shutdown()

        XCTAssertEqual(
            fake.events,
            ["init", "allocateTransfer", "submitTransfer", "freeTransfer", "exit"]
        )
    }

    func testHandleCloseCancelsAndWaitsForTerminalCallbackBeforeClosing() throws {
        let fake = FakeLibUSBFunctions()
        let context = try LibUSBContext(
            functions: fake.table,
            startsEventLoop: false
        )
        let handle = try makeTestLibUSBDeviceHandle(context: context, functions: fake.table)
        let transfer = LibUSBTransfer(
            handle: handle,
            endpoint: 0x81,
            buffer: .input(capacity: 64),
            timeoutMilliseconds: 1_000,
            functions: fake.table
        )
        let transferFinished = DispatchSemaphore(value: 0)
        let closeFinished = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            _ = try? transfer.execute(cancellation: MTPCancellationToken())
            transferFinished.signal()
        }
        XCTAssertTrue(fake.waitForEvent("submitTransfer"))
        DispatchQueue.global().async {
            handle.close()
            closeFinished.signal()
        }

        XCTAssertTrue(fake.waitForEvent("cancelTransfer"))
        XCTAssertEqual(closeFinished.wait(timeout: .now() + 0.05), .timedOut)
        XCTAssertFalse(fake.events.contains("close"))
        fake.complete(status: LIBUSB_TRANSFER_CANCELLED)

        XCTAssertEqual(transferFinished.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(closeFinished.wait(timeout: .now() + 1), .success)
        let events = fake.events
        XCTAssertLessThan(
            try XCTUnwrap(events.firstIndex(of: "freeTransfer")),
            try XCTUnwrap(events.firstIndex(of: "release:3"))
        )
        XCTAssertLessThan(
            try XCTUnwrap(events.firstIndex(of: "release:3")),
            try XCTUnwrap(events.firstIndex(of: "close"))
        )
        context.shutdown()
    }

    func testDuplicateTerminalCallbackIsIgnoredBeforeTransferIsFreed() throws {
        let fake = FakeLibUSBFunctions()
        fake.transferBehavior = .immediateDuplicate(
            status: LIBUSB_TRANSFER_COMPLETED,
            data: Data([1, 2, 3])
        )
        let context = try LibUSBContext(functions: fake.table, startsEventLoop: false)
        let transfer = LibUSBTransfer(
            context: context,
            deviceHandle: OpaquePointer(bitPattern: 0x200)!,
            endpoint: 0x81,
            buffer: .input(capacity: 64),
            timeoutMilliseconds: 1_000,
            functions: fake.table
        )

        XCTAssertEqual(
            try transfer.execute(cancellation: MTPCancellationToken()),
            Data([1, 2, 3])
        )
        XCTAssertEqual(fake.events.filter { $0 == "freeTransfer" }.count, 1)
        context.shutdown()
    }

    func testCompletedTransferRemovesItsCancellationCallback() throws {
        let fake = FakeLibUSBFunctions()
        fake.transferBehavior = .immediate(
            status: LIBUSB_TRANSFER_COMPLETED,
            data: Data([1])
        )
        let context = try LibUSBContext(functions: fake.table, startsEventLoop: false)
        let token = MTPCancellationToken()
        let transfer = LibUSBTransfer(
            context: context,
            deviceHandle: OpaquePointer(bitPattern: 0x200)!,
            endpoint: 0x81,
            buffer: .input(capacity: 64),
            timeoutMilliseconds: 1_000,
            functions: fake.table
        )

        XCTAssertEqual(try transfer.execute(cancellation: token), Data([1]))
        XCTAssertEqual(token.registeredCallbackCount, 0)
        context.shutdown()
    }

    func testTimeoutAndNoDeviceTerminalCallbacksMapAfterCallbackOwnershipEnds() throws {
        for (status, expectedError) in [
            (LIBUSB_TRANSFER_TIMED_OUT, MTPCoreError.timeout),
            (LIBUSB_TRANSFER_NO_DEVICE, MTPCoreError.disconnected),
        ] {
            let fake = FakeLibUSBFunctions()
            fake.transferBehavior = .immediate(status: status, data: Data())
            let context = try LibUSBContext(functions: fake.table, startsEventLoop: false)
            let transfer = LibUSBTransfer(
                context: context,
                deviceHandle: OpaquePointer(bitPattern: 0x200)!,
                endpoint: 0x81,
                buffer: .input(capacity: 64),
                timeoutMilliseconds: 1_000,
                functions: fake.table
            )

            XCTAssertThrowsError(
                try transfer.execute(cancellation: MTPCancellationToken())
            ) {
                XCTAssertEqual($0 as? MTPCoreError, expectedError)
            }
            XCTAssertEqual(fake.events.suffix(2), ["submitTransfer", "freeTransfer"])
            context.shutdown()
        }
    }

}
