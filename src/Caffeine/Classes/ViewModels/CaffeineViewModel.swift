//
//  CaffeineViewModel.swift
//  Caffeine
//
//  Created by Dominic Rodemer on 11.11.25.
//

import ApplicationServices
import Combine
import SwiftUI

/// Main view model for the Caffeine application
@MainActor
class CaffeineViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var isActive = false
    @Published var timeRemaining: TimeInterval?
    @Published var showPreferences = false
    let automaticLid = AutomaticLidManager()
    @Published private(set) var pauseReason: PowerPauseReason?
    var isPaused: Bool {
        self.pauseReason != nil
    }

    // MARK: - Private Properties

    private let readPower: () -> PowerSnapshot
    private var powerPolicy = PowerPauseState()
    private var powerMonitor: Task<Void, Never>?
    private lazy var powerSourceMonitor = PowerSourceMonitor { [weak self] in self?.refreshPowerState() }
    private var timeoutTimer: Timer?
    private var displayTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(readPower: @escaping () -> PowerSnapshot = { PowerSnapshot.current() }) {
        self.readPower = readPower
        // Explicitly ensure we start inactive
        self.isActive = false
        self.timeRemaining = nil

        UserDefaults.standard.register(defaults: [PreferenceKeys.automaticLidControl: true])
        self.setupObservers()
        self.automaticLid.didFail = { [weak self] in
            self?.deactivate()
            self?.showPreferences = true
        }

        // Check if we should activate at launch
        if UserDefaults.standard.bool(forKey: PreferenceKeys.activateAtLaunch) {
            self.activate()
        }

        // Show preferences on first launch
        if !UserDefaults.standard.bool(forKey: PreferenceKeys.suppressLaunchMessage) {
            self.showPreferences = true
        }
    }

    // MARK: - Public Methods

    /// Toggles the active state
    func toggleActive() {
        if self.isActive {
            self.deactivate()
        } else {
            self.activate()
        }
    }

    /// Activates Caffeine with optional timeout
    func activate(withTimeout timeout: TimeInterval? = nil) {
        // Use default duration if no timeout specified
        let duration: TimeInterval?
        if let timeout {
            duration = timeout > 0 ? timeout : nil
        } else {
            let defaultMinutes = UserDefaults.standard.integer(forKey: PreferenceKeys.defaultDuration)
            duration = defaultMinutes > 0 ? TimeInterval(defaultMinutes * 60) : nil
        }

        // Cancel existing timers
        self.cancelTimers()

        // Set up timeout timer if duration specified
        if let duration {
            self.timeRemaining = duration

            self.timeoutTimer = Timer.scheduledTimer(
                withTimeInterval: duration,
                repeats: false
            ) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.deactivate()
                }
            }

            // Update display every second
            self.displayTimer = Timer.scheduledTimer(
                withTimeInterval: 1.0,
                repeats: true
            ) { [weak self] _ in
                DispatchQueue.main.async {
                    guard
                        let self,
                        let timeoutTimer = self.timeoutTimer else
                    {
                        self?.displayTimer?.invalidate()
                        return
                    }

                    self.timeRemaining = max(0, timeoutTimer.fireDate.timeIntervalSinceNow)
                    if self.timeRemaining ?? 0 <= 0 {
                        self.displayTimer?.invalidate()
                        self.displayTimer = nil
                    }
                }
            }
        } else {
            self.timeRemaining = nil
        }

        self.isActive = true
        self.refreshPowerState(force: true)
        guard self.isActive else { return }
        self.powerSourceMonitor.start()
        if self.powerMonitor == nil {
            self.powerMonitor = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(2)) } catch { return }
                    guard let self, self.isActive else { return }
                    self.refreshPowerState()
                }
            }
        }
    }

    func refreshPowerState(force: Bool = false) {
        guard self.isActive else { return }
        // A paused session keeps its original deadline, including across sleep.
        if let timer = self.timeoutTimer, timer.fireDate <= Date() {
            self.deactivate()
            return
        }
        let reason = self.powerPolicy.update(self.readPower())
        guard force || reason != self.pauseReason else { return }
        self.pauseReason = reason
        self.applyActivationState()
    }

    private func applyActivationState() {
        guard self.isActive else { return }
        if self.isPaused {
            self.automaticLid.stop(preservingLidPrivacy: true)
            SleepPreventionManager.shared.allowSleep()
            ActivitySimulator.shared.stopMonitoring()
            return
        }
        SleepPreventionManager.shared.preventSleep()
        self.updateActivitySimulation(enabled: UserDefaults.standard.bool(forKey: PreferenceKeys.keepAppsActive))
        if UserDefaults.standard.bool(forKey: PreferenceKeys.automaticLidControl), !self.automaticLid.isEngaged {
            Task { [weak self] in
                guard
                    let self, self.isActive, !self.isPaused,
                    UserDefaults.standard.bool(forKey: PreferenceKeys.automaticLidControl) else { return }
                await self.automaticLid.start()
            }
        }
    }

    /// Deactivates Caffeine
    func deactivate() {
        self.cancelTimers()
        self.timeRemaining = nil
        self.isActive = false
        self.powerSourceMonitor.stop()
        self.powerMonitor?.cancel()
        self.powerMonitor = nil
        self.powerPolicy = PowerPauseState()
        self.pauseReason = nil
        self.automaticLid.stop()
        SleepPreventionManager.shared.allowSleep()
        ActivitySimulator.shared.stopMonitoring()
    }

    func updateAutomaticLidControl(enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: PreferenceKeys.automaticLidControl)
        if !enabled {
            self.automaticLid.stop()
            self.automaticLid.errorMessage = nil
        }
        self.refreshPowerState(force: true)
    }

    /// Updates activity simulation based on preference
    func updateActivitySimulation(enabled: Bool) {
        if enabled, !self.isPaused, !self.automaticLid.isLidClosed {
            // Trigger the Accessibility permission prompt by posting a no-op event
            // This prompts for "Events" permission which CGEvent.post requires
            ActivitySimulator.shared.requestPermission()
        }

        if enabled, self.isActive, !self.isPaused, !self.automaticLid.isLidClosed {
            ActivitySimulator.shared.startMonitoring()
        } else {
            ActivitySimulator.shared.stopMonitoring()
        }
    }

    /// Returns a formatted string for the remaining time
    func formattedTimeRemaining() -> String? {
        // Only return a status if actually active
        guard self.isActive else {
            return nil
        }

        // If there's time remaining, format it
        if let reason = self.pauseReason {
            return reason.message
        }
        if let remaining = timeRemaining, remaining > 0 {
            let seconds = Int(remaining)

            if seconds >= 3600 {
                let hours = seconds / 3600
                let minutes = (seconds % 3600) / 60
                return String(format: "%02d:%02d", hours, minutes)
            } else if seconds > 60 {
                let minutes = seconds / 60
                let format = String(localized: "%d minutes", comment: "Time remaining in minutes")
                return String.localizedStringWithFormat(format, minutes)
            } else {
                let format = String(localized: "%d seconds", comment: "Time remaining in seconds")
                return String.localizedStringWithFormat(format, seconds)
            }
        }

        // Active with no timer (indefinite)
        return String(localized: "Caffeine is active")
    }

    // MARK: - Private Methods

    private func setupObservers() {
        // Observe workspace sleep notification
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    if
                        self?.isPaused == false,
                        UserDefaults.standard.bool(forKey: PreferenceKeys.deactivateOnManualSleep)
                    {
                        self?.deactivate()
                    }
                }
            }
            .store(in: &self.cancellables)

        // Run-loop timers don't advance during sleep, so on wake check whether
        // the activation period elapsed and deactivate if so
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refreshPowerState()
                }
            }
            .store(in: &self.cancellables)
    }

    private func cancelTimers() {
        self.timeoutTimer?.invalidate()
        self.timeoutTimer = nil
        self.displayTimer?.invalidate()
        self.displayTimer = nil
    }
}

// MARK: - Preference Keys

enum PreferenceKeys {
    static let activateAtLaunch = "CAActivateAtLaunch"
    static let defaultDuration = "CADefaultDuration"
    static let suppressLaunchMessage = "CASuppressLaunchMessage"
    static let deactivateOnManualSleep = "CADeactivateOnManualSleep"
    static let automaticLidControl = "CAAutomaticLidControl"
    static let keepAppsActive = "CAKeepAppsActive"
}
