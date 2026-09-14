/// Pure transition policy, independently tested without changing real hardware.
struct LidCycleState {
    enum Action: Equatable { case darken, lock }
    private(set) var closed = false
    private(set) var lockPending = false

    mutating func update(closed: Bool) -> Action? {
        guard self.closed != closed else { return nil }
        self.closed = closed
        if closed {
            return .darken
        }
        self.lockPending = true
        return .lock
    }

    /// Brightness may return only after native lock confirmation, with lid open.
    mutating func confirmLock() -> Bool {
        guard self.lockPending else { return false }
        self.lockPending = false
        return !self.closed
    }
}
