//
//  SleepPreventionManager.swift
//  Caffeine
//
//  Created by Dominic Rodemer on 11.11.25.
//

import Foundation
import AppKit
import IOKit.pwr_mgt

/// Manages the core functionality of preventing system sleep
final class SleepPreventionManager {
    static let shared = SleepPreventionManager()
    
    private var sleepAssertionID: IOPMAssertionID?
    private var assertionTimer: Timer?
    private var isUserSessionActive = true
    
    private init() {
        setupWorkspaceNotifications()
    }
    
    deinit {
        releaseSleepAssertion()
        assertionTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Public Methods
    
    /// Prevents the system from sleeping
    func preventSleep() {
        // Start or restart the assertion timer
        assertionTimer?.invalidate()
        assertionTimer = Timer.scheduledTimer(
            withTimeInterval: 10.0,
            repeats: true
        ) { [weak self] _ in
            self?.refreshSleepAssertion()
        }
        assertionTimer?.fire() // Fire immediately
    }
    
    /// Allows the system to sleep normally
    func allowSleep() {
        assertionTimer?.invalidate()
        assertionTimer = nil
        releaseSleepAssertion()
    }
    
    // MARK: - Private Methods
    
    private func refreshSleepAssertion() {
        guard isUserSessionActive else { return }
        
        // Release existing assertion
        if let assertionID = sleepAssertionID {
            IOPMAssertionRelease(assertionID)
        }
        
        // Create new assertion
        var assertionID: IOPMAssertionID = 0
        let reason = String(localized: "Caffeine prevents sleep") as CFString
        let result = IOPMAssertionCreateWithDescription(
            kIOPMAssertPreventUserIdleDisplaySleep as CFString,
            reason,
            nil as CFString?,
            nil as CFString?,
            nil as CFString?,
            8, // Timeout after 8 seconds
            nil as CFString?,
            &assertionID
        )
        
        if result == kIOReturnSuccess {
            sleepAssertionID = assertionID
        }
    }
    
    private func releaseSleepAssertion() {
        if let assertionID = sleepAssertionID {
            IOPMAssertionRelease(assertionID)
            sleepAssertionID = nil
        }
    }
    
    private func setupWorkspaceNotifications() {
        let notificationCenter = NSWorkspace.shared.notificationCenter
        
        notificationCenter.addObserver(
            self,
            selector: #selector(sessionDidResignActive),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        
        notificationCenter.addObserver(
            self,
            selector: #selector(sessionDidBecomeActive),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
    }
    
    @objc private func sessionDidResignActive() {
        isUserSessionActive = false
    }
    
    @objc private func sessionDidBecomeActive() {
        isUserSessionActive = true
    }
}


