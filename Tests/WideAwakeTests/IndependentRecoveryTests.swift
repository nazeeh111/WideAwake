import Foundation
import XCTest
@testable import WideAwake

@MainActor final class IndependentRecoveryTests: XCTestCase {
    func testPendingUnreadableEndPreservesFileAcrossDurationChanges() async throws {
        for action in ["extend", "reset"] {
            let h = Harness(); defer { h.home.destroy() }
            let m = h.makeManager()
            let started = await m.start(duration: 600)
            XCTAssertNotNil(started)
            let corrupt = Data("diagnostic bytes".utf8)
            try corrupt.write(to: h.home.paths.sessionFile)
            let outcome = await m.end(reason: .user)
            XCTAssertEqual(outcome, .sessionUnreadable)
            let initialArms = h.backstop.arms
            if action == "extend" {
                await m.extend(by: 600)
            } else {
                let reset = await m.resetDuration(900)
                XCTAssertFalse(reset)
            }
            XCTAssertEqual(try Data(contentsOf:h.home.paths.sessionFile),corrupt,action)
            XCTAssertEqual(h.backstop.arms, initialArms, action)
        }
    }

    func testReleaseOwnedLowPowerRefusesUnknownCurrentValue() async throws {
        let h = Harness(); defer { h.home.destroy() }
        let m = h.makeManager()
        let started = await m.start(duration: 600)
        XCTAssertNotNil(started)
        let enabled = await m.setLowPower(true)
        XCTAssertTrue(enabled)
        h.guardFake.throwOn = ["pmset -g custom"]
        let released = await m.setLowPower(false)
        XCTAssertFalse(released)
        XCTAssertFalse(h.guardFake.calls.contains("lowpowermode 0"))
        XCTAssertEqual(try h.store.loadState()?.lowPowerSetByUs, true)
    }

    func testReconcileDeadlineExpiresDuringArming() async throws {
        let h = Harness(); defer { h.home.destroy() }
        let now = h.clock.now
        try h.store.saveSession(Session(startedAt: now, endsAt: now.addingTimeInterval(2)))
        let gate = AsyncGate(); h.backstop.armGate = gate
        let m = h.makeManager()
        let task = Task { await m.reconcile() }
        await gate.waitUntilStarted()
        h.clock.advance(5)
        await gate.open(); await task.value
        XCTAssertFalse(h.guardFake.calls.contains("disablesleep 1"))
        XCTAssertFalse(h.guardFake.sleepDisabled)
    }

    func testReconcilePreservesBothRestoreFailures() async throws {
        let h = Harness(); defer { h.home.destroy() }
        var state = RuntimeState(); state.sleepDisabledByUs = true; state.savedMuted = false
        try h.store.saveState(state)
        h.guardFake.throwOn = ["pmset -g"]
        try h.audio.mute(); h.audio.throwOnApply = true
        let m = h.makeManager(); await m.reconcile()
        XCTAssertEqual(try h.store.loadState(), state)
        XCTAssertTrue((m.lastError ?? "").contains("audio"), m.lastError ?? "")
    }
}
