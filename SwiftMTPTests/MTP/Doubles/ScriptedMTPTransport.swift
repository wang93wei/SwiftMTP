import Foundation
@testable import SwiftMTP

final class ScriptedMTPTransport: MTPTransport {
    struct Step {
        let expectedRequest: Data
        let result: Result<[Data], MTPCoreError>
    }

    private var steps: [Step]

    init(steps: [Step]) {
        self.steps = steps
    }

    func transact(_ request: Data, cancellation: MTPCancellationToken) throws -> [Data] {
        try cancellation.throwIfCancelled()
        guard !steps.isEmpty else {
            throw MTPCoreError.protocolViolation("unexpected scripted transport request")
        }
        let step = steps[0]
        guard step.expectedRequest == request else {
            throw MTPCoreError.protocolViolation("scripted transport request mismatch")
        }
        steps.removeFirst()
        return try step.result.get()
    }

    func verifyConsumed() throws {
        guard steps.isEmpty else {
            throw MTPCoreError.protocolViolation("\(steps.count) scripted transport steps remain")
        }
    }
}
