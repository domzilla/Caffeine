//
//  AppDelegate.swift
//  Caffeine
//
//  Created by Dominic Rodemer on 11.11.25.
//

import SwiftUI
import Cocoa
import Sparkle

class AppDelegate: NSObject, NSApplicationDelegate, SPUStandardUserDriverDelegate {
    // Make this lazy so `self` can be used safely
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: self
    )
    private var statusItem: NSStatusItem?
    private var menuBarController: MenuBarController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the menu bar controller
        menuBarController = MenuBarController(updaterController: updaterController)
        
        // Hide the dock icon - this is a menu bar only app
        NSApp.setActivationPolicy(.accessory)
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Clean up
        menuBarController?.cleanup()
    }
    
    // MARK: SPUStandardUserDriverDelegate
    // MARK: ---
    func supportsGentleScheduledUpdateReminders() -> Bool {
        return true
    }
}
