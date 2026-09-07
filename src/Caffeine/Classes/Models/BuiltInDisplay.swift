import AppKit

@MainActor
final class BuiltInDisplay {
    private typealias GetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (UInt32, Float) -> Int32
    private let library = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
        RTLD_LAZY
    )
    private var displayID: CGDirectDisplayID?
    private var brightness: Float?
    private var isDarkened = false

    func prepare() -> Bool {
        guard self.getBrightness != nil, self.setBrightness != nil else { return false }
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &displays, &count) == .success else { return false }
        self.displayID = displays.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
        self.rememberBrightness()
        return self.displayID != nil && self.brightness != nil
    }

    func rememberBrightness() {
        guard !self.isDarkened, let displayID, let get = self.getBrightness else { return }
        var value: Float = 0
        if get(displayID, &value) == 0, value.isFinite, (0...1).contains(value) {
            self.brightness = value
        }
    }

    @discardableResult
    func darken() -> Bool {
        guard let displayID, let set = self.setBrightness else { return false }
        self.isDarkened = true
        return set(displayID, 0) == 0
    }

    func restore() {
        guard self.isDarkened, let displayID, let brightness, let set = self.setBrightness else { return }
        if set(displayID, brightness) == 0 {
            self.isDarkened = false
        }
    }

    private var getBrightness: GetBrightness? {
        guard let library, let symbol = dlsym(library, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(symbol, to: GetBrightness.self)
    }

    private var setBrightness: SetBrightness? {
        guard let library, let symbol = dlsym(library, "DisplayServicesSetBrightness") else { return nil }
        return unsafeBitCast(symbol, to: SetBrightness.self)
    }
}
