import Foundation

/// Percentages use the same strict "below" boundary in the panel and rules.
struct BatterySettings: Equatable, Sendable {
    static let defaults = BatterySettings(lowPowerPercent: 40, stopPercent: 10)
    let lowPowerPercent: Int
    let stopPercent: Int

    func validate() throws {
        guard (1...100).contains(lowPowerPercent), (1...99).contains(stopPercent) else {
            throw SettingsError.invalid("Use 1–100% for Low Power Mode and 1–99% for stopping.")
        }
        guard stopPercent < lowPowerPercent else {
            throw SettingsError.invalid("The stop percentage must be lower than the Low Power Mode percentage.")
        }
    }
}

struct PowerSnapshot: Sendable {
    var percent: Int?
    var isCharging = false
    var thermal: ProcessInfo.ThermalState = .nominal

    static func read() -> Self {
        let battery = PowerMonitor.readBattery()
        return Self(percent: battery.percent, isCharging: battery.charging,
                    thermal: ProcessInfo.processInfo.thermalState)
    }

    func stopReason(config: Config) -> EndReason? {
        FloorRules.stopReason(percent: percent, isCharging: isCharging, thermal: thermal, config: config)
    }

    func blockingMessage(config: Config) -> String? {
        switch stopReason(config: config) {
        case .batteryFloor:
            return "Battery at \(percent ?? 0)%, below your \(config.endFloor)% stop limit. Connect power or lower the limit in Settings."
        case .thermalCritical:
            return "Your Mac is too hot. Let it cool before starting another timer."
        default: return nil
        }
    }
}
