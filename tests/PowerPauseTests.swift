import AppKit
import Combine

/// Compile the real view model and power policy with inert hardware adapters.
/// No installed preferences, power settings, screen locking, or UI are changed.
@MainActor
final class AutomaticLidManager {
    var didFail: (() -> Void)?
    var errorMessage: String?
    var isEngaged = false
    var isLidClosed = false
    var starts = 0
    var keptPrivacy = false
    func start() async {
        self.isEngaged = true
        self.starts += 1
    }

    func stop(preservingLidPrivacy: Bool = false) {
        self.isEngaged = false
        self.keptPrivacy = preservingLidPrivacy
    }
}

@MainActor
final class SleepPreventionManager {
    static let shared = SleepPreventionManager()
    var held = false
    func preventSleep() {
        self.held = true
    }

    func allowSleep() {
        self.held = false
    }
}

@MainActor
final class ActivitySimulator {
    static let shared = ActivitySimulator()
    var running = false
    func requestPermission() {}
    func startMonitoring() {
        self.running = true
    }

    func stopMonitoring() {
        self.running = false
    }
}

extension PowerSnapshot {
    static func current() -> Self {
        Self(onExternalPower: true, batteryFraction: 1, isTooHot: false)
    }
}

@MainActor
final class PowerSourceMonitor {
    init(changed _: @escaping () -> Void) {}
    func start() {}
    func stop() {}
}

@main
struct PowerPauseTests {
    @MainActor
    static func settle() async throws {
        try await Task.sleep(for: .milliseconds(30))
    }

    @MainActor
    static func main() async throws {
        UserDefaults.standard.setVolatileDomain([
            PreferenceKeys.activateAtLaunch: false,
            PreferenceKeys.suppressLaunchMessage: true,
            PreferenceKeys.keepAppsActive: true,
            PreferenceKeys.automaticLidControl: true,
            PreferenceKeys.deactivateOnManualSleep: true,
        ], forName: UserDefaults.argumentDomain)
        var power = PowerSnapshot(onExternalPower: false, batteryFraction: 0.11, isTooHot: false)
        let model = CaffeineViewModel(readPower: { power })
        model.activate(withTimeout: 60)
        try await self.settle()
        precondition(model.isActive && !model.isPaused && model.automaticLid.isEngaged)
        precondition(SleepPreventionManager.shared.held && ActivitySimulator.shared.running)
        let remaining = model.timeRemaining

        power.batteryFraction = 0.10
        model.refreshPowerState()
        precondition(model.isActive && model.pauseReason == .lowBattery && !model.showPreferences)
        precondition(!SleepPreventionManager.shared.held && !ActivitySimulator.shared.running)
        precondition(!model.automaticLid.isEngaged && model.automaticLid.keptPrivacy)
        precondition(model.timeRemaining == remaining)
        precondition(model.formattedTimeRemaining() == PowerPauseReason.lowBattery.message)
        model.updateActivitySimulation(enabled: true)
        precondition(!ActivitySimulator.shared.running)

        power.batteryFraction = 0.12
        model.refreshPowerState()
        precondition(model.pauseReason == .lowBattery, "Must wait for the charger, not a fluctuating percentage")
        power.onExternalPower = nil
        model.refreshPowerState()
        precondition(model.pauseReason == .lowBattery, "Unknown power source must not resume")
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        try await self.settle()
        precondition(model.isActive && model.isPaused, "Pause must survive ordinary system sleep")

        power.onExternalPower = true
        power.batteryFraction = 0.04
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await self.settle()
        precondition(model.isActive && !model.isPaused && model.automaticLid.isEngaged)
        precondition(model.timeRemaining == remaining, "Resume must not reset the duration")
        precondition(!model.showPreferences)

        power.onExternalPower = false
        power.isTooHot = true
        model.refreshPowerState()
        precondition(model.pauseReason == .overheating && !model.showPreferences)
        power.isTooHot = false
        model.refreshPowerState()
        precondition(model.pauseReason == .lowBattery, "Cooling must retain the wait for AC")
        power.isTooHot = true
        power.onExternalPower = true
        model.refreshPowerState()
        precondition(model.pauseReason == .overheating, "AC must not bypass thermal protection")
        power.isTooHot = false
        model.refreshPowerState()
        try await self.settle()
        precondition(!model.isPaused && model.automaticLid.isEngaged)

        power.onExternalPower = false
        model.refreshPowerState()
        model.deactivate()
        power.onExternalPower = true
        model.refreshPowerState()
        try await self.settle()
        precondition(!model.isActive && !model.automaticLid.isEngaged)
        precondition(!SleepPreventionManager.shared.held, "Manual off must cancel automatic resume")

        power.onExternalPower = false
        model.activate(withTimeout: 0.02)
        precondition(model.isPaused && !model.automaticLid.isEngaged, "Low-battery activation must begin paused")
        try await self.settle()
        power.onExternalPower = true
        model.refreshPowerState()
        precondition(!model.isActive && !model.automaticLid.isEngaged, "Expired deadline must never resume")
        precondition(!model.showPreferences)

        // A queued activation must not win a race with the low-battery pause.
        model.activate(withTimeout: 0)
        power.onExternalPower = false
        model.refreshPowerState()
        try await self.settle()
        precondition(model.isPaused && !model.automaticLid.isEngaged)
        model.deactivate()
        print("Power pause, charger resume, exact reasons, privacy retention, timer and cancellation tests passed")
    }
}
