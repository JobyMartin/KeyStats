import SwiftUI

// Hardcoded "Backlit" palette — the only theme that exists right now.
// Deliberately flat (no protocol, no @AppStorage selection) because there's
// nothing to switch between yet; see znotes/design.md §3 for the other three
// themes this will eventually pick from once theme switching is built.
enum Theme {
    static let bg = Color(hex: 0x0c0e13)
    static let surface = Color(hex: 0x151822)
    static let surfaceRaised = Color(hex: 0x1a1e2a)
    static let border = Color(hex: 0x262b3a)
    static let borderSoft = Color(hex: 0x1e222e)

    static let text = Color(hex: 0xe9ebf2)
    static let textDim = Color(hex: 0x8991a8)
    static let textFaint = Color(hex: 0x565c70)

    static let accent = Color(hex: 0xff8a3d)
    static let good = Color(hex: 0x5fd6a0)
    static let bad = Color(hex: 0xff6b6b)

    /// Categorical colors for modifier bars / app dots — deliberately
    /// distinct from `accent` so a 4-item legend doesn't read as the same
    /// color repeated four times.
    static let series: [Color] = [accent, Color(hex: 0x6ea8fe), Color(hex: 0xb78af0), good]
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
