import AppKit
import ServiceManagement

@main @MainActor enum WideAwakeApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

/// Can accept keyboard input without becoming a Dock application.
@MainActor final class MenuBarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let manager = SessionManager.live()
    private var item: NSStatusItem?
    private var window: MenuBarPanel!
    private let lid = LidObserver(debounce: 0)
    private var controller: ManualLidSession!
    private var panel: SliderPanel!
    private var terminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installKeyboardCommands()
        manager.showsLiveCountdown = false
        if manager.config.launchAtLogin, [.notRegistered, .notFound].contains(SMAppService.mainApp.status) {
            do { try SMAppService.mainApp.register() }
            catch { Log.error("login registration: \(error.localizedDescription)") }
        }
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "sun.horizon.fill", accessibilityDescription: "WideAwake")
        status.button?.toolTip = "WideAwake"
        status.button?.target = self; status.button?.action = #selector(togglePanel)
        item = status
        controller = ManualLidSession(manager: manager)
        panel = SliderPanel(controller: controller, manager: manager)
        window = MenuBarPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 360), styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
        window.title = "WideAwake"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.contentViewController = panel; window.isReleasedWhenClosed = false; window.delegate = self
        window.isFloatingPanel = true; window.level = .popUpMenu; window.hidesOnDeactivate = false
        window.isMovable = false; window.isExcludedFromWindowsMenu = true; window.animationBehavior = .none
        panel.onResize = { [weak self] height in self?.resizePanel(height) }
        controller.onChange = { [weak self] in self?.panel.refresh() }
        lid.onChange = { [weak self] closed in Task { @MainActor in await self?.controller.lidChanged(closed) } }
        Task {
            await manager.reconcile()
            await controller.prepare(lidClosed: lid.isClosed)
            lid.start(); panel.enable()
            Log.info("WideAwake ready: menu bar only; no session detection")
            if !UserDefaults.standard.bool(forKey: "SliderPresented") {
                UserDefaults.standard.set(true, forKey: "SliderPresented")
                showPanel()
            }
        }
    }
    private func installKeyboardCommands() {
        let menu = NSMenu()
        let appItem = NSMenuItem(); menu.addItem(appItem)
        let appMenu = NSMenu(title: "WideAwake")
        appMenu.addItem(withTitle: "Quit WideAwake", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let editItem = NSMenuItem(); menu.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        NSApp.mainMenu = menu
    }
    private func resizePanel(_ height: CGFloat) {
        let top = window.frame.maxY
        window.setContentSize(NSSize(width: 360, height: height))
        window.setFrameTopLeftPoint(NSPoint(x: window.frame.minX, y: top))
    }
    @objc private func togglePanel() {
        if window.isVisible { window.orderOut(nil) } else { showPanel() }
    }
    private func showPanel() {
        guard let button = item?.button, let host = button.window else { return }
        panel.refresh()
        let anchor = host.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = host.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        let x = max(visible.minX + 8, min(anchor.maxX - 360, visible.maxX - 368))
        window.setFrameTopLeftPoint(NSPoint(x: x, y: anchor.minY - 4))
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showPanel() }
        return true
    }
    func windowDidResignKey(_ notification: Notification) { window.orderOut(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateCancel }
        terminating = true; lid.stop()
        Task {
            let outcome = await manager.end(reason: .quit)
            switch outcome {
            case .restored, .incomplete(agentArmed: true): sender.reply(toApplicationShouldTerminate: true)
            default: terminating = false; lid.start(); sender.reply(toApplicationShouldTerminate: false)
            }
        }
        return .terminateLater
    }
}

@MainActor final class SliderPanel: NSViewController, NSTextFieldDelegate {
    var onResize: ((CGFloat) -> Void)?
    private let controller: ManualLidSession
    private let manager: SessionManager
    private var ready = false
    private var showingSettings = false
    private var duration = NSTextField()
    private var message = NSTextField()
    private var rangeNote = NSTextField()
    private var maxLabel = NSTextField()
    private var middleLabel = NSTextField()
    private var minus = NSButton(), plus = NSButton(), turnOff = NSButton()
    private var stepField = NSTextField(), maximumField = NSTextField()
    private var stepUnit = NSPopUpButton(), maximumUnit = NSPopUpButton()
    private var settingsMessage = NSTextField()
    private var apply = NSButton()
    private let units = [("Minutes", 1), ("Hours", 60), ("Days", 1440)]
    let slider = NSSlider(value: 0, minValue: 0, maxValue: 24, target: nil, action: nil)

    init(controller: ManualLidSession, manager: SessionManager) {
        self.controller = controller; self.manager = manager
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    override func loadView() { view = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 360)); buildTimer() }
    private func label(_ text: String, _ frame: NSRect, size: CGFloat = 12, color: NSColor = .labelColor, weight: NSFont.Weight = .regular) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight); field.textColor = color; field.frame = frame
        view.addSubview(field); return field
    }
    private func button(_ text: String, _ frame: NSRect, action: Selector) -> NSButton {
        let button = NSButton(title: text, target: self, action: action)
        button.frame = frame; button.bezelStyle = .rounded; view.addSubview(button); return button
    }
    private func separator(y: CGFloat) {
        let line = NSBox(frame: NSRect(x: 22, y: y, width: 316, height: 1)); line.boxType = .separator; view.addSubview(line)
    }
    private func header(_ title: String, y: CGFloat) {
        let mark = NSImageView(frame: NSRect(x: 22, y: y, width: 25, height: 25))
        mark.image = NSImage(systemSymbolName: "sun.horizon.fill", accessibilityDescription: nil)
        mark.contentTintColor = .systemOrange; view.addSubview(mark)
        _ = label(title, NSRect(x: 56, y: y - 1, width: 240, height: 28), size: 18, weight: .semibold)
    }
    private func buildTimer() {
        view.subviews.forEach { $0.removeFromSuperview() }
        header("WideAwake", y: 310)
        let gear = button("", NSRect(x: 306, y: 309, width: 30, height: 28), action: #selector(openSettings))
        gear.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
        gear.isBordered = false; gear.toolTip = "Slider settings"; gear.setAccessibilityLabel("Settings")
        _ = label("Keep awake for", NSRect(x: 24, y: 270, width: 310, height: 20), size: 12, color: .secondaryLabelColor)
        duration = label("Off", NSRect(x: 22, y: 214, width: 316, height: 58), size: 42, weight: .medium)
        duration.font = .monospacedDigitSystemFont(ofSize: 42, weight: .medium)
        minus = button("−", NSRect(x: 21, y: 168, width: 30, height: 28), action: #selector(decrease))
        minus.setAccessibilityLabel("Decrease duration")
        slider.frame = NSRect(x: 56, y: 165, width: 248, height: 33)
        slider.target = self; slider.action = #selector(changed); slider.isContinuous = false
        view.addSubview(slider)
        plus = button("+", NSRect(x: 309, y: 168, width: 30, height: 28), action: #selector(increase))
        plus.setAccessibilityLabel("Increase duration")
        _ = label("Off", NSRect(x: 58, y: 144, width: 55, height: 18), size: 11, color: .secondaryLabelColor)
        middleLabel = label("3h", NSRect(x: 130, y: 144, width: 100, height: 18), size: 11, color: .secondaryLabelColor)
        middleLabel.alignment = .center
        maxLabel = label("6h", NSRect(x: 228, y: 144, width: 74, height: 18), size: 11, color: .secondaryLabelColor); maxLabel.alignment = .right
        message = label("", NSRect(x: 24, y: 88, width: 312, height: 45), size: 12)
        _ = label("Opening the lid stops and resets the timer.", NSRect(x: 24, y: 62, width: 312, height: 20), size: 11, color: .secondaryLabelColor)
        separator(y: 49)
        rangeNote = label("", NSRect(x: 24, y: 17, width: 184, height: 20), size: 11, color: .secondaryLabelColor)
        turnOff = button("Turn off", NSRect(x: 216, y: 13, width: 73, height: 27), action: #selector(stopTimer))
        turnOff.bezelStyle = .inline
        rangeNote.maximumNumberOfLines = 1
        rangeNote.lineBreakMode = .byTruncatingTail
        let quit = button("Quit", NSRect(x: 291, y: 13, width: 47, height: 27), action: #selector(quit))
        quit.bezelStyle = .inline
        refresh()
    }
    func enable() { ready = true; refresh() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func stopTimer() { Task { await controller.stop() } }
    @objc private func decrease() { select(controller.steps - 1) }
    @objc private func increase() { select(controller.steps + 1) }
    private func select(_ steps: Int) { Task { await controller.choose(steps) } }
    @objc private func changed() { select(Int(slider.doubleValue.rounded())) }

    func refresh() {
        guard isViewLoaded else { return }
        if showingSettings { validateSettings(); return }
        let scale = controller.settings
        slider.maxValue = Double(scale.stepCount)
        slider.numberOfTickMarks = scale.stepCount <= 24 ? scale.stepCount + 1 : 0
        slider.allowsTickMarkValuesOnly = scale.stepCount <= 24
        slider.doubleValue = Double(controller.steps)
        slider.setAccessibilityLabel("Keep awake duration, \(SliderSettings.label(minutes: scale.stepMinutes)) steps")
        let enabled = ready && controller.phase != .arming && controller.phase != .stopping
        slider.isEnabled = enabled; minus.isEnabled = enabled && controller.steps > 0
        plus.isEnabled = enabled && controller.steps < scale.stepCount
        turnOff.isEnabled = ready && controller.steps > 0 && controller.phase != .stopping
        duration.stringValue = SliderSettings.label(minutes: Int(controller.seconds / 60))
        duration.font = .monospacedDigitSystemFont(ofSize: duration.stringValue.count > 10 ? 31 : 42, weight: .medium)
        maxLabel.stringValue = SliderSettings.label(minutes: scale.maximumMinutes)
        middleLabel.stringValue = scale.stepCount > 1 ? SliderSettings.label(minutes: (scale.stepCount / 2) * scale.stepMinutes) : ""
        rangeNote.stringValue = "\(SliderSettings.label(minutes: scale.stepMinutes)) steps · \(SliderSettings.label(minutes: scale.maximumMinutes)) max"
        rangeNote.toolTip = rangeNote.stringValue
        message.textColor = .secondaryLabelColor
        switch controller.phase {
        case .idle: message.stringValue = "Choose a time, then close the lid to start."
        case .arming: message.stringValue = "Preparing sleep protection… Wait before closing."
        case .ready:
            message.stringValue = "Ready. Timer starts on close.\nClose within \(SliderSettings.label(minutes: Int(controller.armingWindow / 60)))."
            message.textColor = .labelColor
        case .running:
            let until = manager.session?.endsAt.formatted(date: controller.seconds >= 86400 ? .abbreviated : .omitted, time: .shortened) ?? "the timer ends"
            message.stringValue = "Keeping awake until \(until)."
        case .stopping: message.stringValue = "Restoring normal sleep…"
        case let .failed(text): message.stringValue = text; message.textColor = .systemRed
        }
        message.toolTip = message.stringValue
    }
    @objc private func openSettings() {
        showingSettings = true
        view.subviews.forEach { $0.removeFromSuperview() }
        view.setFrameSize(NSSize(width: 360, height: 420)); onResize?(420)
        header("Slider settings", y: 370)
        _ = label("Increment", NSRect(x: 24, y: 328, width: 310, height: 20), size: 12, weight: .medium)
        stepField = input(y: 288, label: "Increment value")
        stepUnit = unitPicker(y: 288, label: "Increment unit")
        _ = label("Maximum duration", NSRect(x: 24, y: 244, width: 310, height: 20), size: 12, weight: .medium)
        maximumField = input(y: 204, label: "Maximum value")
        maximumUnit = unitPicker(y: 204, label: "Maximum unit")
        _ = label("Whole minutes, hours or days, up to 30 days.\nMaximum must be a multiple of the increment.", NSRect(x: 24, y: 144, width: 312, height: 44), size: 11, color: .secondaryLabelColor)
        settingsMessage = label("", NSRect(x: 24, y: 80, width: 312, height: 56), size: 12)
        separator(y: 67)
        let defaults = button("Defaults", NSRect(x: 18, y: 20, width: 84, height: 30), action: #selector(restoreDefaults)); defaults.bezelStyle = .inline
        _ = button("Cancel", NSRect(x: 164, y: 20, width: 83, height: 30), action: #selector(closeSettings))
        apply = button("Save", NSRect(x: 252, y: 20, width: 84, height: 30), action: #selector(saveSettings)); apply.keyEquivalent = "\r"
        populate(controller.settings); validateSettings()
    }
    private func input(y: CGFloat, label: String) -> NSTextField {
        let field = NSTextField(string: "")
        field.frame = NSRect(x: 24, y: y, width: 114, height: 30); field.font = .monospacedDigitSystemFont(ofSize: 17, weight: .regular)
        field.delegate = self; field.setAccessibilityLabel(label); view.addSubview(field); return field
    }
    private func unitPicker(y: CGFloat, label: String) -> NSPopUpButton {
        let picker = NSPopUpButton(frame: NSRect(x: 150, y: y - 1, width: 186, height: 32), pullsDown: false)
        picker.addItems(withTitles: units.map(\.0)); picker.target = self; picker.action = #selector(unitsChanged)
        picker.setAccessibilityLabel(label); view.addSubview(picker); return picker
    }
    private func populate(_ scale: SliderSettings) {
        for (minutes, field, picker) in [(scale.stepMinutes, stepField, stepUnit), (scale.maximumMinutes, maximumField, maximumUnit)] {
            let index = minutes % 1440 == 0 ? 2 : minutes % 60 == 0 ? 1 : 0
            picker.selectItem(at: index); field.stringValue = String(minutes / units[index].1)
        }
    }
    private func draft() throws -> SliderSettings {
        func minutes(_ field: NSTextField, _ picker: NSPopUpButton) throws -> Int {
            guard let n = Int(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)),
                  (1...SliderSettings.limitMinutes).contains(n), units.indices.contains(picker.indexOfSelectedItem) else {
                throw SettingsError.invalid("Enter a positive whole number for each duration.")
            }
            let value = n * units[picker.indexOfSelectedItem].1
            guard value <= SliderSettings.limitMinutes else { throw SettingsError.invalid("The longest duration is 30 days.") }
            return value
        }
        let result = try SliderSettings(stepMinutes: minutes(stepField, stepUnit), maximumMinutes: minutes(maximumField, maximumUnit))
        try result.validate(); return result
    }
    func controlTextDidChange(_ obj: Notification) { validateSettings() }
    @objc private func unitsChanged() { validateSettings() }
    private func validateSettings() {
        guard showingSettings else { return }
        do {
            let scale = try draft()
            guard ready, !manager.isActive, !manager.state.isDirty, controller.phase != .arming, controller.phase != .stopping else {
                throw SettingsError.invalid("Turn off the timer before changing these settings.")
            }
            settingsMessage.textColor = .secondaryLabelColor
            settingsMessage.stringValue = "Off → \(SliderSettings.label(minutes: scale.maximumMinutes))\n\(scale.stepCount) steps of \(SliderSettings.label(minutes: scale.stepMinutes))"
            apply.isEnabled = true
        } catch { settingsMessage.textColor = .systemRed; settingsMessage.stringValue = error.localizedDescription; apply.isEnabled = false }
    }
    @objc private func restoreDefaults() { populate(.defaults); validateSettings() }
    @objc private func saveSettings() {
        do { try controller.applySettings(draft()); closeSettings() }
        catch { settingsMessage.textColor = .systemRed; settingsMessage.stringValue = "Could not save: \(error.localizedDescription)" }
    }
    @objc private func closeSettings() {
        showingSettings = false
        view.setFrameSize(NSSize(width: 360, height: 360)); onResize?(360)
        buildTimer()
    }
}
