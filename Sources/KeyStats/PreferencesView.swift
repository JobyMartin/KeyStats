import SwiftUI

// Real Preferences window — design §4, §8.4. General is a placeholder
// (design §8 pickup order puts display name/pause-resume ahead of it);
// Appearance and Goals are both fully wired since they only needed
// `@AppStorage` state that already exists from the goal/streak and theme
// work.
struct PreferencesView: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case general = "General"
        case appearance = "Appearance"
        case goals = "Goals"
        var id: String { rawValue }
    }

    @AppStorage(AppConfig.Defaults.themeID) private var themeID = AppTheme.backlit.id
    @AppStorage(AppConfig.Defaults.dailyGoal) private var dailyGoal = AppConfig.Goal.defaultDaily
    @AppStorage(AppConfig.Defaults.countWeekendsTowardStreak) private var countWeekendsTowardStreak = AppConfig.Goal.countWeekendsTowardStreakDefault
    @AppStorage(AppConfig.Defaults.displayName) private var displayName = ""
    @AppStorage(AppConfig.Defaults.fontScale) private var fontScaleRaw = FontScale.regular.rawValue
    @AppStorage(AppConfig.Defaults.fontPresetID) private var fontPresetID = FontPreset.system.id
    @ObservedObject private var permissions = PermissionMonitor.shared
    @State private var selectedTab: Tab = .appearance
    @State private var longestStreak: (days: Int, start: String, end: String)?

    private var theme: AppTheme { AppTheme.theme(forID: themeID) }
    private var typography: AppTypography {
        AppTypography(preset: FontPreset.preset(forID: fontPresetID), scale: FontScale(rawValue: fontScaleRaw) ?? .regular)
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider().overlay(theme.borderSoft)
            ScrollView {
                content
                    .padding(20)
            }
        }
        .frame(width: AppConfig.Window.preferencesSize.width, height: AppConfig.Window.preferencesSize.height)
        .background(theme.bg)
        .environment(\.theme, theme)
        .environment(\.typography, typography)
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(Tab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(typography.tabLabel)
                        .foregroundStyle(selectedTab == tab ? theme.text : theme.textDim)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(selectedTab == tab ? theme.surfaceRaised : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(14)
        .background(theme.surface)
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .general: generalTab
        case .appearance: appearanceTab
        case .goals: goalsTab
        }
    }

    /// The card chrome duplicated across every settings section — padding,
    /// `surfaceRaised` background, radius-10, 1px `border` stroke.
    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(12)
            .background(theme.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            )
    }

    // MARK: - General

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            displayNameSection
            accessibilitySection
            VStack(alignment: .leading, spacing: 8) {
                Text("More settings coming soon.")
                    .font(typography.body)
                    .foregroundStyle(theme.textDim)
                Text("Launch at login and the frontmost-app toggle land here next.")
                    .font(typography.caption)
                    .foregroundStyle(theme.textFaint)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
    }

    // MARK: - Display name

    private var displayNameSection: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Display name")
                    .font(typography.label)
                    .foregroundStyle(theme.text)
                TextField(AppConfig.Profile.namePlaceholder, text: $displayName)
                    .textFieldStyle(.plain)
                    .font(typography.body)
                    .foregroundStyle(theme.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(theme.border, lineWidth: 1)
                    )
                    // The placeholder itself is never persisted — this just
                    // caps what gets typed in, so `displayName` stays either
                    // "" or a real name, never the placeholder text.
                    .onChange(of: displayName) { _, newValue in
                        if newValue.count > AppConfig.Profile.nameMaxLength {
                            displayName = String(newValue.prefix(AppConfig.Profile.nameMaxLength))
                        }
                    }
                Text("Shows up in the menu bar dropdown's greeting. Leave blank to stay anonymous.")
                    .font(typography.caption)
                    .foregroundStyle(theme.textFaint)
            }
        }
    }

    private var accessibilitySection: some View {
        let granted = permissions.state == .granted
        return settingsCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Accessibility")
                        .font(typography.label)
                        .foregroundStyle(theme.text)
                    Spacer()
                    Text(granted ? "Granted" : "Not granted")
                        .font(typography.strongSmall)
                        .foregroundStyle(granted ? theme.good : theme.bad)
                }
                if !granted {
                    Text("KeyStats can't count keystrokes without Accessibility access. If it already appears enabled in the list, switch it off and back on: select it, press \u{2212}, then press + and re-add KeyStatsApp.")
                        .font(typography.caption)
                        .foregroundStyle(theme.textFaint)
                    Button {
                        permissions.openAccessibilitySettings()
                    } label: {
                        Text("Open Accessibility Settings")
                            .font(typography.strongSmall)
                            .foregroundStyle(theme.bg)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Appearance

    private var appearanceTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            fontSizeSection
            fontPresetSection
            VStack(alignment: .leading, spacing: 8) {
                Text("Theme")
                    .font(typography.label)
                    .foregroundStyle(theme.text)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(AppTheme.all) { candidate in
                        themeCard(candidate)
                    }
                }
            }
        }
    }

    // MARK: - Font size

    private var fontSizeSection: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Font size")
                    .font(typography.label)
                    .foregroundStyle(theme.text)
                HStack(spacing: 8) {
                    ForEach(FontScale.allCases) { scale in
                        fontSizeChip(scale)
                    }
                }
            }
        }
    }

    private func fontSizeChip(_ scale: FontScale) -> some View {
        let isActive = scale.rawValue == fontScaleRaw
        return Button {
            fontScaleRaw = scale.rawValue
        } label: {
            VStack(spacing: 3) {
                // Deliberately a raw literal, not a typography token — this
                // previews the actual step's size, which is the entire
                // point of the chip.
                Text("Aa")
                    .font(.system(size: 14 * scale.multiplier, weight: .semibold))
                Text(scale.label)
                    .font(.system(size: 9.5, weight: .medium))
            }
            .foregroundStyle(isActive ? theme.bg : theme.textDim)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(isActive ? theme.accent : theme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isActive ? Color.clear : theme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Font preset

    private var fontPresetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Font")
                .font(typography.label)
                .foregroundStyle(theme.text)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(FontPreset.all) { preset in
                    fontPresetCard(preset)
                }
            }
        }
    }

    private func fontPresetCard(_ preset: FontPreset) -> some View {
        let isSelected = preset.id == fontPresetID
        // Surfaces the same degrade-to-system behavior `FontFace.font`
        // already applies, rather than letting a preset render as system
        // with no explanation why — matters most for the bundled ★ presets
        // under `swift run`, which has no app bundle to register fonts from.
        let unavailable = preset.uiFace.isUnavailable || preset.monoFace.isUnavailable
        return Button {
            fontPresetID = preset.id
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(preset.name)
                        .font(preset.uiFace.font(size: 13, weight: .semibold))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.accent)
                    }
                }
                Text("14,208")
                    .font(preset.monoFace.font(size: 15, weight: .semibold))
                    .foregroundStyle(theme.accent)
                Text(unavailable ? "Not installed — falls back to system" : preset.description)
                    .font(typography.caption)
                    .foregroundStyle(unavailable ? theme.bad : theme.textFaint)
                    .lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: AppConfig.Layout.fontPresetCardHeight, maxHeight: AppConfig.Layout.fontPresetCardHeight, alignment: .topLeading)
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? theme.accent : theme.border, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func themeCard(_ candidate: AppTheme) -> some View {
        let isSelected = candidate.id == themeID
        return Button {
            themeID = candidate.id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Circle().fill(candidate.accent).frame(width: 12, height: 12)
                    ForEach(Array(candidate.series.enumerated()), id: \.offset) { _, color in
                        Circle().fill(color).frame(width: 8, height: 8)
                    }
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(candidate.accent)
                    }
                }
                Text(candidate.name)
                    .font(typography.cardTitle)
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                // Fixed height (not just `lineLimit(2)`) so a one-line
                // description doesn't leave its card shorter than a
                // neighbor's two-line one — LazyVGrid sizes each row to its
                // tallest item, but does nothing to equalize row heights
                // against each other, so uneven text is what was making the
                // cards look mismatched.
                Text(candidate.description)
                    .font(typography.caption)
                    .foregroundStyle(theme.textFaint)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .frame(height: AppConfig.Layout.themeCardDescriptionHeight, alignment: .top)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: AppConfig.Layout.themeCardHeight, maxHeight: AppConfig.Layout.themeCardHeight, alignment: .topLeading)
            .background(candidate.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? candidate.accent : candidate.border, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Goals

    private var goalsTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            dailyGoalEditor
            weekendToggle
            longestStreakSection
        }
        .task { loadLongestStreak() }
        .onChange(of: countWeekendsTowardStreak) { _, _ in loadLongestStreak() }
    }

    // MARK: - Longest streak

    private var longestStreakSection: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("Longest streak")
                    .font(typography.label)
                    .foregroundStyle(theme.text)
                if let longestStreak {
                    Text("\(longestStreak.days) day\(longestStreak.days == 1 ? "" : "s")")
                        .font(typography.streakNumber)
                        .foregroundStyle(theme.accent)
                    Text(Self.streakRangeLabel(longestStreak))
                        .font(typography.caption)
                        .foregroundStyle(theme.textFaint)
                } else {
                    Text("No streak yet")
                        .font(typography.body)
                        .foregroundStyle(theme.textDim)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func loadLongestStreak() {
        let countWeekends = countWeekendsTowardStreak
        Storage.shared.allMetGoalDays { days in
            longestStreak = StreakCalculator.longestStreak(metGoalDays: days, countWeekends: countWeekends)
        }
    }

    /// "Mar 4 – Apr 5" (or just "Mar 4" for a one-day streak) from a
    /// `StreakCalculator.longestStreak` result's raw "yyyy-MM-dd" bounds.
    private static func streakRangeLabel(_ streak: (days: Int, start: String, end: String)) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        guard let startDate = DayKey.date(from: streak.start) else { return "\(streak.start) – \(streak.end)" }
        let startLabel = formatter.string(from: startDate)
        if streak.start == streak.end { return startLabel }
        guard let endDate = DayKey.date(from: streak.end) else { return "\(streak.start) – \(streak.end)" }
        return "\(startLabel) – \(formatter.string(from: endDate))"
    }

    private var weekendToggle: some View {
        Toggle(isOn: $countWeekendsTowardStreak) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Count weekends toward streak")
                    .font(typography.label)
                    .foregroundStyle(theme.text)
                Text("Off by default — a quiet Saturday or Sunday won't break a streak built on weekdays.")
                    .font(typography.caption)
                    .foregroundStyle(theme.textFaint)
            }
        }
        .toggleStyle(.switch)
        .tint(theme.accent)
    }

    private var dailyGoalEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Daily goal")
                    .font(typography.label)
                    .foregroundStyle(theme.text)
                Spacer()
                Text("\(dailyGoal.formatted()) keys")
                    .font(typography.monoValue)
                    .foregroundStyle(theme.textDim)
            }
            Slider(
                value: sliderBinding,
                in: Double(AppConfig.Goal.range.lowerBound)...Double(AppConfig.Goal.range.upperBound),
                step: Double(AppConfig.Goal.step)
            )
            .tint(theme.accent)

            HStack(spacing: 8) {
                ForEach(AppConfig.Goal.presets, id: \.name) { preset in
                    presetChip(preset)
                }
            }

            // See Storage.recalculateTodayGoalMet's doc comment for the
            // exact tradeoff: today's credit can move either direction
            // (raise the goal past today's total and it un-earns; lower it
            // back and it re-earns), but any day that's already closed out
            // keeps whatever goal_met it was written with, permanently.
            Text("Changing this only affects today — past days keep whatever they already earned, and raising the goal above what you've already typed today un-earns just today's credit.")
                .font(typography.caption)
                .foregroundStyle(theme.textFaint)
        }
        // dailyGoal itself is the source of truth (@AppStorage, read
        // everywhere else via UserSettings.dailyGoal/@AppStorage) — this
        // just runs the one side effect a goal change needs beyond
        // persisting the number.
        .onChange(of: dailyGoal) { _, newValue in
            Storage.shared.recalculateTodayGoalMet(goal: newValue)
        }
    }

    private func presetChip(_ preset: (name: String, value: Int)) -> some View {
        let isActive = dailyGoal == preset.value
        return Button {
            dailyGoal = preset.value
        } label: {
            VStack(spacing: 1) {
                Text(preset.name)
                    .font(typography.strongSmall)
                Text(preset.value.formatted())
                    .font(typography.monoChipSmall)
            }
            .foregroundStyle(isActive ? theme.bg : theme.textDim)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(isActive ? theme.accent : theme.surfaceRaised)
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isActive ? Color.clear : theme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var sliderBinding: Binding<Double> {
        Binding(get: { Double(dailyGoal) }, set: { dailyGoal = Int($0) })
    }
}
