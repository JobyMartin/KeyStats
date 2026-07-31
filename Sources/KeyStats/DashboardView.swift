import SwiftUI
import Charts

struct DashboardView: View {
    @State private var snapshot = Storage.Snapshot()
    @State private var isVisible = false
    // @State so SwiftUI owns this publisher's lifetime, not the (possibly
    // re-created) view struct.
    @State private var refreshTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if !Storage.shared.isAvailable {
                    errorBanner
                }
                headerStats
                weeklySection
                hourlySection
                topKeysSection
                modifierSection
                keybindsSection
                appsSection
            }
            .padding(22)
        }
        .background(Theme.bg)
        .scrollContentBackground(.hidden)
        .frame(minWidth: 560, minHeight: 760)
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

    // Ring Gauge mark + wordmark. Static for now — a status pill, settings
    // gear, and theme switcher were all designed (see znotes/design.md
    // §4.1) but need state this app doesn't have yet (pause/resume,
    // Preferences window, theme selection), so they're left out here.
    private var header: some View {
        HStack(spacing: 9) {
            RingGaugeMark(size: 28)
            Text("KeyStats")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)
            Spacer()
        }
    }

    // MARK: - Error banner

    private var errorBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Database unavailable").font(.headline)
            Text(Storage.shared.lastError ?? "Unknown error")
                .font(.caption)
                .foregroundStyle(Theme.textDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.bad.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .foregroundStyle(Theme.bad)
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
                .foregroundStyle(Theme.textFaint)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundStyle(primary ? Theme.accent : Theme.text)
            // Always render this line, even when there's no subtitle —
            // otherwise this card is one line shorter than its siblings
            // and the row heights in headerStats' grid don't match.
            Text(subtitle ?? " ")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textFaint)
                .opacity(subtitle == nil ? 0 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(primary ? Theme.surfaceRaised : Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(primary ? Theme.accent.opacity(0.35) : Theme.border, lineWidth: 1)
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
                .foregroundStyle(day.day == todayKey ? Theme.accent : Theme.surfaceRaised)
                .cornerRadius(3)
                .annotation(position: .top) {
                    if day.total > 0 {
                        Text(day.total.formatted())
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Theme.textFaint)
                    }
                }
            }
            .frame(height: 160)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel().foregroundStyle(Theme.textFaint)
                }
            }
        }
    }

    // MARK: - Hourly (heatmap grid)

    private var hourlySection: some View {
        sectionCard("Activity — last 24 hours") {
            if snapshot.hourly.isEmpty {
                Text("No data yet").foregroundStyle(Theme.textFaint).frame(height: 120)
            } else {
                Chart(snapshot.hourly) { bucket in
                    BarMark(
                        x: .value("Hour", Date(timeIntervalSince1970: Double(bucket.hour)), unit: .hour),
                        y: .value("Keys", bucket.count)
                    )
                    .foregroundStyle(Theme.accent)
                    .cornerRadius(2)
                }
                .frame(height: 140)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 4)) {
                        AxisGridLine().foregroundStyle(Theme.borderSoft)
                        AxisValueLabel(format: .dateTime.hour()).foregroundStyle(Theme.textFaint)
                    }
                }
                .chartYAxis {
                    AxisMarks {
                        AxisGridLine().foregroundStyle(Theme.borderSoft)
                        AxisValueLabel().foregroundStyle(Theme.textFaint)
                    }
                }
            }
        }
    }

    // MARK: - Top keys

    private var topKeysSection: some View {
        sectionCard("Most-pressed keys") {
            if snapshot.topKeys.isEmpty {
                Text("No data yet").foregroundStyle(Theme.textFaint)
            } else {
                let maxCount = snapshot.topKeys.first?.count ?? 1
                VStack(spacing: 8) {
                    ForEach(snapshot.topKeys) { item in
                        HStack(spacing: 10) {
                            keycapChip(item.keyName)
                            barTrack(fraction: Double(item.count) / Double(maxCount), color: Theme.accent)
                                .frame(height: 16)
                            Text(item.count.formatted())
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.textDim)
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
            .foregroundStyle(Theme.textDim)
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .frame(width: 34, height: 20)
            .background(Theme.surfaceRaised)
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
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
                .fill(Theme.borderSoft)
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
                Text("No data yet").foregroundStyle(Theme.textFaint)
            } else {
                let total = max(1, snapshot.modifierCounts.reduce(0) { $0 + $1.count })
                VStack(spacing: 9) {
                    ForEach(Array(snapshot.modifierCounts.enumerated()), id: \.offset) { index, item in
                        let color = Theme.series[index % Theme.series.count]
                        let pct = Double(item.count) / Double(total)
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(color)
                                .frame(width: 8, height: 8)
                            Text(item.keyName)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Theme.text)
                                .frame(width: 64, alignment: .leading)
                            barTrack(fraction: pct, color: color)
                                .frame(height: 6)
                            Text(String(format: "%.0f%%", pct * 100))
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textFaint)
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
                Text("No data yet").foregroundStyle(Theme.textFaint)
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
                        Text("+").font(.system(size: 10)).foregroundStyle(Theme.textFaint)
                    }
                    Text(part)
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Theme.bg)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            Text(count.formatted())
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.surfaceRaised)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
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
                Text("No data yet").foregroundStyle(Theme.textFaint)
            } else {
                let items = Array(snapshot.topApps.prefix(15).enumerated())
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.offset) { position, pair in
                        let (index, item) = pair
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Theme.series[index % Theme.series.count])
                                .frame(width: 9, height: 9)
                            Text(item.appName.isEmpty ? "(unknown)" : item.appName)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.text)
                            Spacer()
                            Text(item.count.formatted())
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(Theme.textDim)
                        }
                        .padding(.vertical, 7)
                        if position < items.count - 1 {
                            Divider().overlay(Theme.borderSoft)
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
                .foregroundStyle(Theme.text)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
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
