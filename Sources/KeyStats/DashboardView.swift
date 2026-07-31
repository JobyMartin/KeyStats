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
            VStack(alignment: .leading, spacing: 28) {
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
            .padding(20)
        }
        .frame(minWidth: 500, minHeight: 700)
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

    // MARK: - Error banner

    private var errorBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Database unavailable").font(.headline)
            Text(Storage.shared.lastError ?? "Unknown error")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.red.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .foregroundStyle(.red)
    }

    // MARK: - Header

    private var headerStats: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statCard(title: "Today", value: snapshot.totalToday.formatted())
            statCard(title: "Lifetime", value: snapshot.lifetimeTotal.formatted())
            statCard(title: "Delete ratio", value: String(format: "%.1f%%", snapshot.backspaceRatio * 100))
        }
    }

    private func statCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2).bold().monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Weekly

    private var weeklySection: some View {
        sectionCard("Last 7 days") {
            Chart(snapshot.weeklyTotals) { day in
                BarMark(
                    x: .value("Day", day.label),
                    y: .value("Keys", day.total)
                )
                .foregroundStyle(.blue.opacity(day.day == todayKey ? 1.0 : 0.5))
                .annotation(position: .top) {
                    if day.total > 0 {
                        Text(day.total.formatted())
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 160)
            .chartYAxis(.hidden)
        }
    }

    // MARK: - Hourly

    private var hourlySection: some View {
        sectionCard("Activity — last 24 hours") {
            if snapshot.hourly.isEmpty {
                Text("No data yet").foregroundStyle(.secondary).frame(height: 100)
            } else {
                Chart(snapshot.hourly) { bucket in
                    BarMark(
                        x: .value("Hour", Date(timeIntervalSince1970: Double(bucket.hour)), unit: .hour),
                        y: .value("Keys", bucket.count)
                    )
                }
                .frame(height: 120)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 4)) {
                        AxisValueLabel(format: .dateTime.hour())
                    }
                }
            }
        }
    }

    // MARK: - Top keys

    private var topKeysSection: some View {
        sectionCard("Most-pressed keys") {
            if snapshot.topKeys.isEmpty {
                Text("No data yet").foregroundStyle(.secondary)
            } else {
                Chart(snapshot.topKeys) { item in
                    BarMark(
                        x: .value("Count", item.count),
                        y: .value("Key", item.keyName)
                    )
                    .foregroundStyle(.blue)
                    .annotation(position: .trailing) {
                        Text("\(item.count)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let str = value.as(String.self) {
                                Text(str).font(.system(.caption, design: .monospaced))
                            }
                        }
                    }
                }
                .frame(height: CGFloat(max(snapshot.topKeys.count, 5)) * 26 + 20)
            }
        }
    }

    // MARK: - Modifiers

    private var modifierSection: some View {
        sectionCard("Modifier key usage") {
            if snapshot.modifierCounts.isEmpty {
                Text("No data yet").foregroundStyle(.secondary)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    Chart(snapshot.modifierCounts) { item in
                        SectorMark(angle: .value("Count", item.count), innerRadius: .ratio(0.5))
                            .foregroundStyle(by: .value("Modifier", item.keyName))
                    }
                    .frame(width: 160, height: 160)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(snapshot.modifierCounts.enumerated()), id: \.offset) { _, item in
                            HStack {
                                Text(item.keyName)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(item.count.formatted())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - Keybinds

    private var keybindsSection: some View {
        sectionCard("Top keybinds") {
            if snapshot.topKeybinds.isEmpty {
                Text("No data yet").foregroundStyle(.secondary)
            } else {
                legendList(snapshot.topKeybinds.map { ($0.combo, $0.count) })
            }
        }
    }

    // MARK: - Apps

    private var appsSection: some View {
        sectionCard("Keystrokes by app") {
            if snapshot.topApps.isEmpty {
                Text("No data yet").foregroundStyle(.secondary)
            } else {
                legendList(snapshot.topApps.map { ($0.appName, $0.count) })
            }
        }
    }

    // MARK: - Helpers

    private func sectionCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func legendList(_ items: [(String, Int)]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(items.prefix(15).enumerated()), id: \.offset) { index, item in
                HStack(spacing: 8) {
                    Text(item.0.isEmpty ? "(unknown)" : item.0)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(item.1.formatted())
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                if index < items.prefix(15).count - 1 {
                    Divider().opacity(0.4)
                }
            }
        }
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
