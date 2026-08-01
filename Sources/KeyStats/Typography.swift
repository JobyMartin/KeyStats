import AppKit
import SwiftUI

// Font size + font-face tokens for the whole app — see znotes/fonts.md for
// the research behind which faces are actually safe to use and why. Modeled
// on Theme.swift's proven shape (a plain struct + a custom EnvironmentKey)
// rather than inventing a new pattern.

// MARK: - Font scale

/// Four steps, applied as a multiplier over every token's base size rather
/// than as four separate size tables — one number per step instead of 4x
/// the tokens to maintain.
enum FontScale: String, CaseIterable, Identifiable {
    case xs, s, regular, large
    var id: String { rawValue }

    var multiplier: CGFloat {
        switch self {
        case .xs: return 0.85
        case .s: return 0.925
        case .regular: return 1.0
        case .large: return 1.12
        }
    }

    var label: String {
        switch self {
        case .xs: return "XS"
        case .s: return "S"
        case .regular: return "Regular"
        case .large: return "Large"
        }
    }
}

// MARK: - Font face

/// How a preset's UI or mono face is reached. `.systemDesign` is the ONLY
/// safe route to SF Pro, SF Mono, SF Rounded, or New York — none of those
/// resolve via `NSFont(name:)`. `.SFNS-Regular` in particular silently
/// resolves to Times New Roman instead of failing, so `Font.custom` must
/// never be used for a system face. See znotes/fonts.md for the verified
/// availability tables this is built from.
enum FontFace: Equatable {
    case systemDesign(Font.Design)
    case named(String)

    /// True only for `.named` faces that don't actually resolve on this
    /// machine — a bundled font whose registration failed, or (in the
    /// `swift run` dev loop, which has no app bundle at all) any bundled
    /// face. `font(size:weight:)` already degrades to system in this case;
    /// this exists so UI can also surface *why* a preset looks unexpected.
    var isUnavailable: Bool {
        guard case .named(let name) = self else { return false }
        return NSFont(name: name, size: 12) == nil
    }

    func font(size: CGFloat, weight: Font.Weight) -> Font {
        switch self {
        case .systemDesign(let design):
            return .system(size: size, weight: weight, design: design)
        case .named(let name):
            guard NSFont(name: name, size: size) != nil else {
                // Degrade to system rather than let SwiftUI silently
                // substitute its own fallback with no signal to the caller.
                return .system(size: size, weight: weight)
            }
            return .custom(name, size: size).weight(weight)
        }
    }
}

// MARK: - Font preset

/// Pairs a UI face with a mono face — design.md's "two roles, no third
/// face" still holds, it's just user-selectable now. ★ (bundled) presets
/// need Resources/Fonts wiring in build-app.sh/Info.plist to actually
/// resolve; see znotes/fonts.md.
struct FontPreset: Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let uiFace: FontFace
    let monoFace: FontFace

    static let system = FontPreset(
        id: "default", name: "Default", description: "SF Pro + SF Mono — the original look.",
        uiFace: .systemDesign(.default), monoFace: .systemDesign(.monospaced)
    )

    static let all: [FontPreset] = [
        system,
        FontPreset(
            id: "modern-dev", name: "Modern Dev", description: "The current-decade coding face. ★ bundled",
            uiFace: .systemDesign(.default), monoFace: .named("JetBrains Mono")
        ),
        FontPreset(
            id: "classic-mac", name: "Classic Mac", description: "Pre-Retina nostalgia.",
            uiFace: .named("Helvetica Neue"), monoFace: .named("Monaco")
        ),
        FontPreset(
            id: "editorial", name: "Editorial", description: "Magazine, unexpected.",
            uiFace: .systemDesign(.serif), monoFace: .named("PT Mono")
        ),
        FontPreset(
            id: "geometric", name: "Geometric", description: "Architectural, bold.",
            uiFace: .named("Futura"), monoFace: .named("Andale Mono")
        ),
        // Iowan Old Style is the font Apple Books itself reads with — the
        // closest thing to "old book" macOS ships. Courier New pairs it
        // with a typewriter/manuscript mono face, not a modern coding one.
        FontPreset(
            id: "manuscript", name: "Manuscript", description: "Old book, dog-eared pages, ink on paper.",
            uiFace: .named("Iowan Old Style"), monoFace: .named("Courier New")
        ),
    ]

    static func preset(forID id: String) -> FontPreset {
        all.first { $0.id == id } ?? .system
    }
}

// MARK: - Typography tokens

/// The ~21 role-named fonts every `.font(...)` call site in the app
/// collapses onto — replaces 54 inline literals across DashboardView,
/// PreferencesView, and MenuBarDropdownRows. Named by role, not size, so
/// call sites read intentionally (`typography.label`, not
/// `.font(.system(size: 12.5, weight: .medium))`).
///
/// Sizes here are a normalized pass over what existed before — several
/// near-duplicate sizes (10 vs 10.5, 11 vs 11.5, 12 vs 12.5) were merged
/// onto one token, so a handful of elements shift by up to a point even at
/// `.regular` scale. Deliberate, not a bug.
struct AppTypography: Equatable {
    let preset: FontPreset
    let scale: FontScale

    private func ui(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        preset.uiFace.font(size: size * scale.multiplier, weight: weight)
    }

    private func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        preset.monoFace.font(size: size * scale.multiplier, weight: weight)
    }

    // UI face — labels, titles, body text, buttons.
    var wordmark: Font { ui(14, .semibold) }        // "KeyStats" header wordmark
    var heroLabel: Font { ui(14.5, .bold) }         // "72% of daily goal"
    var emphasis: Font { ui(13.5, .semibold) }      // banner titles, streak text
    var cardTitle: Font { ui(13, .semibold) }       // section card / theme card titles
    var greeting: Font { ui(13, .bold) }            // dropdown greeting
    var body: Font { ui(13, .regular) }             // prose / plain text
    var label: Font { ui(12.5, .medium) }           // field/section labels
    var tabLabel: Font { ui(12, .medium) }          // Preferences tab bar
    var strongSmall: Font { ui(11.5, .semibold) }   // filled-button labels, status badges
    var mediumLabel: Font { ui(11.5, .medium) }     // link-style actions, small stat labels
    var caption: Font { ui(10.5, .regular) }        // faint helper/description text
    var statLabel: Font { ui(10.5, .semibold) }     // uppercase stat-card labels (pair with .tracking(0.5))

    // Mono face — every number, keycap, and keybind.
    var heroNumber: Font { mono(22, .bold) }        // stat card hero value
    var streakNumber: Font { mono(18, .bold) }      // longest streak number
    var statNumber: Font { mono(13, .bold) }        // dropdown "Today" count
    var monoValue: Font { mono(12) }                // goal/keycount values
    var monoChipStrong: Font { mono(10.5, .semibold) } // combo chip letters/counts
    var monoKeycap: Font { mono(10, .semibold) }    // keycap chip label
    var monoSmall: Font { mono(11) }                // list row counts
    var monoTiny: Font { mono(9) }                  // chart bar annotations
    var monoChipSmall: Font { mono(9.5) }           // preset chip value line
}

private struct TypographyEnvironmentKey: EnvironmentKey {
    static let defaultValue = AppTypography(preset: .system, scale: .regular)
}

extension EnvironmentValues {
    var typography: AppTypography {
        get { self[TypographyEnvironmentKey.self] }
        set { self[TypographyEnvironmentKey.self] = newValue }
    }
}
