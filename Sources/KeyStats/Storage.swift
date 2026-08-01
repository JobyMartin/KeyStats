import Foundation
import SQLite3

// SQLITE_TRANSIENT tells SQLite to copy the string before the call returns,
// which is essential when passing Swift String values — without it, SQLite
// holds a pointer to memory that Swift may have already freed, causing the
// corrupted/truncated text we saw in the dashboard.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type?.self)

// MARK: - Threading contract (read this before touching this file)
//
// This class has exactly one `OpaquePointer` sqlite3 connection and one
// serial dispatch `queue`. The crash this app used to have was two threads
// (the event tap's main-thread callback and the dashboard's 5s reader
// timer) calling into that ONE connection at the same time, which corrupts
// SQLite's internal allocator (not a Swift-level crash — a heap-corruption
// SIGSEGV *inside* libsqlite3).
//
// Rules, enforced by convention because Swift can't check them for us:
//   1. Any function named `_foo()` or `fooOnQueue()` assumes it is already
//      running on `queue`. It must NEVER call `queue.sync` or `queue.async`.
//   2. Every public method except `record(_:)` hops onto `queue` exactly
//      once, at its outermost level.
//   3. `record(_:)` never touches `queue` at all — it only touches the
//      in-memory buffer, guarded by `bufferLock`.
//   4. `bufferLock` is never held across a `sqlite3_*` call, and never held
//      while acquiring any other lock.
// Breaking rule 1 causes `queue.sync` to be called from a block already
// running on `queue`, which is an immediate, permanent deadlock (not a
// timeout) — the single easiest way to reintroduce a bug here.
final class Storage {
    static let shared = Storage()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "keystats.db.queue")

    /// False when the database could not be opened. Writes become no-ops,
    /// reads return empty results — the app keeps running instead of
    /// crashing (this used to be a `fatalError`).
    private(set) var isAvailable = false
    /// Human-readable reason we're degraded, shown on the dashboard.
    private(set) var lastError: String?
    /// Where we actually opened. Logged because it differs between the
    /// sandboxed .app (its container) and `swift run` (real ~/Library).
    private(set) var databasePath = ""

    private init() {
        let fm = FileManager.default
        // NOTE: if this app's App Sandbox entitlement is ever removed,
        // this resolves to a DIFFERENT directory than the sandboxed build
        // used, and a whole month of history will appear to vanish. Any
        // future de-sandboxing must explicitly migrate from the old
        // container path (~/Library/Containers/com.joby.KeyStatsApp/Data/…)
        // rather than trusting this API to keep pointing at the same place.
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        let dir = base.appendingPathComponent("KeyStats", isDirectory: true)

        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            lastError = "Could not create \(dir.path): \(error.localizedDescription)"
            NSLog("KeyStats: %@", lastError!)
            return // degraded: isAvailable stays false
        }

        databasePath = dir.appendingPathComponent("keystats.sqlite").path

        // FULLMUTEX makes sqlite take its own mutex around every call on
        // this connection. It is defence in depth, NOT the fix — it does
        // nothing about two threads sharing one *statement*. The actual fix
        // is the queue discipline documented above.
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databasePath, &db, flags, nil) == SQLITE_OK, db != nil else {
            let msg = db != nil ? String(cString: sqlite3_errmsg(db)) : "unknown error"
            lastError = "Could not open \(databasePath): \(msg)"
            NSLog("KeyStats: %@", lastError!)
            if db != nil { sqlite3_close(db); db = nil } // open_v2 can hand back a handle even on failure
            return
        }

        sqlite3_busy_timeout(db, AppConfig.Timing.sqliteBusyTimeoutMs)
        exec("PRAGMA journal_mode = WAL;")
        exec("PRAGMA synchronous = NORMAL;") // safe with WAL

        createTables()
        guard migrate() else {
            lastError = lastError ?? "Schema migration failed"
            NSLog("KeyStats: %@", lastError!)
            sqlite3_close(db)
            db = nil
            return // degraded: isAvailable stays false, matching the open-failure path above
        }
        isAvailable = true
        NSLog("KeyStats: opened db at %@ (threadsafe=%d)", databasePath, sqlite3_threadsafe())

        startFlushTimer()
        logStartupSanity()
    }

    // MARK: - Schema
    //
    // Do NOT change this. The live database (a month of real stats) has
    // this exact schema; these CREATE TABLE statements are idempotent
    // no-ops against it. This is version 0 of the schema — see `migrate()`
    // below for how to change it going forward.
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
            NSLog("KeyStats: SQLite error: %@ (sql: %@)", msg, sql)
            sqlite3_free(errMsg)
        }
    }

    // MARK: - Migrations
    //
    // `createTables()`'s `CREATE TABLE IF NOT EXISTS` handles a *missing
    // table* fine, but does nothing for a new column on a table that
    // already exists — SQLite has no `ADD COLUMN IF NOT EXISTS`. Without
    // this, an update that adds a column would ship fine to a fresh install
    // (which gets it from `createTables()`) but leave every existing
    // install's table one column short, and every write touching it would
    // fail from then on. This is the numbered-steps system called for above.
    //
    // Rules for adding a step:
    //   1. Steps are APPEND-ONLY. Never edit a step that has already
    //      shipped — an install that already ran it will never run it again.
    //   2. `ALTER TABLE ... ADD COLUMN` can't add `NOT NULL` without a
    //      `DEFAULT`; always supply one (see the existing counter columns'
    //      `DEFAULT 0` for the convention).
    //   3. This runs on the init thread, before `startFlushTimer()` — i.e.
    //      before `queue` has any other work queued — so it is the one
    //      place in this file exempt from the "never call queue.sync/async
    //      from code already on queue" rule at the top of this file. It
    //      talks to `db` directly, the same as `createTables()`.
    private typealias MigrationStep = (version: Int32, apply: () -> Bool)
    private var migrationSteps: [MigrationStep] {
        [(version: 1, apply: migrateV1_addGoalMetColumn)]
    } // version 0 = today's six tables

    /// v1: adds `daily_totals.goal_met` — nullable, 1 means that day's
    /// keystrokes reached the goal in effect at the time it was recorded,
    /// NULL means it didn't (or hasn't been evaluated yet). Once written,
    /// 1 is never cleared back to NULL — see `_markGoalMetIfNeeded` — so
    /// raising the goal later doesn't retroactively take a day back.
    ///
    /// Backfills existing rows using the goal in effect right now (whatever
    /// `UserSettings.dailyGoal` reads as at upgrade time) so an installed
    /// user's streak reflects real history instead of resetting to zero the
    /// moment this ships. This is a one-time judgment call made at the
    /// point of upgrade, not a live goal — a day's persisted flag doesn't
    /// change again after this if the goal changes later.
    private func migrateV1_addGoalMetColumn() -> Bool {
        guard addColumnIfMissing(table: "daily_totals", column: "goal_met", definition: "INTEGER") else { return false }
        guard let db else { return false }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "UPDATE daily_totals SET goal_met = 1 WHERE total_keys >= ?;", -1, &stmt, nil) == SQLITE_OK else {
            return false
        }
        sqlite3_bind_int(stmt, 1, Int32(UserSettings.dailyGoal))
        let ok = sqlite3_step(stmt) == SQLITE_DONE
        sqlite3_finalize(stmt)
        return ok
    }

    /// MUST be called already running on the init thread (see note above).
    private func migrate() -> Bool {
        guard let db else { return false }
        var version: Int32 = 0
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                version = sqlite3_column_int(stmt, 0)
            }
        }
        sqlite3_finalize(stmt)

        for step in migrationSteps where step.version > version {
            guard sqlite3_exec(db, "BEGIN IMMEDIATE;", nil, nil, nil) == SQLITE_OK else {
                lastError = "Migration \(step.version) failed to begin: \(String(cString: sqlite3_errmsg(db)))"
                return false
            }
            guard step.apply() else {
                sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                lastError = "Migration \(step.version) failed"
                return false
            }
            // PRAGMA user_version can't be bound as a parameter; safe to
            // interpolate since `step.version` is a compile-time constant,
            // never user input.
            exec("PRAGMA user_version = \(step.version);")
            guard sqlite3_exec(db, "COMMIT;", nil, nil, nil) == SQLITE_OK else {
                sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                lastError = "Migration \(step.version) failed to commit: \(String(cString: sqlite3_errmsg(db)))"
                return false
            }
            version = step.version
        }
        return true
    }

    /// Adds `column` to `table` only if it isn't already there. Safe to call
    /// even when `user_version` is out of sync with reality (e.g. a db
    /// restored from a backup, or one that ran a beta build) — the check is
    /// against the table's actual columns, not the version number.
    private func addColumnIfMissing(table: String, column: String, definition: String) -> Bool {
        guard let db else { return false }
        var stmt: OpaquePointer?
        var exists = false
        if sqlite3_prepare_v2(db, "PRAGMA table_info(\(table));", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let raw = sqlite3_column_text(stmt, 1), String(cString: raw) == column {
                    exists = true
                    break
                }
            }
        }
        sqlite3_finalize(stmt)
        guard !exists else { return true }
        return sqlite3_exec(db, "ALTER TABLE \(table) ADD COLUMN \(column) \(definition);", nil, nil, nil) == SQLITE_OK
    }

    /// Runs PRAGMA quick_check + a row count on launch, purely for the log —
    /// never auto-quarantines the file. A false positive that moved the
    /// user's database aside would be worse than a logged warning.
    private func logStartupSanity() {
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            var stmt: OpaquePointer?
            var result = "?"
            if sqlite3_prepare_v2(db, "PRAGMA quick_check;", -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_ROW, let text = sqlite3_column_text(stmt, 0) {
                    result = String(cString: text)
                }
            }
            sqlite3_finalize(stmt)
            NSLog("KeyStats: startup quick_check = %@", result)
        }
    }

    // MARK: - Sample (what the event tap hands us)

    /// One keystroke or one modifier-down transition, captured on the event
    /// tap's callback. Building this must stay allocation-light; nothing in
    /// here touches SQLite or the disk.
    struct Sample {
        var keyCode: Int?
        var keyName: String?
        var isBackspace = false
        var countsTowardDaily = false
        var modifierName: String?
        var combo: String?
        var appName: String?
        var timestamp = Date()
    }

    // MARK: - In-memory buffer (the batching layer)

    private struct Buffer {
        var keys: [Int: (name: String, delta: Int)] = [:]
        var modifiers: [String: Int] = [:]
        var keybinds: [String: (delta: Int, lastUsed: Int64)] = [:]
        var hourly: [Int64: Int] = [:]
        var apps: [String: Int] = [:]
        var daily: [String: (total: Int, backspaces: Int)] = [:]

        var isEmpty: Bool {
            keys.isEmpty && modifiers.isEmpty && keybinds.isEmpty
                && hourly.isEmpty && apps.isEmpty && daily.isEmpty
        }
    }

    private let bufferLock = NSLock()
    private var buffer = Buffer()

    // Derived-value caches, also touched only under bufferLock, so the hot
    // path never calls into Calendar/DateFormatter per keystroke.
    private var cachedDayKey = ""
    private var cachedDayValidUntil: TimeInterval = 0
    private var cachedHourBucket: Int64 = 0
    private var cachedHourValidUntil: TimeInterval = 0

    /// Called from the CGEventTap callback (main thread). Must stay cheap:
    /// one lock, a handful of dictionary updates, no dispatch, no SQLite,
    /// no I/O of any kind.
    ///
    /// Semantics preserved bit-for-bit from the original per-keystroke code:
    ///  - key_counts:      +1 per keyDown. key_name is NOT re-written on
    ///                     conflict (matches the old UPDATE, which only
    ///                     touched `count`).
    ///  - modifier_counts: +1 only when a modifier transitions held->down.
    ///  - keybind_counts:  +1, last_used is last-write-wins.
    ///  - hourly_activity: +1 on keyDown AND on modifier-down.
    ///  - app_activity:    +1 on keyDown AND on modifier-down, only when a
    ///                     frontmost app name is known.
    ///  - daily_totals:    total_keys +1 per keyDown; backspace_count +1 for
    ///                     Delete/Forward Delete.
    func record(_ s: Sample) {
        guard isAvailable else { return }
        let t = s.timestamp.timeIntervalSince1970

        bufferLock.lock()
        defer { bufferLock.unlock() }

        if let code = s.keyCode, let name = s.keyName {
            let existing = buffer.keys[code]
            buffer.keys[code] = (name: name, delta: (existing?.delta ?? 0) + 1)
        }
        if let m = s.modifierName {
            buffer.modifiers[m, default: 0] += 1
        }
        if let combo = s.combo {
            let existing = buffer.keybinds[combo]
            buffer.keybinds[combo] = (delta: (existing?.delta ?? 0) + 1, lastUsed: Int64(t))
        }
        if let app = s.appName, !app.isEmpty {
            buffer.apps[app, default: 0] += 1
        }

        // hourly: matches recordHourlyActivity()'s two old call sites
        // (on keyDown and on modifier-down).
        if s.keyCode != nil || s.modifierName != nil {
            if t >= cachedHourValidUntil {
                cachedHourBucket = Int64(t / 3600) * 3600 // same formula as before
                cachedHourValidUntil = Double(cachedHourBucket) + 3600
            }
            buffer.hourly[cachedHourBucket, default: 0] += 1
        }

        // daily: keyDown only.
        if s.countsTowardDaily {
            if t >= cachedDayValidUntil {
                cachedDayKey = DayKey.string(from: s.timestamp)
                cachedDayValidUntil = DayKey.endOfDay(for: s.timestamp)
            }
            var d = buffer.daily[cachedDayKey] ?? (0, 0)
            d.total += 1
            if s.isBackspace { d.backspaces += 1 }
            buffer.daily[cachedDayKey] = d
        }
    }

    // MARK: - Flush (buffer -> disk, on `queue`)

    private var stmtKey: OpaquePointer?
    private var stmtModifier: OpaquePointer?
    private var stmtKeybind: OpaquePointer?
    private var stmtHourly: OpaquePointer?
    private var stmtApp: OpaquePointer?
    private var stmtDaily: OpaquePointer?
    private var stmtMarkGoalMet: OpaquePointer?
    private var statementsPrepared = false
    private var flushTimer: DispatchSourceTimer?

    private func startFlushTimer() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + AppConfig.Timing.dbFlush, repeating: AppConfig.Timing.dbFlush, leeway: .seconds(1))
        t.setEventHandler { [weak self] in self?.flushOnQueue() }
        t.resume()
        flushTimer = t
    }

    /// Ask for a flush; returns immediately.
    func flush() {
        guard isAvailable else { return }
        queue.async { [weak self] in self?.flushOnQueue() }
    }

    /// Flush and wait for it to finish. For app-terminate / sleep. Must
    /// NEVER be called from a context already running on `queue`.
    func flushSynchronously() {
        guard isAvailable else { return }
        queue.sync { self.flushOnQueue() }
    }

    /// Called when the user changes their daily goal in Preferences. Past
    /// days' `goal_met` is permanent once written (see
    /// `migrateV1_addGoalMetColumn`'s doc comment) and untouched here —
    /// this only ever rewrites *today's* row, recomputed from scratch
    /// against the new goal. That's deliberate: today isn't "the past" yet,
    /// so raising the goal above what's already been typed today should
    /// undo today's credit, and lowering it back should be able to re-grant
    /// it — neither is true for any day that's already closed out.
    func recalculateTodayGoalMet(goal: Int) {
        guard isAvailable else { return }
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            self.flushOnQueue() // today's in-memory buffer must land first, or this checks a stale total_keys.
            let today = DayKey.string(from: Date())
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(
                db,
                "UPDATE daily_totals SET goal_met = CASE WHEN total_keys >= ? THEN 1 ELSE 0 END WHERE day = ?;",
                -1, &stmt, nil
            ) == SQLITE_OK else { return }
            sqlite3_bind_int(stmt, 1, Int32(goal))
            sqlite3_bind_text(stmt, 2, today, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) != SQLITE_DONE {
                NSLog("KeyStats: recalculateTodayGoalMet failed: %s", sqlite3_errmsg(db))
            }
        }
    }

    /// MUST be called already running on `queue`.
    private func prepareStatementsIfNeeded() -> Bool {
        guard !statementsPrepared, let db else { return statementsPrepared }
        func prep(_ sql: String) -> OpaquePointer? {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                NSLog("KeyStats: failed to prepare: %@ (%s)", sql, sqlite3_errmsg(db))
                return nil
            }
            return stmt
        }
        stmtKey = prep("""
            INSERT INTO key_counts (key_code, key_name, count) VALUES (?, ?, ?)
            ON CONFLICT(key_code) DO UPDATE SET count = count + excluded.count;
            """)
        stmtModifier = prep("""
            INSERT INTO modifier_counts (modifier, count) VALUES (?, ?)
            ON CONFLICT(modifier) DO UPDATE SET count = count + excluded.count;
            """)
        stmtKeybind = prep("""
            INSERT INTO keybind_counts (combo, count, last_used) VALUES (?, ?, ?)
            ON CONFLICT(combo) DO UPDATE SET count = count + excluded.count,
                                             last_used = excluded.last_used;
            """)
        stmtHourly = prep("""
            INSERT INTO hourly_activity (hour_bucket, count) VALUES (?, ?)
            ON CONFLICT(hour_bucket) DO UPDATE SET count = count + excluded.count;
            """)
        stmtApp = prep("""
            INSERT INTO app_activity (app_name, count) VALUES (?, ?)
            ON CONFLICT(app_name) DO UPDATE SET count = count + excluded.count;
            """)
        stmtDaily = prep("""
            INSERT INTO daily_totals (day, total_keys, backspace_count) VALUES (?, ?, ?)
            ON CONFLICT(day) DO UPDATE SET total_keys = total_keys + excluded.total_keys,
                                           backspace_count = backspace_count + excluded.backspace_count;
            """)
        // Only ever moves goal_met from NULL/0 -> 1, never back — see the
        // migrateV1_addGoalMetColumn doc comment for why that's intentional.
        stmtMarkGoalMet = prep("""
            UPDATE daily_totals SET goal_met = 1 WHERE day = ? AND total_keys >= ?;
            """)
        statementsPrepared = [stmtKey, stmtModifier, stmtKeybind, stmtHourly, stmtApp, stmtDaily, stmtMarkGoalMet].allSatisfy { $0 != nil }
        return statementsPrepared
    }

    /// Reset + rebind + step a persistent statement. MUST be called on `queue`.
    private func step(_ stmt: OpaquePointer?, bind: (OpaquePointer?) -> Void) -> Bool {
        guard let stmt else { return false }
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
        bind(stmt)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            NSLog("KeyStats: step failed: %s", sqlite3_errmsg(db))
            return false
        }
        return true
    }

    /// Merge unwritten deltas back into the live buffer so a transient
    /// failure (e.g. SQLITE_BUSY) doesn't silently drop keystrokes. MUST be
    /// called on `queue` (it takes bufferLock, which is fine — no sqlite
    /// call happens while holding it).
    private func requeue(_ pending: Buffer) {
        bufferLock.lock()
        for (code, v) in pending.keys {
            let existing = buffer.keys[code]
            buffer.keys[code] = (name: v.name, delta: (existing?.delta ?? 0) + v.delta)
        }
        for (name, d) in pending.modifiers { buffer.modifiers[name, default: 0] += d }
        for (combo, v) in pending.keybinds {
            let existing = buffer.keybinds[combo]
            buffer.keybinds[combo] = (delta: (existing?.delta ?? 0) + v.delta, lastUsed: v.lastUsed)
        }
        for (bucket, d) in pending.hourly { buffer.hourly[bucket, default: 0] += d }
        for (app, d) in pending.apps { buffer.apps[app, default: 0] += d }
        for (day, v) in pending.daily {
            var existing = buffer.daily[day] ?? (0, 0)
            existing.total += v.total
            existing.backspaces += v.backspaces
            buffer.daily[day] = existing
        }
        bufferLock.unlock()
    }

    /// MUST be called already running on `queue`.
    private func flushOnQueue() {
        bufferLock.lock()
        let pending = buffer
        buffer = Buffer()
        bufferLock.unlock()

        guard !pending.isEmpty, let db else { return }
        guard prepareStatementsIfNeeded() else { return }

        guard sqlite3_exec(db, "BEGIN IMMEDIATE;", nil, nil, nil) == SQLITE_OK else {
            NSLog("KeyStats: BEGIN failed: %s", sqlite3_errmsg(db))
            requeue(pending)
            return
        }

        var ok = true
        for (code, v) in pending.keys {
            ok = step(stmtKey) { s in
                sqlite3_bind_int(s, 1, Int32(code))
                sqlite3_bind_text(s, 2, v.name, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int(s, 3, Int32(v.delta))
            } && ok
        }
        for (name, d) in pending.modifiers {
            ok = step(stmtModifier) { s in
                sqlite3_bind_text(s, 1, name, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int(s, 2, Int32(d))
            } && ok
        }
        for (combo, v) in pending.keybinds {
            ok = step(stmtKeybind) { s in
                sqlite3_bind_text(s, 1, combo, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int(s, 2, Int32(v.delta))
                sqlite3_bind_int64(s, 3, v.lastUsed)
            } && ok
        }
        for (bucket, d) in pending.hourly {
            ok = step(stmtHourly) { s in
                sqlite3_bind_int64(s, 1, bucket)
                sqlite3_bind_int(s, 2, Int32(d))
            } && ok
        }
        for (app, d) in pending.apps {
            ok = step(stmtApp) { s in
                sqlite3_bind_text(s, 1, app, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int(s, 2, Int32(d))
            } && ok
        }
        // Read once per flush, not once per day — UserDefaults is cheap but
        // there's no reason to hit it more than the batch needs.
        let currentGoal = Int32(UserSettings.dailyGoal)
        for (day, v) in pending.daily {
            ok = step(stmtDaily) { s in
                sqlite3_bind_text(s, 1, day, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int(s, 2, Int32(v.total))
                sqlite3_bind_int(s, 3, Int32(v.backspaces))
            } && ok
            // Must run after stmtDaily above: it checks the row's
            // just-upserted cumulative total_keys, not this flush's delta.
            ok = step(stmtMarkGoalMet) { s in
                sqlite3_bind_text(s, 1, day, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int(s, 2, currentGoal)
            } && ok
        }

        if ok {
            if sqlite3_exec(db, "COMMIT;", nil, nil, nil) != SQLITE_OK {
                NSLog("KeyStats: COMMIT failed: %s", sqlite3_errmsg(db))
                sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                requeue(pending)
            }
        } else {
            sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
            requeue(pending)
        }
    }

    // MARK: - Shutdown

    /// Flush, finalize statements, close the connection. Call from
    /// applicationWillTerminate. Not reached on a hard kill/crash — that is
    /// the accepted "lose the last few seconds" tradeoff of batching.
    func shutdown() {
        guard isAvailable else { return }
        queue.sync {
            self.flushTimer?.cancel()
            self.flushTimer = nil
            self.flushOnQueue()
            for s in [stmtKey, stmtModifier, stmtKeybind, stmtHourly, stmtApp, stmtDaily, stmtMarkGoalMet] {
                sqlite3_finalize(s)
            }
            statementsPrepared = false
            let rc = sqlite3_close(self.db)
            if rc != SQLITE_OK {
                NSLog("KeyStats: sqlite3_close rc=%d", rc)
            }
            self.db = nil
        }
        isAvailable = false
    }

    // MARK: - Model types (unchanged shapes for the dashboard)

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
        let id: Int
        let hour: Int
        let count: Int
    }
    struct DayTotal: Identifiable {
        let id: String
        let day: String
        let label: String
        let total: Int
        let backspaces: Int
    }

    /// One consistent view of everything the dashboard shows, produced by a
    /// single hop onto `queue` (a flush, then all reads) instead of the old
    /// eight separate un-synchronized transactions.
    struct Snapshot {
        var topKeys: [KeyCount] = []
        var modifierCounts: [KeyCount] = []
        var topKeybinds: [ComboCount] = []
        var topApps: [AppCount] = []
        var hourly: [HourBucket] = []
        var weeklyTotals: [DayTotal] = []
        var lifetimeTotal = 0
        var backspaceRatio: Double = 0
        var totalToday = 0
        /// Formatted "MMM d" of the earliest `daily_totals` row — shown as
        /// "since ..." under the Lifetime stat. This is a proxy for "when
        /// did I start using KeyStats", derived from data rather than a
        /// stored value, so it's only as good as this database's history:
        /// if the real (production) database's history doesn't reach back
        /// to the actual install date — e.g. after a reset — this should
        /// be replaced with a real stored join date instead of re-deriving it.
        var joinedLabel = ""
        /// "yyyy-MM-dd" days (within `AppConfig.Goal.streakLookbackDays`)
        /// where `daily_totals.goal_met = 1` — persisted at write time, not
        /// recomputed against today's goal, so a later goal change doesn't
        /// retroactively add or remove days from this set. See
        /// `Storage.migrateV1_addGoalMetColumn` and `StreakCalculator`.
        var streakEligibleDays: Set<String> = []
    }

    /// Synchronous snapshot. Callers on a background thread are fine; do not
    /// call this from `queue` itself (rule 1 above).
    func snapshot() -> Snapshot {
        guard isAvailable else { return Snapshot() }
        return queue.sync { self.snapshotOnQueue() }
    }

    /// Off-main variant; delivers the result on the main queue.
    func snapshot(completion: @escaping (Snapshot) -> Void) {
        guard isAvailable else {
            DispatchQueue.main.async { completion(Snapshot()) }
            return
        }
        queue.async {
            let s = self.snapshotOnQueue()
            DispatchQueue.main.async { completion(s) }
        }
    }

    /// MUST be called already running on `queue`.
    private func snapshotOnQueue() -> Snapshot {
        flushOnQueue() // pending in-memory deltas land before we read them
        var s = Snapshot()
        s.topKeys = _topKeys()
        s.modifierCounts = _modifierCounts()
        s.topKeybinds = _topKeybinds()
        s.topApps = _topApps()
        s.hourly = _last24Hours()
        s.weeklyTotals = _lastSevenDays()
        s.lifetimeTotal = _lifetimeTotal()
        s.backspaceRatio = _backspaceRatioToday()
        s.totalToday = s.weeklyTotals.last?.total ?? 0
        s.joinedLabel = _joinedLabel()
        s.streakEligibleDays = _metGoalDaysSince(daysAgo: AppConfig.Goal.streakLookbackDays)
        return s
    }

    // MARK: - Readers (all assume they're already on `queue`; see rule 1)

    private func _topKeys(limit: Int = AppConfig.Query.topKeysLimit) -> [KeyCount] {
        _readPairs("SELECT key_name, count FROM key_counts ORDER BY count DESC LIMIT \(limit);")
            .map { KeyCount(keyName: $0.0, count: $0.1) }
    }

    private func _modifierCounts() -> [KeyCount] {
        _readPairs("SELECT modifier, count FROM modifier_counts ORDER BY count DESC;")
            .map { KeyCount(keyName: $0.0, count: $0.1) }
    }

    private func _topKeybinds(limit: Int = AppConfig.Query.topKeybindsLimit) -> [ComboCount] {
        _readPairs("SELECT combo, count FROM keybind_counts ORDER BY count DESC LIMIT \(limit);")
            .map { ComboCount(combo: $0.0, count: $0.1) }
    }

    private func _topApps(limit: Int = AppConfig.Query.topAppsLimit) -> [AppCount] {
        _readPairs("SELECT app_name, count FROM app_activity ORDER BY count DESC LIMIT \(limit);")
            .map { AppCount(appName: $0.0, count: $0.1) }
    }

    private func _last24Hours() -> [HourBucket] {
        let cutoff = Int64(Date().timeIntervalSince1970) - Int64(AppConfig.Query.hourlyWindowHours) * 3600
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
    private func _lastSevenDays() -> [DayTotal] {
        let cal = Calendar.current
        let today = Date()
        let days: [String] = (0..<AppConfig.Query.weeklyDays).reversed().compactMap { offset in
            guard let date = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DayKey.string(from: date)
        }

        var rows: [String: (Int, Int)] = [:]
        var stmt: OpaquePointer?
        let placeholders = days.map { _ in "?" }.joined(separator: ",")
        let sql = "SELECT day, total_keys, backspace_count FROM daily_totals WHERE day IN (\(placeholders));"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            for (i, day) in days.enumerated() {
                sqlite3_bind_text(stmt, Int32(i + 1), day, -1, SQLITE_TRANSIENT)
            }
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let raw = sqlite3_column_text(stmt, 0) else { continue }
                let d = String(cString: raw)
                let t = Int(sqlite3_column_int64(stmt, 1))
                let b = Int(sqlite3_column_int64(stmt, 2))
                rows[d] = (t, b)
            }
        }
        sqlite3_finalize(stmt)

        let weekdayFormatter = DateFormatter() // one local allocation per call, irrelevant at 5s cadence
        weekdayFormatter.dateFormat = "EEE"
        return days.compactMap { dayStr -> DayTotal? in
            guard let date = DayKey.date(from: dayStr) else { return nil }
            let label = weekdayFormatter.string(from: date)
            let (total, backspaces) = rows[dayStr] ?? (0, 0)
            return DayTotal(id: dayStr, day: dayStr, label: label, total: total, backspaces: backspaces)
        }
    }

    private func _lifetimeTotal() -> Int {
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

    private func _joinedLabel() -> String {
        var stmt: OpaquePointer?
        var earliestDay: String?
        let sql = "SELECT MIN(day) FROM daily_totals;"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW, let raw = sqlite3_column_text(stmt, 0) {
                earliestDay = String(cString: raw)
            }
        }
        sqlite3_finalize(stmt)

        guard let earliestDay, let date = DayKey.date(from: earliestDay) else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    /// Days (within `daysAgo`, including today) where `goal_met = 1` was
    /// persisted at write time — see `stmtMarkGoalMet`. Today's flag is
    /// current as of this call because `snapshotOnQueue()` always flushes
    /// first, so any goal crossed by buffered-but-unflushed keystrokes has
    /// already been written before this reads it.
    private func _metGoalDaysSince(daysAgo: Int) -> Set<String> {
        let cal = Calendar.current
        guard let cutoffDate = cal.date(byAdding: .day, value: -daysAgo, to: Date()) else { return [] }
        let cutoff = DayKey.string(from: cutoffDate)

        var result: Set<String> = []
        var stmt: OpaquePointer?
        let sql = "SELECT day FROM daily_totals WHERE day >= ? AND goal_met = 1;"
        // String comparison is safe here because DayKey is zero-padded
        // "yyyy-MM-dd" — lexicographic order matches date order.
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, cutoff, -1, SQLITE_TRANSIENT)
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let raw = sqlite3_column_text(stmt, 0) else { continue }
                result.insert(String(cString: raw))
            }
        }
        sqlite3_finalize(stmt)
        return result
    }

    private func _backspaceRatioToday() -> Double {
        let day = DayKey.string(from: Date())
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

    private func _readPairs(_ sql: String) -> [(String, Int)] {
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

/// Stateless replacement for the old shared `DateFormatter.dayKey`.
/// `DateFormatter` is not thread-safe, and the old one was read from both
/// the db queue and the main thread. Output MUST stay identical to
/// `"yyyy-MM-dd"` in the current calendar, or the month of existing
/// `daily_totals` keys stops matching.
enum DayKey {
    static func string(from date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func date(from key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var c = DateComponents()
        c.year = parts[0]; c.month = parts[1]; c.day = parts[2]; c.hour = 12
        return Calendar.current.date(from: c)
    }

    /// Start of the *next* day, as a timeIntervalSince1970 — used to know
    /// when the hot-path's cached day key needs recomputing.
    static func endOfDay(for date: Date) -> TimeInterval {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let next = cal.date(byAdding: .day, value: 1, to: start) ?? date.addingTimeInterval(3600)
        return next.timeIntervalSince1970
    }
}
