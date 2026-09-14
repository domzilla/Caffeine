import Foundation

@MainActor
final class KeyboardBacklight {
    private typealias Read = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias Write = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool
    private typealias IsBuiltIn = @convention(c) (AnyObject, Selector, UInt64) -> Bool
    private let library = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY)
    private var client: NSObject?
    private var keyboardID: UInt64?
    private var brightness: Float?
    private var isDarkened = false
    private let readSelector = NSSelectorFromString("brightnessForKeyboard:")
    private let writeSelector = NSSelectorFromString("setBrightness:forKeyboard:")

    func prepare() -> Bool {
        guard
            self.library != nil,
            let type = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else { return false }
        let client = type.init()
        let idsSelector = NSSelectorFromString("copyKeyboardBacklightIDs")
        let builtInSelector = NSSelectorFromString("isKeyboardBuiltIn:")
        guard
            [idsSelector, builtInSelector, self.readSelector, self.writeSelector]
                .allSatisfy({ client.responds(to: $0) }),
            let ids = client.perform(idsSelector)?.takeRetainedValue() as? [NSNumber] else { return false }
        let builtIn = unsafeBitCast(client.method(for: builtInSelector), to: IsBuiltIn.self)
        self.keyboardID = ids.first { builtIn(client, builtInSelector, $0.uint64Value) }?.uint64Value
        self.client = client
        self.rememberBrightness()
        return self.keyboardID != nil && self.brightness != nil
    }

    func rememberBrightness() {
        guard !self.isDarkened, let client, let keyboardID else { return }
        let read = unsafeBitCast(client.method(for: self.readSelector), to: Read.self)
        let value = read(client, self.readSelector, keyboardID)
        if value.isFinite, (0...1).contains(value) {
            self.brightness = value
        }
    }

    @discardableResult
    func darken() -> Bool {
        guard let client, let keyboardID else { return false }
        self.isDarkened = true
        let write = unsafeBitCast(client.method(for: self.writeSelector), to: Write.self)
        return write(client, self.writeSelector, 0, keyboardID)
    }

    func restore() {
        guard self.isDarkened, let client, let keyboardID, let brightness else { return }
        let write = unsafeBitCast(client.method(for: self.writeSelector), to: Write.self)
        if write(client, self.writeSelector, brightness, keyboardID) {
            self.isDarkened = false
        }
    }
}
