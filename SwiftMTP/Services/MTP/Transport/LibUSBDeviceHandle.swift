import Foundation

nonisolated final class LibUSBDeviceCandidate {
    let rawDevice: OpaquePointer
    let interface: MTPUSBInterface

    private let functions: LibUSBFunctionTable
    private let ownsReference: Bool

    init(
        rawDevice: OpaquePointer,
        interface: MTPUSBInterface,
        functions: LibUSBFunctionTable,
        ownsReference: Bool
    ) {
        self.rawDevice = rawDevice
        self.interface = interface
        self.functions = functions
        self.ownsReference = ownsReference
    }

    deinit {
        if ownsReference {
            functions.unrefDevice(rawDevice)
        }
    }
}

nonisolated final class LibUSBDeviceHandle {
    let context: LibUSBContext
    let interface: MTPUSBInterface

    private let functions: LibUSBFunctionTable
    private let condition = NSCondition()
    private var handle: OpaquePointer?
    private var claimed = false
    private var closing = false
    private var activeTransfers: [ObjectIdentifier: LibUSBTransfer] = [:]

    init(
        context: LibUSBContext,
        candidate: LibUSBDeviceCandidate,
        functions: LibUSBFunctionTable = LibUSBFunctionTable()
    ) throws {
        self.context = context
        self.interface = candidate.interface
        self.functions = functions
        try context.beginHandleCreation()
        var creationCompleted = false
        defer {
            if !creationCompleted {
                context.cancelHandleCreation()
            }
        }

        var handle: OpaquePointer?
        let openResult = functions.open(candidate.rawDevice, &handle)
        guard openResult == 0, let handle else {
            throw mtpErrorFromLibUSB(openResult)
        }
        self.handle = handle

        do {
            var currentConfiguration: Int32 = 0
            let getConfigurationResult = functions.getConfiguration(
                handle,
                &currentConfiguration
            )
            guard getConfigurationResult == 0 else {
                throw mtpErrorFromLibUSB(getConfigurationResult)
            }
            let targetConfiguration = Int32(interface.configurationValue)
            if currentConfiguration != targetConfiguration {
                let setResult = functions.setConfiguration(handle, targetConfiguration)
                guard setResult == 0 else {
                    throw mtpErrorFromLibUSB(setResult)
                }
            }

            let interfaceNumber = Int32(interface.interfaceNumber)
            let claimResult = functions.claimInterface(handle, interfaceNumber)
            guard claimResult == 0 else {
                throw mtpErrorFromLibUSB(claimResult)
            }
            claimed = true

            if interface.alternateSetting != 0 {
                let alternateResult = functions.setInterfaceAltSetting(
                    handle,
                    interfaceNumber,
                    Int32(interface.alternateSetting)
                )
                guard alternateResult == 0 else {
                    throw mtpErrorFromLibUSB(alternateResult)
                }
            }
            creationCompleted = true
            context.completeHandleCreation(self)
        } catch {
            close()
            throw error
        }
    }

    deinit {
        close()
    }

    func close() {
        let transfers: [LibUSBTransfer] = condition.withLock {
            guard handle != nil, !closing else {
                return []
            }
            closing = true
            return Array(activeTransfers.values)
        }
        transfers.forEach { $0.requestCancellationFromHandle() }

        condition.lock()
        while !activeTransfers.isEmpty {
            condition.wait()
        }
        guard let handle else {
            condition.unlock()
            return
        }
        if claimed {
            _ = functions.releaseInterface(handle, Int32(interface.interfaceNumber))
            claimed = false
        }
        functions.close(handle)
        self.handle = nil
        condition.broadcast()
        condition.unlock()
        context.unregister(self)
    }

    func rawHandleForTransfer() throws -> OpaquePointer {
        try condition.withLock {
            guard !closing, let handle else {
                throw MTPCoreError.disconnected
            }
            return handle
        }
    }

    func lease(_ transfer: LibUSBTransfer) throws -> OpaquePointer {
        try condition.withLock {
            guard !closing, let handle else {
                throw MTPCoreError.disconnected
            }
            activeTransfers[ObjectIdentifier(transfer)] = transfer
            return handle
        }
    }

    func release(_ transfer: LibUSBTransfer) {
        condition.withLock {
            activeTransfers.removeValue(forKey: ObjectIdentifier(transfer))
            condition.broadcast()
        }
    }
}
