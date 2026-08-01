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
    @ObservedObject private var permissions = PermissionMonitor.shared
    @State private var selectedTab: Tab = .appearance

    private var theme: AppTheme { AppTheme.theme(forID: themeID) }

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
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(Tab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 12, weight: .medium))
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

    // MARK: - General

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            accessibilitySection
            VStack(alignment: .leading, spacing: 8) {
                Text("More settings coming soon.")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.textDim)
                Text("Display name, launch at login, and the frontmost-app toggle land here next.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.textFaint)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
    }

    private var accessibilitySection: some View {
        let granted = permissions.state == .granted
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Accessibility")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(theme.text)
                Spacer()
                Text(granted ? "Granted" : "Not granted")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(granted ? theme.good : theme.bad)
            }
            if !granted {
                Text("KeyStats can't count keystrokes without Accessibility access. If it already appears enabled in the list, switch it off and back on: select it, press \u{2212}, then press + and re-add KeyStatsApp.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.textFaint)
                Button {
                    permissions.openAccessibilitySettings()
                } label: {
                    Text("Open Accessibility Settings")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.bg)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(theme.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
    }

    // MARK: - Appearance

    private var appearanceTab: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(AppTheme.all) { candidate in
                themeCard(candidate)
            }
        }
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
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                // Fixed height (not just `lineLimit(2)`) so a one-line
                // description doesn't leave its card shorter than a
                // neighbor's two-line one — LazyVGrid sizes each row to its
                // tallest item, but does nothing to equalize row heights
                // against each other, so uneven text is what was making the
                // cards look mismatched.
                Text(candidate.description)
                    .font(.system(size: 10.5))
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
        }
    }

    private var weekendToggle: some View {
        Toggle(isOn: $countWeekendsTowardStreak) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Count weekends toward streak")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(theme.text)
                Text("Off by default — a quiet Saturday or Sunday won't break a streak built on weekdays.")
                    .font(.system(size: 10.5))
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
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(theme.text)
                Spacer()
                Text("\(dailyGoal.formatted()) keys")
                    .font(.system(size: 12, design: .monospaced))
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
                .font(.system(size: 10.5))
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
                    .font(.system(size: 11, weight: .semibold))
                Text(preset.value.formatted())
                    .font(.system(size: 9.5, design: .monospaced))
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
