import SwiftUI

/// Sizes are derived from cap heights measured in the design frame, so they
/// track `Design.scale` along with everything else.
enum Typography {
    /// The percent under each provider ring. Cap height 27px in the frame.
    static let percent = Font.system(size: Design.fontSize(capPixels: 27), weight: .semibold)

    /// "Claude Usage". Cap height 26px.
    static let cardTitle = Font.system(size: Design.fontSize(capPixels: 26), weight: .semibold)

    /// "Current session", "73% Used", "Resets in 51 min". Cap height 18px.
    static let cardBody = Font.system(size: Design.fontSize(capPixels: 18), weight: .regular)

    /// The one big figure on a card. Rounded, because it is a readout rather
    /// than prose, and large enough that nothing else on the card competes.
    static let hero = Font.system(size: Design.fontSize(capPixels: 64),
                                  weight: .semibold, design: .rounded)
    /// The line that says what the hero figure means.
    static let heroCaption = Font.system(size: Design.fontSize(capPixels: 20), weight: .medium)
}
