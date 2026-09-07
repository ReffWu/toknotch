import XCTest
import SwiftUI
@testable import TokNotch

/// Renders a real card for every ring the app can show.
///
/// Partly a smoke test — a card that fails to lay out fails here rather than on
/// someone's screen — and partly a way to actually look at it: set
/// `TOOLTIP_RENDER_PATH` to a directory and each frame is written into it.
@MainActor
final class TooltipRenderTests: XCTestCase {
    func testEveryCardLaysOutAtItsBudgetedHeight() throws {
        let rings = Fixtures.rings()
        XCTAssertFalse(rings.isEmpty)

        for ring in rings {
            let budget = ring.cardHeight(showingModels: RingSnapshot.collapsedModels)
            let renderer = ImageRenderer(
                content: TooltipCard(ring: ring).padding(20).background(Color(white: 0.26))
            )
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.nsImage, "\(ring.id) failed to render")

            // The shell is drawn at exactly the budgeted height, so the rendered
            // frame is that plus the padding either side. A card that silently
            // collapsed would still render, just far too short.
            XCTAssertEqual(image.size.height, budget + 40, accuracy: 1.5,
                           "\(ring.id) drew at a height its hover region does not match")
            XCTAssertGreaterThan(image.size.width, NotchLayout.cardWidth)

            if let directory = ProcessInfo.processInfo.environment["TOOLTIP_RENDER_PATH"] {
                let tiff = try XCTUnwrap(image.tiffRepresentation)
                let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?
                    .representation(using: .png, properties: [:]))
                try png.write(to: URL(fileURLWithPath: directory)
                    .appendingPathComponent("\(ring.id).png"))
            }
        }
    }

    /// A card with more models than it shows, collapsed and opened out.
    func testTheMoreLineAndTheExpandedCard() throws {
        guard let directory = ProcessInfo.processInfo.environment["TOOLTIP_RENDER_PATH"] else {
            throw XCTSkip("set TOOLTIP_RENDER_PATH to write the shots")
        }
        let ring = try XCTUnwrap(Fixtures.rings().first { $0.modelRows.count > 3 })
        for (name, limit) in [("collapsed", RingSnapshot.collapsedModels), ("expanded", 8)] {
            let renderer = ImageRenderer(
                content: TooltipCard(ring: ring, modelLimit: limit,
                                     canExpand: limit == RingSnapshot.collapsedModels)
                    .padding(20).background(Color(white: 0.26))
            )
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.nsImage)
            let tiff = try XCTUnwrap(image.tiffRepresentation)
            let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?
                .representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: directory)
                .appendingPathComponent("more-\(name).png"))
        }
    }

    /// The tail at every orientation, large, for looking at.
    func testTheTailAtEveryOrientation() throws {
        guard let directory = ProcessInfo.processInfo.environment["TOOLTIP_RENDER_PATH"] else {
            throw XCTSkip("set TOOLTIP_RENDER_PATH to write the shots")
        }
        let ring = Fixtures.rings()[0]
        for direction in [NotchEdge.TooltipDirection.leading, .trailing, .up, .down] {
            let renderer = ImageRenderer(
                content: TooltipCard(ring: ring, direction: direction)
                    .padding(30).background(Color(white: 0.26))
            )
            renderer.scale = 3
            let image = try XCTUnwrap(renderer.nsImage)
            let tiff = try XCTUnwrap(image.tiffRepresentation)
            let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?
                .representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: directory)
                .appendingPathComponent("tail-\(direction.rawValue).png"))
        }
    }

    /// A ring that could not be read says so instead of showing rows, and the
    /// card still has to hold that sentence.
    func testANoteCardHoldsItsMessage() throws {
        let ring = RingBuilder.placeholder(.today, language: .simplifiedChinese,
                                           note: "未找到 tokscale。用 Homebrew 安装后即可读取用量：brew install tokscale")
        let renderer = ImageRenderer(
            content: TooltipCard(ring: ring).padding(20).background(Color(white: 0.26))
        )
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        let budget = ring.cardHeight(showingModels: RingSnapshot.collapsedModels)
        XCTAssertEqual(image.size.height, budget + 40, accuracy: 1.5)
    }
}
