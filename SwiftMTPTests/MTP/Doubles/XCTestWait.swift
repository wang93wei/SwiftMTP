import XCTest

@MainActor
func waitUntil(
    timeout: Duration = .seconds(2),
    condition: @escaping @MainActor () -> Bool
) async {
    let deadline = ContinuousClock().now.advanced(by: timeout)
    while !condition(), ContinuousClock().now < deadline {
        await Task.yield()
    }
    XCTAssertTrue(condition())
}
