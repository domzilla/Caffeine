//
//  SleepPreventionManager.swift
//  Caffeine
//
//  Created by Dominic Rodemer on 11.11.25.
//

import AppKit
import Foundation
import IOKit.ps
import IOKit.pwr_mgt

/// Manages the core functionality of preventing system sleep
final class SleepPreventionManager {
    static let shared = SleepPreventionManager()

    private var sleepAssertionID: IOPMAssertionID?
    private var powerSourceRunLoopSource: CFRunLoopSource?
    private var isUserSessionActive = true
    private var isPreventingSleep = false

    private init() {
        self.setupWorkspaceNotifications()
        self.setupPowerSourceNotifications()
    }

    deinit {
        self.releaseSleepAssertion()
        if let source = self.powerSourceRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public Methods

    /// Prevents the system from sleeping
    func preventSleep() {
        guard !self.isPreventingSleep else { return }
        self.isPreventingSleep = true
        self.createSleepAssertion()
    }

    /// Allows the system to sleep normally
    func allowSleep() {
        self.isPreventingSleep = false
        self.releaseSleepAssertion()
    }

    // MARK: - Private Methods

    /// Creates a persistent display-sleep assertion.
    ///
    /// The assertion has no timeout: it survives power source transitions and is
    /// released only via `releaseSleepAssertion()` or when the process exits
    /// (IOPM releases a dead client's assertions automatically).
    private func createSleepAssertion() {
        guard self.isUserSessionActive, self.sleepAssertionID == nil else { return }

        var assertionID: IOPMAssertionID = 0
        let reason = String(localized: "Caffeine prevents sleep") as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &assertionID
        )

        if result == kIOReturnSuccess {
            self.sleepAssertionID = assertionID
        }
    }

    private func releaseSleepAssertion() {
        if let assertionID = sleepAssertionID {
            IOPMAssertionRelease(assertionID)
            self.sleepAssertionID = nil
        }
    }

    private func setupWorkspaceNotifications() {
        let notificationCenter = NSWorkspace.shared.notificationCenter

        notificationCenter.addObserver(
            self,
            selector: #selector(self.sessionDidResignActive),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )

        notificationCenter.addObserver(
            self,
            selector: #selector(self.sessionDidBecomeActive),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
    }

    /// macOS re-evaluates its idle display-sleep timer on every power source
    /// transition (AC <-> battery). Observing these transitions lets us refresh
    /// the assertion so the new power state sees it immediately instead of
    /// sleeping the display during the handover.
    private func setupPowerSourceNotifications() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let manager = Unmanaged<SleepPreventionManager>.fromOpaque(context)
                .takeUnretainedValue()
            manager.handlePowerSourceChange()
        }, context)?.takeRetainedValue() else { return }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.powerSourceRunLoopSource = source
    }

    private func handlePowerSourceChange() {
        guard self.isPreventingSleep else { return }
        self.releaseSleepAssertion()
        self.createSleepAssertion()
    }

    @objc
    private func sessionDidResignActive() {
        self.isUserSessionActive = false
        self.releaseSleepAssertion()
    }

    @objc
    private func sessionDidBecomeActive() {
        self.isUserSessionActive = true
        if self.isPreventingSleep {
            self.createSleepAssertion()
        }
    }
}
