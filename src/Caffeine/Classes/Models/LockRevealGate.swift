import Foundation

/// A logical lock flag may precede presentation of the secure screen.
/// Keep the cover until confirmation remains stable through a settling period.
struct LockRevealGate {
    private var lockedSince: TimeInterval?
    private let settlingTime: TimeInterval = 0.75

    mutating func canReveal(locked: Bool?, lidClosed: Bool, now: TimeInterval) -> Bool {
        guard locked == true, !lidClosed else { self.lockedSince = nil
            return false
        }
        guard let since = self.lockedSince else { self.lockedSince = now
            return false
        }
        return now - since >= self.settlingTime
    }
}
