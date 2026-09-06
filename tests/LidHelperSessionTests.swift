import Foundation

/// Exercises the real Swift client against the actual helper script with fake
/// power commands. No display, keyboard, locking, or installed helper is touched.
@main
struct LidHelperSessionTests {
    @MainActor
    static func main() async throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let client = LidHelperSession(directory: directory)
        for _ in 0..<4 {
            try await client.start(id: UUID())
            try client.renew()
            client.stop()
            // Deliberately no delay: the helper still reports the old session.
        }

        let cancelledID = UUID()
        let cancelledStart = Task { try await client.start(id: cancelledID) }
        try await Task.sleep(for: .milliseconds(10))
        client.stop()
        let newID = UUID()
        try await client.start(id: newID)
        do {
            try await cancelledStart.value
            fatalError("Cancelled startup unexpectedly succeeded")
        } catch is CancellationError {
            // Expected: the previous continuation cannot write the new lease.
        }
        try client.renew()
        let lease = try String(contentsOf: directory.appendingPathComponent("request/lease"), encoding: .utf8)
        precondition(lease.hasSuffix(newID.uuidString), "Stale startup replaced the current lease")
        client.stop()
        print("Rapid off/on and cancelled-start regression tests passed")
    }
}
