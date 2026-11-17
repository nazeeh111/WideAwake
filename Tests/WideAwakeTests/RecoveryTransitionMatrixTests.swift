import Foundation
import XCTest
@testable import WideAwake

@MainActor final class RecoveryTransitionMatrixTests: XCTestCase {
    func testStartHoldCompletionMatrixPreservesOtherGenerations() async throws {
        for ending in [false, true] {
            for failure in [false, true] {
                for corrupt in [false, true] {
                    let h = Harness(); defer { h.home.destroy() }
                    let gate = AsyncGate(); h.guardFake.sleepGate = gate
                    if failure { h.guardFake.throwAfterEffect = ["disablesleep 1"] }
                    let manager = h.makeManager()
                    let start = Task { await manager.start(duration: 600) }
                    await gate.waitUntilStarted()
                    let end: Task<EndOutcome, Never>?
                    if ending {
                        end = Task { await manager.end(reason: .user) }
                        await settleQueuedRequests()
                    } else { end = nil }
                    let bytes: Data
                    if corrupt {
                        bytes = Data("other corrupt generation".utf8)
                        try bytes.write(to: h.home.paths.sessionFile)
                    } else {
                        let other = Session(startedAt: h.clock.now, endsAt: h.clock.now.addingTimeInterval(3000))
                        try h.store.saveSession(other)
                        bytes = try Data(contentsOf: h.home.paths.sessionFile)
                    }
                    await gate.open()
                    let started = await start.value
                    XCTAssertNil(started, "end=\(ending), failure=\(failure), corrupt=\(corrupt)")
                    if let end {
                        let outcome = await end.value
                        XCTAssertEqual(outcome, corrupt ? .sessionUnreadable : .sessionChanged)
                        XCTAssertNotNil(manager.pendingEnd)
                    }
                    XCTAssertEqual(try Data(contentsOf: h.home.paths.sessionFile), bytes)
                    XCTAssertFalse(h.guardFake.calls.contains("disablesleep 0"))
                    XCTAssertEqual(try h.store.loadState()?.sleepDisabledByUs, true)
                    if failure { XCTAssertTrue((manager.lastError ?? "").contains("could not disable sleep")) }
                }
            }
        }
    }

    func testReconcileCompletionMatrixPreservesOtherGenerations() async throws {
        for gateHold in [false, true] {
            for failure in [false, true] {
                for ending in [false, true] {
                    for corrupt in [false, true] {
                        let h = Harness(); defer { h.home.destroy() }
                        let now = h.clock.now
                        try h.store.saveSession(Session(startedAt: now, endsAt: now.addingTimeInterval(600)))
                        let gate = AsyncGate()
                        if gateHold {
                            h.guardFake.sleepGate = gate
                            if failure { h.guardFake.throwAfterEffect = ["disablesleep 1"] }
                        } else { h.backstop.armGate = gate }
                        let manager = h.makeManager()
                        let work = Task { await manager.reconcile() }
                        await gate.waitUntilStarted()
                        if !gateHold && failure { h.backstop.failArm = true }
                        let end: Task<EndOutcome, Never>?
                        if ending { end = Task { await manager.end(reason: .user) }; await settleQueuedRequests() }
                        else { end = nil }
                        let bytes: Data
                        if corrupt {
                            bytes = Data("other corrupt generation".utf8)
                            try bytes.write(to: h.home.paths.sessionFile)
                        } else {
                            try h.store.saveSession(Session(startedAt: now, endsAt: now.addingTimeInterval(3000)))
                            bytes = try Data(contentsOf: h.home.paths.sessionFile)
                        }
                        await gate.open(); await work.value
                        if let end {
                            let outcome = await end.value
                            XCTAssertEqual(outcome, corrupt ? .sessionUnreadable : .sessionChanged)
                        }
                        XCTAssertEqual(try Data(contentsOf: h.home.paths.sessionFile), bytes)
                        XCTAssertFalse(h.guardFake.calls.contains("disablesleep 0"))
                        if !gateHold { XCTAssertFalse(h.guardFake.calls.contains("disablesleep 1")) }
                        if failure {
                            let expected = gateHold ? "could not re-apply sleep guard" : "could not arm recovery agent"
                            XCTAssertTrue((manager.lastError ?? "").contains(expected), "gateHold=\(gateHold), end=\(ending), corrupt=\(corrupt)")
                        }
                    }
                }
            }
        }
    }

    func testStartExpiryAtEachSuspensionNeverLeavesANewHold() async throws {
        for gateHold in [false, true] {
            for failure in [false, true] {
                let h = Harness(); defer { h.home.destroy() }
                let gate = AsyncGate()
                if gateHold { h.guardFake.sleepGate = gate } else { h.backstop.armGate = gate }
                if failure { h.guardFake.throwAfterEffect = ["disablesleep 1"] }
                let manager = h.makeManager()
                let work = Task { await manager.start(duration: 60) }
                await gate.waitUntilStarted(); h.clock.advance(120); await gate.open()
                let started = await work.value
                XCTAssertNil(started)
                XCTAssertFalse(h.guardFake.sleepDisabled)
                XCTAssertNil(try h.store.loadSession())
                XCTAssertEqual(try h.store.loadState(), .clean)
                if !gateHold { XCTAssertFalse(h.guardFake.calls.contains("disablesleep 1")) }
                if gateHold && failure { XCTAssertTrue((manager.lastError ?? "").contains("could not disable sleep")) }
            }
        }
    }

    func testUnknownLowPowerPreservesAllPendingJournalEntries() async throws {
        let h = Harness(); defer { h.home.destroy() }
        let manager = h.makeManager()
        _ = await manager.start(duration: 600)
        _ = await manager.setLowPower(true)
        try manager.journal { $0.displayRestoredUnderLowPower = 0.7 }
        h.display.brightness = 0.2
        let before = try Data(contentsOf: h.home.paths.stateFile)
        h.guardFake.throwOn = ["pmset -g custom"]
        let changed = await manager.setLowPower(false)
        XCTAssertFalse(changed)
        XCTAssertEqual(try Data(contentsOf: h.home.paths.stateFile), before)
        XCTAssertFalse(h.guardFake.calls.contains("lowpowermode 0"))
    }
    func testQueuedEndKeepsPrimaryAndCleanupFailureUntilRetry() async throws {
        let h = Harness(); defer { h.home.destroy() }
        let gate = AsyncGate(); h.guardFake.sleepGate = gate
        h.guardFake.throwAfterEffect = ["disablesleep 1"]
        h.guardFake.throwOn = ["disablesleep 0"]
        let manager = h.makeManager()
        let work = Task { await manager.start(duration: 600) }
        await gate.waitUntilStarted()
        let end = Task { await manager.end(reason: .user) }
        await settleQueuedRequests(); await gate.open()
        let started = await work.value; let outcome = await end.value
        XCTAssertNil(started)
        XCTAssertEqual(outcome, .incomplete(agentArmed: true))
        XCTAssertTrue((manager.lastError ?? "").contains("could not disable sleep"))
        XCTAssertTrue((manager.lastError ?? "").contains("could not restore sleep"))
        XCTAssertEqual(try h.store.loadState()?.sleepDisabledByUs, true)
        h.guardFake.throwOn = []
        let retried = await manager.end(reason: .user)
        XCTAssertEqual(retried, .restored)
        XCTAssertEqual(try h.store.loadState(), .clean)
        XCTAssertFalse(h.guardFake.sleepDisabled)
    }

    func testEndDuringFailedStartCleanupKeepsPrimaryAndOtherGeneration() async throws {
        let h = Harness(); defer { h.home.destroy() }
        let hold = AsyncGate(); let cleanupRead = AsyncGate()
        h.guardFake.sleepGate = hold
        h.guardFake.throwAfterEffect = ["disablesleep 1"]
        let manager = h.makeManager()
        let start = Task { await manager.start(duration: 600) }
        await hold.waitUntilStarted()
        h.guardFake.readGate = cleanupRead
        await hold.open(); await cleanupRead.waitUntilStarted()
        let end = Task { await manager.end(reason: .user) }
        await settleQueuedRequests()
        let replacement = Session(startedAt: h.clock.now, endsAt: h.clock.now.addingTimeInterval(3000))
        try h.store.saveSession(replacement)
        let bytes = try Data(contentsOf: h.home.paths.sessionFile)
        let arms = h.backstop.arms
        await cleanupRead.open(); _ = await start.value; let outcome = await end.value
        XCTAssertEqual(outcome, .sessionChanged)
        XCTAssertEqual(try Data(contentsOf: h.home.paths.sessionFile), bytes)
        XCTAssertTrue((manager.lastError ?? "").contains("could not disable sleep"))
        XCTAssertFalse(h.guardFake.calls.contains("disablesleep 0"))
        XCTAssertEqual(h.backstop.arms, arms)
        XCTAssertEqual(try h.store.loadState()?.sleepDisabledByUs, true)
    }

    func testEndDoesNotUndoOwnedSleepAfterAnotherSessionAppears() async throws {
        for corrupt in [false, true] {
            let h = Harness(); defer { h.home.destroy() }
            let manager = h.makeManager()
            _ = await manager.start(duration: 600)
            let gate = AsyncGate(); h.guardFake.readGate = gate
            let work = Task { await manager.end(reason: .user) }
            await gate.waitUntilStarted()
            let bytes: Data
            if corrupt {
                bytes = Data("other corrupt generation".utf8)
                try bytes.write(to: h.home.paths.sessionFile)
            } else {
                let other = Session(startedAt: h.clock.now, endsAt: h.clock.now.addingTimeInterval(3000))
                try h.store.saveSession(other)
                bytes = try Data(contentsOf: h.home.paths.sessionFile)
            }
            await gate.open(); let outcome = await work.value
            XCTAssertEqual(outcome, .sessionChanged)
            XCTAssertEqual(try Data(contentsOf: h.home.paths.sessionFile), bytes)
            XCTAssertFalse(h.guardFake.calls.contains("disablesleep 0"))
            XCTAssertEqual(try h.store.loadState()?.sleepDisabledByUs, true)
        }
    }

    func testEndDoesNotUndoLowPowerAfterAnotherSessionAppears() async throws {
        for corrupt in [false, true] {
            let h = Harness(); defer { h.home.destroy() }
            let manager = h.makeManager()
            _ = await manager.start(duration: 600)
            _ = await manager.setLowPower(true)
            let gate = AsyncGate(); h.guardFake.lowPowerReadGate = gate
            let work = Task { await manager.end(reason: .user) }
            await gate.waitUntilStarted()
            let bytes: Data
            if corrupt {
                bytes = Data("other corrupt generation".utf8)
                try bytes.write(to: h.home.paths.sessionFile)
            } else {
                try h.store.saveSession(Session(startedAt: h.clock.now, endsAt: h.clock.now.addingTimeInterval(3000)))
                bytes = try Data(contentsOf: h.home.paths.sessionFile)
            }
            await gate.open(); let outcome = await work.value
            XCTAssertEqual(outcome, .sessionChanged)
            XCTAssertEqual(try Data(contentsOf: h.home.paths.sessionFile), bytes)
            XCTAssertFalse(h.guardFake.calls.contains("lowpowermode 0"))
            XCTAssertEqual(try h.store.loadState()?.lowPowerSetByUs, true)
        }
    }

    func testNormalReleaseDoesNotUndoAfterSessionChangesDuringObservation() async throws {
        let h = Harness(); defer { h.home.destroy() }
        let manager = h.makeManager()
        _ = await manager.start(duration: 600)
        _ = await manager.setLowPower(true)
        let gate = AsyncGate(); h.guardFake.lowPowerReadGate = gate
        let work = Task { await manager.setLowPower(false) }
        await gate.waitUntilStarted()
        let bytes = Data("changed generation".utf8)
        try bytes.write(to: h.home.paths.sessionFile)
        await gate.open(); let changed = await work.value
        XCTAssertFalse(changed)
        XCTAssertFalse(h.guardFake.calls.contains("lowpowermode 0"))
        XCTAssertEqual(try h.store.loadState()?.lowPowerSetByUs, true)
        XCTAssertEqual(try Data(contentsOf: h.home.paths.sessionFile), bytes)
    }

    func testLowPowerEnableFinishingAfterDeadlineIsNotReportedAsActive() async throws {
        for failure in [false, true] {
            let h = Harness(); defer { h.home.destroy() }
            let manager = h.makeManager()
            _ = await manager.start(duration: 60)
            let gate = AsyncGate(); h.guardFake.lowPowerGate = gate
            if failure { h.guardFake.throwAfterEffect = ["lowpowermode 1"] }
            let work = Task { await manager.setLowPower(true) }
            await gate.waitUntilStarted(); h.clock.advance(120); await gate.open()
            let changed = await work.value
            XCTAssertFalse(changed)
            XCTAssertFalse(h.guardFake.lowPowerOn)
            XCTAssertFalse(h.guardFake.sleepDisabled)
            XCTAssertNil(try h.store.loadSession())
            XCTAssertEqual(try h.store.loadState(), .clean)
            if failure { XCTAssertTrue((manager.lastError ?? "").contains("could not enable low power")) }
        }
    }

}
