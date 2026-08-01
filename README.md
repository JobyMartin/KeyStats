# KeyStats

A menu-bar-only macOS app that tracks your keystrokes locally and shows you
juicy stats about them. Nothing leaves your machine — it's a local SQLite file at
`~/Library/Application Support/KeyStats/keystats.sqlite`, no networking code
exists in the app at all.

## What it tracks

- **Per-key counts** — which letters/keys you press most (A, S, Backspace, etc.)
- **Modifier key usage** — how often you hit Cmd, Shift, Option, Control, Fn on their own
- **Keybind / combo usage** — e.g. `Cmd+Tab`, `Cmd+S`, `Control+C`, `Cmd+Shift+Z`,
  counted as canonical combos regardless of press order
- **Hourly activity** — bar chart of keystrokes for the last 24 hours, useful for
  spotting your most productive coding hours
- **Per-app activity** — which app was frontmost when you were typing (handy to
  see how much time goes to your editor vs. terminal vs. Slack)
- **Daily totals + backspace ratio** — rough proxy for how much you're
  correcting yourself while coding
- **Daily goal + streak** — a progress ring against a daily keystroke goal
  (15,000 by default), and a streak of consecutive days you've hit it. Once
  a day is credited it stays credited even if you change the goal later —
  see "Customizing it" below for how to change the goal itself

It intentionally does **not** store the sequence/content of what you typed —
only aggregate counts. That keeps it useful without turning into an actual
keylogger that could leak passwords if the DB were ever read by someone else.

## Requirements

- macOS 14+ (Sonoma or later — needed for the `SectorMark` pie chart in the dashboard)
- Xcode 15+ (for Swift 5.9 toolchain) — either Xcode itself, or just the
  Command Line Tools (`xcode-select --install`) if you'd rather build from
  the terminal with `swift build`.

## Running it

```bash
cd KeyStats
swift build -c release
swift run -c release
```

Or open the folder in Xcode (`File > Open` on `Package.swift`) and hit Run —
this is the easier path if you want to attach a debugger or edit the UI live.

### First launch: Accessibility permission

macOS requires Accessibility permission for any app that wants to observe
keystrokes globally (this is the same permission used by apps like Rectangle
or Karabiner). On first launch:

1. A system prompt will appear — click **Open System Settings**.
2. Go to **Privacy & Security → Accessibility**.
3. Enable the toggle for **KeyStats** (or for `Terminal`/`Xcode` if you're
   running it via `swift run` from there — in dev builds the permission
   often attaches to the parent process rather than the binary itself).
4. The app polls for permission every 2 seconds and starts capturing
   automatically once granted — no need to relaunch.

### Using it

The app has no Dock icon — look for the keyboard icon in your menu bar.
Click it → **Open Dashboard** to see your stats, **Preferences…** for theme/
goal settings, or **Quit KeyStats** to stop tracking and exit. The dashboard's
gear icon opens the same Preferences window.

Preferences has an Appearance tab (11 dark themes, click a card to switch —
same list as `znotes/themes.json`) and a Goals tab (daily goal slider +
presets, and a "count weekends toward streak" toggle, off by default so a
quiet Saturday or Sunday can't break a streak built on weekdays). Changing
the goal only ever affects *today* — past days keep whatever `goal_met` they
were written with, permanently; raising the goal above what you've already
typed today un-earns just today's credit, and lowering it back re-earns it.

## Customizing it

Every tunable number in the app — window size, the daily goal's default/
range/presets, refresh intervals, chart sizing, query limits — lives in one
file, `Sources/KeyStats/AppConfig.swift`. Edit a constant there and rebuild
rather than hunting a number down across files.

The daily goal and weekend toggle are also reachable via `defaults write` if
you'd rather script it than use Preferences:

```bash
defaults write com.joby.KeyStatsApp dailyGoal 20000
defaults write com.joby.KeyStatsApp countWeekendsTowardStreak -bool true

# back to the defaults (15,000 / weekends don't count)
defaults delete com.joby.KeyStatsApp dailyGoal
defaults delete com.joby.KeyStatsApp countWeekendsTowardStreak
```

(If you're running via `swift run` rather than the packaged `.app`, these
land in a different `defaults` domain — the SwiftPM executable's, not
`com.joby.KeyStatsApp` — since they're keyed by bundle identifier.)

## Notes on accuracy / extending it

- The keycode → name map in `KeyCodeMap.swift` covers a standard US ANSI
  keyboard. If you use a different layout, some keys may show as `Key#NN` —
  just add the missing codes to the map.
- Combos are canonicalized in a fixed order (`Control+Option+Shift+Cmd+Fn+Key`)
  so `Shift+Cmd+Z` and `Cmd+Shift+Z` count as the same keybind.
- If you'd rather not track which app is frontmost (e.g. for extra privacy),
  delete the `recordFrontmostApp()` calls in `EventTapManager.swift`.
- To reset all stats, quit the app and delete
  `~/Library/Application Support/KeyStats/keystats.sqlite`.
- If you need to change the SQLite schema, don't edit the `CREATE TABLE`
  statements directly — `Storage.swift` has a numbered-migration system
  (`migrate()`/`addColumnIfMissing`) specifically so an update doesn't break
  installs that already have data. See the comment block above `migrate()`
  for the rules (append-only steps, always provide a `DEFAULT` for `NOT
  NULL` columns).

## Packaging as a real .app (to come)

`swift run` is fine and all, but I eventually want a proper app...so stay tuned
