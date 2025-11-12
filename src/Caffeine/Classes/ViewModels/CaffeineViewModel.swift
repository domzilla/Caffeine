//
//  CaffeineViewModel.swift
//  Caffeine
//
//  Created by Dominic Rodemer on 11.11.25.
//

import SwiftUI
import Combine

/// Main view model for the Caffeine application
@MainActor
class CaffeineViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var isActive = false
    @Published var timeRemaining: TimeInterval?
    @Published var showPreferences = false
    
    // MARK: - Private Properties
    
    private var timeoutTimer: Timer?
    private var displayTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init() {
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
        if isActive {
            deactivate()
        } else {
            activate()
        }
    }
    
    /// Activates Caffeine with optional timeout
    func activate(withTimeout timeout: TimeInterval? = nil) {
        // Use default duration if no timeout specified
        let duration: TimeInterval?
        if let timeout = timeout {
            duration = timeout > 0 ? timeout : nil
        } else {
            let defaultMinutes = UserDefaults.standard.integer(forKey: PreferenceKeys.defaultDuration)
            duration = defaultMinutes > 0 ? TimeInterval(defaultMinutes * 60) : nil
        }
        
        // Cancel existing timers
        cancelTimers()
        
        // Set up timeout timer if duration specified
        if let duration = duration {
            timeRemaining = duration
            
            timeoutTimer = Timer.scheduledTimer(
                withTimeInterval: duration,
                repeats: false
            ) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.deactivate()
                }
            }
            
            // Update display every second
            displayTimer = Timer.scheduledTimer(
                withTimeInterval: 1.0,
                repeats: true
            ) { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self = self,
                          let timeoutTimer = self.timeoutTimer else {
                        self?.displayTimer?.invalidate()
                        return
                    }
                    
                    self.timeRemaining = timeoutTimer.fireDate.timeIntervalSinceNow
                    if self.timeRemaining ?? 0 <= 0 {
                        self.displayTimer?.invalidate()
                        self.displayTimer = nil
                    }
                }
            }
        } else {
            timeRemaining = nil
        }
        
        isActive = true
        SleepPreventionManager.shared.preventSleep()
    }
    
    /// Deactivates Caffeine
    func deactivate() {
        cancelTimers()
        timeRemaining = nil
        isActive = false
        SleepPreventionManager.shared.allowSleep()
    }
    
    /// Returns a formatted string for the remaining time
    func formattedTimeRemaining() -> String? {
        // Only return a status if actually active
        guard isActive else {
            return nil
        }
        
        // If there's time remaining, format it
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
                    if UserDefaults.standard.bool(forKey: PreferenceKeys.deactivateOnManualSleep) {
                        self?.deactivate()
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    private func cancelTimers() {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        displayTimer?.invalidate()
        displayTimer = nil
    }
}

// MARK: - Preference Keys

enum PreferenceKeys {
    static let activateAtLaunch = "CAActivateAtLaunch"
    static let defaultDuration = "CADefaultDuration"
    static let suppressLaunchMessage = "CASuppressLaunchMessage"
    static let deactivateOnManualSleep = "CADeactivateOnManualSleep"
}
