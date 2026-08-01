import Cocoa

/// Observable Accessibility-permission state, so SwiftUI views (dashboard
/// banner, Preferences) and the menu bar can all react live instead of each
/// polling `AXIsProcessTrusted()` on their own timers.
final class PermissionMonitor: ObservableObject {
    static let shared = PermissionMonitor()

    enum State {
        /// Trusted and the event tap is live.
        case granted
        /// `AXIsProcessTrusted()` is false — permission was never granted,
        /// or was revoked.
        case notTrusted
        /// `AXIsProcessTrusted()` is true but `EventTapManager` couldn't
        /// create a tap. Seen when TCC's on-disk grant is stale relative to
        /// the running binary — the fix is revoke-then-re-grant, not just
        /// waiting.
        case trustedButTapFailed
    }

    @Published private(set) var state: State = .notTrusted
    /// True once the event tap has ever started successfully on this
    /// machine — distinguishes "lost permission after an update" from a
    /// first-run install that's never been granted at all.
    @Published private(set) var everHadPermission = UserDefaults.standard.bool(forKey: AppConfig.Defaults.hasEverTracked)

    private init() {
        refresh()
    }

    func refresh() {
        #if DEBUG
        // Lets `swift run` preview every banner state on demand without
        // touching the real Accessibility grant, e.g.:
        //   KEYSTATS_FORCE_PERMISSION_STATE=notTrusted swift run
        //   KEYSTATS_FORCE_PERMISSION_STATE=notTrustedFirstRun swift run
        //   KEYSTATS_FORCE_PERMISSION_STATE=trustedButTapFailed swift run
        // Compiled out of release builds, so it never ships.
        if let forced = ProcessInfo.processInfo.environment["KEYSTATS_FORCE_PERMISSION_STATE"] {
            switch forced {
            case "granted":
                everHadPermission = true
                state = .granted
            case "notTrustedFirstRun":
                everHadPermission = false
                state = .notTrusted
            case "trustedButTapFailed":
                everHadPermission = true
                state = .trustedButTapFailed
            default: // "notTrusted"
                everHadPermission = true
                state = .notTrusted
            }
            return
        }
        #endif

        everHadPermission = UserDefaults.standard.bool(forKey: AppConfig.Defaults.hasEverTracked)

        let trusted = AXIsProcessTrusted()
        let running = EventTapManager.shared.isRunning

        let newState: State
        switch (trusted, running) {
        case (false, _):
            newState = .notTrusted
        case (true, true):
            newState = .granted
        case (true, false):
            newState = .trustedButTapFailed
        }

        if newState != state {
            state = newState
        }
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: AppConfig.Permission.accessibilitySettingsURL) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Puts the `tccutil reset` command on the pasteboard — the app is
    /// sandboxed and can't run it itself.
    func copyResetCommand() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.joby.KeyStatsApp"
        let command = "\(AppConfig.Permission.resetCommand) \(bundleID)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }
}

extension PermissionMonitor.State: Equatable {}
