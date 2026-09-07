import Foundation

/// Serializes each client handshake with the helper's asynchronous cleanup.
@MainActor
final class LidHelperSession {
    private let directory: URL
    private let heartbeat: LidLeaseHeartbeat
    private var activity: NSObjectProtocol?
    private var sessionID: UUID?
    private var leaseURL: URL {
        self.directory.appendingPathComponent("request/lease")
    }

    init(directory: URL = URL(fileURLWithPath: "/Library/Application Support/CaffeineLid", isDirectory: true)) {
        self.directory = directory
        self.heartbeat = LidLeaseHeartbeat(leaseURL: directory.appendingPathComponent("request/lease"))
    }

    func start(id: UUID, isInstalled: () -> Bool = { true }) async throws {
        guard self.sessionID == nil else { throw SessionError.unavailable }
        self.sessionID = id
        self.activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Maintain Caffeine lid-control lease"
        )
        do {
            // Off/on can happen within the helper's one-second polling interval.
            // Leave the old request removed until the helper has restored power.
            try await self.wait(id: id) {
                guard isInstalled(), let status = self.status else { return false }
                return status == "idle" || status.hasPrefix("failed:") || status.hasPrefix("conflict:")
            }
            try self.writeRequest(active: false, id: id)
            try await self.wait(id: id) { self.status == "ready:\(id.uuidString)" }
            try self.writeRequest(active: true, id: id)
            try await self.wait(id: id) { self.status == "active:\(id.uuidString)" }
            try self.heartbeat.start(value: self.request(active: true, id: id))
        } catch {
            if self.sessionID == id {
                self.stop()
            }
            throw error
        }
    }

    func checkHealth() throws {
        try self.heartbeat.checkHealth()
        guard let id = self.sessionID, self.status == "active:\(id.uuidString)" else { throw SessionError.unavailable }
    }

    func stop() {
        let oldID = self.sessionID
        self.sessionID = nil
        self.heartbeat.stop()
        if let activity = self.activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
        if
            let oldID, let value = try? String(contentsOf: self.leaseURL, encoding: .utf8),
            value.hasSuffix(":" + oldID.uuidString)
        {
            try? FileManager.default.removeItem(at: self.leaseURL)
        }
    }

    private var status: String? {
        try? String(contentsOf: self.directory.appendingPathComponent("status"), encoding: .utf8)
    }

    private func writeRequest(active: Bool, id: UUID) throws {
        guard self.sessionID == id, !Task.isCancelled else { throw CancellationError() }
        try self.request(active: active, id: id).write(to: self.leaseURL, atomically: true, encoding: .utf8)
    }

    private func request(active: Bool, id: UUID) -> String {
        // Keep the installed version-1 helper's historical activation opcode.
        "\(active ? "locked" : "pending"):\(ProcessInfo.processInfo.processIdentifier):\(id.uuidString)"
    }

    private func wait(id: UUID, until ready: () -> Bool) async throws {
        for _ in 0..<120 {
            guard self.sessionID == id, !Task.isCancelled else { throw CancellationError() }
            if ready() {
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw SessionError.unavailable
    }

    private enum SessionError: Error { case unavailable }
}
