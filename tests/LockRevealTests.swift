import Foundation

@main
struct LockRevealTests {
    static func main() {
        var gate = LockRevealGate()
        precondition(!gate.canReveal(locked: false, lidClosed: false, now: 0))
        precondition(
            !gate.canReveal(locked: true, lidClosed: false, now: 1),
            "First logical lock flag cannot expose the panel"
        )
        precondition(!gate.canReveal(locked: true, lidClosed: false, now: 1.7), "Wait through lock-screen presentation")
        precondition(gate.canReveal(locked: true, lidClosed: false, now: 1.75))

        var flicker = LockRevealGate()
        precondition(!flicker.canReveal(locked: true, lidClosed: false, now: 0))
        precondition(
            !flicker.canReveal(locked: nil, lidClosed: false, now: 0.6),
            "Unknown lock status invalidates confirmation"
        )
        precondition(!flicker.canReveal(locked: true, lidClosed: false, now: 1))
        precondition(!flicker.canReveal(locked: true, lidClosed: false, now: 1.7))
        precondition(flicker.canReveal(locked: true, lidClosed: false, now: 1.75))

        var reopened = LockRevealGate()
        precondition(!reopened.canReveal(locked: true, lidClosed: false, now: 0))
        precondition(!reopened.canReveal(locked: true, lidClosed: true, now: 1), "Never illuminate a reclosed lid")
        precondition(!reopened.canReveal(locked: true, lidClosed: false, now: 2), "Reopening restarts confirmation")
        precondition(
            !reopened.canReveal(locked: false, lidClosed: false, now: 3),
            "Unlock cannot satisfy the reveal gate"
        )

        var failed = LockRevealGate()
        for time in [0.0, 1, 10, 100] {
            precondition(
                !failed.canReveal(locked: false, lidClosed: false, now: time),
                "Timeout cannot reveal an unlocked desktop"
            )
        }
        print("Lock reveal timing and failure regression tests passed")
    }
}
