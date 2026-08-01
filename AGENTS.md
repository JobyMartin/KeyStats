# KeyStats

Menu-bar-only macOS app (SwiftUI + Swift Package Manager) that tracks
keystroke stats locally in SQLite. See `README.md` for what it tracks and
how to run it, and `znotes/design.md` for the in-progress UI redesign
reference (logo, color themes, component specs, tokens) — pull from that
doc when building any feature so the implementation matches what was
designed.

`CLAUDE.md` in this repo is just a one-line pointer to this file, so both
Claude Code and other agent tooling read the same instructions.

Do not edit `znotes/todo.md` — it's the user's own list, for them only.

Never build, sign, install, or launch the app without the user's explicit
permission — no `./build-app.sh`, no `swift run`, no relaunching
`/Applications/KeyStatsApp.app`. A plain `swift build` compile check is fine
on its own, but anything that touches `/Applications`, replaces the installed
bundle, quits the running app, or re-signs it needs a go-ahead each time, not
a standing one. Installing quits whatever's running and swaps the bundle,
which can disturb live tracking, the SQLite database, or the Accessibility
grant — that's the user's call, not the agent's.
