import Cocoa
import SwiftUI

extension Notification.Name {
    /// Posted by the dashboard's settings gear (SwiftUI) so AppDelegate
    /// (AppKit, owns the actual NSWindow) can open Preferences — same
    /// indirection `showDashboard`'s menu item uses, just triggered from a
    /// view instead of an NSMenuItem.
    static let openPreferences = Notification.Name("KeyStats.openPreferences")
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var window: NSWindow?
    private var preferencesWindow: NSWindow?
    private var permissionPollTimer: Timer?
    private var lastMenuPermissionState: PermissionMonitor.State?
    private lazy var lastFontSignature = Self.fontSignature()
    private let launchedAt = Date()
    private static let launchTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only — no Dock icon, no main window on launch.
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        registerPowerNotifications()
        NotificationCenter.default.addObserver(forName: .openPreferences, object: nil, queue: .main) { [weak self] _ in
            self?.showPreferences()
        }
        // The dropdown's hosted rows measure their own `fittingSize` once,
        // at menu-build time (see makeMenuBarHostingItem), so a font/size
        // change made in Preferences needs a full menu rebuild to actually
        // resize — menuWillOpen only refreshes row *content*, not layout.
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.rebuildMenuIfFontChanged()
        }

        EventTapManager.shared.ensureAccessibilityPermission()
        EventTapManager.shared.start()
        refreshStatusItemForPermissionState()
        pollForPermission()
    }

    /// Runs for the lifetime of the app, not just until the first grant —
    /// permission can be revoked (e.g. after an update breaks the CDHash-
    /// keyed grant) or re-granted at any point during a session, and this is
    /// the only thing that notices without a relaunch. Also drives the menu
    /// bar's permission-warning state.
    private func pollForPermission() {
        permissionPollTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: AppConfig.Timing.permissionPoll, repeats: true) { [weak self] _ in
            PermissionMonitor.shared.refresh()
            if AXIsProcessTrusted() && !EventTapManager.shared.isRunning {
                EventTapManager.shared.start()
            }
            self?.refreshStatusItemForPermissionState()
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
        statusItem = item
        rebuildMenu(permissionState: PermissionMonitor.shared.state)
    }

    /// Rebuilds the status icon + menu from scratch for the given
    /// permission state. Called on launch and whenever `pollForPermission()`
    /// notices the state changed, so a mid-session revoke/re-grant updates
    /// the menu bar without a relaunch.
    private func refreshStatusItemForPermissionState() {
        let state = PermissionMonitor.shared.state
        guard state != lastMenuPermissionState else { return }
        lastMenuPermissionState = state
        rebuildMenu(permissionState: state)
    }

    private func rebuildMenu(permissionState: PermissionMonitor.State) {
        guard let item = statusItem else { return }
        updateStatusIcon(permissionState: permissionState)

        let menu = NSMenu()
        menu.delegate = self
        if permissionState != .granted {
            let warning = NSMenuItem(title: "⚠ Accessibility permission needed", action: #selector(showDashboard), keyEquivalent: "")
            menu.addItem(warning)
            menu.addItem(NSMenuItem.separator())
        }

        // Greeting + today's stat — hosted SwiftUI so they can carry state
        // (display name, live count) an NSMenuItem's plain title can't
        // format. Refreshed on every open in menuWillOpen(_:), since
        // rebuildMenu itself only runs on launch and on permission changes.
        menu.addItem(makeMenuBarHostingItem(MenuBarGreetingRow(firstName: UserSettings.firstName, launchTime: Self.launchTimeFormatter.string(from: launchedAt))))
        menu.addItem(makeMenuBarHostingItem(MenuBarStatRow(todayTotal: 0, goalPercent: 0)))
        menu.addItem(NSMenuItem.separator())

        menu.addItem(menuItem(title: "Open Dashboard", symbol: "chart.bar.fill", action: #selector(showDashboard), keyEquivalent: "d"))
        menu.addItem(menuItem(title: "Preferences…", symbol: "gearshape.fill", action: #selector(showPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(title: "Quit KeyStats", symbol: "power", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        item.menu = menu
    }

    private static func fontSignature() -> String {
        "\(UserSettings.fontScale.rawValue)|\(UserSettings.fontPreset.id)"
    }

    /// `UserDefaults.didChangeNotification` fires for ANY defaults write,
    /// not just the font keys, so this filters down to an actual change
    /// before paying for a menu rebuild.
    private func rebuildMenuIfFontChanged() {
        let signature = Self.fontSignature()
        guard signature != lastFontSignature else { return }
        lastFontSignature = signature
        rebuildMenu(permissionState: PermissionMonitor.shared.state)
    }

    private func menuItem(title: String, symbol: String, action: Selector, keyEquivalent: String) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        menuItem.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return menuItem
    }

    private func updateStatusIcon(permissionState: PermissionMonitor.State) {
        guard let button = statusItem?.button else { return }
        if permissionState == .granted {
            let goal = UserSettings.dailyGoal
            let progress = goal > 0 ? Double(Storage.shared.todayTotal()) / Double(goal) : 0
            button.image = MenuBarIcon.ringGaugeTemplate(progress: progress)
            button.contentTintColor = nil
        } else {
            // Template images can't carry color, so a real (non-template)
            // symbol image is used here to show the warning in its
            // natural color instead of menu-bar black/white.
            button.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Accessibility permission needed")
            button.image?.isTemplate = false
            button.contentTintColor = .systemYellow
        }
    }

    /// Refreshes the two hosted stat rows (and the status-bar ring itself)
    /// every time the dropdown opens — `rebuildMenu` only runs at launch and
    /// on permission-state changes, so nothing else keeps "Today" current.
    func menuWillOpen(_ menu: NSMenu) {
        updateStatusIcon(permissionState: PermissionMonitor.shared.state)

        let today = Storage.shared.todayTotal()
        let goal = UserSettings.dailyGoal
        let percent = goal > 0 ? Int((Double(today) / Double(goal) * 100).rounded()) : 0

        for item in menu.items {
            if let hosting = item.view as? NSHostingView<MenuBarStatRow> {
                hosting.rootView = MenuBarStatRow(todayTotal: today, goalPercent: percent)
                hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
            } else if let hosting = item.view as? NSHostingView<MenuBarGreetingRow> {
                hosting.rootView = MenuBarGreetingRow(firstName: UserSettings.firstName, launchTime: Self.launchTimeFormatter.string(from: launchedAt))
                hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
            }
        }
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
