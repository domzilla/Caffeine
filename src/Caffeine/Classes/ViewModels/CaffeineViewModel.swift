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
    @Published var elapsedTime: TimeInterval = 0
    @Published var showPreferences = false

    // MARK: - Private Properties

    private var timeoutTimer: Timer?
    private var displayTimer: Timer?
    private var activationDate: Date?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {
        Self.registerDefaults()

        // Explicitly ensure we start inactive
        self.isActive = false
        self.timeRemaining = nil

        self.setupObservers()

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

        self.activationDate = Date()
        self.elapsedTime = 0

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
        } else {
            self.timeRemaining = nil
        }

        // Update display every second, whether or not a timeout is set, so that
        // elapsed time keeps ticking for indefinite activations too
        self.displayTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0,
            repeats: true
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateDisplayTime()
            }
        }

        self.isActive = true
        SleepPreventionManager.shared.preventSleep()

        if UserDefaults.standard.bool(forKey: PreferenceKeys.keepAppsActive) {
            ActivitySimulator.shared.startMonitoring()
        }
    }

    /// Deactivates Caffeine
    func deactivate() {
        self.cancelTimers()
        self.timeRemaining = nil
        self.activationDate = nil
        self.elapsedTime = 0
        self.isActive = false
        SleepPreventionManager.shared.allowSleep()
        ActivitySimulator.shared.stopMonitoring()
    }

    /// Updates activity simulation based on preference
    func updateActivitySimulation(enabled: Bool) {
        if enabled {
            // Trigger the Accessibility permission prompt by posting a no-op event
            // This prompts for "Events" permission which CGEvent.post requires
            ActivitySimulator.shared.requestPermission()
        }

        if enabled, self.isActive {
            ActivitySimulator.shared.startMonitoring()
        } else {
            ActivitySimulator.shared.stopMonitoring()
        }
    }

    /// Returns the title to show next to the menu bar icon, or `nil` when no timer should be shown
    func menuBarTitle() -> String? {
        guard
            self.isActive,
            UserDefaults.standard.bool(forKey: PreferenceKeys.showMenuBarTimer) else
        {
            return nil
        }

        return Self.formattedDuration(self.displayedInterval, format: self.timerFormat)
    }

    /// Returns a formatted status string for the menu, honoring the timer display preference
    func formattedStatusText() -> String? {
        // Only return a status if actually active
        guard self.isActive else {
            return nil
        }

        if self.timerDisplayMode == .elapsed {
            return Self.descriptiveDuration(self.elapsedTime)
        }

        // If there's time remaining, format it
        if let remaining = timeRemaining, remaining > 0 {
            return Self.descriptiveDuration(remaining)
        }

        // Active with no timer (indefinite)
        return String(localized: "Caffeine is active")
    }

    // MARK: - Private Methods

    /// The interval the menu bar timer should show. Remaining time is undefined for indefinite
    /// activations, so those fall back to elapsed time.
    private var displayedInterval: TimeInterval {
        if self.timerDisplayMode == .remaining, let timeRemaining {
            return timeRemaining
        }
        return self.elapsedTime
    }

    private var timerDisplayMode: TimerDisplayMode {
        let raw = UserDefaults.standard.string(forKey: PreferenceKeys.timerDisplayMode) ?? ""
        return TimerDisplayMode(rawValue: raw) ?? .elapsed
    }

    private var timerFormat: TimerFormat {
        let raw = UserDefaults.standard.string(forKey: PreferenceKeys.timerFormat) ?? ""
        return TimerFormat(rawValue: raw) ?? .compact
    }

    /// Terse duration for the menu bar, e.g. `1:23:45` / `5:07` or `1h 23m` / `5m` / `42s`.
    /// Both styles are formatted by the system and therefore localized automatically.
    private static func formattedDuration(_ interval: TimeInterval, format: TimerFormat) -> String {
        let seconds = max(0, Int(interval))
        let duration = Duration.seconds(seconds)

        switch format {
        case .compact:
            return duration.formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))

        case .verbose:
            let allowed: Set<Duration.UnitsFormatStyle.Unit> =
                if seconds >= 3600 {
                    [.hours, .minutes]
                } else if seconds >= 60 {
                    [.minutes]
                } else {
                    [.seconds]
                }
            // Truncate rather than round, so verbose never runs ahead of compact (1:23:45 -> "1h 23m")
            return duration.formatted(
                .units(
                    allowed: allowed,
                    width: .narrow,
                    maximumUnitCount: 2,
                    fractionalPart: .hide(rounded: .towardZero)
                )
            )
        }
    }

    /// Wordier duration for the menu's status item, matching the app's existing phrasing
    private static func descriptiveDuration(_ interval: TimeInterval) -> String {
        let seconds = Int(max(0, interval))

        if seconds >= 3600 {
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            return String(format: "%02d:%02d", hours, minutes)
        } else if seconds > 60 {
            let format = String(localized: "%d minutes", comment: "Time remaining in minutes")
            return String.localizedStringWithFormat(format, seconds / 60)
        } else {
            let format = String(localized: "%d seconds", comment: "Time remaining in seconds")
            return String.localizedStringWithFormat(format, seconds)
        }
    }

    private static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            PreferenceKeys.showMenuBarTimer: true,
            PreferenceKeys.timerDisplayMode: TimerDisplayMode.elapsed.rawValue,
            PreferenceKeys.timerFormat: TimerFormat.compact.rawValue,
        ])
    }

    private func updateDisplayTime() {
        guard let activationDate = self.activationDate else { return }

        self.elapsedTime = Date().timeIntervalSince(activationDate)

        if let timeoutTimer = self.timeoutTimer {
            self.timeRemaining = max(0, timeoutTimer.fireDate.timeIntervalSinceNow)
        }
    }

    private func setupObservers() {
        // Observe workspace sleep notification
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    if UserDefaults.standard.bool(forKey: PreferenceKeys.deactivateOnManualSleep) {
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
                    guard let self, let timeoutTimer = self.timeoutTimer else { return }
                    if timeoutTimer.fireDate.timeIntervalSinceNow <= 0 {
                        self.deactivate()
                    }
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

// MARK: - Timer Display Preferences

/// Whether the menu bar timer counts up from activation or down to the timeout
enum TimerDisplayMode: String {
    case elapsed
    case remaining
}

/// How the menu bar timer renders a duration
enum TimerFormat: String {
    case compact
    case verbose
}

// MARK: - Preference Keys

enum PreferenceKeys {
    static let activateAtLaunch = "CAActivateAtLaunch"
    static let defaultDuration = "CADefaultDuration"
    static let suppressLaunchMessage = "CASuppressLaunchMessage"
    static let deactivateOnManualSleep = "CADeactivateOnManualSleep"
    static let keepAppsActive = "CAKeepAppsActive"
    static let showMenuBarTimer = "CAShowMenuBarTimer"
    static let timerDisplayMode = "CATimerDisplayMode"
    static let timerFormat = "CATimerFormat"
}
