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
}
