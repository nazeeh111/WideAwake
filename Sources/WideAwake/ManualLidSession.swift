import Foundation

/// One selected duration, one close/open cycle. No polling or app detection.
@MainActor
final class ManualLidSession {
    enum Phase: Equatable { case idle, arming, ready, running, stopping, failed(String) }
    private(set) var steps = 0
    private(set) var phase: Phase = .idle
    var onChange: (() -> Void)?
    private let manager: SessionManager
    private var revision = 0
    private var closed = false
    var settings: SliderSettings { manager.config.sliderSettings }
    var seconds: TimeInterval { settings.seconds(at: steps) }
    var armingWindow: TimeInterval { min(6 * 3600, settings.maximumSeconds) }
    func applySettings(_ settings: SliderSettings) throws {
        try settings.validate()
        guard !manager.isActive, !manager.state.isDirty, phase != .arming, phase != .stopping else {
            throw SettingsError.invalid("Cancel the current timer before changing the slider.")
        }
        var updated = manager.config
        updated.sliderStepMinutes = settings.stepMinutes
        updated.maxDuration = settings.maximumSeconds
        try manager.store.saveConfig(updated)
        manager.config = updated
        steps = 0
        onChange?()
    }

    init(manager: SessionManager) {
        self.manager = manager
        manager.onEndCompleted = { [weak self] outcome in self?.ended(outcome) }
    }
    private func ended(_ outcome: EndOutcome) {
        if phase != .stopping { revision += 1 }
        steps = 0
        if outcome == .restored { phase = .idle }
        else { phase = .failed(manager.lastError ?? "Restoration is pending. Leave WideAwake running.") }
        onChange?()
    }
    func prepare(lidClosed: Bool) async {
        closed = lidClosed
        if lidClosed, let s = manager.session {
            steps = min(settings.stepCount, max(1, Int(ceil(s.remaining(at: Date()) / settings.stepSeconds))))
            phase = .running
        } else {
            if manager.isActive || manager.state.isDirty {
                let outcome = await manager.end(reason: .user)
                ended(outcome)
            } else { steps = 0; phase = .idle }
        }
        onChange?()
    }
    func choose(_ rawSteps: Int) async {
        revision += 1
        let ticket = revision
        steps = min(settings.stepCount, max(0, rawSteps))
        guard steps > 0 else { await stop(); return }
        phase = .arming; onChange?()
        let ok: Bool
        let prearm = closed ? seconds : armingWindow
        if manager.isActive { ok = await manager.resetDuration(prearm) }
        else { ok = await manager.start(duration: prearm) != nil }
        guard revision == ticket else { return }
        if ok, manager.isActive { phase = closed ? .running : .ready }
        else { await failSafely(manager.lastError ?? "Could not start. Try again.") }
        onChange?()
    }
    func lidChanged(_ isClosed: Bool) async {
        guard isClosed != closed else { return }
        closed = isClosed
        if !isClosed {
            if steps > 0 || manager.isActive || manager.state.isDirty { await stop() }
            return
        }
        guard steps > 0, manager.isActive else { return }
        let ticket = revision
        let ok = await manager.resetDuration(seconds)
        guard revision == ticket, closed else { return }
        if ok { phase = .running }
        else { await failSafely(manager.lastError ?? "Timer could not be updated.") }
        onChange?()
    }
    private func failSafely(_ message: String) async {
        await stop()
        guard steps == 0, phase == .idle else { return }
        phase = .failed(message)
        onChange?()
    }
    func stop() async {
        revision += 1
        let ticket = revision
        steps = 0
        if !manager.isActive && !manager.state.isDirty { phase = .idle; onChange?(); return }
        phase = .stopping; onChange?()
        let outcome = await manager.end(reason: .user)
        guard revision == ticket else { return }
        if outcome == .restored { phase = .idle }
        else { phase = .failed(manager.lastError ?? "Restoration is pending. Leave WideAwake running.") }
        onChange?()
    }
}
