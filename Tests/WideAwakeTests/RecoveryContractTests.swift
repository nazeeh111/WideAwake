import Darwin
import Foundation
import XCTest
@testable import WideAwake

@MainActor
final class RecoveryContractTests: XCTestCase {
    func testSymlinkJournalIsRefusedWithoutChangingTarget() throws {
        let home = TempHome(); defer { home.destroy() }
        let target = home.root.appendingPathComponent("external.json")
        let bytes = Data("{}".utf8)
        try bytes.write(to: target)
        try FileManager.default.createSymbolicLink(at: home.paths.stateFile, withDestinationURL: target)
        XCTAssertThrowsError(try Store(paths: home.paths).loadState())
        XCTAssertEqual(try Data(contentsOf: target), bytes)
    }

    func testOversizedJournalIsRefusedWithoutChangingBytes() throws {
        let home = TempHome(); defer { home.destroy() }
        let bytes = Data(repeating: 32, count: 8 * 1024 * 1024 + 1)
        try bytes.write(to: home.paths.stateFile)
        XCTAssertThrowsError(try Store(paths: home.paths).loadState())
        XCTAssertEqual(try Data(contentsOf: home.paths.stateFile), bytes)
    }

    func testCapturedBytesRemainUsableAfterPathReplacement() throws {
        let home = TempHome(); defer { home.destroy() }
        let store = Store(paths: home.paths)
        var first = RuntimeState(); first.sleepDisabledByUs = true
        try store.saveState(first)
        let captured = try XCTUnwrap(store.capture(from: home.paths.stateFile))
        try store.saveState(.clean)
        XCTAssertEqual(try Store.makeDecoder().decode(RuntimeState.self, from: captured), first)
        XCTAssertEqual(try store.loadState(), .clean)
    }

    func testFailedRecoveryRetainsOwnershipAndRetryClearsIt() async throws {
        let h = Harness(); defer { h.home.destroy() }
        var state = RuntimeState(); state.sleepDisabledByUs = true
        try h.store.saveState(state); h.guardFake.sleepDisabled = true
        h.guardFake.throwOn = ["disablesleep 0"]
        let manager = h.makeManager()
        let failed = await manager.end(reason: .quit)
        XCTAssertEqual(failed, .incomplete(agentArmed: true))
        XCTAssertTrue(h.guardFake.sleepDisabled)
        XCTAssertEqual(try h.store.loadState(), state)
        h.guardFake.throwOn = []
        let retried = await manager.end(reason: .user)
        XCTAssertEqual(retried, .restored)
        XCTAssertFalse(h.guardFake.sleepDisabled)
        XCTAssertEqual(try h.store.loadState(), .clean)
        XCTAssertNil(manager.lastError)
        XCTAssertEqual(h.guardFake.calls.filter { $0 != "pmset -g" }, ["disablesleep 0", "disablesleep 0"])
    }

    func testReconcileDoesNotClearUnownedSleepSetting() async throws {
        let h = Harness(); defer { h.home.destroy() }
        h.guardFake.sleepDisabled = true
        let manager = h.makeManager()
        await manager.reconcile()
        XCTAssertTrue(h.guardFake.sleepDisabled)
        XCTAssertFalse(h.guardFake.calls.contains("disablesleep 0"))
    }

    func testStartRefusesUnownedPreexistingSleepSetting() async throws {
        let h = Harness(); defer { h.home.destroy() }
        h.guardFake.sleepDisabled = true
        let manager = h.makeManager()
        let session = await manager.start(duration: 60)
        XCTAssertNil(session)
        XCTAssertTrue(h.guardFake.sleepDisabled)
        XCTAssertFalse(h.guardFake.calls.contains("disablesleep 1"))
        XCTAssertNil(try h.store.loadSession())
    }

    func testEndDuringReconcilePreventsLateHold() async throws {
        let h = Harness(); defer { h.home.destroy() }
        let now = h.clock.now
        try h.store.saveSession(Session(startedAt: now, endsAt: now.addingTimeInterval(3600)))
        var state = RuntimeState(); state.sleepDisabledByUs = true
        try h.store.saveState(state)
        h.guardFake.sleepDisabled = true
        let gate = AsyncGate(); h.backstop.armGate = gate
        let manager = h.makeManager()
        let reconcile = Task { await manager.reconcile() }
        await gate.waitUntilStarted()
        let end = Task { await manager.end(reason: .user) }
        await settleQueuedRequests()
        await gate.open()
        await reconcile.value
        let outcome = await end.value
        XCTAssertEqual(outcome, .restored)
        XCTAssertFalse(h.guardFake.calls.contains("disablesleep 1"))
        XCTAssertFalse(h.guardFake.sleepDisabled)
        XCTAssertEqual(try h.store.loadState(), .clean)
    }

    func testUnknownSleepSettingRefusesStartWithoutWrites() async throws {
        let h = Harness(); defer { h.home.destroy() }
        h.guardFake.throwOn = ["pmset -g"]
        let manager = h.makeManager()
        let session = await manager.start(duration: 60)
        XCTAssertNil(session)
        XCTAssertNil(try h.store.loadSession())
        XCTAssertEqual(h.guardFake.calls, ["pmset -g"])
        XCTAssertEqual(h.backstop.arms, 0)
        XCTAssertTrue((manager.lastError ?? "").contains("observe"))
    }

    func testLiveSessionWithoutJournalDoesNotClaimObservedDisabledSleep() async throws {
        let h = Harness(); defer { h.home.destroy() }
        let now = h.clock.now
        let session = Session(startedAt: now, endsAt: now.addingTimeInterval(3600))
        try h.store.saveSession(session)
        h.guardFake.sleepDisabled = true
        let manager = h.makeManager()
        await manager.reconcile()
        XCTAssertNil(manager.session)
        XCTAssertEqual(try h.store.loadSession(), session)
        XCTAssertNil(try h.store.loadState())
        XCTAssertEqual(h.guardFake.calls, ["pmset -g"])
        XCTAssertEqual(h.backstop.arms, 0)
        XCTAssertTrue(h.guardFake.sleepDisabled)
        XCTAssertNotNil(manager.lastError)
    }

    func testReconcileDoesNotReassertAnObservedChangedSleepSetting() async throws {
        let h = Harness(); defer { h.home.destroy() }
        let now = h.clock.now
        let session = Session(startedAt: now, endsAt: now.addingTimeInterval(3600))
        try h.store.saveSession(session)
        var state = RuntimeState(); state.sleepDisabledByUs = true
        try h.store.saveState(state)
        h.guardFake.sleepDisabled = false
        let manager = h.makeManager()
        await manager.reconcile()
        XCTAssertFalse(h.guardFake.sleepDisabled)
        XCTAssertFalse(h.guardFake.calls.contains("disablesleep 1"))
        XCTAssertEqual(try h.store.loadSession(), session)
        XCTAssertEqual(try h.store.loadState(), state)
    }

    func testStartPreservesUnreadableExistingSession() async throws {
        let h = Harness(); defer { h.home.destroy() }
        let bytes = Data("{broken".utf8)
        try bytes.write(to: h.home.paths.sessionFile)
        let manager = h.makeManager()
        let created = await manager.start(duration: 60)
        XCTAssertNil(created)
        XCTAssertEqual(try Data(contentsOf: h.home.paths.sessionFile), bytes)
        XCTAssertFalse(h.guardFake.calls.contains("disablesleep 1"))
    }

    func testUnreadableSessionRefusesRecoveryUntilRepaired() async throws {
        let h = Harness(); defer { h.home.destroy() }
        let bytes = Data("{broken".utf8)
        try bytes.write(to: h.home.paths.sessionFile)
        var state = RuntimeState(); state.sleepDisabledByUs = true
        try h.store.saveState(state); h.guardFake.sleepDisabled = true
        let manager = h.makeManager()
        await manager.reconcile()
        XCTAssertEqual(try Data(contentsOf: h.home.paths.sessionFile), bytes)
        XCTAssertEqual(h.guardFake.calls, [])
        let refused = await manager.end(reason: .quit)
        XCTAssertEqual(refused, .sessionUnreadable)
        XCTAssertEqual(try Data(contentsOf: h.home.paths.sessionFile), bytes)
        XCTAssertEqual(try h.store.loadState(), state)
        XCTAssertEqual(h.guardFake.calls, [])
        let now = h.clock.now
        try h.store.saveSession(Session(startedAt: now, endsAt: now.addingTimeInterval(60)))
        let stillUnowned = await manager.end(reason: .user)
        XCTAssertEqual(stillUnowned, .sessionChanged)
        XCTAssertEqual(h.guardFake.calls, [])
        // Explicit synthetic user resolution: move the unowned record aside.
        let aside = h.home.root.appendingPathComponent("resolved-session.json")
        try FileManager.default.moveItem(at: h.home.paths.sessionFile, to: aside)
        let recovered = await manager.end(reason: .user)
        XCTAssertEqual(recovered, .restored)
        XCTAssertTrue(FileManager.default.fileExists(atPath: aside.path))
        XCTAssertNil(try h.store.loadSession())
        XCTAssertEqual(try h.store.loadState(), .clean)
        XCTAssertFalse(h.guardFake.sleepDisabled)
    }

    func testJournalWriteFailureAfterEffectKeepsPriorEvidence() async throws {
        let h = Harness()
        let root = h.home.root
        let backup = root.appendingPathExtension("saved")
        defer {
            h.home.destroy()
            try? FileManager.default.removeItem(at: backup)
        }
        var state = RuntimeState(); state.savedDisplayBrightness = 0.8
        try h.store.saveState(state)
        h.display.brightness = 0
        h.display.onSet = { _ in
            try! FileManager.default.moveItem(at: root, to: backup)
            FileManager.default.createFile(atPath: root.path, contents: Data())
        }
        let manager = h.makeManager()
        let outcome = await manager.end(reason: .user)
        XCTAssertEqual(outcome, .incomplete(agentArmed: true))
        XCTAssertEqual(h.display.brightness, 0.8, accuracy: 0.0001)
        XCTAssertEqual(try Store(paths: Paths(root: backup)).loadState(), state)
        XCTAssertEqual(manager.state, state)
        XCTAssertTrue((manager.lastError ?? "").contains("journal"))
        try FileManager.default.removeItem(at: root)
        try FileManager.default.moveItem(at: backup, to: root)
        h.display.onSet = nil
        let retry = await manager.end(reason: .user)
        XCTAssertEqual(retry, .restored)
        XCTAssertEqual(try h.store.loadState(), .clean)
        XCTAssertEqual(h.display.sets, [0.8])
    }

    func testMultipleRestoreFailuresRemainVisibleAndRetryable() async throws {
        let h = Harness(); defer { h.home.destroy() }
        var state = RuntimeState(); state.sleepDisabledByUs = true; state.savedMuted = false
        try h.store.saveState(state)
        h.guardFake.sleepDisabled = true
        h.guardFake.throwOn = ["disablesleep 0"]
        try h.audio.mute(); h.audio.throwOnApply = true
        let manager = h.makeManager()
        let outcome = await manager.end(reason: .user)
        XCTAssertEqual(outcome, .incomplete(agentArmed: true))
        XCTAssertTrue((manager.lastError ?? "").contains("sleep"))
        XCTAssertTrue((manager.lastError ?? "").contains("audio"))
        XCTAssertEqual(try h.store.loadState(), state)
    }

    func testAlreadyRestoredSettingsAreNotWrittenAgain() async throws {
        let h = Harness(); defer { h.home.destroy() }
        var state = RuntimeState(); state.sleepDisabledByUs = true; state.lowPowerSetByUs = true
        try h.store.saveState(state)
        h.guardFake.sleepDisabled = false; h.guardFake.lowPowerOn = false
        let manager = h.makeManager()
        let outcome = await manager.end(reason: .user)
        XCTAssertEqual(outcome, .restored)
        XCTAssertFalse(h.guardFake.calls.contains("disablesleep 0"))
        XCTAssertFalse(h.guardFake.calls.contains("lowpowermode 0"))
        XCTAssertEqual(try h.store.loadState(), .clean)
    }

    func testUnknownOwnedSleepIsNotMutated() async throws {
        let h = Harness(); defer { h.home.destroy() }
        var state = RuntimeState(); state.sleepDisabledByUs = true
        try h.store.saveState(state)
        h.guardFake.throwOn = ["pmset -g"]
        let manager = h.makeManager()
        let outcome = await manager.end(reason: .user)
        XCTAssertEqual(outcome, .incomplete(agentArmed: true))
        XCTAssertFalse(h.guardFake.calls.contains("disablesleep 0"))
        XCTAssertEqual(try h.store.loadState(), state)
    }

    func testFIFOJournalIsRefused() throws {
        let home = TempHome(); defer { home.destroy() }
        XCTAssertEqual(mkfifo(home.paths.stateFile.path, 0o600), 0)
        XCTAssertThrowsError(try Store(paths: home.paths).loadState())
    }

    func testRecoveryPreservesObservedBrightnessChanges() async throws {
        let h = Harness(); defer { h.home.destroy() }
        var state = RuntimeState()
        state.savedDisplayBrightness = 0.8
        state.savedKeyboardBrightness = 0.7
        try h.store.saveState(state)
        h.display.brightness = 0.25
        h.keyboard.brightness = 0.35
        let manager = h.makeManager()
        let outcome = await manager.end(reason: .user)
        XCTAssertEqual(outcome, .restored)
        XCTAssertEqual(h.display.brightness, 0.25, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(h.keyboard.brightness), 0.35, accuracy: 0.0001)
        XCTAssertEqual(try h.store.loadState(), .clean)
    }

    func testDelayedRestoreDoesNotOverwriteLaterBrightnessChanges() async throws {
        let h = Harness(); defer { h.home.destroy() }
        var state = RuntimeState()
        state.savedDisplayBrightness = 0.8
        state.savedKeyboardBrightness = 0.7
        try h.store.saveState(state)
        h.display.brightness = 0
        h.keyboard.brightness = 0
        let manager = h.makeManager(reassertDelay: .milliseconds(100))
        let outcome = await manager.end(reason: .user)
        XCTAssertEqual(outcome, .restored)
        h.display.brightness = 0.25
        h.keyboard.brightness = 0.35
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(h.display.brightness, 0.25, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(h.keyboard.brightness), 0.35, accuracy: 0.0001)
    }

    func testRecoveryPreservesVolumeAndUserUnmute() async throws {
        let h = Harness(); defer { h.home.destroy() }
        var state = RuntimeState()
        state.savedOutputVolume = 0.2
        state.savedMuted = true
        try h.store.saveState(state)
        let manager = h.makeManager()
        let outcome = await manager.end(reason: .user)
        XCTAssertEqual(outcome, .restored)
        XCTAssertEqual(h.audio.volume, 0.6, accuracy: 0.0001)
        XCTAssertFalse(h.audio.muted)
        XCTAssertEqual(try h.store.loadState(), .clean)
    }
}
