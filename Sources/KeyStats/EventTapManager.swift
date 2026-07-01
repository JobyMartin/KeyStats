import Cocoa
import Carbon.HIToolbox

/// Captures system-wide key events via a CGEventTap and turns them into
/// aggregated stats. Never stores raw text/passwords — only counts.
final class EventTapManager {
    static let shared = EventTapManager()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Tracks which modifier keys are currently held down, so we can build
    // combo strings like "⌘⇧Z" when a regular key is pressed alongside them.
    private var heldModifiers: Set<String> = []

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
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly, // we only observe; we never block or alter keystrokes
            eventsOfInterest: CGEventMask(eventMask),
            callback: { _, type, event, refcon in
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
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
    }

    // MARK: - Event handling

    private func handle(type: CGEventType, event: CGEvent) {
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
            Storage.shared.recordModifier(modifierName)
            Storage.shared.recordHourlyActivity()
            recordFrontmostApp()
        } else if !isDown {
            heldModifiers.remove(modifierName)
        }
    }

    private func handleKeyDown(event: CGEvent) {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let keyName = KeyCodeMap.name(for: keyCode)

        Storage.shared.recordKey(code: keyCode, name: keyName)
        Storage.shared.recordHourlyActivity()
        Storage.shared.recordDaily(isBackspace: keyName == "Delete" || keyName == "Forward Delete")
        recordFrontmostApp()

        if !heldModifiers.isEmpty {
            let nonShiftMods = heldModifiers.subtracting(["Shift"])
            guard !nonShiftMods.isEmpty else { return }
            let combo = comboString(modifiers: heldModifiers, key: keyName)
            Storage.shared.recordKeybind(combo)
        }
    }

    private func recordFrontmostApp() {
        if let app = NSWorkspace.shared.frontmostApplication, let name = app.localizedName {
            Storage.shared.recordApp(name)
        }
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
