import AppKit
import Foundation

/// Private native host. The shipping panel/controller use only existing fake effects.
@main @MainActor enum NativeCase {
    static func main() {
        let app = NSApplication.shared
        let delegate = CaseDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
@MainActor final class CaseDelegate: NSObject, NSApplicationDelegate {
    let h = Harness(now: Date())
    var manager: SessionManager!
    var controller: ManualLidSession!
    var panel: SliderPanel!
    var window: MenuBarPanel!
    var helper: NSWindow!
    var item: NSStatusItem!
    var clockTimer: Timer?
    var rows = [[String: Any]]()
    let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["WIDEAWAKE_CASE_OUTPUT"] ?? FileManager.default.temporaryDirectory.appendingPathComponent("wideawake-case-\(ProcessInfo.processInfo.processIdentifier)").path, isDirectory: true)
    func applicationDidFinishLaunching(_ note: Notification) {
        guard !FileManager.default.fileExists(atPath: output.path) else { print("Refusing to overwrite preview output: \(output.path)"); NSApp.terminate(nil); return }
        try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        NSApp.setActivationPolicy(.accessory)
        manager = h.makeManager(powerSnapshot: { PowerSnapshot(percent: 67) })
        manager.config.sliderStepMinutes = 1
        manager.config.maxDuration = 60
        manager.config.launchAtLogin = false
        try! h.store.saveConfig(manager.config)
        manager.showsLiveCountdown = false
        controller = ManualLidSession(manager: manager)
        panel = SliderPanel(controller: controller, manager: manager)
        window = MenuBarPanel(contentRect: NSRect(x: 300, y: 300, width: 360, height: 412), styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        window.title = "WideAwake • simulated hardware"
        window.contentViewController = panel
        window.isReleasedWhenClosed = false
        panel.onResize = { [weak self] value in self?.window.setContentSize(NSSize(width: 360, height: value)) }
        controller.onChange = { [weak self] in self?.panel.refresh(); self?.record("transition") }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "sun.horizon.fill", accessibilityDescription: "WideAwake controlled preview")
        item.button?.target = self; item.button?.action = #selector(showPanel)
        helper = NSWindow(contentRect: NSRect(x: 300, y: 130, width: 360, height: 118), styleMask: [.titled], backing: .buffered, defer: false)
        helper.title = "Preview controls • no system effects"
        let label = NSTextField(labelWithString: "Real one-minute clock · all hardware effects simulated")
        label.font = .systemFont(ofSize: 11); label.frame = NSRect(x: 12, y: 84, width: 340, height: 22); helper.contentView!.addSubview(label)
        for (text, action, x) in [("Simulate close", #selector(closeLid), 8), ("Simulate open", #selector(openLid), 126), ("Show panel", #selector(showPanel), 244)] {
            let b = NSButton(title: text, target: self, action: action); b.frame = NSRect(x: x, y: 46, width: 110, height: 30); helper.contentView!.addSubview(b)
        }
        let quit = NSButton(title: "Quit preview", target: self, action: #selector(quitCase)); quit.frame = NSRect(x: 120, y: 8, width: 120, height: 30); helper.contentView!.addSubview(quit)
        let menu = NSMenu(); let top = NSMenuItem(); let appMenu = NSMenu(); appMenu.addItem(withTitle: "Quit preview", action: #selector(quitCase), keyEquivalent: "q");top.submenu = appMenu; menu.addItem(top); NSApp.mainMenu = menu
        clockTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in Task { @MainActor in self?.h.clock.now = Date() } }
        panel.enable(); helper.makeKeyAndOrderFront(nil); showPanel(); record("initial")
    }
    @objc func showPanel() { panel.refresh(); NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil); record("shown") }
    @objc func closeLid() { h.clock.now = Date(); h.clamshell.closed = true; Task { await controller.lidChanged(true); panel.refresh(); record("simulated-close") } }
    @objc func openLid() { h.clock.now = Date(); h.clamshell.closed = false; Task { await controller.lidChanged(false); panel.refresh(); record("simulated-open") } }
    @objc func quitCase() { Task { await controller.stop(); record("quit"); clockTimer?.invalidate(); h.home.destroy(); NSApp.terminate(nil) } }
    func record(_ event: String) {
        guard panel != nil else { return }
        let phase = String(describing: controller.phase)
        let row: [String: Any] = ["event": event, "wall_time": Date().timeIntervalSince1970, "phase": phase, "steps": controller.steps, "selected_seconds": controller.seconds, "active": manager.isActive, "journal_dirty": manager.state.isDirty, "notice": controller.notice ?? "", "fake_effect_calls": h.guardFake.calls, "real_system_effects": false]
        rows.append(row)
        do {
            try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("journey.json"))
            panel.view.layoutSubtreeIfNeeded()
            if let bitmap = panel.view.bitmapImageRepForCachingDisplay(in: panel.view.bounds) {
                panel.view.cacheDisplay(in: panel.view.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("\(rows.count)-\(phase).png"))
            }
            for (name, file) in [("config", h.home.paths.configFile), ("session", h.home.paths.sessionFile), ("journal", h.home.paths.stateFile)] {
                if FileManager.default.fileExists(atPath: file.path) { try Data(contentsOf: file).write(to: output.appendingPathComponent("\(rows.count)-\(name).json")) }
            }
        } catch { print("case recording failed: \(error)") }
    }
}
