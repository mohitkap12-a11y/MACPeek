import XCTest
@testable import MacPeekCore

final class ShellCommandTests: XCTestCase {
    func testCapturesOutputAndStatus() async throws {
        let out = try await ShellCommand().run("/bin/echo", ["hello"])
        XCTAssertEqual(out.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "hello")
        XCTAssertEqual(out.status, 0)
    }

    func testHungCommandIsTerminatedAtDeadline() async {
        let started = Date()
        do {
            _ = try await ShellCommand(timeout: 0.5).run("/bin/sleep", ["30"])
            XCTFail("expected timeout")
        } catch {
            XCTAssertEqual(error as? CommandError, .timedOut("sleep"))
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 10, "must not wait for the child to finish")
    }

    func testCancellationTerminatesChild() async {
        let task = Task { try await ShellCommand(timeout: 60).run("/bin/sleep", ["30"]) }
        try? await Task.sleep(nanoseconds: 300_000_000)
        let started = Date()
        task.cancel()
        let result = await task.result
        if case .success = result { XCTFail("expected cancellation error") }
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
    }
}
