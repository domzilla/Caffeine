//
//  AppDelegate.swift
//  Caffeine
//
//  Created by Dominic Rodemer on 11.11.25.
//

import Cocoa
import Sparkle
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, SPUStandardUserDriverDelegate {
    /// Make this lazy so `self` can be used safely
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: self
    )
    private var statusItem: NSStatusItem?
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_: Notification) {
        // Re-enable sleep if a previous run left it disabled (crash or forced quit)
        ClamshellSleepController.shared.restoreIfNeeded()

        // Create the menu bar controller
        self.menuBarController = MenuBarController(updaterController: self.updaterController)

        // Hide the dock icon - this is a menu bar only app
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationWillTerminate(_: Notification) {
        // Clean up
        self.menuBarController?.cleanup()

        // Re-enable sleep if we disabled it for lid-close prevention
        ClamshellSleepController.shared.restoreIfNeeded()
    }

    // MARK: SPUStandardUserDriverDelegate

    // MARK: - --

    func supportsGentleScheduledUpdateReminders() -> Bool {
        true
    }
}
