import Foundation

/// Pure streak math — no SQLite, no UserDefaults, no threading constraints.
/// Everything it needs is passed in, so it's trivially testable and safe to
/// call from any thread (in practice: the main thread, from DashboardView).
enum StreakCalculator {
    /// Walks backward from `today`, counting consecutive days present in
    /// `metGoalDays`, and returns the streak length.
    ///
    /// - Parameters:
    ///   - metGoalDays: "yyyy-MM-dd" (see `DayKey`) days that persisted
    ///     `goal_met = 1` at write time (`Storage._metGoalDaysSince`). This
    ///     is a fact recorded once, not recomputed against today's goal —
    ///     so changing the goal later doesn't retroactively add or remove
    ///     days here.
    ///   - countWeekends: when false, Saturday/Sunday are skipped entirely
    ///     (neither extend nor break the streak) — design §5.
    ///   - today: the current date, used both to know which weekday is
    ///     "today" and as the walk's starting point.
    ///   - lookback: hard cap on how many days to walk, regardless of data.
    static func currentStreak(
        metGoalDays: Set<String>,
        countWeekends: Bool,
        today: Date,
        lookback: Int = AppConfig.Goal.streakLookbackDays
    ) -> Int {
        let cal = Calendar.current
        var streak = 0
        var isToday = true

        for offset in 0..<max(lookback, 0) {
            guard let date = cal.date(byAdding: .day, value: -offset, to: today) else { break }

            if !countWeekends {
                let weekday = cal.component(.weekday, from: date) // 1 = Sunday, 7 = Saturday
                if weekday == 1 || weekday == 7 {
                    continue // skips without touching `isToday` or breaking the streak
                }
            }

            let metGoal = metGoalDays.contains(DayKey.string(from: date))

            if isToday {
                // Today is still in progress. Meeting goal already extends
                // the streak; not meeting it yet must NOT break the streak —
                // that would reset every user's streak to 0 every midnight
                // until they've typed enough for the day.
                isToday = false
                if metGoal {
                    streak += 1
                }
                continue
            }

            guard metGoal else { break }
            streak += 1
        }

        return streak
    }

    /// The longest run of consecutive met-goal days across all of
    /// `metGoalDays`, unlike `currentStreak` which only walks backward from
    /// today. Unlike `currentStreak`, there's no "today is still in
    /// progress" exemption here — a streak this returns is made entirely of
    /// days that were already earned.
    ///
    /// - Parameters:
    ///   - metGoalDays: all-time "yyyy-MM-dd" days with `goal_met = 1`
    ///     (`Storage.allMetGoalDays`), not the 365-day-capped
    ///     `Snapshot.streakEligibleDays`.
    ///   - countWeekends: when false, Saturday/Sunday are skipped entirely —
    ///     a run that spans a weekend continues uninterrupted, matching
    ///     `currentStreak`'s semantics (design §5).
    /// - Returns: nil when `metGoalDays` is empty; otherwise the streak
    ///   length and its "yyyy-MM-dd" start/end days.
    static func longestStreak(
        metGoalDays: Set<String>,
        countWeekends: Bool
    ) -> (days: Int, start: String, end: String)? {
        guard let earliestKey = metGoalDays.min(),
              let earliest = DayKey.date(from: earliestKey) else { return nil }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var cursor = cal.startOfDay(for: earliest)

        var best: (days: Int, start: String, end: String)?
        var runLength = 0
        var runStart: String?

        while cursor <= today {
            defer { cursor = cal.date(byAdding: .day, value: 1, to: cursor) ?? today.addingTimeInterval(86400) }

            if !countWeekends {
                let weekday = cal.component(.weekday, from: cursor) // 1 = Sunday, 7 = Saturday
                if weekday == 1 || weekday == 7 {
                    continue // skips without breaking a run in progress
                }
            }

            let key = DayKey.string(from: cursor)
            if metGoalDays.contains(key) {
                if runStart == nil { runStart = key }
                runLength += 1
                if best == nil || runLength > best!.days {
                    best = (days: runLength, start: runStart!, end: key)
                }
            } else {
                runLength = 0
                runStart = nil
            }
        }

        return best
    }
}
