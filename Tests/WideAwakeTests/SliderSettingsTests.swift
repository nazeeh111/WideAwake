import XCTest
@testable import WideAwake

final class SliderSettingsTests: XCTestCase {
    func testDefaultsAndExactCustomRanges() throws {
        let defaults = SliderSettings.defaults
        XCTAssertEqual(defaults.stepCount, 24)
        XCTAssertEqual(defaults.seconds(at: 24), 21600)
        let days = SliderSettings(stepMinutes: 120, maximumMinutes: 3 * 1440)
        try days.validate()
        XCTAssertEqual(days.stepCount, 36)
        XCTAssertEqual(days.seconds(at: 1), 7200)
        XCTAssertEqual(days.seconds(at: 36), 259200)
        XCTAssertEqual(days.seconds(at: Int.max), 259200)
        XCTAssertEqual(days.seconds(at: Int.min), 0)
        XCTAssertEqual(SliderSettings.label(minutes: 1440 + 125), "1d 2h 5min")
    }
    func testInvalidAndBoundaryRanges() throws {
        for scale in [SliderSettings(stepMinutes: 0, maximumMinutes: 60),
                      SliderSettings(stepMinutes: -1, maximumMinutes: 60),
                      SliderSettings(stepMinutes: 120, maximumMinutes: 60),
                      SliderSettings(stepMinutes: 7, maximumMinutes: 60),
                      SliderSettings(stepMinutes: Int.max, maximumMinutes: Int.max),
                      SliderSettings(stepMinutes: 1, maximumMinutes: 43201)] {
            XCTAssertThrowsError(try scale.validate())
        }
        let scale = SliderSettings(stepMinutes: 1, maximumMinutes: 43200)
        try scale.validate(); XCTAssertEqual(scale.stepCount, 43200)
        try SliderSettings(stepMinutes: 43200, maximumMinutes: 43200).validate()
    }
    func testLegacyConfigAndInvalidConfigFallBackSafely() throws {
        let legacy = try Store.makeDecoder().decode(Config.self, from: Data("{\"maxDuration\":21600}".utf8))
        XCTAssertEqual(legacy.sliderSettings, .defaults)
        for json in ["{\"sliderStepMinutes\":0,\"maxDuration\":21600}",
                     "{\"sliderStepMinutes\":15,\"maxDuration\":1e100}",
                     "{\"sliderStepMinutes\":7,\"maxDuration\":3600}"] {
            let config = try Store.makeDecoder().decode(Config.self, from: Data(json.utf8))
            XCTAssertEqual(config.sliderSettings, .defaults)
            XCTAssertEqual(config.maxDuration, 21600)
        }
    }
}
@MainActor final class CustomLidSessionTests: XCTestCase {
    func testCustomDaysPersistAndStartOnCloseThenReset() async throws {
        let h = Harness(now: Date()); defer { h.home.destroy() }
        let m = h.makeManager(); let c = ManualLidSession(manager: m)
        await c.prepare(lidClosed: false)
        let scale = SliderSettings(stepMinutes: 120, maximumMinutes: 3 * 1440)
        try c.applySettings(scale)
        XCTAssertEqual(try h.store.loadConfig()?.sliderSettings, scale)
        XCTAssertEqual(h.makeManager().config.sliderSettings, scale)
        await c.choose(36)
        XCTAssertEqual(m.session?.remaining(at: h.clock.now), 21600, "Long ranges still have a bounded preparation window")
        h.clock.advance(1800)
        await c.lidChanged(true)
        XCTAssertEqual(m.session?.remaining(at: h.clock.now), 259200)
        XCTAssertThrowsError(try c.applySettings(.defaults))
        XCTAssertEqual(c.settings, scale)
        await c.lidChanged(false)
        XCTAssertEqual(c.steps, 0); XCTAssertFalse(m.isActive); XCTAssertFalse(h.guardFake.sleepDisabled)
        try c.applySettings(.defaults)
        XCTAssertEqual(c.settings, .defaults)
    }
    func testShortMaximumBoundsPreparationAndMinimumWorks() async throws {
        let h = Harness(now: Date()); defer { h.home.destroy() }
        let m = h.makeManager(); let c = ManualLidSession(manager: m)
        await c.prepare(lidClosed: false)
        try c.applySettings(SliderSettings(stepMinutes: 1, maximumMinutes: 5))
        await c.choose(2)
        XCTAssertEqual(c.armingWindow, 300)
        XCTAssertEqual(m.session?.remaining(at: h.clock.now), 300)
        await c.lidChanged(true)
        XCTAssertEqual(m.session?.remaining(at: h.clock.now), 120)
        await c.lidChanged(false)
    }
    func testFailedSaveDoesNotChangeRunningConfiguration() async throws {
        let h = Harness(now: Date()); defer { h.home.destroy() }
        let m = h.makeManager(); let c = ManualLidSession(manager: m)
        await c.prepare(lidClosed: false)
        try h.store.remove(at: h.home.paths.configFile)
        try FileManager.default.createDirectory(at: h.home.paths.configFile, withIntermediateDirectories: true)
        XCTAssertThrowsError(try c.applySettings(SliderSettings(stepMinutes: 60, maximumMinutes: 1440)))
        XCTAssertEqual(c.settings, .defaults)
    }
}
