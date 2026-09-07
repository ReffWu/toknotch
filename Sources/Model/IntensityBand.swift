import SwiftUI

/// The colour a ring takes at a given level of activity.
///
/// Deliberately *not* a warning scale. This app measures what you have spent,
/// not what you have left, so a full ring is an achievement rather than an
/// alarm — the Apple Watch reading of a closed ring, not a fuel gauge's. The
/// ramp therefore runs cool to warm as the number climbs, and the brightest,
/// warmest tone is reserved for beating your own best.
///
/// Using the old red-means-danger palette here would have said the opposite of
/// what the number means: your busiest day of the month would light up in the
/// colour reserved for "you are out".
enum IntensityBand: Equatable {
    case quiet
    case steady
    case strong
    case record

    static func band(for fraction: Double?) -> IntensityBand {
        guard let fraction else { return .quiet }
        switch fraction {
        case ..<0.34: return .quiet
        case ..<0.67: return .steady
        case ..<1.00: return .strong
        default:      return .record
        }
    }

    var color: Color {
        switch self {
        case .quiet:  return Color(hex: 0x6FA8DC)   // a calm blue: barely started
        case .steady: return Color(hex: 0x70E3B5)   // mint: a normal working day
        case .strong: return Color(hex: 0xFFC85C)   // amber: pushing it
        case .record: return Color(hex: 0xFF8A3D)   // ember: past your own best
        }
    }
}
