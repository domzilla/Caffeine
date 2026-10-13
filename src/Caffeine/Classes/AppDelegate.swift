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
        // Hide the dock icon before creating the menu bar-only interface
        NSApp.setActivationPolicy(.accessory)

        // Create the menu bar controller
        self.menuBarController = MenuBarController(updaterController: self.updaterController)
    }

    func applicationWillTerminate(_: Notification) {
        // Clean up
        self.menuBarController?.cleanup()
    }

    // MARK: SPUStandardUserDriverDelegate

    // MARK: - --

    func supportsGentleScheduledUpdateReminders() -> Bool {
        true
    }
}
