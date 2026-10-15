import Foundation

/// Vacation mode: days covered by it neither extend nor break a streak.
///
/// Anti-cheat rules (both enforced here, not in the UI):
/// - Turning it on only takes effect *tomorrow*, so it can't be flipped on
///   late in the day to rescue a streak that today would otherwise break.
/// - Turning it off takes effect *today*, so today becomes a normal day
///   again immediately. Re-enabling is still deferred to tomorrow, so an
///   off/on flip can't be used to skip today either.
///
/// Past vacations are frozen into `periods` when it's turned off, so the
/// history of which days were exempt never changes after the fact.
enum VacationMode {
    enum Status: Equatable {
        case off
        case scheduled(startDay: String)
        case active(startDay: String)
    }

    struct Period: Equatable {
        let start: String
        let end: String
    }

    static func status(startDay: String, today: Date = Date()) -> Status {
        guard !startDay.isEmpty else { return .off }
        return startDay > DayKey.string(from: today) ? .scheduled(startDay: startDay) : .active(startDay: startDay)
    }

    /// The new `startDay` to store when the user turns vacation on.
    static func enabledStartDay(currentStartDay: String, today: Date = Date()) -> String {
        guard currentStartDay.isEmpty else { return currentStartDay }
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)
        return DayKey.string(from: tomorrow)
    }

    /// The new encoded `periods` to store when the user turns vacation off.
    /// A vacation that hasn't started yet leaves no trace.
    static func periodsAfterDisabling(startDay: String, encodedPeriods: String, today: Date = Date()) -> String {
        guard !startDay.isEmpty,
              let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) else { return encodedPeriods }
        let yesterdayKey = DayKey.string(from: yesterday)
        guard startDay <= yesterdayKey else { return encodedPeriods }
        return encode(decode(encodedPeriods) + [Period(start: startDay, end: yesterdayKey)])
    }

    /// Every "yyyy-MM-dd" day exempt from streak math, including the
    /// in-progress vacation (through today) when one is active.
    static func days(startDay: String, encodedPeriods: String, today: Date = Date()) -> Set<String> {
        var ranges = decode(encodedPeriods)
        if case .active(let start) = status(startDay: startDay, today: today) {
            ranges.append(Period(start: start, end: DayKey.string(from: today)))
        }

        let cal = Calendar.current
        var result = Set<String>()
        for range in ranges {
            guard var cursor = DayKey.date(from: range.start) else { continue }
            var key = range.start
            while key <= range.end {
                result.insert(key)
                guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
                key = DayKey.string(from: cursor)
            }
        }
        return result
    }

    static func decode(_ encoded: String) -> [Period] {
        encoded.split(separator: ";").compactMap { pair in
            let bounds = pair.split(separator: ":").map(String.init)
            guard bounds.count == 2 else { return nil }
            return Period(start: bounds[0], end: bounds[1])
        }
    }

    static func encode(_ periods: [Period]) -> String {
        periods.map { "\($0.start):\($0.end)" }.joined(separator: ";")
    }
}
