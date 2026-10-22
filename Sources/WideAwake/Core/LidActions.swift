import Foundation

/// Saves brightness before darkening a closed lid; restoration uses the journal.
@MainActor
final class LidActions {
    private weak var manager: SessionManager?
    private let display: any DisplayDimming
    private let keyboard: any KeyboardBacklighting
    private let sampler: BrightnessSampler?
    init(manager: SessionManager, display: any DisplayDimming, keyboard: any KeyboardBacklighting, sampler: BrightnessSampler?) {
        self.manager = manager; self.display = display; self.keyboard = keyboard; self.sampler = sampler
    }
    func onClose() async {
        guard let manager, manager.isActive, !Task.isCancelled else { return }
        _ = await manager.runExclusive("darken closed lid") { [self, manager] in
            guard manager.isActive, !Task.isCancelled else { return }
            darkenSavingCurrent(manager)
        }
    }
    func onOpen() async {
        guard let manager, manager.isActive else { return }
        await manager.undoLidActions()
    }
    private func darkenSavingCurrent(_ manager: SessionManager) {
        do {
            let current = try display.readBrightness()
            let value: Float
            if let sampled = sampler?.last?.display {
                value = sampled
                if sampled != current {
                    Log.info("display brightness reads \(current) at the close; journaling the last open-lid sample \(sampled)")
                }
            } else if manager.state.lowPowerSetByUs, let owed = manager.state.displayRestoredUnderLowPower {
                value = owed
                Log.info("display brightness reads \(current) at the close under our low power mode with no sample; journaling the value restored under it, \(owed)")
            } else if sampler?.displayReadIsTrusted ?? !display.isAsleep() {
                value = current
            } else {
                value = current
                Log.info("display brightness read while dimmed or asleep and no trusted sample; restoring that value on open")
            }
            try manager.journal { s in
                // Keep an earlier save if a previous close was never undone.
                if s.savedDisplayBrightness == nil { s.savedDisplayBrightness = value }
            }
            do {
                try display.setBrightness(0)
                Log.info("display darkened (was brightness \(value))")
            } catch {
                // The journal entry stays: the open restores whatever is there.
                Log.error("display darken failed: \(error.localizedDescription)")
            }
        } catch {
            Log.error("display darken on lid close skipped: \(error.localizedDescription)")
        }

        do {
            if let current = try keyboard.readBrightness() {
                let value: Float?
                if sampler?.keyboardReadIsTrusted ?? !keyboard.isSuppressedOrDimmed() {
                    value = current
                } else if let sampled = sampler?.last?.keyboard {
                    value = sampled
                    Log.info("keyboard backlight read while suppressed or dimmed (\(current)); journaling the last trusted sample \(sampled)")
                } else {
                    value = nil
                }
                if let value {
                    try manager.journal { s in
                        if s.savedKeyboardBrightness == nil { s.savedKeyboardBrightness = value }
                    }
                    do {
                        try keyboard.setBrightness(0)
                        Log.info("keyboard backlight off (was brightness \(value))")
                    } catch {
                        Log.error("keyboard backlight off failed: \(error.localizedDescription)")
                    }
                } else {
                    Log.info("keyboard backlight suppressed by display sleep and no trusted sample; leaving it to macOS")
                }
            } else {
                Log.info("no built-in keyboard backlight; skipped")
            }
        } catch {
            Log.error("keyboard backlight on lid close skipped: \(error.localizedDescription)")
        }

        do {
            try display.requestSleep()
            Log.info("display sleep requested")
        } catch {
            Log.info("display sleep request failed: \(error.localizedDescription)")
        }
    }

}
