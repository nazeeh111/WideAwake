import Foundation

struct Config: Codable, Equatable, Sendable {
    var presets: [TimeInterval] = [1800]
    var defaultPreset: TimeInterval = 1800
    var maxDuration: TimeInterval = 21600
    var darkenDisplayOnLidClose: Bool = true
    var lowPowerOnLidClose: Bool = true
    var lowPowerFloor: Int = 40
    var endFloor: Int = 10
    var thermalRules: Bool = true
    var launchAtLogin: Bool = true
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        presets = try c.decodeIfPresent([TimeInterval].self, forKey: .presets) ?? [1800]
        defaultPreset = try c.decodeIfPresent(TimeInterval.self, forKey: .defaultPreset) ?? 1800
        maxDuration = try c.decodeIfPresent(TimeInterval.self, forKey: .maxDuration) ?? 21600
        darkenDisplayOnLidClose = try c.decodeIfPresent(Bool.self, forKey: .darkenDisplayOnLidClose) ?? true
        lowPowerOnLidClose = try c.decodeIfPresent(Bool.self, forKey: .lowPowerOnLidClose) ?? true
        lowPowerFloor = try c.decodeIfPresent(Int.self, forKey: .lowPowerFloor) ?? 40
        endFloor = try c.decodeIfPresent(Int.self, forKey: .endFloor) ?? 10
        thermalRules = try c.decodeIfPresent(Bool.self, forKey: .thermalRules) ?? true
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? true
    }
}
