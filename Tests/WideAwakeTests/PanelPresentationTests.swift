import AppKit
import XCTest
@testable import WideAwake

/// Uses the shipping AppKit views with disposable state and fake hardware.
@MainActor final class PanelPresentationTests: XCTestCase {
    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }

    private func capture(_ panel: SliderPanel, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["WIDEAWAKE_CAPTURE_DIR"] else { return }
        let root = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        panel.view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(panel.view.bitmapImageRepForCachingDisplay(in: panel.view.bounds))
        panel.view.effectiveAppearance.performAsCurrentDrawingAppearance {
            panel.view.cacheDisplay(in: panel.view.bounds, to: bitmap)
        }
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: root.appendingPathComponent(name + ".png"))
    }

    func testSettingsValidationAndSaveThroughNativeControls() async throws {
        _ = NSApplication.shared
        let h = Harness(now: Date()); defer { h.home.destroy() }
        let m = h.makeManager(powerSnapshot: { PowerSnapshot(percent: 67) })
        let c = ManualLidSession(manager: m)
        let panel = SliderPanel(controller: c, manager: m)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 412), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentViewController = panel
        panel.view.wantsLayer = true
        panel.view.layer?.backgroundColor = NSColor(white: 0.96, alpha: 1).cgColor
        panel.view.appearance = NSAppearance(named: .aqua)
        panel.enable()
        try capture(panel, name: "panel-off")
        await c.choose(6); panel.refresh()
        try capture(panel, name: "panel-ready")
        panel.view.appearance = NSAppearance(named: .darkAqua)
        panel.view.layer?.backgroundColor = NSColor(white: 0.16, alpha: 1).cgColor
        try capture(panel, name: "panel-dark")
        await c.stop(); panel.view.appearance = NSAppearance(named: .aqua)
        panel.view.layer?.backgroundColor = NSColor(white: 0.96, alpha: 1).cgColor
        _ = panel.perform(NSSelectorFromString("openSettings"))
        window.setContentSize(NSSize(width: 360, height: 572))
        let views = descendants(panel.view)
        let low = try XCTUnwrap(views.compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "Low Power Mode battery percentage" })
        let stop = try XCTUnwrap(views.compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "Stop timer battery percentage" })
        let save = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first { $0.title == "Save" })
        XCTAssertEqual(low.stringValue, "40"); XCTAssertEqual(stop.stringValue, "10")
        XCTAssertTrue(save.isEnabled)
        try capture(panel, name: "settings")
        stop.stringValue = "45"; panel.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        XCTAssertFalse(save.isEnabled)
        try capture(panel, name: "settings-invalid")
        low.stringValue = "25"; stop.stringValue = "5"
        panel.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        XCTAssertTrue(save.isEnabled)
        save.performClick(nil)
        XCTAssertEqual(m.config.batterySettings, BatterySettings(lowPowerPercent: 25, stopPercent: 5))
        XCTAssertEqual(try h.store.loadConfig()?.batterySettings, m.config.batterySettings)
        window.orderOut(nil)
    }

    func testLowBatteryAndFailedRestoreHaveVisibleRecovery() async throws {
        _ = NSApplication.shared
        let h = Harness(now: Date()); defer { h.home.destroy() }
        let power = Locked(PowerSnapshot(percent: 9))
        let m = h.makeManager(powerSnapshot: { power.value })
        let c = ManualLidSession(manager: m)
        let panel = SliderPanel(controller: c, manager: m)
        _ = panel.view
        panel.view.appearance = NSAppearance(named: .aqua)
        panel.view.wantsLayer = true
        panel.view.layer?.backgroundColor = NSColor(white: 0.96, alpha: 1).cgColor
        panel.enable()
        XCTAssertTrue(panel.slider.isEnabled)
        try capture(panel, name: "panel-low-battery")
        await c.choose(1); panel.refresh()
        XCTAssertEqual(c.phase, .blocked)
        power.value = PowerSnapshot(percent: 9, isCharging: true)
        panel.refresh()
        XCTAssertTrue(descendants(panel.view).compactMap { $0 as? NSTextField }.contains { $0.stringValue == "Power is ready. Choose a time to try again." })
        power.value = PowerSnapshot(percent: 50)
        await c.choose(1)
        h.guardFake.throwOn = ["disablesleep 0"]
        await c.stop(); panel.refresh()
        let retry = try XCTUnwrap(descendants(panel.view).compactMap { $0 as? NSButton }.first { $0.title == "Retry" })
        XCTAssertTrue(retry.isEnabled)
        XCTAssertFalse(panel.slider.isEnabled)
        try capture(panel, name: "panel-recovery")
        h.guardFake.throwOn = []
        await c.stop(); panel.refresh()
        XCTAssertTrue(panel.slider.isEnabled)
    }
}
