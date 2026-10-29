import XCTest
@testable import WideAwake

final class BatterySettingsTests: XCTestCase {
    func testValidAndInvalidThresholds() {
        for (low, stop) in [(40, 10), (20, 5), (100, 99), (2, 1)] {
            XCTAssertNoThrow(try BatterySettings(lowPowerPercent: low, stopPercent: stop).validate())
        }
        for (low, stop) in [(0, 10), (101, 10), (40, 0), (40, -1), (40, 40), (10, 40), (100, 100)] {
            XCTAssertThrowsError(try BatterySettings(lowPowerPercent: low, stopPercent: stop).validate())
        }
    }

    func testOldConfigKeepsDefaultsAndCustomConfigSurvivesRoundTrip() throws {
        let old = try Store.makeDecoder().decode(Config.self, from: Data("{}".utf8))
        XCTAssertEqual(old.batterySettings, .defaults)
        var custom = Config(); custom.lowPowerFloor = 25; custom.endFloor = 5
        let decoded = try Store.makeDecoder().decode(Config.self, from: Store.makeEncoder().encode(custom))
        XCTAssertEqual(decoded, custom)
    }

    func testInvalidStoredThresholdsFallBackTogether() throws {
        for json in ["{\"lowPowerFloor\":5,\"endFloor\":20}", "{\"lowPowerFloor\":150}", "{\"endFloor\":0}"] {
            let decoded = try Store.makeDecoder().decode(Config.self, from: Data(json.utf8))
            XCTAssertEqual(decoded.batterySettings, .defaults)
        }
    }

    func testCustomBoundariesAndPluggedInException() {
        var config = Config(); config.lowPowerFloor = 25; config.endFloor = 5
        func evaluate(_ percent: Int?, charging: Bool = false) -> [FloorRules.Action] {
            FloorRules.evaluate(percent: percent, isCharging: charging, thermal: .nominal,
                                lidClosed: false, lowPowerSetByUs: false, config: config)
        }
        XCTAssertEqual(evaluate(25), [])
        XCTAssertEqual(evaluate(24), [.enableLowPower(.battery)])
        XCTAssertEqual(evaluate(5), [.enableLowPower(.battery)])
        XCTAssertEqual(evaluate(4), [.endSession(.batteryFloor)])
        XCTAssertEqual(evaluate(1, charging: true), [])
        XCTAssertEqual(evaluate(nil), [])
    }
}

@MainActor final class BatterySliderTests: XCTestCase {
    func testBelowStopLimitExplainsRefusalWithoutChangingPowerAndCanRetry() async throws {
        let h = Harness(now: Date()); defer { h.home.destroy() }
        let power = Locked(PowerSnapshot(percent: 9))
        let m = h.makeManager(powerSnapshot: { power.value })
        let c = ManualLidSession(manager: m)
        await c.prepare(lidClosed: false); await c.choose(1)
        XCTAssertEqual(c.steps, 0); XCTAssertFalse(m.isActive)
        XCTAssertTrue(h.guardFake.calls.isEmpty)
        XCTAssertEqual(h.backstop.arms, 0)
        XCTAssertNil(try h.store.loadSession())
        XCTAssertEqual(c.phase, .blocked)
        let message = try XCTUnwrap(m.startBlockMessage)
        XCTAssertTrue(message.contains("9%")); XCTAssertTrue(message.contains("10%"))
        try c.applySettings(.defaults, battery: BatterySettings(lowPowerPercent: 30, stopPercent: 5))
        await c.choose(1)
        XCTAssertEqual(c.phase, .ready)
        XCTAssertTrue(h.guardFake.sleepDisabled)
        await c.stop()
    }

    func testChargingBypassesBatteryStopButCriticalHeatDoesNot() async {
        let h = Harness(now: Date()); defer { h.home.destroy() }
        let power = Locked(PowerSnapshot(percent: 2, isCharging: true))
        let m = h.makeManager(powerSnapshot: { power.value })
        let c = ManualLidSession(manager: m)
        await c.choose(1); XCTAssertEqual(c.phase, .ready); await c.stop()
        power.value = PowerSnapshot(percent: 2, isCharging: true, thermal: .critical)
        await c.choose(1)
        XCTAssertFalse(m.isActive)
        XCTAssertEqual(c.phase, .blocked)
        XCTAssertTrue(m.startBlockMessage?.contains("hot") == true)
    }

    func testPowerReconnectAllowsRetryWithoutRelaunch() async {
        let h = Harness(now: Date()); defer { h.home.destroy() }
        let power = Locked(PowerSnapshot(percent: 9))
        let m = h.makeManager(powerSnapshot: { power.value })
        let c = ManualLidSession(manager: m)
        await c.choose(1); XCTAssertFalse(m.isActive)
        power.value = PowerSnapshot(percent: 9, isCharging: true)
        await c.choose(1); XCTAssertEqual(c.phase, .ready); await c.stop()
    }

    func testCustomSafetyStopRestoresAndKeepsReasonVisible() async throws {
        let h = Harness(now: Date()); defer { h.home.destroy() }
        let m = h.makeManager(); let c = ManualLidSession(manager: m)
        try c.applySettings(.defaults, battery: BatterySettings(lowPowerPercent: 25, stopPercent: 5))
        await c.choose(2)
        let driver = FloorRuleDriver(manager: m, notifier: h.notifier)
        await driver.run(percent: 4, isCharging: false, thermal: .nominal, lidClosed: true)
        XCTAssertFalse(m.isActive); XCTAssertFalse(h.guardFake.sleepDisabled)
        XCTAssertEqual(c.phase, .idle); XCTAssertEqual(c.steps, 0)
        XCTAssertTrue(c.notice?.contains("5%") == true)
        await c.choose(1); XCTAssertNil(c.notice); await c.stop()
    }

    func testSettingsPersistAtomicallyAndRejectInvalidOrActiveChanges() async throws {
        let h = Harness(now: Date()); defer { h.home.destroy() }
        let m = h.makeManager(); let c = ManualLidSession(manager: m)
        let battery = BatterySettings(lowPowerPercent: 30, stopPercent: 5)
        try c.applySettings(.defaults, battery: battery)
        XCTAssertEqual(try h.store.loadConfig()?.batterySettings, battery)
        XCTAssertEqual(h.makeManager().config.batterySettings, battery)
        XCTAssertThrowsError(try c.applySettings(.defaults, battery: BatterySettings(lowPowerPercent: 5, stopPercent: 30)))
        XCTAssertEqual(m.config.batterySettings, battery)
        await c.choose(1)
        XCTAssertThrowsError(try c.applySettings(.defaults, battery: .defaults))
        await c.stop()
        let before = m.config
        try FileManager.default.removeItem(at: h.home.paths.configFile)
        try FileManager.default.createDirectory(at: h.home.paths.configFile, withIntermediateDirectories: false)
        XCTAssertThrowsError(try c.applySettings(.defaults, battery: .defaults))
        XCTAssertEqual(m.config, before)
    }

    func testManualRetryCompletesPendingSessionDeletionWithCleanJournal() async throws {
        let h = Harness(now: Date()); defer { h.home.destroy() }
        let m = h.makeManager(); let c = ManualLidSession(manager: m)
        await c.choose(1)
        let path = h.home.paths.sessionFile.path
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: path) }
        await c.stop()
        XCTAssertFalse(m.isActive); XCTAssertFalse(m.state.isDirty)
        XCTAssertNotNil(m.pendingEnd)
        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: path)
        await c.stop()
        XCTAssertNil(m.pendingEnd)
        XCTAssertNil(try h.store.loadSession())
        XCTAssertEqual(c.phase, .idle)
    }
}
