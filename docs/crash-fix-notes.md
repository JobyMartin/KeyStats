# Notes from the July 2026 crash fix (PR #3)

Context for whoever (human or AI) touches this app next. None of this is
obvious from reading the code cold.

## The real database is not where the README says

The installed, packaged app is **sandboxed** (`com.apple.security.app-sandbox`
in `KeyStats.entitlements`). That means `FileManager`'s
`.applicationSupportDirectory` resolves inside its container, not the plain
path in the README:

```
~/Library/Containers/com.joby.KeyStatsApp/Data/Library/Application Support/KeyStats/keystats.sqlite
```

`~/Library/Application Support/KeyStats/keystats.sqlite` (the README's path)
is only used by an **unsandboxed** run — i.e. `swift build && swift run`, or
`.build/release/KeyStats` invoked directly from Terminal. That's actually
convenient: **all dev/stress testing should target that path**, since it's
physically a different file from the real data.

If the sandbox entitlement is ever removed, the app will silently start
reading/writing an empty database at the README path and it will look like
a data-loss bug, not a packaging change. There's a comment above the path
construction in `Storage.init` flagging this — read it before touching that
entitlement.

## Why it crashed

Every one of ~10 crash reports (`~/Library/Logs/DiagnosticReports/`) was a
`SIGSEGV` inside `libsqlite3.dylib` — heap corruption, not a normal Swift
crash. Two of the faulting addresses were literally ASCII SQL fragments
(`"app_name"`, `"total_ke"`) being read as pointers.

Cause: `Storage`'s writers used a serial dispatch queue correctly, but every
*reader* (`topKeys`, `last24Hours`, `lifetimeTotal`, etc.) touched the raw
`sqlite3` connection directly on the calling thread, bypassing that queue.
The dashboard's 5-second refresh timer ran those readers on the **main**
thread while writers ran on the **queue** thread — two threads sharing one
SQLite connection, which SQLite does not tolerate at its default threading
mode. The fix (`Storage.swift`) puts every SQL operation — read or write —
through the same serial queue, with an in-memory buffer absorbing the
per-keystroke hot path so the queue isn't hammered on every key.

There's a documented set of four rules at the top of `Storage.swift` about
this (which functions may call `queue.sync`, which assume they're already
on it, etc.) — a `queue.sync` from something already running on `queue` is
an instant, permanent deadlock. That's the easiest way to reintroduce a bug
here.

## Why tracking silently stopped, separately from crashing

`EventTapManager` never handled `kCGEventTapDisabledByTimeout` /
`kCGEventTapDisabledByUserInput`. Once macOS disabled the tap (which it
will do if the callback is ever slow), nothing ever called
`CGEvent.tapEnable` again — capture died permanently until the app was
force-relaunched. This was made likely by the callback itself doing a
synchronous cross-process `NSWorkspace` lookup plus several SQLite writes
per keystroke, all on the main thread. Now fixed with an explicit
tap-disabled handler plus a 30s watchdog as a backstop.

## App name attribution — a gotcha to know about

`NSWorkspace`'s `localizedName` for an app is not always the name you'd
guess from the `.app` file. Concretely: **Visual Studio Code reports its
name as `"Code"`**, not `"Visual Studio Code"`. During the DB repair after
the crash, a corrupted row's name was restored to `"Visual Studio Code"` —
which then diverged from new keystrokes, which kept landing under a new
`"Code"` row, because `app_activity.app_name` is the primary key. Had to
merge the two rows by hand after noticing the split. If you ever manually
edit `app_activity` rows, first check what `NSWorkspace.shared
.frontmostApplication?.localizedName` (or `defaults read
"/Applications/<App>.app/Contents/Info.plist" CFBundleName`) actually
returns for that app — don't guess from the app's display name.

## Toolchain constraints on this machine

- **No Xcode, Command Line Tools only.** `swift build` in this environment
  has no `--arch` flag (Swift 6.3.3). Cross-architecture builds need
  `--triple` + separate scratch paths + `lipo`, and cross-compiling x86_64
  without Xcode is unreliable — `build-app.sh` deliberately only targets
  `arm64`.
- **No Xcode project exists anywhere.** The previously-installed app was
  built by hand at some point; there's no record of how. `Info.plist`,
  `KeyStats.entitlements`, and `build-app.sh` (all new in PR #3) are the
  first checked-in way to reproduce that bundle's identity.

## Packaging / update workflow

`./build-app.sh` builds from source and installs to `/Applications`,
whether or not an app is already installed there (see the script's own
comments — the "quit if running" / "back up if a database exists" / "move
aside if a bundle already exists" steps are all conditional and no-op
cleanly on a fresh machine).

**Every rebuild changes the ad-hoc code-signing hash**, which means macOS
will very likely require Accessibility permission to be re-granted after
each install — the app will otherwise run with the menu bar icon showing
but zero keystrokes counted, with no dialog telling you why. `tccutil reset
Accessibility com.joby.KeyStatsApp` (or manually removing + re-adding
`KeyStatsApp` in System Settings → Privacy & Security → Accessibility) is
the fix. If this friction becomes annoying, a free self-signed cert in
Keychain Access + `--sign "KeyStats Local"` instead of `--sign -` gives TCC
a stable identity to key on instead of the ad-hoc hash.

## One surprising thing that's easy to "fix" into a regression

This app is **sandboxed** *and* successfully creates a session-wide
`CGEventTap`. Apple's official guidance says a sandboxed app cannot get
Accessibility access, and the App Store rejects sandboxed event-tap apps.
It works here anyway — the sandbox restricts filesystem/network/IPC, but
tap creation is authorized by TCC (a user-level Accessibility grant), which
is orthogonal to the sandbox. Don't "clean this up" by dropping the
sandbox entitlement because it looks contradictory — it's how the existing
month+ of data ended up where it is, and removing it relocates the
database (see the first section above).

## Backups from this incident

`~/KeyStats-backups/` has timestamped copies from the repair, in case
anything needs to be re-derived: `keystats.sqlite.pre-repair.*` (state
right after the corrupted app was quit, before any repair), `recover.*.sql`
(the `.recover` dump used to rebuild it), and `repaired.*.sqlite` (what got
installed). Nothing in that directory should be deleted casually.
