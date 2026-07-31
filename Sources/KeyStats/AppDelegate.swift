import Cocoa
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var window: NSWindow?
    private var permissionPollTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only — no Dock icon, no main window on launch.
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        registerPowerNotifications()

        if EventTapManager.shared.ensureAccessibilityPermission() {
            EventTapManager.shared.start()
        } else {
            // Permission dialog was just shown by the OS. Poll until granted,
            // since the user has to go grant it in System Settings and there's
            // no callback for that.
            pollForPermission()
        }
    }

    private func pollForPermission() {
        permissionPollTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            self?.permissionPollTimer = nil
            EventTapManager.shared.start()
        }
        permissionPollTimer = timer
    }

    private func registerPowerNotifications() {
        let nc = NSWorkspace.shared.notificationCenter
        for name: NSNotification.Name in [NSWorkspace.willSleepNotification, NSWorkspace.willPowerOffNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { _ in
                Storage.shared.flushSynchronously()
            }
        }
        nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            // Sleep/wake is a common way for a tap to end up disabled
            // without a callback ever arriving to tell us.
            EventTapManager.shared.reenableIfNeeded()
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "KeyStats")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Dashboard", action: #selector(showDashboard), keyEquivalent: "d"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit KeyStats", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        item.menu = menu

        statusItem = item
    }

    @objc private func showDashboard() {
        if window == nil {
            let hosting = NSHostingController(rootView: DashboardView())
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = "KeyStats"
            newWindow.setContentSize(NSSize(width: 520, height: 700))
            newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            newWindow.isReleasedWhenClosed = false
            window = newWindow
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() {
        // applicationWillTerminate does the actual teardown now, so this
        // path and logout/restart get the same clean shutdown.
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        EventTapManager.shared.stop()
        Storage.shared.shutdown()
    }
}
