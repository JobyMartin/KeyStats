import Foundation
import SQLite3

// SQLITE_TRANSIENT tells SQLite to copy the string before the call returns,
// which is essential when passing Swift String values — without it, SQLite
// holds a pointer to memory that Swift may have already freed, causing the
// corrupted/truncated text we saw in the dashboard.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type?.self)

final class Storage {
    static let shared = Storage()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "keystats.db.queue")

    private init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KeyStats", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbPath = dir.appendingPathComponent("keystats.sqlite").path

        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            fatalError("Unable to open database at \(dbPath)")
        }
        createTables()
    }

    private func createTables() {
        let statements = [
            """
            CREATE TABLE IF NOT EXISTS key_counts (
                key_code INTEGER PRIMARY KEY,
                key_name TEXT NOT NULL,
                count INTEGER NOT NULL DEFAULT 0
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS modifier_counts (
                modifier TEXT PRIMARY KEY,
                count INTEGER NOT NULL DEFAULT 0
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS keybind_counts (
                combo TEXT PRIMARY KEY,
                count INTEGER NOT NULL DEFAULT 0,
                last_used INTEGER NOT NULL DEFAULT 0
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS hourly_activity (
                hour_bucket INTEGER PRIMARY KEY,
                count INTEGER NOT NULL DEFAULT 0
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS app_activity (
                app_name TEXT PRIMARY KEY,
                count INTEGER NOT NULL DEFAULT 0
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS daily_totals (
                day TEXT PRIMARY KEY,
                total_keys INTEGER NOT NULL DEFAULT 0,
                backspace_count INTEGER NOT NULL DEFAULT 0
            );
            """
        ]
        for sql in statements { exec(sql) }
    }

    private func exec(_ sql: String) {
        var errMsg: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown error"
            print("SQLite error: \(msg)")
            sqlite3_free(errMsg)
        }
    }

    // MARK: - Writers

    func recordKey(code: Int, name: String) {
        queue.async {
            self.run("""
                INSERT INTO key_counts (key_code, key_name, count) VALUES (?, ?, 1)
                ON CONFLICT(key_code) DO UPDATE SET count = count + 1;
                """) { stmt in
                sqlite3_bind_int(stmt, 1, Int32(code))
                sqlite3_bind_text(stmt, 2, name, -1, SQLITE_TRANSIENT)
            }
        }
    }

    func recordModifier(_ name: String) {
        queue.async {
            self.run("""
                INSERT INTO modifier_counts (modifier, count) VALUES (?, 1)
                ON CONFLICT(modifier) DO UPDATE SET count = count + 1;
                """) { stmt in
                sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT)
            }
        }
    }

    func recordKeybind(_ combo: String) {
        queue.async {
            let now = Int64(Date().timeIntervalSince1970)
            self.run("""
                INSERT INTO keybind_counts (combo, count, last_used) VALUES (?, 1, ?)
                ON CONFLICT(combo) DO UPDATE SET count = count + 1, last_used = excluded.last_used;
                """) { stmt in
                sqlite3_bind_text(stmt, 1, combo, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int64(stmt, 2, now)
            }
        }
    }

    func recordHourlyActivity() {
        queue.async {
            let bucket = Int64(Date().timeIntervalSince1970 / 3600) * 3600
            self.run("""
                INSERT INTO hourly_activity (hour_bucket, count) VALUES (?, 1)
                ON CONFLICT(hour_bucket) DO UPDATE SET count = count + 1;
                """) { stmt in
                sqlite3_bind_int64(stmt, 1, bucket)
            }
        }
    }

    func recordApp(_ appName: String) {
        queue.async {
            self.run("""
                INSERT INTO app_activity (app_name, count) VALUES (?, 1)
                ON CONFLICT(app_name) DO UPDATE SET count = count + 1;
                """) { stmt in
                sqlite3_bind_text(stmt, 1, appName, -1, SQLITE_TRANSIENT)
            }
        }
    }

    func recordDaily(isBackspace: Bool) {
        queue.async {
            let day = DateFormatter.dayKey.string(from: Date())
            self.run("""
                INSERT INTO daily_totals (day, total_keys, backspace_count) VALUES (?, 1, ?)
                ON CONFLICT(day) DO UPDATE SET
                    total_keys = total_keys + 1,
                    backspace_count = backspace_count + excluded.backspace_count;
                """) { stmt in
                sqlite3_bind_text(stmt, 1, day, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int(stmt, 2, isBackspace ? 1 : 0)
            }
        }
    }

    private func run(_ sql: String, bind: (OpaquePointer?) -> Void) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            print("Failed to prepare: \(sql)")
            return
        }
        bind(stmt)
        if sqlite3_step(stmt) != SQLITE_DONE {
            print("Failed to step: \(sql)")
        }
        sqlite3_finalize(stmt)
    }

    // MARK: - Model types

    struct KeyCount: Identifiable {
        let id = UUID()
        let keyName: String
        let count: Int
    }
    struct ComboCount: Identifiable {
        let id = UUID()
        let combo: String
        let count: Int
    }
    struct AppCount: Identifiable {
        let id = UUID()
        let appName: String
        let count: Int
    }
    struct HourBucket: Identifiable {
        let id: Int  // the unix timestamp of the hour
        let hour: Int
        let count: Int
    }
    struct DayTotal: Identifiable {
        let id: String  // the day string e.g. "2025-06-01"
        let day: String
        let label: String  // short display label e.g. "Mon"
        let total: Int
        let backspaces: Int
    }

    // MARK: - Readers

    func topKeys(limit: Int = 15) -> [KeyCount] {
        readPairs("SELECT key_name, count FROM key_counts ORDER BY count DESC LIMIT \(limit);")
            .map { KeyCount(keyName: $0.0, count: $0.1) }
    }

    func modifierCounts() -> [KeyCount] {
        readPairs("SELECT modifier, count FROM modifier_counts ORDER BY count DESC;")
            .map { KeyCount(keyName: $0.0, count: $0.1) }
    }

    func topKeybinds(limit: Int = 15) -> [ComboCount] {
        readPairs("SELECT combo, count FROM keybind_counts ORDER BY count DESC LIMIT \(limit);")
            .map { ComboCount(combo: $0.0, count: $0.1) }
    }

    func topApps(limit: Int = 10) -> [AppCount] {
        readPairs("SELECT app_name, count FROM app_activity ORDER BY count DESC LIMIT \(limit);")
            .map { AppCount(appName: $0.0, count: $0.1) }
    }

    func last24Hours() -> [HourBucket] {
        let cutoff = Int64(Date().timeIntervalSince1970) - 24 * 3600
        var result: [HourBucket] = []
        var stmt: OpaquePointer?
        let sql = "SELECT hour_bucket, count FROM hourly_activity WHERE hour_bucket >= ? ORDER BY hour_bucket ASC;"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, cutoff)
            while sqlite3_step(stmt) == SQLITE_ROW {
                let h = Int(sqlite3_column_int64(stmt, 0))
                let c = Int(sqlite3_column_int64(stmt, 1))
                result.append(HourBucket(id: h, hour: h, count: c))
            }
        }
        sqlite3_finalize(stmt)
        return result
    }

    /// Returns the last 7 days (including today) as daily totals, oldest first.
    func lastSevenDays() -> [DayTotal] {
        let cal = Calendar.current
        let today = Date()
        // Build the list of day strings we want
        let days: [String] = (0..<7).reversed().compactMap { offset in
            guard let date = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DateFormatter.dayKey.string(from: date)
        }

        // Fetch all rows for those days
        var rows: [String: (Int, Int)] = [:]
        var stmt: OpaquePointer?
        // SQLite IN clause with 7 placeholders
        let placeholders = days.map { _ in "?" }.joined(separator: ",")
        let sql = "SELECT day, total_keys, backspace_count FROM daily_totals WHERE day IN (\(placeholders));"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            for (i, day) in days.enumerated() {
                sqlite3_bind_text(stmt, Int32(i + 1), day, -1, SQLITE_TRANSIENT)
            }
            while sqlite3_step(stmt) == SQLITE_ROW {
                let d = String(cString: sqlite3_column_text(stmt, 0))
                let t = Int(sqlite3_column_int64(stmt, 1))
                let b = Int(sqlite3_column_int64(stmt, 2))
                rows[d] = (t, b)
            }
        }
        sqlite3_finalize(stmt)

        let shortDay = DateFormatter.shortDay
        return days.compactMap { dayStr -> DayTotal? in
            guard let date = DateFormatter.dayKey.date(from: dayStr) else { return nil }
            let label = shortDay.string(from: date)
            let (total, backspaces) = rows[dayStr] ?? (0, 0)
            return DayTotal(id: dayStr, day: dayStr, label: label, total: total, backspaces: backspaces)
        }
    }

    func lifetimeTotal() -> Int {
        var stmt: OpaquePointer?
        var total = 0
        let sql = "SELECT COALESCE(SUM(total_keys), 0) FROM daily_totals;"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                total = Int(sqlite3_column_int64(stmt, 0))
            }
        }
        sqlite3_finalize(stmt)
        return total
    }

    func backspaceRatioToday() -> Double {
        let day = DateFormatter.dayKey.string(from: Date())
        var stmt: OpaquePointer?
        var total = 0
        var backspaces = 0
        let sql = "SELECT total_keys, backspace_count FROM daily_totals WHERE day = ?;"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, day, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW {
                total = Int(sqlite3_column_int64(stmt, 0))
                backspaces = Int(sqlite3_column_int64(stmt, 1))
            }
        }
        sqlite3_finalize(stmt)
        guard total > 0 else { return 0 }
        return Double(backspaces) / Double(total)
    }

    private func readPairs(_ sql: String) -> [(String, Int)] {
        var result: [(String, Int)] = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let raw = sqlite3_column_text(stmt, 0) else { continue }
                let name = String(cString: raw)
                let count = Int(sqlite3_column_int64(stmt, 1))
                result.append((name, count))
            }
        }
        sqlite3_finalize(stmt)
        return result
    }
}

extension DateFormatter {
    static let dayKey: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    static let shortDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"  // "Mon", "Tue", etc.
        return f
    }()
}
