import Cocoa
import Carbon.HIToolbox

/// Captures system-wide key events via a CGEventTap and turns them into
/// aggregated stats. Never stores raw text/passwords — only counts.
final class EventTapManager {
    static let shared = EventTapManager()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var watchdog: Timer?

    // Tracks which modifier keys are currently held down, so we can build
    // combo strings like "⌘⇧Z" when a regular key is pressed alongside them.
    private var heldModifiers: Set<String> = []

    // Cached frontmost-app name, kept current by an NSWorkspace notification
    // observer instead of a synchronous per-keystroke IPC lookup. Both
    // written and read on the main thread, so it needs no lock.
    private var frontmostAppName = ""
    private var activationObserver: NSObjectProtocol?

    private init() {}

    // MARK: - Permission

    /// Prompts the user for Accessibility access if not already granted.
    /// Returns true if the process is already trusted.
    @discardableResult
    func ensureAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Tap lifecycle

    func start() {
        // Idempotent: calling twice would otherwise create a second tap
        // that double-counts every keystroke and leaks the first one.
        guard eventTap == nil else { return }
        assert(Thread.isMainThread, "EventTapManager.start() must run on the main thread")

        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly, // we only observe; we never block or alter keystrokes
            eventsOfInterest: CGEventMask(eventMask),
            callback: { _, type, event, refcon in
                // Safe only because EventTapManager.shared is an immortal
                // singleton with no deinit path — this becomes a
                // use-after-free the moment a second instance ever exists.
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<EventTapManager>.fromOpaque(refcon).takeUnretainedValue()
                manager.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("Failed to create event tap. Is Accessibility permission granted?")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        startObservingFrontmostApp()
        startWatchdog()
    }

    func stop() {
        watchdog?.invalidate()
        watchdog = nil

        if let observer = activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            activationObserver = nil
        }

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        heldModifiers.removeAll()
    }

    /// Called after sleep/wake, where a tap can end up disabled without any
    /// callback ever being delivered to tell us.
    func reenableIfNeeded() {
        guard let tap = eventTap else { return }
        if !CGEvent.tapIsEnabled(tap: tap) {
            NSLog("KeyStats: re-enabling event tap after wake")
            CGEvent.tapEnable(tap: tap, enable: true)
            heldModifiers.removeAll()
        }
    }

    private func startWatchdog() {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.reenableIfNeeded()
        }
    }

    private func startObservingFrontmostApp() {
        // Prime it: the notification only fires on subsequent *changes*.
        frontmostAppName = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.frontmostAppName = app?.localizedName ?? ""
        }
    }

    // MARK: - Event handling

    private func handle(type: CGEventType, event: CGEvent) {
        // macOS delivers these as out-of-band notifications with rawValues
        // 0xFFFFFFFE / 0xFFFFFFFF when the tap has been disabled (usually
        // because our callback was too slow, i.e. blocked the main thread).
        // The OLD code had no case for these, so once disabled the tap
        // stayed dead for the rest of the process's life — this is why
        // stats used to just stop appearing. We compare rawValue rather
        // than switching on the enum because CGEventType is a non-frozen
        // imported C enum, and matching an undeclared rawValue in a Swift
        // `switch` is undefined behaviour.
        let raw = type.rawValue
        if raw == 0xFFFF_FFFE || raw == 0xFFFF_FFFF {
            NSLog("KeyStats: event tap disabled (%@); re-enabling",
                  raw == 0xFFFF_FFFE ? "timeout" : "user input")
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            } else {
                start()
            }
            // We may have missed key-up flagsChanged events while disabled,
            // so our held-modifier state is stale. Drop it rather than risk
            // every future combo being miscounted forever.
            heldModifiers.removeAll()
            return
        }

        switch type {
        case .flagsChanged:
            handleFlagsChanged(event: event)
        case .keyDown:
            handleKeyDown(event: event)
        default:
            break
        }
    }

    private func handleFlagsChanged(event: CGEvent) {
        let flags = event.flags
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))

        // Figure out which single modifier this keyCode corresponds to, and
        // whether it just went down or up, by diffing against our held set.
        guard let modifierName = modifierName(forKeyCode: keyCode) else { return }

        let isDown = isModifierActive(flags: flags, modifierName: modifierName)

        if isDown && !heldModifiers.contains(modifierName) {
            heldModifiers.insert(modifierName)

            var sample = Storage.Sample()
            sample.modifierName = modifierName
            sample.appName = frontmostAppName
            Storage.shared.record(sample)
        } else if !isDown {
            heldModifiers.remove(modifierName)
        }
    }

    private func handleKeyDown(event: CGEvent) {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let keyName = KeyCodeMap.name(for: keyCode)

        var sample = Storage.Sample()
        sample.keyCode = keyCode
        sample.keyName = keyName
        sample.isBackspace = (keyName == "Delete" || keyName == "Forward Delete")
        sample.countsTowardDaily = true
        sample.appName = frontmostAppName

        if !heldModifiers.isEmpty {
            let nonShiftMods = heldModifiers.subtracting(["Shift"])
            if !nonShiftMods.isEmpty {
                sample.combo = comboString(modifiers: heldModifiers, key: keyName)
            }
        }

        Storage.shared.record(sample)
    }

    // MARK: - Modifier helpers

    private func modifierName(forKeyCode code: Int) -> String? {
        switch code {
        case kVK_Command, kVK_RightCommand: return "Cmd"
        case kVK_Shift, kVK_RightShift: return "Shift"
        case kVK_Option, kVK_RightOption: return "Option"
        case kVK_Control, kVK_RightControl: return "Control"
        case kVK_Function: return "Fn"
        default: return nil
        }
    }

    private func isModifierActive(flags: CGEventFlags, modifierName: String) -> Bool {
        switch modifierName {
        case "Cmd": return flags.contains(.maskCommand)
        case "Shift": return flags.contains(.maskShift)
        case "Option": return flags.contains(.maskAlternate)
        case "Control": return flags.contains(.maskControl)
        case "Fn": return flags.contains(.maskSecondaryFn)
        default: return false
        }
    }

    /// Builds a canonical, sorted combo string e.g. "Cmd+Shift+Z" so that
    /// "Shift+Cmd+Z" and "Cmd+Shift+Z" are counted as the same keybind.
    private func comboString(modifiers: Set<String>, key: String) -> String {
        let order = ["Control", "Option", "Shift", "Cmd", "Fn"]
        let sortedMods = order.filter { modifiers.contains($0) }
        return (sortedMods + [key]).joined(separator: "+")
    }
}
