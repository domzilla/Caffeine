//
//  AppDelegate.swift
//  Caffeine
//
//  Created by Dominic Rodemer on 29.06.24.
//

import Cocoa
import IOKit.pwr_mgt
import Sparkle

@main
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, SPUStandardUserDriverDelegate {
    
    var isActive:Bool
    var userSessionIsActive:Bool
    
    var timer:Timer!
    var timeoutTimer:Timer?
    var sleepAssertionID:IOPMAssertionID?
    
    var statusItem:NSStatusItem!
    var statusItemMenuIcon:NSImage!
    var statusItemMenuIconActive:NSImage!
    
    @IBOutlet var menu:NSMenu!
    @IBOutlet var infoMenuItem:NSMenuItem!
    @IBOutlet var infoSeparatorItem:NSMenuItem!
    
    var preferencesWindowController:PreferencesWindowController!
    var updaterController:SPUStandardUpdaterController!
    
    override init() {
        self.isActive = false
        self.userSessionIsActive = true
        
        super.init()
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        timer = Timer.scheduledTimer(timeInterval: 10.0,
                                     target: self,
                                     selector: #selector(AppDelegate.timer(_:)),
                                     userInfo: nil,
                                     repeats: true)
                
        NSWorkspace.shared.notificationCenter.addObserver(self,
                                                          selector: #selector(AppDelegate.workspaceSessionDidResignActiveNotification(_:)),
                                                          name: NSWorkspace.sessionDidResignActiveNotification,
                                                          object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self,
                                                          selector: #selector(AppDelegate.workspaceSessionDidBecomeActiveNotification(_:)),
                                                          name: NSWorkspace.sessionDidBecomeActiveNotification,
                                                          object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self,
                                                          selector: #selector(AppDelegate.workspaceWillSleepNotification(_:)),
                                                          name: NSWorkspace.willSleepNotification,
                                                          object: nil)
        
        UserDefaults.standard.register(defaults: ["CASuppressLaunchMessage" : false])
        
        preferencesWindowController = PreferencesWindowController(windowNibName: "PreferencesWindowController")
        updaterController = SPUStandardUpdaterController(startingUpdater: true,
                                                         updaterDelegate: nil,
                                                         userDriverDelegate: self);
        
        if !UserDefaults.standard.bool(forKey: "CASuppressLaunchMessage") {
            self.showPreferences(nil)
        }
    }
    
    override func awakeFromNib() {
        statusItemMenuIcon = NSImage(named: "inactive")
        statusItemMenuIcon.isTemplate = true
        statusItemMenuIconActive = NSImage(named: "active")
        statusItemMenuIconActive.isTemplate = true
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = statusItemMenuIcon
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.button?.action = #selector(AppDelegate.statusItemAction(_:))
        statusItem.button?.target = self
        
        if UserDefaults.standard.bool(forKey: "CAActivateAtLaunch") {
            self.activate()
        }
    }
    
    // MARK: Actions
    // MARK: ---
    @IBAction func timer(_ sender:Timer) {
        if isActive && userSessionIsActive {
            if self.sleepAssertionID != nil {
                IOPMAssertionRelease(self.sleepAssertionID!)
            }
            self.sleepAssertionID = IOPMAssertionID(0)
            print(kIOPMAssertPreventUserIdleDisplaySleep)
            IOPMAssertionCreateWithDescription(kIOPMAssertPreventUserIdleDisplaySleep as CFString,
                                               "Caffeine prevents sleep" as CFString,
                                               nil,
                                               nil,
                                               nil,
                                               8, //Timeout assertion after 8 sec
                                               nil,
                                               &self.sleepAssertionID!)
        }
    }
    
    @IBAction func timeoutReached(_ sender:Timer) {
        self.deactivate()
    }
    
    @IBAction func statusItemAction(_ sender:NSStatusBarButton?) {
        let event = NSApp.currentEvent
        let modifierFlags = event?.modifierFlags ?? []
        if event?.type == .rightMouseUp || (event?.type == .leftMouseUp && modifierFlags.contains(.control)) {
            statusItem.menu = menu
            sender?.performClick(nil)
            statusItem.menu = nil
        } else {
            toggleActive(sender)
        }
    }
    
    @IBAction func activateWithTimeout(_ sender:NSMenuItem) {
        let minutes = sender.tag
        var seconds = minutes*60
        
        if seconds == -60 {
            seconds = 2
        }
        
        self.activate(withTimeoutDuration: seconds)
    }
    
    @IBAction func showAbout(_ sender:Any?) {
        NSApp.activate(ignoringOtherApps: true)
        
        let credits = "© 2006 Tomas Franzén \n © 2018 Michael Jones \n © 2022 Dominic Rodemer \n\n Source code: \n https://github.caffeine-app.net"
        NSApp.orderFrontStandardAboutPanel(options: [.credits : credits])
    }
    
    @IBAction func showPreferences(_ sender:Any?) {
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindowController.showWindow(self)
    }
    
    @IBAction func checkForUpdates(_ sender:Any?) {
        updaterController.checkForUpdates(sender)
    }
    
    
    // MARK:  Public
    // MARK:  ---
    func activate() {
        let defaultMinutesDuration = UserDefaults.standard.integer(forKey: "CADefaultDuration")
        var seconds = defaultMinutesDuration*60
        
        if seconds == -60 {
            seconds = 2
        }
        
        self.activate(withTimeoutDuration: seconds)
    }
    
    func activate(withTimeoutDuration seconds:Int) {
        if let timeoutTimer = self.timeoutTimer {
            timeoutTimer.invalidate()
        }
        
        if seconds > 0 {
            timeoutTimer = Timer.scheduledTimer(timeInterval: TimeInterval(seconds),
                                                target: self,
                                                selector: #selector(AppDelegate.timeoutReached(_:)),
                                                userInfo: nil,
                                                repeats: false)
        }
        
        isActive = true
        statusItem.button?.image = self.statusItemMenuIconActive
    }
    
    func deactivate() {
        isActive = false
        
        if let timeoutTimer = self.timeoutTimer {
            timeoutTimer.invalidate()
        }
        timeoutTimer = nil
        
        statusItem.button?.image = statusItemMenuIcon
    }
    
    func toggleActive(_ sender:Any?) {
        if let timeoutTimer = self.timeoutTimer {
            timeoutTimer.invalidate()
        }
        timeoutTimer = nil
        
        if isActive {
            self.deactivate()
        } else {
            self.activate()
        }
    }
    
    
    // MARK: NSMenuDelegate
    // MARK: ---
    func menuNeedsUpdate(_ menu: NSMenu) {
        if isActive {
            infoMenuItem.isHidden = false
            infoSeparatorItem.isHidden = false
            
            if let timeoutTimer = self.timeoutTimer {
                let left = Int(timeoutTimer.fireDate.timeIntervalSinceNow)
                if left >= 3600 {
                    infoMenuItem.title = String(format: "%02d:%02d", left/3600, (left%3600)/60)
                } else if left > 60 {
                    infoMenuItem.title = String(format: NSLocalizedString("%d minutes", comment: "e.g. 5 minutes"), left/60)
                } else {
                    infoMenuItem.title = String(format: NSLocalizedString("%d seconds", comment: "e.g. 54 seconds"), left)
                }
            } else {
                infoMenuItem.title = NSLocalizedString("Caffeine is active", comment: "Indicate that Caffeine is active")
            }
        } else {
            infoMenuItem.isHidden = true
            infoSeparatorItem.isHidden = true
        }
    }

    
    // MARK: SPUStandardUserDriverDelegate
    // MARK: ---
    func supportsGentleScheduledUpdateReminders() -> Bool {
        return true
    }
    
    
    // MARK: NSWorkspace Notifications
    // MARK: ---
    @objc func workspaceSessionDidResignActiveNotification(_ notification:NSNotification) {
        userSessionIsActive = false
    }
    
    @objc func workspaceSessionDidBecomeActiveNotification(_ notification:NSNotification) {
        userSessionIsActive = true
    }
    
    @objc func workspaceWillSleepNotification(_ notification:NSNotification) {
        if UserDefaults.standard.bool(forKey: "CADeactivateOnManualSleep") {
            self.deactivate()
        }
    }
}

