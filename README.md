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
Click it → **Open Dashboard** to see your stats, or **Quit KeyStats** to stop
tracking and exit.

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

## Packaging as a real .app (to come)

`swift run` is fine and all, but I eventually want a proper app...so stay tuned
