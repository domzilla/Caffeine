//
//  PreferencesView.swift
//  Caffeine
//
//  Created by Dominic Rodemer on 11.11.25.
//

import ServiceManagement
import SwiftUI

struct PreferencesView: View {
    @ObservedObject var viewModel: CaffeineViewModel
    @AppStorage(PreferenceKeys.defaultDuration) private var defaultDuration = 0
    @AppStorage(PreferenceKeys.activateAtLaunch) private var activateAtLaunch = false
    @AppStorage(PreferenceKeys.suppressLaunchMessage) private var suppressLaunchMessage = false
    @AppStorage(PreferenceKeys.deactivateOnManualSleep) private var deactivateOnManualSleep = false
    @AppStorage(PreferenceKeys.keepAppsActive) private var keepAppsActive = false
    @AppStorage(PreferenceKeys.keepAwakeWithLidClosed) private var keepAwakeWithLidClosed = false
    @ObservedObject private var closedLid = ClosedLidManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Icon and description
            HStack(alignment: .center, spacing: 16) {
                // App icon with background
                ZStack {
                    Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                        .resizable()
                        .frame(width: 140, height: 140)
                        .accessibilityHidden(true)
                }

                // Description text
                VStack(alignment: .leading, spacing: 16) {
                    Text(
                        "Caffeine is now running. You can find its icon in the right side of your menu bar. Click it to disable automatic sleep, click it again to enable automatic sleep."
                    )
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)

                    Text("Right-click (or ⌃-click) the menu bar icon to show the Caffeine menu.")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 30)

            // Default duration
            HStack(spacing: 8) {
                Text("Default duration:")
                    .font(.system(size: 13))

                Picker("", selection: self.$defaultDuration) {
                    Text("5 minutes").tag(5)
                    Text("10 minutes").tag(10)
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("1 hour").tag(60)
                    Text("2 hours").tag(120)
                    Text("5 hours").tag(300)
                    Text("Indefinitely").tag(0)
                }
                .pickerStyle(.menu)
                .frame(width: 180)
                .accessibilityIdentifier("PreferencesView.defaultDurationPicker")

                Spacer()
            }
            .padding(.bottom, 16)

            // Checkboxes
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Activate when starting Caffeine", isOn: self.$activateAtLaunch)
                    .font(.system(size: 13))
                    .accessibilityIdentifier("PreferencesView.activateAtLaunchToggle")

                Toggle("Deactivate when device goes to sleep manually", isOn: self.$deactivateOnManualSleep)
                    .font(.system(size: 13))
                    .accessibilityIdentifier("PreferencesView.deactivateOnManualSleepToggle")

                Toggle("Show this message when starting Caffeine", isOn: Binding(
                    get: { !self.suppressLaunchMessage },
                    set: { self.suppressLaunchMessage = !$0 }
                ))
                .font(.system(size: 13))
                .accessibilityIdentifier("PreferencesView.showLaunchMessageToggle")

                Divider()
                    .padding(.vertical, 4)
                    .accessibilityHidden(true)

                Toggle("Keep apps active", isOn: Binding(
                    get: { self.keepAppsActive },
                    set: { newValue in
                        self.keepAppsActive = newValue
                        self.viewModel.updateActivitySimulation(enabled: newValue)
                    }
                ))
                .font(.system(size: 13))
                .accessibilityIdentifier("PreferencesView.keepAppsActiveToggle")

                Text("Prevents apps from becoming inactive and the screen saver from starting.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.leading, 20)

                Toggle("Keep awake with the lid closed", isOn: Binding(
                    get: { self.keepAwakeWithLidClosed },
                    set: { newValue in
                        self.keepAwakeWithLidClosed = newValue
                        self.viewModel.updateClosedLid(enabled: newValue)
                    }
                ))
                .font(.system(size: 13))
                .padding(.top, 8)
                .accessibilityIdentifier("PreferencesView.keepAwakeWithLidClosedToggle")

                Text(
                    "Lets your Mac keep running with the lid closed while Caffeine is active, with the built-in speakers muted. Turns off below 10% battery."
                )
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 20)

                if self.keepAwakeWithLidClosed {
                    self.closedLidStatus
                        .padding(.leading, 20)
                }
            }

            Spacer()
                .frame(height: 30)

            // Footer buttons
            HStack {
                Button(String(localized: "Quit")) {
                    NSApp.terminate(nil)
                }
                .controlSize(.large)
                .accessibilityIdentifier("PreferencesView.quitButton")

                Spacer()

                Button(String(localized: "Close")) {
                    NSApp.keyWindow?.close()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("PreferencesView.closeButton")
            }
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 20)
        .frame(width: 640)
        .onAppear {
            self.closedLid.refreshStatus()
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

extension PreferencesView {
    @ViewBuilder
    private var closedLidStatus: some View {
        switch self.closedLid.status {
        case .enabled:
            if let error = self.closedLid.lastError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        case .requiresApproval:
            HStack(spacing: 8) {
                Text("Allow Caffeine in System Settings to finish turning this on.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Button(String(localized: "Open Login Items")) {
                    SMAppService.openSystemSettingsLoginItems()
                }
                .controlSize(.small)
                .accessibilityIdentifier("PreferencesView.openLoginItemsButton")
            }
        default:
            HStack(spacing: 8) {
                Text(self.closedLid.lastError ?? String(localized: "Caffeine's helper isn't set up."))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Button(String(localized: "Set Up")) {
                    self.viewModel.updateClosedLid(enabled: true)
                }
                .controlSize(.small)
                .accessibilityIdentifier("PreferencesView.setUpClosedLidButton")
            }
        }
    }
}

#Preview {
    PreferencesView(viewModel: CaffeineViewModel())
        .environment(\.locale, .init(identifier: "en"))
}
