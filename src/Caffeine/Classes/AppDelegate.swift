//
//  AppDelegate.swift
//  Caffeine
//
//  Created by Dominic Rodemer on 11.11.25.
//

import Cocoa
import DZFoundation
import KeyboardShortcuts
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
        // Create the menu bar controller
        self.menuBarController = MenuBarController(updaterController: self.updaterController)

        // Hide the dock icon - this is a menu bar only app
        NSApp.setActivationPolicy(.accessory)

        self.registerGlobalShortcut()
    }

    private func registerGlobalShortcut() {
        KeyboardShortcuts.onKeyUp(for: .toggleActive) { [weak self] in
            Task { @MainActor in
                self?.menuBarController?.toggleActive()
            }
        }
        DZLog("Registered global toggle shortcut")
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
