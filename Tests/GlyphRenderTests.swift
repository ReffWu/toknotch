import XCTest
import SwiftUI
@testable import TokNotch

/// Renders every ring mark side by side, at the size the notch draws them.
///
/// Optical weight cannot be checked by reading numbers — a mark either sits
/// right next to its neighbours or it does not. Set `GLYPH_RENDER_PATH` and the
/// sheet is written there.
@MainActor
final class GlyphRenderTests: XCTestCase {
    private var everyGlyph: [(String, RingGlyph)] {
        [("today", .today), ("month", .month), ("lifetime", .lifetime)]
            + Vendor.allCases.map { ($0.rawValue, RingGlyph.vendor($0)) }
    }

    func testEveryMarkRendersAtTheRingSize() throws {
        let sheet = VStack(spacing: 0) {
            ForEach(Array(everyGlyph.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 14) {
                    // The real thing: the mark inside a ring, on the notch's black.
                    ZStack {
                        Circle().strokeBorder(Palette.ringTrack, lineWidth: NotchLayout.trackStroke)
                        RingGlyphView(glyph: item.1)
                            .foregroundStyle(Self.tint(for: item.1))
                    }
                    .frame(width: NotchLayout.ringDiameter, height: NotchLayout.ringDiameter)

                    Text(item.0).font(.system(size: 11)).foregroundStyle(.white)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
            }
        }
        .frame(width: 220)
        .background(Color.black)

        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.nsImage)
        XCTAssertGreaterThan(image.size.height, 100)

        if let path = ProcessInfo.processInfo.environment["GLYPH_RENDER_PATH"] {
            let tiff = try XCTUnwrap(image.tiffRepresentation)
            let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?
                .representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: path).appendingPathComponent("glyphs.png"))
        }
    }

    private static func tint(for glyph: RingGlyph) -> Color {
        if case .vendor(let vendor) = glyph { return vendor.ringTint }
        return .white
    }
}
