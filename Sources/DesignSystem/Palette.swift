import SwiftUI

/// Sampled from `docs/design/frame-124-hover-tooltip.png`, not invented.
///
/// Note these differ slightly from the hexes written in the design spec — the
/// frame is the source of truth, so the sampled values win.
enum Palette {
    static let notch         = Color.black                    // #000000
    static let card          = Color.black                    // #000000
    static let ringTrack     = Color(hex: 0x303030)
    /// The rule that divides two groups of rows inside a card. Brighter than
    /// the ring track: that one only has to be visible against the notch, this
    /// has to read as a division between two different questions.
    static let cardRule      = Color(hex: 0x424242)
    static let barTrack      = Color(hex: 0x2D2D2D)

    static let ample         = Color(hex: 0x00FF88)           // green
    static let watch         = Color(hex: 0xF2FF00)           // yellow
    static let critical      = Color(hex: 0xFF3F00)           // orange

    // TokNotch OLED Semantic Accents
    static let cyan          = Color(hex: 0x5CC8EC)           // Riffle Cyan
    static let mint          = Color(hex: 0x70E3B5)           // Mint Green
    static let amber         = Color(hex: 0xFFC85C)           // Amber Gold
    static let indigo        = Color(hex: 0x818CF8)           // Cyber Indigo

    /// The payback verdict, and nothing else: green once a plan has paid for
    /// itself, orange while it is still on the way. The same pair Settings
    /// uses (the system green and orange, in their dark-appearance values), so
    /// a multiple means the same thing wherever it is read. Deliberately not
    /// the intensity bands, whose ember means "past your own best" and made a
    /// paid-back plan look like a warning.
    static let paidBack      = Color(hex: 0x30D158)
    static let onTheWay      = Color(hex: 0xFF9F0A)

    static let textPrimary   = Color.white
    static let textSecondary = Color(hex: 0x808080)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue:  Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
