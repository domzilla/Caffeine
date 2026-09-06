import Foundation

/// All mutable state and lease writes are serialized on this queue. Renewal
/// must not wait for AppKit, brightness calls, or the main actor to respond.
final class LidLeaseHeartbeat: @unchecked Sendable {
    private let queue = DispatchQueue(label: "net.ziyad.caffeine.lid-heartbeat", qos: .utility)
    private let leaseURL: URL
    private var timer: DispatchSourceTimer?
    private var failure: Error?

    init(leaseURL: URL) {
        self.leaseURL = leaseURL
    }

    func start(value: String) throws {
        try self.queue.sync {
            self.timer?.cancel()
            self.timer = nil
            self.failure = nil
            try value.write(to: self.leaseURL, atomically: true, encoding: .utf8)
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(100))
            timer.setEventHandler { [weak self, weak timer] in
                guard let self, let timer, self.timer === timer else { return }
                do {
                    try value.write(to: self.leaseURL, atomically: true, encoding: .utf8)
                } catch {
                    self.failure = error
                    timer.cancel()
                    self.timer = nil
                }
            }
            self.timer = timer
            timer.resume()
        }
    }

    func checkHealth() throws {
        try self.queue.sync {
            if let failure = self.failure {
                throw failure
            }
        }
    }

    func stop() {
        // Drain any in-flight write before the caller removes the lease. A
        // queued event must never recreate a stopped or newer session's lease.
        self.queue.sync {
            self.timer?.cancel()
            self.timer = nil
            self.failure = nil
        }
    }

    deinit {
        self.timer?.cancel()
    }
}
