import Foundation

/// Whole-minute, finite ranges keep slider snapping exact and recovery bounded.
struct SliderSettings: Equatable, Sendable {
    static let defaults = SliderSettings(stepMinutes: 15, maximumMinutes: 360)
    static let limitMinutes = 30 * 24 * 60
    let stepMinutes: Int
    let maximumMinutes: Int
    var stepCount: Int { maximumMinutes / stepMinutes }
    var maximumSeconds: TimeInterval { TimeInterval(maximumMinutes * 60) }
    var stepSeconds: TimeInterval { TimeInterval(stepMinutes * 60) }

    func validate() throws {
        guard (1...Self.limitMinutes).contains(stepMinutes),
              (1...Self.limitMinutes).contains(maximumMinutes) else {
            throw SettingsError.invalid("Choose whole minutes from 1 minute to 30 days.")
        }
        guard maximumMinutes >= stepMinutes else {
            throw SettingsError.invalid("Maximum must be at least one increment.")
        }
        guard maximumMinutes % stepMinutes == 0 else {
            throw SettingsError.invalid("Maximum must be a multiple of the increment.")
        }
    }
    func seconds(at step: Int) -> TimeInterval {
        TimeInterval(min(stepCount, max(0, step))) * stepSeconds
    }
    static func label(minutes: Int) -> String {
        guard minutes > 0 else { return "Off" }
        let days = minutes / 1440, hours = (minutes % 1440) / 60, mins = minutes % 60
        return [(days, "d"), (hours, "h"), (mins, "min")]
            .filter { $0.0 > 0 }.map { "\($0.0)\($0.1)" }.joined(separator: " ")
    }
}
enum SettingsError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { switch self { case let .invalid(message): message } }
}
