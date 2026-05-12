//
//  LaunchContext.swift
//  Caffeine
//

import AppKit
import Carbon

enum LaunchContext {
    case standard
    case loginItem

    static var current: LaunchContext {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else {
            return .standard
        }

        let launchedAsLoginItem = event.eventID == kAEOpenApplication &&
            event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem

        return launchedAsLoginItem ? .loginItem : .standard
    }
}
