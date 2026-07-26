import Foundation

nonisolated struct MTPDeviceID: RawRepresentable, Hashable, Sendable {
    let rawValue: String

    init(validating rawValue: String) throws {
        guard !rawValue.isEmpty else {
            throw MTPCoreError.invalidInput("device ID must not be empty")
        }
        self.rawValue = rawValue
    }

    init(rawValue: String) {
        precondition(!rawValue.isEmpty, "MTP device ID must not be empty")
        self.rawValue = rawValue
    }
}

nonisolated struct MTPStorageID: RawRepresentable, Hashable, Sendable {
    let rawValue: UInt32

    init(validating rawValue: UInt32) throws {
        guard rawValue != 0 else {
            throw MTPCoreError.invalidIdentifier(kind: .storage, value: rawValue)
        }
        self.rawValue = rawValue
    }

    init(rawValue: UInt32) {
        precondition(rawValue != 0, "MTP storage ID must be non-zero")
        self.rawValue = rawValue
    }
}

nonisolated struct MTPObjectID: RawRepresentable, Hashable, Sendable {
    static let root = Self(rawValue: 0xFFFF_FFFF)

    let rawValue: UInt32

    init(validating rawValue: UInt32) throws {
        guard rawValue != 0 else {
            throw MTPCoreError.invalidIdentifier(kind: .object, value: rawValue)
        }
        self.rawValue = rawValue
    }

    init(rawValue: UInt32) {
        precondition(rawValue != 0, "MTP object ID must be non-zero")
        self.rawValue = rawValue
    }
}

nonisolated struct MTPSessionID: RawRepresentable, Hashable, Sendable {
    let rawValue: UInt32

    init(validating rawValue: UInt32) throws {
        guard rawValue != 0, rawValue != 0xFFFF_FFFF else {
            throw MTPCoreError.invalidIdentifier(kind: .session, value: rawValue)
        }
        self.rawValue = rawValue
    }

    init(rawValue: UInt32) {
        precondition(
            rawValue != 0 && rawValue != 0xFFFF_FFFF,
            "MTP session ID must exclude zero and 0xFFFFFFFF"
        )
        self.rawValue = rawValue
    }
}

nonisolated struct MTPTransactionID: RawRepresentable, Hashable, Sendable {
    let rawValue: UInt32

    init(validating rawValue: UInt32) throws {
        self.rawValue = rawValue
    }

    init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
}
