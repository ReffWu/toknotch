import SwiftUI

/// The mark in the middle of a ring.
///
/// The three primaries take a symbol that says which stretch of time they
/// measure; a vendor takes its own logo where we have one traced, and its
/// initials where we do not. Initials rather than a stand-in symbol on
/// purpose — a generic glyph on six different rings makes them look like six
/// of the same thing, which is the one thing the stack must never do.
enum RingGlyph: Equatable {
    case today
    case month
    case lifetime
    case vendor(Vendor)

    /// Trims each mark to the same optical weight.
    ///
    /// Not the same as the same *size*: `infinity` is a wide, thin mark that
    /// occupies a fraction of its box, `sun.max.fill` fills most of one, and a
    /// flattened logo fills all of it. Matching the boxes leaves the marks
    /// looking wildly different; matching the ink is what makes a stack of
    /// rings look like one set.
    var opticalScale: CGFloat {
        switch self {
        case .today:    return 1.14
        // Already the heaviest mark of the three: a grid inside a frame reads
        // darker than a logo of the same width, so it is trimmed rather than
        // matched.
        case .month:    return 0.96
        case .lifetime: return 1.30
        case .vendor:   return 0.96
        }
    }
}

struct RingGlyphView: View {
    let glyph: RingGlyph
    var size: CGFloat = NotchLayout.glyphSize

    var body: some View {
        Group {
            switch glyph {
            case .today:    symbol("sun.max.fill")
            case .month:    symbol("calendar")
            case .lifetime: symbol("infinity")
            case .vendor(let vendor): mark(for: vendor)
            }
        }
        // Every mark is drawn into the same box and then scaled to the same
        // optical weight, so the layout grid stays fixed while the ink is
        // evened out within it.
        .scaleEffect(glyph.opticalScale)
        .frame(width: size, height: size)
    }

    /// SF Symbols carry their own generous margin inside the box; a flattened
    /// logo fills it edge to edge. Left alone the three primaries read as
    /// visibly smaller than the vendor marks beside them in the same stack.
    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .resizable()
            .scaledToFit()
    }

    @ViewBuilder
    private func mark(for vendor: Vendor) -> some View {
        if let outline = vendor.outline {
            GlyphShape(outline: outline).fill(style: FillStyle(eoFill: true))
        } else {
            // Honest letters rather than a stand-in symbol: a generic glyph on
            // several rings makes them look like several of the same thing.
            Text(vendor.initials)
                .font(.system(size: size * (vendor.initials.count >= 3 ? 0.42 : 0.60),
                              weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
    }
}

extension Vendor {
    /// Kept distinct from one another on purpose: `Mi`/`Ms`/`Me` for Xiaomi,
    /// Mistral and Meta would be one letter apart and unreadable at 17pt.
    var initials: String {
        switch self {
        case .anthropic: return "A"
        case .openai:    return "O"
        case .google:    return "G"
        case .deepseek:  return "DS"
        case .alibaba:   return "Q"
        case .zhipu:     return "GLM"
        case .moonshot:  return "K"
        case .minimax:   return "MM"
        case .xai:       return "X"
        case .xiaomi:    return "MiMo"
        case .nvidia:    return "NV"
        case .meta:      return "Llama"
        case .mistral:   return "MsT"
        case .other:     return "···"
        }
    }
}

/// A traced outline scaled into the view's bounds, filled even-odd so the
/// counters inside a knot stay open.
struct GlyphShape: Shape {
    let outline: [[CGPoint]]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for loop in outline {
            guard let first = loop.first else { continue }
            path.move(to: point(first, in: rect))
            for p in loop.dropFirst() { path.addLine(to: point(p, in: rect)) }
            path.closeSubpath()
        }
        return path
    }

    private func point(_ p: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height)
    }
}
