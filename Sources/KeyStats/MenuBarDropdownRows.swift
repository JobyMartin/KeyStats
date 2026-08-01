import Cocoa
import SwiftUI

// The two hosted-SwiftUI rows at the top of the menu-bar dropdown — design
// §4.3. Everything below them (Open Dashboard, Preferences…, Quit) stays a
// plain NSMenuItem so ⌘D/⌘,/⌘Q and native hover/keyboard nav keep working;
// only the greeting and the live stat row need real views, since they carry
// state (name, today's count) an NSMenuItem's plain title can't format well.
//
// Both views compute their own `theme` the same way DashboardView and
// PreferencesView do (from the `themeID` default) rather than relying on an
// inherited environment, since NSHostingView roots don't get one.

private let dropdownRowWidth: CGFloat = 260

struct MenuBarGreetingRow: View {
    let firstName: String?
    let launchTime: String
    var isPaused: Bool = false
    @AppStorage(AppConfig.Defaults.themeID) private var themeID = AppTheme.backlit.id
    @AppStorage(AppConfig.Defaults.fontScale) private var fontScaleRaw = FontScale.regular.rawValue
    @AppStorage(AppConfig.Defaults.fontPresetID) private var fontPresetID = FontPreset.system.id
    private var theme: AppTheme { AppTheme.theme(forID: themeID) }
    private var typography: AppTypography {
        AppTypography(preset: FontPreset.preset(forID: fontPresetID), scale: FontScale(rawValue: fontScaleRaw) ?? .regular)
    }

    private var greeting: String {
        if let firstName {
            return "Hey, \(firstName) \u{1F44B}"
        }
        return "Hey there \u{1F44B}"
    }

    var body: some View {
        HStack(spacing: 10) {
            RingGaugeMark(size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(greeting)
                    .font(typography.greeting)
                    .foregroundStyle(theme.text)
                Text(isPaused ? "Paused · resume anytime" : "Tracking since \(launchTime)")
                    .font(typography.caption)
                    .foregroundStyle(theme.textFaint)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: dropdownRowWidth, alignment: .leading)
        .background(theme.bg)
        .environment(\.theme, theme)
        .environment(\.typography, typography)
    }
}

struct MenuBarStatRow: View {
    let todayTotal: Int
    let goalPercent: Int
    @AppStorage(AppConfig.Defaults.themeID) private var themeID = AppTheme.backlit.id
    @AppStorage(AppConfig.Defaults.fontScale) private var fontScaleRaw = FontScale.regular.rawValue
    @AppStorage(AppConfig.Defaults.fontPresetID) private var fontPresetID = FontPreset.system.id
    private var theme: AppTheme { AppTheme.theme(forID: themeID) }
    private var typography: AppTypography {
        AppTypography(preset: FontPreset.preset(forID: fontPresetID), scale: FontScale(rawValue: fontScaleRaw) ?? .regular)
    }

    var body: some View {
        HStack {
            Text("Today")
                .font(typography.mediumLabel)
                .foregroundStyle(theme.textDim)
            Spacer()
            Text(todayTotal.formatted())
                .font(typography.statNumber)
                .foregroundStyle(theme.accent)
            Text("\(goalPercent)% of goal")
                .font(typography.monoSmall)
                .foregroundStyle(theme.textDim)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(theme.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .frame(width: dropdownRowWidth, alignment: .leading)
        .background(theme.bg)
        .environment(\.theme, theme)
        .environment(\.typography, typography)
    }
}

/// Wraps a hosted SwiftUI view for use as an `NSMenuItem.view`. Menu items
/// with a custom `view` don't get the item's own highlight/click handling
/// (there's no action here — these two rows are display-only), so
/// `isEnabled = false` is not needed; the hosting view simply doesn't
/// respond to clicks.
func makeMenuBarHostingItem<Content: View>(_ content: Content) -> NSMenuItem {
    let hosting = NSHostingView(rootView: content)
    hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
    let item = NSMenuItem()
    item.view = hosting
    return item
}
