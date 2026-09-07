import Foundation

struct PowerSnapshot {
    var onExternalPower: Bool?
    var batteryFraction: Double?
    var isTooHot: Bool
}

enum PowerPauseReason: Equatable {
    case lowBattery, overheating

    var message: String {
        switch self {
        case .lowBattery:
            String(localized: "Paused for low battery. Connect the charger to resume.")
        case .overheating:
            String(localized: "Paused because the Mac is too hot. Resumes after it cools down.")
        }
    }
}

/// Low battery stays latched until AC is actually detected; a fluctuating or
/// unavailable battery reading must not repeatedly restart the sleep override.
struct PowerPauseState {
    private var waitingForCharger = false

    mutating func update(_ snapshot: PowerSnapshot) -> PowerPauseReason? {
        if snapshot.onExternalPower == true {
            self.waitingForCharger = false
        } else if
            snapshot.onExternalPower == false,
            let fraction = snapshot.batteryFraction, fraction <= 0.10
        {
            self.waitingForCharger = true
        }
        if snapshot.isTooHot {
            return .overheating
        }
        return self.waitingForCharger ? .lowBattery : nil
    }
}
