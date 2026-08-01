import Cocoa
import SwiftUI

extension Notification.Name {
    /// Posted by the dashboard's settings gear (SwiftUI) so AppDelegate
    /// (AppKit, owns the actual NSWindow) can open Preferences — same
    /// indirection `showDashboard`'s menu item uses, just triggered from a
    /// view instead of an NSMenuItem.
    static let openPreferences = Notification.Name("KeyStats.openPreferences")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var window: NSWindow?
    private var preferencesWindow: NSWindow?
    private var permissionPollTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only — no Dock icon, no main window on launch.
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        registerPowerNotifications()
        NotificationCenter.default.addObserver(forName: .openPreferences, object: nil, queue: .main) { [weak self] _ in
            self?.showPreferences()
        }

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
        let timer = Timer.scheduledTimer(withTimeInterval: AppConfig.Timing.permissionPoll, repeats: true) { [weak self] timer in
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
            button.image = MenuBarIcon.ringGaugeTemplate()
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Dashboard", action: #selector(showDashboard), keyEquivalent: "d"))
        menu.addItem(NSMenuItem(title: "Preferences…", action: #selector(showPreferences), keyEquivalent: ","))
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
            newWindow.title = AppConfig.Window.title
            newWindow.setContentSize(NSSize(width: AppConfig.Window.dashboardSize.width, height: AppConfig.Window.dashboardSize.height))
            newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            newWindow.isReleasedWhenClosed = false
            window = newWindow
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func showPreferences() {
        if preferencesWindow == nil {
            let hosting = NSHostingController(rootView: PreferencesView())
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = AppConfig.Window.preferencesTitle
            newWindow.setContentSize(NSSize(width: AppConfig.Window.preferencesSize.width, height: AppConfig.Window.preferencesSize.height))
            newWindow.styleMask = [.titled, .closable, .miniaturizable]
            newWindow.isReleasedWhenClosed = false
            // Closes itself the moment focus moves anywhere else — the
            // dashboard, another app, the menu bar — so it behaves like a
            // lightweight panel instead of a window that's easy to lose
            // behind other windows. `didResignKeyNotification` fires
            // exactly on that transition.
            NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: newWindow, queue: .main) { [weak self] _ in
                self?.preferencesWindow?.close()
            }
            preferencesWindow = newWindow
        }
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindow?.makeKeyAndOrderFront(nil)
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
