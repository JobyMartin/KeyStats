# Postmortem: the dashboard/preferences CPU leak (2026-08-20)

## Symptom

`KeyStatsApp` would end up pegging ~40-60% of one core indefinitely,
starting from the moment the Dashboard or Preferences window was ever
opened during a session — even after closing it, even with no windows
open at all. Only a full relaunch cleared it. Sustained main-thread load
like that is exactly the condition that trips `EventTapManager`'s
`kCGEventTapDisabledByTimeout` handling, so this is very plausibly why
keystrokes were being missed ("stuck"/"not tracking" symptom).

## What it actually was (took three tries to nail down)

1. **First guess (wrong): the status-pill's `repeatForever` pulse
   animation never stopped on window close.** True as far as it went —
   `pulseOn` was `@State` on the top-level `DashboardView`, so every 1s
   animation tick invalidated the *entire* body and re-ran every section's
   getter (topKeysSection, appsSection, etc. — real work: font lookups,
   array copies, string splits). Isolating the pulse into its own leaf
   `PulsingDot` subview (`DashboardView.swift`) fixed *that* specific
   waste, and did measurably cut CPU. But CPU stayed high regardless —
   proven by pausing tracking (which stops the pulse) while the dashboard
   stayed open, and it made no difference at all.

2. **Second finding (the real cause): SwiftUI keeps ticking a
   per-window render/update pass (`AttributeGraph` / `DisplayList.ViewUpdater`
   in every CPU sample) at display refresh rate for as long as an
   `NSHostingController`'s content is loaded into *any* window — hidden or
   not, animating or not.** `AppDelegate` deliberately keeps both windows
   alive after "close" (`isReleasedWhenClosed = false`) so reopening is
   instant. That's exactly what keeps their SwiftUI content "loaded"
   forever, and the tick never stops. Confirmed by opening the
   *Preferences* window — which has zero animations of any kind — and
   seeing the exact same sustained high CPU, which ruled out anything
   content-specific.

3. **First fix attempt for #2 (also wrong, and dangerous): set
   `isReleasedWhenClosed = true` and drop our own reference in
   `willCloseNotification`, so the window actually deallocates on close.**
   This crashed — `SIGSEGV` freeing `_NSWindowTransformAnimation` inside
   `CA::Transaction::commit()`. Releasing a window's last reference while
   AppKit is still mid-flight committing that window's own close-transition
   animation frees it out from under itself. Deferring the release by one
   run loop turn (`DispatchQueue.main.async`) did **not** fix this — same
   crash, same stack. **Do not set `isReleasedWhenClosed = true` on these
   windows.** If this is ever revisited, it needs a way to know the close
   animation has actually finished (there isn't a clean notification for
   that), not just "later."

## The actual fix

Keep both windows alive (`isReleasedWhenClosed = false`, as originally),
but swap each one's SwiftUI content for `Color.clear` while hidden, via a
tiny shared `WindowVisibility` (`Sources/KeyStats/WindowVisibility.swift`)
that `AppDelegate` flips on open/`willCloseNotification`. This never
touches window lifecycle — no crash risk — and it works because SwiftUI
has nothing left to tick once the real section tree isn't in the view
graph at all. Verified across many repeated open/close cycles: CPU spikes
only while a window is genuinely visible, and drops to ~0% within a couple
seconds of closing, every time.

Also kept: the `PulsingDot` isolation from attempt #1 — it's a real,
independent improvement (less wasted work while the dashboard genuinely
*is* open), just not the leak itself.

## Open item, not yet fixed

CPU while the dashboard is **genuinely open** is still ~36-42% on this
machine — high for what's on screen (a small pulse, some charts, a few
text sections). Worth profiling later: is Swift Charts itself re-rendering
continuously while its window is key, independent of any app-level
animation? That's a performance question, not the "silently stuck
forever" bug this postmortem is about, so it didn't block this fix.

## Hardening for the future

1. **Treat `isReleasedWhenClosed = false` as a known trap.** Any window
   using it needs an explicit plan for what happens to its hosted content
   while hidden — either a visibility-gated placeholder (this fix's
   pattern) or genuinely tearing the content down (which, per the crash
   above, needs to be done very carefully around AppKit's own close
   animation, if it's attempted at all).
2. **Add a release-checklist smoke test:** open the dashboard, close it,
   watch Activity Monitor (or `ps -o %cpu`) for ~10s, confirm it settles
   back to ~0%. This exact bug would have been caught by that single
   manual check before ever shipping.
3. **Document the CPU↔keystroke-loss coupling** in
   `docs/crash-fix-notes.md` — a future "stats stopped counting" report
   should prompt a CPU check, not just an Accessibility-permission check.
4. **If revisiting window-release-on-close:** don't. Or if it's truly
   worth it, look for a documented, race-free way to know AppKit's close
   animation has finished (possibly disabling the animation outright via
   `NSWindow.animationBehavior = .none` first) before dropping the last
   reference — the run-loop-turn defer tried here was not sufficient.
