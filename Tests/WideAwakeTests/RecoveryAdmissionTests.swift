import Foundation
import XCTest
@testable import WideAwake

@MainActor final class RecoveryAdmissionTests: XCTestCase {
    func testChangedDiskSessionRefusesDurationChangeBeforeArming() async throws {
        let h = Harness(); defer { h.home.destroy() }
        let manager = h.makeManager()
        let started = await manager.start(duration: 600)
        let current = try XCTUnwrap(started)
        var other = current; other.endsAt = other.endsAt.addingTimeInterval(30)
        try h.store.saveSession(other)
        let before = try Data(contentsOf: h.home.paths.sessionFile)
        let arms = h.backstop.arms
        await manager.extend(by: 600)
        XCTAssertEqual(try Data(contentsOf: h.home.paths.sessionFile), before)
        XCTAssertEqual(manager.session, current)
        XCTAssertEqual(h.backstop.arms, arms)
    }

    func testChangedDiskSessionDuringArmingIsNotOverwritten() async throws {
        let h = Harness(); defer { h.home.destroy() }
        let manager = h.makeManager()
        let started = await manager.start(duration: 600)
        var other = try XCTUnwrap(started)
        let gate = AsyncGate(); h.backstop.armGate = gate
        let task = Task { await manager.extend(by: 600) }
        await gate.waitUntilStarted()
        other.endsAt = other.endsAt.addingTimeInterval(30)
        try h.store.saveSession(other)
        let before = try Data(contentsOf: h.home.paths.sessionFile)
        await gate.open(); await task.value
        XCTAssertEqual(try Data(contentsOf: h.home.paths.sessionFile), before)
        XCTAssertEqual(try h.store.loadSession(), other)
    }

    func testExtendThatExpiresWhileArmingDoesNotRewriteSession() async throws {
        let h = Harness(); defer { h.home.destroy() }
        let manager = h.makeManager()
        let started = await manager.start(duration: 2)
        let current = try XCTUnwrap(started)
        let gate = AsyncGate(); h.backstop.armGate = gate
        let task = Task { await manager.extend(by: 600) }
        await gate.waitUntilStarted(); h.clock.advance(65); await gate.open(); await task.value
        XCTAssertEqual(try h.store.loadSession(), current)
        XCTAssertEqual(manager.session, current)
    }

    func testStartPreservesSessionCreatedDuringObservation() async throws {
        let h = Harness(); defer { h.home.destroy() }
        let gate = AsyncGate(); h.guardFake.readGate = gate
        let manager = h.makeManager()
        let task = Task { await manager.start(duration: 600) }
        await gate.waitUntilStarted()
        let bytes = Data("external generation".utf8)
        try bytes.write(to: h.home.paths.sessionFile)
        await gate.open(); let started = await task.value
        XCTAssertNil(started)
        XCTAssertEqual(try Data(contentsOf: h.home.paths.sessionFile), bytes)
        XCTAssertFalse(h.guardFake.calls.contains("disablesleep 1"))
        XCTAssertEqual(h.backstop.arms, 0)
    }

    func testStartDoesNotHoldAfterSessionChangesDuringArming() async throws {
        let h = Harness(); defer { h.home.destroy() }
        let gate = AsyncGate(); h.backstop.armGate = gate
        let manager = h.makeManager()
        let task = Task { await manager.start(duration: 600) }
        await gate.waitUntilStarted()
        let bytes = Data("external generation".utf8)
        try bytes.write(to: h.home.paths.sessionFile)
        await gate.open(); let started = await task.value
        XCTAssertNil(started)
        XCTAssertEqual(try Data(contentsOf: h.home.paths.sessionFile), bytes)
        XCTAssertFalse(h.guardFake.calls.contains("disablesleep 1"))
        XCTAssertTrue(try XCTUnwrap(try h.store.loadState()).sleepDisabledByUs)
    }

    func testReconcileDoesNotHoldAfterSessionChangesDuringArming() async throws {
        let h = Harness(); defer { h.home.destroy() }
        let now = h.clock.now
        try h.store.saveSession(Session(startedAt: now, endsAt: now.addingTimeInterval(60)))
        let gate = AsyncGate(); h.backstop.armGate = gate
        let manager = h.makeManager()
        let task = Task { await manager.reconcile() }
        await gate.waitUntilStarted()
        let bytes = Data("external generation".utf8)
        try bytes.write(to: h.home.paths.sessionFile)
        await gate.open(); await task.value
        XCTAssertEqual(try Data(contentsOf: h.home.paths.sessionFile), bytes)
        XCTAssertFalse(h.guardFake.calls.contains("disablesleep 1"))
        XCTAssertNil(manager.session)
    }

    func testPendingUnreadableEndPreventsLowPowerEnable() async throws {
        let h = Harness(); defer { h.home.destroy() }
        let manager = h.makeManager()
        _ = await manager.start(duration: 600)
        let bytes = Data("unreadable".utf8)
        try bytes.write(to: h.home.paths.sessionFile)
        let outcome = await manager.end(reason: .user)
        XCTAssertEqual(outcome, .sessionUnreadable)
        let changed = await manager.setLowPower(true)
        XCTAssertFalse(changed)
        XCTAssertFalse(h.guardFake.calls.contains("lowpowermode 1"))
        XCTAssertEqual(try Data(contentsOf: h.home.paths.sessionFile), bytes)
    }

    func testReconcileThatExpiresDuringObservationDoesNotArmOrHold() async throws {
        let h = Harness(); defer { h.home.destroy() }
        let now = h.clock.now
        try h.store.saveSession(Session(startedAt: now, endsAt: now.addingTimeInterval(2)))
        let gate = AsyncGate(); h.guardFake.readGate = gate
        let manager = h.makeManager()
        let task = Task { await manager.reconcile() }
        await gate.waitUntilStarted(); h.clock.advance(5); await gate.open(); await task.value
        XCTAssertFalse(h.guardFake.calls.contains("disablesleep 1"))
        XCTAssertEqual(h.backstop.arms, 0)
        XCTAssertNil(try h.store.loadSession())
    }

    func testLowPowerPrimaryAndCleanupFailuresRemainVisible() async throws {
        let h = Harness(); defer { h.home.destroy() }
        let manager = h.makeManager()
        _ = await manager.start(duration: 600)
        h.guardFake.throwAfterEffect = ["lowpowermode 1"]
        h.guardFake.throwOn = ["lowpowermode 0"]
        let changed = await manager.setLowPower(true)
        XCTAssertFalse(changed)
        XCTAssertTrue((manager.lastError ?? "").contains("enable low power"))
        XCTAssertTrue((manager.lastError ?? "").contains("disable low power"))
        XCTAssertEqual(try h.store.loadState()?.lowPowerSetByUs, true)
    }
}
