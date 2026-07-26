import Foundation
import OSLog

nonisolated enum MTPLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "SwiftMTP"

    static let core = Logger(subsystem: subsystem, category: "mtp.core")
    static let usb = Logger(subsystem: subsystem, category: "mtp.usb")
    static let session = Logger(subsystem: subsystem, category: "mtp.session")
    static let fileSystem = Logger(subsystem: subsystem, category: "mtp.filesystem")
    static let transfer = Logger(subsystem: subsystem, category: "mtp.transfer")
}
