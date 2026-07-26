import Foundation
@testable import SwiftMTP

/// Reusable backend contract inputs for provider-specific suites added by later tasks.
struct MTPBackendContract {
    let makeBackend: () -> any MTPBackend
    let deviceID: MTPDeviceID
}
