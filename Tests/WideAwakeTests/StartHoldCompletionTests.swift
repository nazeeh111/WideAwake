import Foundation
import XCTest
@testable import WideAwake

@MainActor final class StartHoldCompletionTests: XCTestCase {
    func testReplacedRecordSurvivesHoldCompletion() async throws {
        for fails in [false, true] {
            let h = Harness(); defer { h.home.destroy() }
            let m = h.makeManager()
            let gate = AsyncGate()
            h.guardFake.sleepGate = gate
            if fails { h.guardFake.throwAfterEffect = ["disablesleep 1"] }
            let work = Task { await m.start(duration: 600) }
            await gate.waitUntilStarted()
            let another = Session(startedAt: h.clock.now, endsAt: h.clock.now.addingTimeInterval(3000))
            try h.store.saveSession(another)
            let bytes = try Data(contentsOf: h.home.paths.sessionFile)
            await gate.open()
            let returned = await work.value
            XCTAssertNil(returned, "Old generation surfaced after hold, fails=\(fails)")
            XCTAssertEqual(try? Data(contentsOf: h.home.paths.sessionFile), bytes, "Replacement lost, fails=\(fails)")
            XCTAssertEqual(try h.store.loadState()?.sleepDisabledByUs, true)
            XCTAssertTrue(h.guardFake.sleepDisabled)
            XCTAssertFalse(h.guardFake.calls.contains("disablesleep 0"))
            if fails { XCTAssertTrue((m.lastError ?? "").contains("could not disable sleep")) }
        }
    }
    func testStartExpiresWhileArming() async throws {
        let h = Harness(); defer { h.home.destroy() }
        let m = h.makeManager()
        let gate = AsyncGate(); h.backstop.armGate = gate
        let work = Task { await m.start(duration: 60) }
        await gate.waitUntilStarted()
        h.clock.advance(120)
        await gate.open()
        let returned = await work.value
        XCTAssertNil(returned)
        XCTAssertFalse(h.guardFake.calls.contains("disablesleep 1"))
        XCTAssertNil(try h.store.loadSession())
        XCTAssertEqual(try h.store.loadState(), .clean)
    }
    func testStartExpiresDuringHoldAndUndoesOnlyItsOwnEffect() async throws {
        let h = Harness(); defer { h.home.destroy() }
        let m = h.makeManager()
        let gate = AsyncGate(); h.guardFake.sleepGate = gate
        let work = Task { await m.start(duration: 60) }
        await gate.waitUntilStarted(); h.clock.advance(120); await gate.open()
        let returned = await work.value
        XCTAssertNil(returned)
        XCTAssertFalse(h.guardFake.sleepDisabled)
        XCTAssertEqual(try h.store.loadState(), .clean)
        XCTAssertNil(try h.store.loadSession())
    }

    func testFailedStartDoesNotUndoEarlierRecoveryOwnership() async throws {
        let h = Harness(); defer { h.home.destroy() }
        var previous = RuntimeState(); previous.lowPowerSetByUs = true
        try h.store.saveState(previous); h.guardFake.lowPowerOn = true
        h.guardFake.throwAfterEffect = ["disablesleep 1"]
        let m = h.makeManager()
        let returned = await m.start(duration: 600)
        XCTAssertNil(returned)
        XCTAssertEqual(try h.store.loadState(), previous)
        XCTAssertTrue(h.guardFake.lowPowerOn)
        XCTAssertFalse(h.guardFake.calls.contains("lowpowermode 0"))
        XCTAssertFalse(h.guardFake.sleepDisabled)
        XCTAssertNil(try h.store.loadSession())
    }

    func testFailedStartPreservesPriorOwnedSleep() async throws {
        let h = Harness(); defer { h.home.destroy() }
        var previous = RuntimeState(); previous.sleepDisabledByUs = true
        try h.store.saveState(previous); h.guardFake.sleepDisabled = true
        h.guardFake.throwAfterEffect = ["disablesleep 1"]
        let m = h.makeManager()
        let returned = await m.start(duration: 600)
        XCTAssertNil(returned)
        XCTAssertEqual(try h.store.loadState(), previous)
        XCTAssertTrue(h.guardFake.sleepDisabled)
        XCTAssertFalse(h.guardFake.calls.contains("disablesleep 0"))
        XCTAssertNil(try h.store.loadSession())
    }

    func testFailedCleanupAndAgentLeavePendingOwnershipForRetry() async throws {
        let h = Harness(); defer { h.home.destroy() }
        let gate = AsyncGate(); h.guardFake.sleepGate = gate
        h.guardFake.throwAfterEffect = ["disablesleep 1"]
        h.guardFake.throwOn = ["disablesleep 0"]
        let m = h.makeManager()
        let work = Task { await m.start(duration: 600) }
        await gate.waitUntilStarted(); h.backstop.failArm = true; await gate.open()
        let returned = await work.value
        XCTAssertNil(returned)
        XCTAssertEqual(m.pendingEnd, .startFailed)
        XCTAssertEqual(try h.store.loadState()?.sleepDisabledByUs, true)
        XCTAssertNil(try h.store.loadSession())
        XCTAssertTrue((m.lastError ?? "").contains("cleanup"))
        XCTAssertTrue((m.lastError ?? "").contains("recovery agent"))
        h.guardFake.throwOn = []; h.backstop.failArm = false
        let outcome = await m.end(reason: .user)
        XCTAssertEqual(outcome, .restored)
        XCTAssertFalse(h.guardFake.sleepDisabled)
        XCTAssertEqual(try h.store.loadState(), .clean)
    }

    func testQueuedEndDoesNotDeleteSessionReplacedDuringHold() async throws {
        let h = Harness(); defer { h.home.destroy() }
        let gate = AsyncGate(); h.guardFake.sleepGate = gate
        let m = h.makeManager()
        let work = Task { await m.start(duration: 600) }
        await gate.waitUntilStarted()
        let ending = Task { await m.end(reason: .user) }
        await settleQueuedRequests()
        let other = Session(startedAt: h.clock.now, endsAt: h.clock.now.addingTimeInterval(3000))
        try h.store.saveSession(other)
        let bytes = try Data(contentsOf: h.home.paths.sessionFile)
        await gate.open(); let started = await work.value; let outcome = await ending.value
        XCTAssertNil(started)
        XCTAssertEqual(outcome, .sessionChanged)
        XCTAssertEqual(try Data(contentsOf: h.home.paths.sessionFile), bytes)
        XCTAssertFalse(h.guardFake.calls.contains("disablesleep 0"))
        XCTAssertEqual(try h.store.loadState()?.sleepDisabledByUs, true)
        let aside = h.home.root.appendingPathComponent("other-session.json")
        try FileManager.default.moveItem(at: h.home.paths.sessionFile, to: aside)
        let retried = await m.end(reason: .user)
        XCTAssertEqual(retried, .restored)
        XCTAssertEqual(try Data(contentsOf: aside), bytes)
        XCTAssertEqual(try h.store.loadState(), .clean)
        XCTAssertFalse(h.guardFake.sleepDisabled)
    }

}
