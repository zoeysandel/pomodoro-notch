import AppKit
import PomodoroCore

@main struct PomodoroNotchApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var model: TimerModel!
    private var overlay: OverlayController!
    private var server: ControlServer?
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let directory: URL
        if let index = CommandLine.arguments.firstIndex(of: "--state-directory"),
           CommandLine.arguments.count > index + 1 {
            directory = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
        } else {
            directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Pomodoro Notch", isDirectory: true)
        }
        let control = ControlServer(directory: directory) { [weak self] request, complete in
            DispatchQueue.main.async {
                guard let self, let model = self.model else {
                    complete(["ok": false, "error": "App is starting"])
                    return
                }
                complete(model.handle(request))
            }
        }
        do { try control.start() }
        catch ControlServer.ServerError.alreadyRunning { NSApp.terminate(nil); return }
        catch {
            fputs("Pomodoro control server could not start: \(error)\n", stderr)
            NSApp.terminate(nil)
            return
        }
        server = control
        model = TimerModel(directory: directory)
        overlay = OverlayController(model: model)
        model.onQuit = { NSApp.terminate(nil) }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Pomodoro Notch")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        model.onStatusChange = { [weak self] in self?.updateStatusItem() }
        updateStatusItem()
    }

    func updateStatusItem() {
        statusItem?.button?.title = model.isActive ? " \(model.clock)" : ""
        statusItem?.button?.toolTip = "Pomodoro Notch — \(model.label.lowercased())"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        func add(_ title: String, _ action: Selector, key: String = "") {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            menu.addItem(item)
        }
        let heading = NSMenuItem(title: model.isActive ? "\(model.clock) · \(model.label)" : "Pomodoro Notch", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)
        menu.addItem(.separator())
        add("Show timer", #selector(showTimer))
        if model.isActive {
            add(model.session.phase == .paused ? "Resume" : "Pause", #selector(pauseResume))
            add("End session", #selector(endSession))
        } else {
            add("Start focus (\(model.focusClock))", #selector(startFocus))
            add("Start 5-minute break", #selector(startBreak))
        }
        add(model.isVisible ? "Hide overlay" : "Show overlay", #selector(toggleVisibility))
        menu.addItem(.separator())
        add("Quit Pomodoro Notch", #selector(quit), key: "q")
    }

    @objc private func showTimer() { model.show() }
    @objc private func startFocus() { model.start() }
    @objc private func startBreak() { model.start(seconds: 300, kind: .rest) }
    @objc private func pauseResume() { model.pauseOrResume() }
    @objc private func endSession() { model.stop() }
    @objc private func toggleVisibility() { if model.isVisible { model.hide() } else { model.show() } }
    @objc private func quit() { NSApp.terminate(nil) }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model?.show()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.persist()
        server?.stop()
    }
}
