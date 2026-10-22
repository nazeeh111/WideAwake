import Foundation

/// Hardware events only. No app, file, network, or browser monitoring.
@MainActor
final class AppServices {
    private let notifier: any Notifying
    private let display: any DisplayDimming
    private let keyboard: any KeyboardBacklighting
    private let sampler: BrightnessSampler
    private let lid = LidObserver()
    private let power = PowerMonitor()
    private weak var manager: SessionManager?
    private var actions: LidActions?
    private var floors: FloorRuleDriver?
    private var lidTask: Task<Void, Never>?
    private var powerTask: Task<Void, Never>?
    private var sampleTimer: Timer?
    private(set) var running = false

    init(paths: Paths, notifier: any Notifying, audio: any AudioControlling, processControl: any ProcessSignaling, display: any DisplayDimming, keyboard: any KeyboardBacklighting) {
        self.notifier = notifier; self.display = display; self.keyboard = keyboard
        sampler = BrightnessSampler(display: display, keyboard: keyboard, idleSeconds: { UserInput.secondsSinceLastInput() })
    }
    func start(for manager: SessionManager) {
        guard !running else { return }
        running = true; self.manager = manager
        actions = LidActions(manager: manager, display: display, keyboard: keyboard, sampler: sampler)
        floors = FloorRuleDriver(manager: manager, notifier: notifier)
        manager.willEnableLowPower = { [weak self] in self?.sample() }
        sampler.displayHeld = { [weak manager] in manager?.state.lowPowerSetByUs ?? false }
        lid.onChange = { [weak self] closed in self?.lidChanged(closed) }; lid.start()
        power.onChange = { [weak self] in self?.powerChanged() }; power.start()
        sample()
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in Task { @MainActor in self?.sample() } }
        t.tolerance = 5; RunLoop.main.add(t, forMode: .common); sampleTimer = t
        powerChanged()
    }
    func stop() {
        running = false; lid.stop(); power.stop(); sampleTimer?.invalidate(); sampleTimer = nil
        lidTask?.cancel(); powerTask?.cancel(); lidTask = nil; powerTask = nil
        actions = nil; floors = nil
    }
    func logStartupSnapshot() {
        Log.info("startup lid \(LidObserver.readClamshellState().map { $0 ? "closed" : "open" } ?? "unavailable")")
    }
    private func sample() {
        guard running, !lid.isClosed else { return }; sampler.sample()
    }
    private func lidChanged(_ closed: Bool) {
        let previous = lidTask
        lidTask = Task { [weak self] in
            await previous?.value
            guard let self, self.running, !Task.isCancelled else { return }
            if closed { await self.actions?.onClose() } else { await self.actions?.onOpen() }
            guard self.running, !Task.isCancelled else { return }
            self.powerChanged()
        }
    }
    private func powerChanged() {
        let previous = powerTask
        powerTask = Task { [weak self] in
            await previous?.value
            guard let self, self.running, !Task.isCancelled else { return }
            await self.floors?.run(percent: self.power.percent, isCharging: self.power.isCharging, thermal: self.power.thermalState, lidClosed: self.lid.isClosed)
        }
    }
}
