import XCTest
@testable import WideAwake

@MainActor final class ManualLidSessionTests: XCTestCase {
    func testCloseStartsFullIntervalAndOpenResetsWithoutSleepGuardGap() async {
        let h = Harness(now: Date()); defer { h.home.destroy() }
        let m = h.makeManager(); m.showsLiveCountdown = false
        let c = ManualLidSession(manager: m)
        await c.prepare(lidClosed: false)
        await c.choose(1)
        XCTAssertEqual(c.phase, .ready); XCTAssertEqual(c.steps, 1)
        XCTAssertTrue(h.guardFake.sleepDisabled); XCTAssertFalse(m.countdownTimerArmed)
        h.clock.advance(120)
        await c.lidChanged(true)
        XCTAssertEqual(c.phase, .running)
        XCTAssertEqual(m.session?.remaining(at: h.clock.now), 900)
        XCTAssertEqual(h.guardFake.calls.filter { $0 == "disablesleep 0" }.count, 0)
        await c.lidChanged(false)
        XCTAssertEqual(c.steps, 0); XCTAssertEqual(c.phase, .idle)
        XCTAssertFalse(m.isActive); XCTAssertFalse(h.guardFake.sleepDisabled)
        await c.choose(2); await c.lidChanged(true)
        XCTAssertEqual(m.session?.remaining(at: h.clock.now), 1800)
        await c.lidChanged(false)
        XCTAssertEqual(c.steps, 0)
    }
    func testSliderBoundsOffAndChangedDuration() async {
        let h = Harness(now: Date()); defer { h.home.destroy() }
        let m = h.makeManager(); let c = ManualLidSession(manager: m)
        await c.prepare(lidClosed: false)
        await c.choose(100)
        XCTAssertEqual(c.steps, 24); XCTAssertEqual(m.session?.remaining(at: h.clock.now), 21600)
        await c.choose(3); await c.lidChanged(true)
        XCTAssertEqual(m.session?.remaining(at: h.clock.now), 2700)
        await c.choose(-1)
        XCTAssertEqual(c.steps, 0); XCTAssertFalse(m.isActive)
    }
    func testSafetyEndClearsSelection() async {
        let h = Harness(now: Date()); defer { h.home.destroy() }
        let m = h.makeManager(); let c = ManualLidSession(manager: m)
        await c.prepare(lidClosed: false); await c.choose(2)
        await settleQueuedRequests()
        _ = await m.end(reason: .batteryFloor)
        await settleQueuedRequests()
        XCTAssertEqual(c.steps, 0); XCTAssertEqual(c.phase, .idle)
    }
    func testFailedRestoreDoesNotClaimResetSucceeded() async {
        let h = Harness(now: Date()); defer { h.home.destroy() }
        let m = h.makeManager(); let c = ManualLidSession(manager: m)
        await c.prepare(lidClosed: false); await c.choose(2)
        h.guardFake.throwOn = ["disablesleep 0"]
        await c.stop(); await settleQueuedRequests()
        if case .failed = c.phase {} else { XCTFail("Restoration failure must stay visible") }
        h.guardFake.throwOn = []
        await c.stop()
        XCTAssertFalse(h.guardFake.sleepDisabled)
    }
    func testArmedWaitDoesNotConsumeSelectedInterval() async {
        let h = Harness(now: Date()); defer { h.home.destroy() }
        let m = h.makeManager(); let c = ManualLidSession(manager: m)
        await c.prepare(lidClosed: false); await c.choose(1)
        h.clock.advance(3600)
        XCTAssertTrue(m.isActive)
        await c.lidChanged(true)
        XCTAssertEqual(m.session?.remaining(at: h.clock.now), 900)
        await c.lidChanged(false)
    }
    func testStartupAndExpiryRestoreFailuresRemainVisible() async {
        let h = Harness(now: Date()); defer { h.home.destroy() }
        let m = h.makeManager()
        await m.start(duration: 900)
        h.guardFake.throwOn = ["disablesleep 0"]
        let c = ManualLidSession(manager: m)
        await c.prepare(lidClosed: false)
        if case .failed = c.phase {} else { XCTFail("Startup restoration failure must remain visible") }
        h.guardFake.throwOn = []; await c.stop(); await c.choose(1)
        h.guardFake.throwOn = ["disablesleep 0"]
        _ = await m.end(reason: .timer)
        if case .failed = c.phase {} else { XCTFail("Expiry restoration failure must remain visible") }
        h.guardFake.throwOn = []; await c.stop()
    }

    func testFailedCloseDeadlineRestoresInsteadOfKeepingPrearm() async {
        let h = Harness(now: Date()); defer { h.home.destroy() }
        let m = h.makeManager(); let c = ManualLidSession(manager: m)
        await c.prepare(lidClosed: false); await c.choose(1)
        h.backstop.failArm = true
        await c.lidChanged(true)
        XCTAssertFalse(m.isActive); XCTAssertFalse(h.guardFake.sleepDisabled)
        XCTAssertEqual(c.steps, 0)
        if case .failed = c.phase {} else { XCTFail("Deadline failure must stay visible") }
    }
    func testFailedReselectionRestoresPriorGuard() async {
        let h = Harness(now: Date()); defer { h.home.destroy() }
        let m = h.makeManager(); let c = ManualLidSession(manager: m)
        await c.prepare(lidClosed: false); await c.choose(1)
        h.backstop.failArm = true
        await c.choose(2)
        XCTAssertFalse(m.isActive); XCTAssertFalse(h.guardFake.sleepDisabled)
        XCTAssertEqual(c.steps, 0)
        if case .failed = c.phase {} else { XCTFail("Selection failure must stay visible") }
    }

}
