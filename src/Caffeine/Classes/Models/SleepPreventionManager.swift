import AppKit
import IOKit.pwr_mgt

/// Holds one continuous display-idle assertion for the active Caffeine session.
/// Closed-lid sleep is handled independently by the privileged lease helper.
final class SleepPreventionManager {
    static let shared = SleepPreventionManager()
    private var assertionID: IOPMAssertionID?

    private init() {}

    func preventSleep() {
        guard self.assertionID == nil else { return }
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            String(localized: "Caffeine prevents sleep") as CFString,
            &id
        )
        if result == kIOReturnSuccess {
            self.assertionID = id
        }
    }

    func allowSleep() {
        if let assertionID {
            IOPMAssertionRelease(assertionID)
            self.assertionID = nil
        }
    }
}
