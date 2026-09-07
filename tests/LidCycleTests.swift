import Foundation

@main
struct LidCycleTests {
    static func main() {
        var state = LidCycleState()
        precondition(state.update(closed: false) == nil, "Activation with an open lid must not lock")
        precondition(state.update(closed: true) == .darken, "Closing only darkens the display and keyboard")
        precondition(!state.lockPending, "Closing must leave the session unlocked")
        precondition(state.update(closed: true) == nil, "Duplicate close notifications must be ignored")
        precondition(state.update(closed: false) == .lock, "Opening must request native locking")
        precondition(state.lockPending, "Do not restore brightness before lock confirmation")
        precondition(state.update(closed: false) == nil, "Polling must not repeatedly lock an open lid")
        precondition(state.confirmLock(), "Restore both brightness levels after lock confirmation")
        precondition(!state.lockPending)
        precondition(!state.confirmLock(), "Ignore duplicate confirmations")
        precondition(state.update(closed: false) == nil, "Unlocking must not retrigger a lock")
        precondition(state.update(closed: true) == .darken, "Remain armed for the next cycle")
        precondition(state.update(closed: false) == .lock)
        precondition(state.update(closed: true) == .darken, "Handle closing again while locking is pending")
        precondition(!state.confirmLock(), "Do not light up a lid that was closed again")
        precondition(state.update(closed: false) == .lock)
        precondition(state.confirmLock())
        var initiallyClosed = LidCycleState()
        precondition(initiallyClosed.update(closed: true) == .darken, "Starting closed must not lock")
        precondition(!initiallyClosed.lockPending)
        precondition(initiallyClosed.update(closed: false) == .lock)
        print("20 lid transition assertions passed")
    }
}
