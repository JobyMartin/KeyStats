import Foundation

// MARK: - Tunables
//
// Every magic number/size/interval in the app lives here instead of being
// hunted across individual files. If you want to change the default daily
// goal, a window size, a refresh interval, etc. — this is the one file to
// edit. Values here are grouped by what they affect, not by which file
// currently reads them.
enum AppConfig {
    enum Goal {
        /// Used the first time the app runs, before any goal has been saved.
        static let defaultDaily = 15_000
        /// Range for the (future) Preferences slider — design §4.6.
        static let range = 2_000...60_000
        static let step = 500
        static let presets: [(name: String, value: Int)] = [
            ("Light", 8_000),
            ("Standard", 20_000),
            ("Heavy", 35_000),
            ("Marathon", 50_000),
        ]
        /// Whether Sat/Sun must hit goal to keep a streak, before any
        /// preference has been saved. See design §5. Defaults to *off* —
        /// weekends don't count, so missing one can't break a streak built
        /// on weekdays.
        static let countWeekendsTowardStreakDefault = false
        /// How far back the streak calculator is allowed to walk.
        static let streakLookbackDays = 365
    }

    enum Profile {
        /// Shown in the greeting row and menu-bar dropdown when no name has
        /// been set. Never persisted — `UserSettings.displayName` stores
        /// `""` and this is computed at read time. Design §4.5.
        static let namePlaceholder = "Anonymous Typist"
        static let nameMaxLength = 24
    }

    enum Window {
        static let dashboardSize = CGSize(width: 560, height: 760)
        static let dashboardMinWidth: CGFloat = 560
        static let dashboardMinHeight: CGFloat = 760
        static let title = "KeyStats"

        static let preferencesSize = CGSize(width: 520, height: 480)
        static let preferencesTitle = "Preferences"
    }

    enum Layout {
        static let contentPadding: CGFloat = 22
        static let sectionSpacing: CGFloat = 20
        static let cardPadding: CGFloat = 16
        static let cardCornerRadius: CGFloat = 11
        static let statCardPadding: CGFloat = 14
        static let statCardCornerRadius: CGFloat = 11
        static let weeklyChartHeight: CGFloat = 160
        static let hourlyChartHeight: CGFloat = 140
        static let legendMaxRows = 15
        /// Size of the goal ring drawn via `RingGauge` in the dashboard's
        /// goal section (distinct from the small `RingGaugeMark` in the
        /// header, which is a fixed brand-mark size). Kept small — the goal
        /// section is a single compact row, not a hero card.
        static let goalRingSize: CGFloat = 56
        static let goalRingLineWidth: CGFloat = 7
        /// Fixed sizing for Preferences → Appearance's theme cards — every
        /// card gets the same height regardless of how long its name/
        /// description happen to be, so the grid reads as even rows.
        static let themeCardHeight: CGFloat = 108
        static let themeCardDescriptionHeight: CGFloat = 28
        /// Preferences → Appearance's font preset cards (Typography.swift's
        /// `FontPreset`) — same fixed-height-grid reasoning as the theme
        /// cards above.
        static let fontPresetCardHeight: CGFloat = 96
    }

    enum Timing {
        static let dashboardRefresh: TimeInterval = 5
        static let dbFlush: TimeInterval = 5
        static let permissionPoll: TimeInterval = 2
        static let tapWatchdog: TimeInterval = 30
        static let sqliteBusyTimeoutMs: Int32 = 3_000
    }

    enum Permission {
        /// Deep link straight to the Accessibility pane, rather than just
        /// "Privacy & Security" — one fewer click for the user to take.
        static let accessibilitySettingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        static let resetCommand = "tccutil reset Accessibility"
    }

    enum Query {
        static let topKeysLimit = 15
        static let topKeybindsLimit = 15
        static let topAppsLimit = 10
        static let weeklyDays = 7
        static let hourlyWindowHours = 24
    }

    /// UserDefaults keys, kept in one place so nothing typos them.
    enum Defaults {
        static let dailyGoal = "dailyGoal"
        static let countWeekendsTowardStreak = "countWeekendsTowardStreak"
        static let themeID = "themeID"
        static let displayName = "displayName"
        static let fontScale = "fontScale"
        static let fontPresetID = "fontPresetID"
        /// Set true the first time the event tap ever starts successfully.
        /// Lets the permission banner distinguish "lost permission after an
        /// update" (scarier, needs revoke-then-re-grant wording) from a
        /// brand-new install that's never been granted at all.
        static let hasEverTracked = "hasEverTracked"
        /// User-initiated pause (design §5, §8 item 6). Persisted so a pause
        /// started before quitting (e.g. "pause before a screen share")
        /// survives a relaunch instead of silently resuming.
        static let isPaused = "isPaused"
    }
}

// MARK: - User settings
//
// Thin, non-View accessors over UserDefaults for code that isn't a SwiftUI
// view (Storage, StreakCalculator callers, etc). Views should prefer
// `@AppStorage(AppConfig.Defaults.dailyGoal)` directly so they re-render
// live when a future Preferences UI writes these keys — these are for
// everything else.
enum UserSettings {
    static var dailyGoal: Int {
        let v = UserDefaults.standard.integer(forKey: AppConfig.Defaults.dailyGoal)
        return v > 0 ? v : AppConfig.Goal.defaultDaily // 0 == never set
    }

    static var countWeekendsTowardStreak: Bool {
        UserDefaults.standard.object(forKey: AppConfig.Defaults.countWeekendsTowardStreak) as? Bool
            ?? AppConfig.Goal.countWeekendsTowardStreakDefault
    }

    /// Raw stored value — `""` when never set. The placeholder
    /// ("Anonymous Typist") is intentionally not stored here; compute it at
    /// the call site (or use `firstName`, which already does).
    static var displayName: String {
        UserDefaults.standard.string(forKey: AppConfig.Defaults.displayName) ?? ""
    }

    /// First space-delimited component of `displayName`, or nil when no
    /// name is set — lets AppKit code (the menu bar dropdown) decide its own
    /// "Hey there" fallback without duplicating the split logic.
    static var firstName: String? {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return name.split(separator: " ").first.map(String.init)
    }

    /// For AppKit code (the menu bar dropdown's rebuild trigger) — SwiftUI
    /// views should prefer `@AppStorage(AppConfig.Defaults.fontScale)`.
    static var fontScale: FontScale {
        FontScale(rawValue: UserDefaults.standard.string(forKey: AppConfig.Defaults.fontScale) ?? "") ?? .regular
    }

    static var fontPreset: FontPreset {
        FontPreset.preset(forID: UserDefaults.standard.string(forKey: AppConfig.Defaults.fontPresetID) ?? "")
    }
}
