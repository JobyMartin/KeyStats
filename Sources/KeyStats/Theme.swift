import SwiftUI

// Four dark themes, switchable live — see znotes/design.md §3 for the
// design source of truth (token table + vibe descriptions). All four share
// the same token *names*; only values differ, so views read `theme.accent`
// etc. and never branch per-theme.
struct AppTheme: Identifiable, Equatable {
    let id: String
    let name: String
    /// Shown on the Appearance tab's theme cards. Source of truth for
    /// name/description is `znotes/themes.json` (kept there for pasting
    /// into GPT for more names) — these two fields are the "promoted"
    /// version, plain string literals so re-naming/re-wording a theme is a
    /// one-line edit, no build tooling involved.
    let description: String

    let bg: Color
    let surface: Color
    let surfaceRaised: Color
    let border: Color
    let borderSoft: Color

    let text: Color
    let textDim: Color
    let textFaint: Color

    let accent: Color
    let good: Color
    let bad: Color

    /// Categorical colors for modifier bars / app dots — deliberately
    /// distinct per theme so a legend doesn't read as the accent color
    /// repeated four times.
    let series: [Color]

    static func == (lhs: AppTheme, rhs: AppTheme) -> Bool { lhs.id == rhs.id }

    static let backlit = AppTheme(
        id: "backlit", name: "Backlit", description: "The keyboard glows. The work begins.",
        bg: Color(hex: 0x0c0e13), surface: Color(hex: 0x151822), surfaceRaised: Color(hex: 0x1a1e2a),
        border: Color(hex: 0x262b3a), borderSoft: Color(hex: 0x1e222e),
        text: Color(hex: 0xe9ebf2), textDim: Color(hex: 0x8991a8), textFaint: Color(hex: 0x565c70),
        accent: Color(hex: 0xff8a3d), good: Color(hex: 0x5fd6a0), bad: Color(hex: 0xff6b6b),
        series: [Color(hex: 0xff8a3d), Color(hex: 0x6ea8fe), Color(hex: 0xb78af0), Color(hex: 0x5fd6a0)]
    )

    // Renamed from "Copper" once the user ran it (and the other three
    // originals) through the same external naming pass as the seven below —
    // see znotes/themes.json. `id` kept as "copper" so no persisted
    // @AppStorage selection breaks; only the display name/description moved.
    static let cinder = AppTheme(
        id: "copper", name: "Cinder", description: "After the fire. Still creating.",
        bg: Color(hex: 0x140f0c), surface: Color(hex: 0x1e1512), surfaceRaised: Color(hex: 0x251a15),
        border: Color(hex: 0x3a2620), borderSoft: Color(hex: 0x2a1c17),
        text: Color(hex: 0xf2e8e2), textDim: Color(hex: 0xb09284), textFaint: Color(hex: 0x6e564a),
        accent: Color(hex: 0xe05a2b), good: Color(hex: 0x9bc47a), bad: Color(hex: 0xff6b5c),
        series: [Color(hex: 0xe05a2b), Color(hex: 0xd4a039), Color(hex: 0x8a5a4a), Color(hex: 0xc98a52)]
    )

    static let nocturne = AppTheme(
        id: "nocturne", name: "Nocturne", description: "When the world goes quiet, ideas come alive.",
        bg: Color(hex: 0x0a0b14), surface: Color(hex: 0x12131f), surfaceRaised: Color(hex: 0x171927),
        border: Color(hex: 0x242640), borderSoft: Color(hex: 0x1a1c2e),
        text: Color(hex: 0xe4e6f7), textDim: Color(hex: 0x8a8cb3), textFaint: Color(hex: 0x52547a),
        accent: Color(hex: 0x7dd3fc), good: Color(hex: 0x2dd4bf), bad: Color(hex: 0xf472b6),
        series: [Color(hex: 0x7dd3fc), Color(hex: 0xa78bfa), Color(hex: 0xf472b6), Color(hex: 0x2dd4bf)]
    )

    static let alpine = AppTheme(
        id: "alpine", name: "Alpine", description: "Quiet growth. Steady focus. One step at a time.",
        bg: Color(hex: 0x0d1210), surface: Color(hex: 0x151d1a), surfaceRaised: Color(hex: 0x1a2420),
        border: Color(hex: 0x283530), borderSoft: Color(hex: 0x1c2622),
        text: Color(hex: 0xe6ece8), textDim: Color(hex: 0x8fa39a), textFaint: Color(hex: 0x57685f),
        accent: Color(hex: 0x5ec8d8), good: Color(hex: 0x8fbf6e), bad: Color(hex: 0xe8836b),
        series: [Color(hex: 0x5ec8d8), Color(hex: 0x4a7a5e), Color(hex: 0xe8b87a), Color(hex: 0x8fbf6e)]
    )

    // The seven below came from a batch the user generated externally
    // (znotes/themes.json) — names/descriptions kept in sync with that
    // file, `accentHover` dropped (no token for it yet), `borderSoft`
    // derived since the source palette didn't define one: a 60/40 blend of
    // its `surface`/`border`, matching the relationship already visible
    // across backlit/cinder/nocturne/alpine (borderSoft sits between
    // surface and border, close to surfaceRaised).
    static let drizzle = AppTheme(
        id: "drizzle", name: "Drizzle", description: "Rainy afternoon. Quiet room. Deep focus.",
        bg: Color(hex: 0x101417), surface: Color(hex: 0x171D22), surfaceRaised: Color(hex: 0x212930),
        border: Color(hex: 0x2F3942), borderSoft: Color(hex: 0x21282F),
        text: Color(hex: 0xE6EDF2), textDim: Color(hex: 0xA8B3BC), textFaint: Color(hex: 0x74818C),
        accent: Color(hex: 0x69B6E8), good: Color(hex: 0x6FB88D), bad: Color(hex: 0xC76A6A),
        series: [Color(hex: 0x69B6E8), Color(hex: 0x97A8B5), Color(hex: 0x7AA77D), Color(hex: 0x8E8AC7)]
    )

    static let afterglow = AppTheme(
        id: "afterglow", name: "Afterglow", description: "The last light on. The keyboard still glowing.",
        bg: Color(hex: 0x11100D), surface: Color(hex: 0x191713), surfaceRaised: Color(hex: 0x242019),
        border: Color(hex: 0x393128), borderSoft: Color(hex: 0x26211B),
        text: Color(hex: 0xF3E8D2), textDim: Color(hex: 0xC7B89A), textFaint: Color(hex: 0x8E8068),
        accent: Color(hex: 0xE3A64A), good: Color(hex: 0x86B879), bad: Color(hex: 0xC96B55),
        series: [Color(hex: 0xE3A64A), Color(hex: 0xD47A45), Color(hex: 0xB8895A), Color(hex: 0x7D9A6A)]
    )

    static let midnight = AppTheme(
        id: "midnight", name: "Midnight", description: "The world sleeps. The keyboard stays awake.",
        bg: Color(hex: 0x0B0D1A), surface: Color(hex: 0x11152A), surfaceRaised: Color(hex: 0x181D38),
        border: Color(hex: 0x292F52), borderSoft: Color(hex: 0x1B1F3A),
        text: Color(hex: 0xE7EBFF), textDim: Color(hex: 0xAAB3D6), textFaint: Color(hex: 0x68729A),
        accent: Color(hex: 0x5CC8FF), good: Color(hex: 0x62C98A), bad: Color(hex: 0xD46A7A),
        series: [Color(hex: 0x5CC8FF), Color(hex: 0x7B6CFF), Color(hex: 0x57C7A3), Color(hex: 0xC27CFF)]
    )

    static let timberline = AppTheme(
        id: "timberline", name: "Timberline", description: "Cold air. Clear mind. Sharp focus.",
        bg: Color(hex: 0x0E1415), surface: Color(hex: 0x151E20), surfaceRaised: Color(hex: 0x1D292C),
        border: Color(hex: 0x304045), borderSoft: Color(hex: 0x202C2F),
        text: Color(hex: 0xE3ECEB), textDim: Color(hex: 0xAABCC0), textFaint: Color(hex: 0x71858A),
        accent: Color(hex: 0x72B7D4), good: Color(hex: 0x83B88A), bad: Color(hex: 0xC66E68),
        series: [Color(hex: 0x72B7D4), Color(hex: 0x7FA58A), Color(hex: 0x9AA7B2), Color(hex: 0x8C86C7)]
    )

    static let prelude = AppTheme(
        id: "prelude", name: "Prelude", description: "First light. Fresh coffee. A new day ahead.",
        bg: Color(hex: 0x151515), surface: Color(hex: 0x1E1C1A), surfaceRaised: Color(hex: 0x282522),
        border: Color(hex: 0x393430), borderSoft: Color(hex: 0x292623),
        text: Color(hex: 0xEEE5D7), textDim: Color(hex: 0xC5B8A5), textFaint: Color(hex: 0x887C6D),
        accent: Color(hex: 0xD39A5A), good: Color(hex: 0x8DAA7A), bad: Color(hex: 0xC47A68),
        series: [Color(hex: 0xD39A5A), Color(hex: 0xB88E72), Color(hex: 0x9AA77B), Color(hex: 0x7E9AA8)]
    )

    static let velocity = AppTheme(
        id: "velocity", name: "Velocity", description: "Fast pace. Clear focus. Keep moving.",
        bg: Color(hex: 0x101214), surface: Color(hex: 0x171B20), surfaceRaised: Color(hex: 0x222830),
        border: Color(hex: 0x303944), borderSoft: Color(hex: 0x21272E),
        text: Color(hex: 0xEDF2F7), textDim: Color(hex: 0xB3BEC9), textFaint: Color(hex: 0x73808C),
        accent: Color(hex: 0x4FD1C5), good: Color(hex: 0x71C985), bad: Color(hex: 0xD96C6C),
        series: [Color(hex: 0x4FD1C5), Color(hex: 0x4D8DFF), Color(hex: 0xE0B45C), Color(hex: 0xB779FF)]
    )

    // Re-colored by the user (znotes/themes.json) — the original Stillness
    // palette read too close to Prelude (both warm amber/tan on near-black);
    // this one moves to an olive/moss accent to actually differentiate.
    static let stillness = AppTheme(
        id: "stillness", name: "Stillness", description: "A quiet pause before the day begins.",
        bg: Color(hex: 0x11130F), surface: Color(hex: 0x191D17), surfaceRaised: Color(hex: 0x222821),
        border: Color(hex: 0x353D33), borderSoft: Color(hex: 0x242A22),
        text: Color(hex: 0xECE8DC), textDim: Color(hex: 0xB8B6A7), textFaint: Color(hex: 0x7A7A6C),
        accent: Color(hex: 0xB9A15B), good: Color(hex: 0x7FA47A), bad: Color(hex: 0xB96E67),
        series: [Color(hex: 0xB9A15B), Color(hex: 0x7FA47A), Color(hex: 0x8EA7B8), Color(hex: 0x9A8CB8)]
    )

    // Added from a further externally-generated batch (znotes/themes.json).
    // `borderSoft` derived the same way as the seven above: a 60/40 blend of
    // `surface`/`border` per channel. Obsidian is dark like every theme
    // before it; Canvas, Linen, and Blueprint are light palettes — the first
    // in the app. That's a direct reversal of design.md §1's "Dark only —
    // no light theme, ever (explicit product decision, not an oversight)."
    // Added anyway per explicit user request (matches the open
    // `znotes/todo.md` item "a couple light themes because those people
    // exist") — design.md needs updating to reflect this is no longer true,
    // and light-theme-specific issues (contrast, any place light/dark is
    // assumed rather than read from `theme`) haven't been audited yet.
    static let obsidian = AppTheme(
        id: "obsidian", name: "Obsidian", description: "Deep focus begins where the light ends.",
        bg: Color(hex: 0x050506), surface: Color(hex: 0x0B0C0E), surfaceRaised: Color(hex: 0x111317),
        border: Color(hex: 0x1D2127), borderSoft: Color(hex: 0x121418),
        text: Color(hex: 0xF4F6F8), textDim: Color(hex: 0x9EA6B4), textFaint: Color(hex: 0x5B6270),
        accent: Color(hex: 0x7DAFFF), good: Color(hex: 0x63D7A0), bad: Color(hex: 0xF26D6D),
        series: [Color(hex: 0x7DAFFF), Color(hex: 0xA78BFA), Color(hex: 0x63D7A0), Color(hex: 0xF0C76A)]
    )

    static let canvas = AppTheme(
        id: "canvas", name: "Canvas", description: "A blank page. Endless possibilities.",
        bg: Color(hex: 0xF8F7F3), surface: Color(hex: 0xF1EFEA), surfaceRaised: Color(hex: 0xE8E5DF),
        border: Color(hex: 0xD6D2CA), borderSoft: Color(hex: 0xE6E3DD),
        text: Color(hex: 0x23262D), textDim: Color(hex: 0x5F6673), textFaint: Color(hex: 0x8C939F),
        accent: Color(hex: 0x4C8BF5), good: Color(hex: 0x4FA56B), bad: Color(hex: 0xD45C5C),
        series: [Color(hex: 0x4C8BF5), Color(hex: 0x7B61FF), Color(hex: 0x4FA56B), Color(hex: 0xD89A36)]
    )

    static let linen = AppTheme(
        id: "linen", name: "Linen", description: "Soft light. Quiet thoughts. Lasting focus.",
        bg: Color(hex: 0xF5F2EC), surface: Color(hex: 0xECE7DF), surfaceRaised: Color(hex: 0xE2DCD3),
        border: Color(hex: 0xCEC6BB), borderSoft: Color(hex: 0xE0DAD1),
        text: Color(hex: 0x2B2926), textDim: Color(hex: 0x666158), textFaint: Color(hex: 0x938A7D),
        accent: Color(hex: 0xB7853F), good: Color(hex: 0x5C9B67), bad: Color(hex: 0xC95A58),
        series: [Color(hex: 0xB7853F), Color(hex: 0x7F9FB5), Color(hex: 0x5C9B67), Color(hex: 0x9A82C8)]
    )

    static let blueprint = AppTheme(
        id: "blueprint", name: "Blueprint", description: "Designed with clarity. Built with precision.",
        bg: Color(hex: 0xF3F7FB), surface: Color(hex: 0xEAF0F6), surfaceRaised: Color(hex: 0xDFE8F1),
        border: Color(hex: 0xC8D4E2), borderSoft: Color(hex: 0xDCE5EE),
        text: Color(hex: 0x1F2B38), textDim: Color(hex: 0x5B6B7D), textFaint: Color(hex: 0x8795A5),
        accent: Color(hex: 0x3F7AE0), good: Color(hex: 0x4D9C71), bad: Color(hex: 0xD35D5D),
        series: [Color(hex: 0x3F7AE0), Color(hex: 0x5FA9DD), Color(hex: 0x4D9C71), Color(hex: 0x8A74D8)]
    )

    static let all: [AppTheme] = [
        backlit, cinder, nocturne, alpine,
        drizzle, afterglow, midnight, timberline, prelude, velocity, stillness,
        obsidian, canvas, linen, blueprint,
    ]

    static func theme(forID id: String) -> AppTheme {
        all.first { $0.id == id } ?? .backlit
    }
}

private struct ThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue = AppTheme.backlit
}

extension EnvironmentValues {
    var theme: AppTheme {
        get { self[ThemeEnvironmentKey.self] }
        set { self[ThemeEnvironmentKey.self] = newValue }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
