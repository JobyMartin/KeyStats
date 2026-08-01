import SwiftUI
import Charts

struct DashboardView: View {
    @State private var snapshot = Storage.Snapshot()
    @State private var isVisible = false
    @ObservedObject private var permissions = PermissionMonitor.shared
    // @State so SwiftUI owns this publisher's lifetime, not the (possibly
    // re-created) view struct.
    @State private var refreshTimer = Timer.publish(every: AppConfig.Timing.dashboardRefresh, on: .main, in: .common).autoconnect()
    // No Preferences UI yet (design §8.4) — this key is read/written today
    // only via `defaults write`/`defaults delete`, but binding through
    // @AppStorage means a future slider needs zero rework here.
    @AppStorage(AppConfig.Defaults.dailyGoal) private var dailyGoal = AppConfig.Goal.defaultDaily
    @AppStorage(AppConfig.Defaults.countWeekendsTowardStreak) private var countWeekendsTowardStreak = AppConfig.Goal.countWeekendsTowardStreakDefault
    // Theme picker itself now lives in Preferences → Appearance
    // (PreferencesView.swift) — this just needs to read the same key so the
    // dashboard repaints when it's changed there.
    @AppStorage(AppConfig.Defaults.themeID) private var themeID = AppTheme.backlit.id

    private var theme: AppTheme { AppTheme.theme(forID: themeID) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppConfig.Layout.sectionSpacing) {
                header
                if permissions.state != .granted {
                    permissionBanner
                }
                if !Storage.shared.isAvailable {
                    errorBanner
                }
                headerStats
                goalSection
                weeklySection
                hourlySection
                topKeysSection
                modifierSection
                keybindsSection
                appsSection
            }
            .padding(AppConfig.Layout.contentPadding)
        }
        .background(theme.bg)
        .scrollContentBackground(.hidden)
        .frame(minWidth: AppConfig.Window.dashboardMinWidth, minHeight: AppConfig.Window.dashboardMinHeight)
        .environment(\.theme, theme)
        .onAppear {
            isVisible = true
            refresh()
        }
        .onDisappear {
            isVisible = false
        }
        .onReceive(refreshTimer) { _ in
            if isVisible { refresh() }
        }
    }

    // MARK: - Header

    // Ring Gauge mark + wordmark + settings gear. The status pill (design
    // §4.1) still needs state this app doesn't have yet (pause/resume). The
    // gear opens the real Preferences window (PreferencesView.swift) —
    // AppDelegate owns that window, so this just posts a notification for
    // it to handle, the same indirection pattern as the power-notification
    // observers in AppDelegate.
    private var header: some View {
        HStack(spacing: 9) {
            RingGaugeMark(size: 28)
            Text("KeyStats")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.text)
            Spacer()
            settingsButton
        }
    }

    private var settingsButton: some View {
        Button {
            NotificationCenter.default.post(name: .openPreferences, object: nil)
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.textDim)
                .frame(width: 26, height: 26)
                .background(theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(theme.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Permission banner

    private var permissionBannerTitle: String {
        switch permissions.state {
        case .granted:
            return ""
        case .notTrusted:
            return permissions.everHadPermission
                ? "KeyStats stopped counting keystrokes"
                : "KeyStats needs Accessibility permission"
        case .trustedButTapFailed:
            return "KeyStats can't read keystrokes"
        }
    }

    private var permissionBannerMessage: String {
        switch permissions.state {
        case .granted:
            return ""
        case .notTrusted:
            return permissions.everHadPermission
                ? "Accessibility permission was lost — this usually happens after the app is updated. If KeyStats already appears enabled in the list below, switch it off and back on: select it, press \u{2212}, then press + and choose KeyStatsApp again."
                : "Grant Accessibility access so KeyStats can count your keystrokes."
        case .trustedButTapFailed:
            return "macOS reports permission as granted but refused to start capturing keystrokes. Remove KeyStats from the list below, add it back, then quit and reopen KeyStats."
        }
    }

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(permissionBannerTitle, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
            Text(permissionBannerMessage)
                .font(.caption)
                .foregroundStyle(theme.textDim)
            HStack(spacing: 8) {
                Button {
                    permissions.openAccessibilitySettings()
                } label: {
                    Text("Open Accessibility Settings")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(theme.bg)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    permissions.copyResetCommand()
                } label: {
                    Text("Copy reset command")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(theme.bad)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(theme.bad.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .foregroundStyle(theme.bad)
    }

    // MARK: - Error banner

    private var errorBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Database unavailable").font(.headline)
            Text(Storage.shared.lastError ?? "Unknown error")
                .font(.caption)
                .foregroundStyle(theme.textDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(theme.bad.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .foregroundStyle(theme.bad)
    }

    // MARK: - Header stats

    private var headerStats: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            statCard(title: "Today", value: snapshot.totalToday.formatted(), primary: true)
            statCard(
                title: "Lifetime",
                value: snapshot.lifetimeTotal.formatted(),
                subtitle: snapshot.joinedLabel.isEmpty ? nil : "since \(snapshot.joinedLabel)"
            )
            statCard(title: "Delete ratio", value: String(format: "%.1f%%", snapshot.backspaceRatio * 100))
        }
    }

    private func statCard(title: String, value: String, subtitle: String? = nil, primary: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(theme.textFaint)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundStyle(primary ? theme.accent : theme.text)
            // Always render this line, even when there's no subtitle —
            // otherwise this card is one line shorter than its siblings
            // and the row heights in headerStats' grid don't match.
            Text(subtitle ?? " ")
                .font(.system(size: 10.5))
                .foregroundStyle(theme.textFaint)
                .opacity(subtitle == nil ? 0 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppConfig.Layout.statCardPadding)
        .background(primary ? theme.surfaceRaised : theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppConfig.Layout.statCardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppConfig.Layout.statCardCornerRadius, style: .continuous)
                .stroke(primary ? theme.accent.opacity(0.35) : theme.border, lineWidth: 1)
        )
    }

    // MARK: - Goal

    private var goalSection: some View {
        HStack(spacing: 16) {
            RingGauge(
                progress: goalProgress,
                lineWidth: AppConfig.Layout.goalRingLineWidth,
                trackColor: theme.borderSoft,
                progressColor: goalMet ? theme.good : theme.accent
            )
            .frame(width: AppConfig.Layout.goalRingSize, height: AppConfig.Layout.goalRingSize)
            .animation(.easeOut(duration: 0.4), value: goalProgress)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(goalPercent)% of daily goal")
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(theme.text)
                Text("\(snapshot.totalToday.formatted()) / \(dailyGoal.formatted()) keys")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.textDim)
            }

            Spacer()

            if streak > 0 {
                Text("🔥 \(streak)-day streak")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(theme.accent)
            }
        }
        .padding(AppConfig.Layout.cardPadding)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppConfig.Layout.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppConfig.Layout.cardCornerRadius, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
    }

    /// Clamped to the ring's 0...1 trim range.
    private var goalProgress: Double {
        guard dailyGoal > 0 else { return 0 }
        return min(max(Double(snapshot.totalToday) / Double(dailyGoal), 0), 1)
    }

    /// Unclamped, unlike `goalProgress` — so "142% of daily goal" reads
    /// correctly once the ring itself is already full.
    private var goalPercent: Int {
        guard dailyGoal > 0 else { return 0 }
        return Int((Double(snapshot.totalToday) / Double(dailyGoal) * 100).rounded())
    }

    private var goalMet: Bool {
        dailyGoal > 0 && snapshot.totalToday >= dailyGoal
    }

    private var streak: Int {
        StreakCalculator.currentStreak(
            metGoalDays: snapshot.streakEligibleDays,
            countWeekends: countWeekendsTowardStreak,
            today: Date()
        )
    }

    // MARK: - Weekly

    private var weeklySection: some View {
        sectionCard("Last 7 days") {
            Chart(snapshot.weeklyTotals) { day in
                BarMark(
                    x: .value("Day", day.label),
                    y: .value("Keys", day.total)
                )
                .foregroundStyle(day.day == todayKey ? theme.accent : theme.surfaceRaised)
                .cornerRadius(3)
                .annotation(position: .top) {
                    if day.total > 0 {
                        Text(day.total.formatted())
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(theme.textFaint)
                    }
                }
            }
            .frame(height: AppConfig.Layout.weeklyChartHeight)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel().foregroundStyle(theme.textFaint)
                }
            }
        }
    }

    // MARK: - Hourly (heatmap grid)

    private var hourlySection: some View {
        sectionCard("Activity — last 24 hours") {
            if snapshot.hourly.isEmpty {
                Text("No data yet").foregroundStyle(theme.textFaint).frame(height: 120)
            } else {
                Chart(snapshot.hourly) { bucket in
                    BarMark(
                        x: .value("Hour", Date(timeIntervalSince1970: Double(bucket.hour)), unit: .hour),
                        y: .value("Keys", bucket.count)
                    )
                    .foregroundStyle(theme.accent)
                    .cornerRadius(2)
                }
                .frame(height: AppConfig.Layout.hourlyChartHeight)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 4)) {
                        AxisGridLine().foregroundStyle(theme.borderSoft)
                        AxisValueLabel(format: .dateTime.hour()).foregroundStyle(theme.textFaint)
                    }
                }
                .chartYAxis {
                    AxisMarks {
                        AxisGridLine().foregroundStyle(theme.borderSoft)
                        AxisValueLabel().foregroundStyle(theme.textFaint)
                    }
                }
            }
        }
    }

    // MARK: - Top keys

    private var topKeysSection: some View {
        sectionCard("Most-pressed keys") {
            if snapshot.topKeys.isEmpty {
                Text("No data yet").foregroundStyle(theme.textFaint)
            } else {
                let maxCount = snapshot.topKeys.first?.count ?? 1
                VStack(spacing: 8) {
                    ForEach(snapshot.topKeys) { item in
                        HStack(spacing: 10) {
                            keycapChip(item.keyName)
                            barTrack(fraction: Double(item.count) / Double(maxCount), color: theme.accent)
                                .frame(height: 16)
                            Text(item.count.formatted())
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(theme.textDim)
                                .frame(width: 42, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    /// A bordered chip styled like a physical keycap. Fixed width so every
    /// row's bar starts at the same x position — long legends ("Forward
    /// Delete") get abbreviated to a symbol instead of widening the chip.
    private func keycapChip(_ label: String) -> some View {
        Text(Self.shortKeyLabel(label))
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(theme.textDim)
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .frame(width: 34, height: 20)
            .background(theme.surfaceRaised)
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    /// Short glyph/abbreviation for key names that would otherwise blow out
    /// a fixed-width keycap chip. Anything not listed here just falls back
    /// to the raw name with `minimumScaleFactor` as a safety net.
    private static func shortKeyLabel(_ name: String) -> String {
        switch name {
        case "Delete": return "⌫"
        case "Forward Delete": return "⌦"
        case "Space": return "␣"
        case "Return": return "⏎"
        case "Tab": return "⇥"
        case "Escape": return "⎋"
        case "Left Arrow": return "←"
        case "Right Arrow": return "→"
        case "Up Arrow": return "↑"
        case "Down Arrow": return "↓"
        case "Enter (Numpad)": return "⌤"
        case "Home": return "Hm"
        case "End": return "End"
        case "Page Up": return "PgU"
        case "Page Down": return "PgD"
        default: return name
        }
    }

    private func barTrack(fraction: Double, color: Color) -> some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(theme.borderSoft)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(LinearGradient(colors: [color.opacity(0.45), color], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * max(0, min(1, fraction)))
                }
        }
    }

    // MARK: - Modifiers

    private var modifierSection: some View {
        sectionCard("Modifier key usage") {
            if snapshot.modifierCounts.isEmpty {
                Text("No data yet").foregroundStyle(theme.textFaint)
            } else {
                let total = max(1, snapshot.modifierCounts.reduce(0) { $0 + $1.count })
                VStack(spacing: 9) {
                    ForEach(Array(snapshot.modifierCounts.enumerated()), id: \.offset) { index, item in
                        let color = theme.series[index % theme.series.count]
                        let pct = Double(item.count) / Double(total)
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(color)
                                .frame(width: 8, height: 8)
                            Text(item.keyName)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(theme.text)
                                .frame(width: 64, alignment: .leading)
                            barTrack(fraction: pct, color: color)
                                .frame(height: 6)
                            Text(String(format: "%.0f%%", pct * 100))
                                .font(.system(size: 11))
                                .foregroundStyle(theme.textFaint)
                                .frame(width: 34, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Keybinds

    private var keybindsSection: some View {
        sectionCard("Top keybinds") {
            if snapshot.topKeybinds.isEmpty {
                Text("No data yet").foregroundStyle(theme.textFaint)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(snapshot.topKeybinds) { item in
                        comboChip(item.combo, count: item.count)
                    }
                }
            }
        }
    }

    /// Renders a combo like "Cmd+Shift+Z" as individual bordered key chips
    /// joined by "+", instead of one plain text label.
    private func comboChip(_ combo: String, count: Int) -> some View {
        let parts = combo.split(separator: "+").map(String.init)
        return HStack(spacing: 8) {
            HStack(spacing: 3) {
                ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                    if index > 0 {
                        Text("+").font(.system(size: 10)).foregroundStyle(theme.textFaint)
                    }
                    Text(part)
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.text)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(theme.bg)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.border, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            Text(count.formatted())
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.accent)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(theme.surfaceRaised)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        // Without this, FlowLayout's placement proposal can end up a hair
        // narrower than the chip's ideal width, and SwiftUI silently
        // truncates one of the inner key labels to "…" instead of just
        // rendering it — this pins the chip to its true intrinsic size so
        // that can't happen.
        .fixedSize()
    }

    // MARK: - Apps

    private var appsSection: some View {
        sectionCard("Keystrokes by app") {
            if snapshot.topApps.isEmpty {
                Text("No data yet").foregroundStyle(theme.textFaint)
            } else {
                let items = Array(snapshot.topApps.prefix(AppConfig.Layout.legendMaxRows).enumerated())
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.offset) { position, pair in
                        let (index, item) = pair
                        HStack(spacing: 10) {
                            Circle()
                                .fill(theme.series[index % theme.series.count])
                                .frame(width: 9, height: 9)
                            Text(item.appName.isEmpty ? "(unknown)" : item.appName)
                                .font(.system(size: 12.5))
                                .foregroundStyle(theme.text)
                            Spacer()
                            Text(item.count.formatted())
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(theme.textDim)
                        }
                        .padding(.vertical, 7)
                        if position < items.count - 1 {
                            Divider().overlay(theme.borderSoft)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(theme.text)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppConfig.Layout.cardPadding)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppConfig.Layout.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppConfig.Layout.cardCornerRadius, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
    }

    private var todayKey: String { DayKey.string(from: Date()) }

    private func refresh() {
        // Runs on the db queue; result delivered back on main. The main
        // thread never touches SQLite anymore — this is the reader half of
        // the crash fix.
        Storage.shared.snapshot { snap in
            snapshot = snap
        }
    }
}

// MARK: - Flow layout

/// Simple left-to-right, wrapping row layout — used for the keybind chips,
/// which vary in width and shouldn't be forced into a fixed grid.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        y += rowHeight
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
