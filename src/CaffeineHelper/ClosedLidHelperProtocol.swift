//
//  ClosedLidHelperProtocol.swift
//  Caffeine
//
//  Shared between the app and CaffeineHelper.
//

import Foundation
import Security

/// XPC interface of the privileged helper that keeps the Mac awake with the lid closed.
///
/// Closing the lid puts a MacBook to sleep regardless of any power assertion, so the only
/// way to keep it awake is `pmset disablesleep`, which requires root. The helper holds that
/// setting for as long as a client asks for it and restores the previous value as soon as
/// the client releases it or its connection goes away (quit, crash, force quit).
@objc
protocol ClosedLidHelperProtocol {
    /// Disables system sleep, including lid-close sleep. Replies `true` on success.
    func preventSleep(withReply reply: @escaping (Bool) -> Void)

    /// Restores the sleep setting that was in place before `preventSleep`.
    func allowSleep(withReply reply: @escaping () -> Void)
}

enum ClosedLidHelper {
    /// launchd label and Mach service name of the helper.
    static let machServiceName = "net.domzilla.caffeine.helper"

    /// File name of the launchd plist in `Contents/Library/LaunchDaemons`.
    static let plistName = "net.domzilla.caffeine.helper.plist"

    /// Team identifier the running process is signed with, if any.
    static func ownTeamIdentifier() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }

        var info: CFDictionary?
        guard
            SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
            == errSecSuccess,
            let info = info as? [String: Any] else
        {
            return nil
        }
        return info[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// Code signing requirement matching code signed by the same team as this process.
    static func sameTeamRequirement() -> String? {
        guard let team = ownTeamIdentifier() else { return nil }
        return "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
    }
}
