import SwiftUI
import Charts

struct DashboardView: View {
    @State private var topKeys: [Storage.KeyCount] = []
    @State private var modifierCounts: [Storage.KeyCount] = []
    @State private var topKeybinds: [Storage.ComboCount] = []
    @State private var topApps: [Storage.AppCount] = []
    @State private var hourly: [Storage.HourBucket] = []
    @State private var weeklyTotals: [Storage.DayTotal] = []
    @State private var lifetimeTotal: Int = 0
    @State private var totalToday: Int = 0
    @State private var backspaceRatio: Double = 0

    private let refreshTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
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
        .onAppear(perform: refresh)
        .onReceive(refreshTimer) { _ in refresh() }
    }

    // MARK: - Header

    private var headerStats: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statCard(title: "Today", value: totalToday.formatted())
            statCard(title: "Lifetime", value: lifetimeTotal.formatted())
            statCard(title: "Delete ratio", value: String(format: "%.1f%%", backspaceRatio * 100))
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
            Chart(weeklyTotals) { day in
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
            if hourly.isEmpty {
                Text("No data yet").foregroundStyle(.secondary).frame(height: 100)
            } else {
                Chart(hourly) { bucket in
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
            if topKeys.isEmpty {
                Text("No data yet").foregroundStyle(.secondary)
            } else {
                Chart(topKeys) { item in
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
                .frame(height: CGFloat(max(topKeys.count, 5)) * 26 + 20)
            }
        }
    }

    // MARK: - Modifiers

    private var modifierSection: some View {
        sectionCard("Modifier key usage") {
            if modifierCounts.isEmpty {
                Text("No data yet").foregroundStyle(.secondary)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    Chart(modifierCounts) { item in
                        SectorMark(angle: .value("Count", item.count), innerRadius: .ratio(0.5))
                            .foregroundStyle(by: .value("Modifier", item.keyName))
                    }
                    .frame(width: 160, height: 160)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(modifierCounts.enumerated()), id: \.offset) { _, item in
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
            if topKeybinds.isEmpty {
                Text("No data yet").foregroundStyle(.secondary)
            } else {
                legendList(topKeybinds.map { ($0.combo, $0.count) })
            }
        }
    }

    // MARK: - Apps

    private var appsSection: some View {
        sectionCard("Keystrokes by app") {
            if topApps.isEmpty {
                Text("No data yet").foregroundStyle(.secondary)
            } else {
                legendList(topApps.map { ($0.appName, $0.count) })
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

    private var todayKey: String { DateFormatter.dayKey.string(from: Date()) }

    private func refresh() {
        topKeys = Storage.shared.topKeys()
        modifierCounts = Storage.shared.modifierCounts()
        topKeybinds = Storage.shared.topKeybinds()
        topApps = Storage.shared.topApps()
        hourly = Storage.shared.last24Hours()
        weeklyTotals = Storage.shared.lastSevenDays()
        lifetimeTotal = Storage.shared.lifetimeTotal()
        backspaceRatio = Storage.shared.backspaceRatioToday()
        totalToday = weeklyTotals.last?.total ?? 0
    }
}
