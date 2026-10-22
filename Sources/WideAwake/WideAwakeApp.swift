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

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let manager = SessionManager.live()
    private var item: NSStatusItem?
    private var window: NSPanel!
    private let lid = LidObserver(debounce: 0)
    private var controller: ManualLidSession!
    private var panel: SliderPanel!
    private var terminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
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
        window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 348, height: 302), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "WideAwake"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.contentViewController = panel; window.isReleasedWhenClosed = false; window.delegate = self
        window.level = .floating; window.hidesOnDeactivate = false
        window.animationBehavior = .none
        controller.onChange = { [weak self] in self?.panel.refresh() }
        lid.onChange = { [weak self] closed in Task { @MainActor in await self?.controller.lidChanged(closed) } }
        Task {
            await manager.reconcile()
            await controller.prepare(lidClosed: lid.isClosed)
            lid.start(); panel.enable()
            Log.info("WideAwake ready: manual slider only; no session detection")
            if !UserDefaults.standard.bool(forKey: "SliderPresented") {
                UserDefaults.standard.set(true, forKey: "SliderPresented")
                togglePanel()
            }
        }
    }
    @objc private func togglePanel() {
        if window.isVisible { window.orderOut(nil); NSApp.setActivationPolicy(.accessory); return }
        guard let button = item?.button, let host = button.window else { return }
        panel.refresh()
        let anchor = host.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = host.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        let x = max(visible.minX + 8, min(anchor.maxX - 348, visible.maxX - 356))
        window.setFrameTopLeftPoint(NSPoint(x: x, y: anchor.minY - 4))
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) { NSApp.setActivationPolicy(.accessory) }
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

@MainActor final class SliderPanel: NSViewController {
    private let controller: ManualLidSession
    private let manager: SessionManager
    private let duration = NSTextField(labelWithString: "Off")
    private let message = NSTextField(wrappingLabelWithString: "Choose a time, then close the lid.")
    let slider = NSSlider(value: 0, minValue: 0, maxValue: 24, target: nil, action: nil)
    private var ready = false
    init(controller: ManualLidSession, manager: SessionManager) {
        self.controller = controller; self.manager = manager
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 348, height: 302))
        let mark = NSImageView(frame: NSRect(x: 24, y: 246, width: 30, height: 30))
        mark.image = NSImage(systemSymbolName: "sun.horizon.fill", accessibilityDescription: nil)
        mark.contentTintColor = .systemOrange; view.addSubview(mark)
        let title = NSTextField(labelWithString: "WideAwake")
        title.font = .systemFont(ofSize: 23, weight: .semibold); title.frame = NSRect(x: 64, y: 247, width: 250, height: 30); view.addSubview(title)
        duration.font = .monospacedDigitSystemFont(ofSize: 35, weight: .medium)
        duration.frame = NSRect(x: 22, y: 185, width: 300, height: 48); view.addSubview(duration)
        slider.frame = NSRect(x: 23, y: 145, width: 302, height: 31)
        slider.numberOfTickMarks = 25; slider.allowsTickMarkValuesOnly = true; slider.isContinuous = false
        slider.target = self; slider.action = #selector(changed); slider.isEnabled = false
        slider.setAccessibilityLabel("Keep awake duration in 15-minute steps")
        view.addSubview(slider)
        for (text, x, width) in [("Off", 24.0, 50.0), ("3h", 161.0, 50.0), ("6h", 299.0, 36.0)] {
            let label = NSTextField(labelWithString: text); label.font = .systemFont(ofSize: 11); label.textColor = .secondaryLabelColor
            label.frame = NSRect(x: x, y: 124, width: width, height: 16); view.addSubview(label)
        }
        message.font = .systemFont(ofSize: 12); message.textColor = .secondaryLabelColor
        message.frame = NSRect(x: 24, y: 68, width: 300, height: 43); view.addSubview(message)
        let reset = NSTextField(labelWithString: "Reopening the lid stops and resets the timer.")
        reset.font = .systemFont(ofSize: 11); reset.textColor = .tertiaryLabelColor
        reset.frame = NSRect(x: 24, y: 46, width: 306, height: 17); view.addSubview(reset)
        let quit = NSButton(title: "Quit", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        quit.bezelStyle = .inline; quit.frame = NSRect(x: 281, y: 12, width: 43, height: 23); view.addSubview(quit)
        let note = NSTextField(labelWithString: "15-minute steps · Up to 6 hours")
        note.font = .systemFont(ofSize: 10); note.textColor = .tertiaryLabelColor
        note.frame = NSRect(x: 24, y: 15, width: 241, height: 16); view.addSubview(note)
    }
    func enable() { ready = true; refresh() }
    @objc private func changed() {
        let steps = min(24, max(0, Int(slider.doubleValue.rounded())))
        slider.doubleValue = Double(steps)
        Task { await controller.choose(steps) }
    }
    func refresh() {
        loadViewIfNeeded()
        slider.doubleValue = Double(controller.steps)
        slider.isEnabled = ready && controller.phase != .arming && controller.phase != .stopping
        let minutes = controller.steps * 15
        duration.stringValue = minutes == 0 ? "Off" : minutes < 60 ? "\(minutes) min" : minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
        switch controller.phase {
        case .idle: message.stringValue = "Choose a time, then close the lid."
        case .arming: message.stringValue = "Preparing sleep protection… Wait before closing."
        case .ready: message.stringValue = "Ready. Timer starts on close. Close within 6 hours."
        case .running:
            let until = manager.session?.endsAt.formatted(date: .omitted, time: .shortened) ?? "the timer ends"
            message.stringValue = "Keeping awake until \(until)."
        case .stopping: message.stringValue = "Restoring normal sleep…"
        case let .failed(text): message.stringValue = text
        }
    }
}
