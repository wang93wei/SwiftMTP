import CLibUSB
import Foundation
@testable import SwiftMTP

final class FakeLibUSBFunctions: @unchecked Sendable {
    enum TransferBehavior {
        case deferred
        case immediate(status: libusb_transfer_status, data: Data)
        case immediateDuplicate(status: libusb_transfer_status, data: Data)
    }

    private let lock = NSLock()
    private let contextPointer = OpaquePointer(bitPattern: 0x100)!
    private let handlePointer = OpaquePointer(bitPattern: 0x200)!
    private var pendingTransfers: [UnsafeMutablePointer<libusb_transfer>] = []
    private var maximumPendingCount = 0

    var events: [String] {
        lock.withLock { recordedEvents }
    }

    var maximumPendingTransferCount: Int {
        lock.withLock { maximumPendingCount }
    }

    var submittedTransferFlags: [UInt8] {
        lock.withLock { recordedTransferFlags }
    }

    var currentConfiguration: Int32 = 0
    var setConfigurationCode: Int32 = 0
    var claimCode: Int32 = 0
    var alternateSettingCode: Int32 = 0
    var submitCode: Int32 = 0
    var cancelCode: Int32 = 0
    var blockSubmit = false
    let allowSubmit = DispatchSemaphore(value: 0)
    var transferBehavior = TransferBehavior.deferred
    var scriptedTransferBehaviors: [TransferBehavior] = []
    private var recordedEvents: [String] = []
    private var recordedTransferFlags: [UInt8] = []

    var table: LibUSBFunctionTable {
        LibUSBFunctionTable(
            initialize: { [weak self] context in
                guard let self else { return Int32(LIBUSB_ERROR_OTHER.rawValue) }
                self.record("init")
                context.pointee = self.contextPointer
                return 0
            },
            exit: { [weak self] _ in
                self?.record("exit")
            },
            open: { [weak self] _, handle in
                guard let self else { return Int32(LIBUSB_ERROR_OTHER.rawValue) }
                self.record("open")
                handle.pointee = self.handlePointer
                return 0
            },
            close: { [weak self] _ in
                self?.record("close")
            },
            getConfiguration: { [weak self] _, configuration in
                guard let self else { return Int32(LIBUSB_ERROR_OTHER.rawValue) }
                self.record("getConfiguration")
                configuration.pointee = self.currentConfiguration
                return 0
            },
            setConfiguration: { [weak self] _, value in
                guard let self else { return Int32(LIBUSB_ERROR_OTHER.rawValue) }
                self.record("setConfiguration:\(value)")
                return self.setConfigurationCode
            },
            claimInterface: { [weak self] _, number in
                guard let self else { return Int32(LIBUSB_ERROR_OTHER.rawValue) }
                self.record("claim:\(number)")
                return self.claimCode
            },
            setInterfaceAltSetting: { [weak self] _, number, alternate in
                guard let self else { return Int32(LIBUSB_ERROR_OTHER.rawValue) }
                self.record("alternate:\(number):\(alternate)")
                return self.alternateSettingCode
            },
            releaseInterface: { [weak self] _, number in
                self?.record("release:\(number)")
                return 0
            },
            allocateTransfer: { [weak self] _ in
                self?.record("allocateTransfer")
                let pointer = UnsafeMutablePointer<libusb_transfer>.allocate(capacity: 1)
                pointer.initialize(to: libusb_transfer())
                return pointer
            },
            submitTransfer: { [weak self] transfer in
                guard let self, let transfer else {
                    return Int32(LIBUSB_ERROR_OTHER.rawValue)
                }
                self.record("submitTransfer")
                self.lock.withLock {
                    self.recordedTransferFlags.append(transfer.pointee.flags)
                }
                if self.blockSubmit {
                    self.allowSubmit.wait()
                }
                if self.submitCode != 0 {
                    return self.submitCode
                }
                let behavior = self.lock.withLock {
                    if self.scriptedTransferBehaviors.isEmpty {
                        return self.transferBehavior
                    }
                    return self.scriptedTransferBehaviors.removeFirst()
                }
                switch behavior {
                case .deferred:
                    self.lock.withLock {
                        self.pendingTransfers.append(transfer)
                        self.maximumPendingCount = max(
                            self.maximumPendingCount,
                            self.pendingTransfers.count
                        )
                    }
                case .immediate(let status, let data):
                    self.populate(transfer, status: status, data: data)
                    transfer.pointee.callback?(transfer)
                case .immediateDuplicate(let status, let data):
                    self.populate(transfer, status: status, data: data)
                    transfer.pointee.callback?(transfer)
                    transfer.pointee.callback?(transfer)
                }
                return 0
            },
            cancelTransfer: { [weak self] transfer in
                guard let self else { return Int32(LIBUSB_ERROR_OTHER.rawValue) }
                self.record("cancelTransfer")
                if self.cancelCode == 0, let transfer {
                    self.lock.withLock {
                        if !self.pendingTransfers.contains(where: { $0 == transfer }) {
                            self.pendingTransfers.append(transfer)
                            self.maximumPendingCount = max(
                                self.maximumPendingCount,
                                self.pendingTransfers.count
                            )
                        }
                    }
                }
                return self.cancelCode
            },
            freeTransfer: { [weak self] transfer in
                self?.record("freeTransfer")
                transfer?.deinitialize(count: 1)
                transfer?.deallocate()
            },
            handleEventsTimeoutCompleted: { _, _, _ in 0 }
        )
    }

    func completeNext(
        status: libusb_transfer_status = LIBUSB_TRANSFER_COMPLETED,
        data: Data = Data()
    ) {
        let transfer: UnsafeMutablePointer<libusb_transfer>? = lock.withLock {
            guard !pendingTransfers.isEmpty else {
                return nil
            }
            return pendingTransfers.removeFirst()
        }
        guard let transfer else {
            return
        }
        populate(transfer, status: status, data: data)
        transfer.pointee.callback?(transfer)
    }

    func complete(
        status: libusb_transfer_status = LIBUSB_TRANSFER_COMPLETED,
        data: Data = Data()
    ) {
        completeNext(status: status, data: data)
    }

    func waitForPendingTransferCount(
        _ count: Int,
        timeout: TimeInterval = 1
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if lock.withLock({ pendingTransfers.count == count }) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.005)
        }
        return lock.withLock { pendingTransfers.count == count }
    }

    func waitForEvent(_ event: String, timeout: TimeInterval = 1) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if events.contains(event) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.005)
        }
        return events.contains(event)
    }

    private func populate(
        _ transfer: UnsafeMutablePointer<libusb_transfer>,
        status: libusb_transfer_status,
        data: Data
    ) {
        transfer.pointee.status = status
        let isCompletedOutput = status == LIBUSB_TRANSFER_COMPLETED
            && transfer.pointee.endpoint & 0x80 == 0
        let copyCount = isCompletedOutput && data.isEmpty
            ? Int(transfer.pointee.length)
            : min(Int(transfer.pointee.length), data.count)
        if copyCount > 0, let buffer = transfer.pointee.buffer {
            if !data.isEmpty {
                data.copyBytes(to: buffer, count: copyCount)
            }
        }
        transfer.pointee.actual_length = Int32(copyCount)
    }

    private func record(_ event: String) {
        lock.withLock {
            recordedEvents.append(event)
        }
    }
}

final class UncheckedResultBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value?

    var value: Value? {
        lock.withLock { storage }
    }

    func store(_ value: Value) {
        lock.withLock {
            storage = value
        }
    }
}
