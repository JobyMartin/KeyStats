import Cocoa
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only — no Dock icon, no main window on launch.
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()

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
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { timer in
            if AXIsProcessTrusted() {
                timer.invalidate()
                EventTapManager.shared.start()
            }
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
        EventTapManager.shared.stop()
        NSApp.terminate(nil)
    }
}
