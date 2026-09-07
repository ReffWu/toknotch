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

    /// Render 100% authentic, high-resolution marketing showcase visuals using real SwiftUI views.
    func testExportMarketingShowcases() throws {
        let outDir = "/tmp/toknotch_renders"
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

        let rings = Fixtures.rings(language: .simplifiedChinese)
        guard let claudeRing = rings.first(where: { $0.id.hasPrefix("anthropic") }) ?? rings.first else { return }

        // 1. Top Notch with Live Tooltip (1000x1000 @ 2x = 2000x2000)
        let v1 = MarketingTopNotchView(rings: rings, activeRing: claudeRing)
            .frame(width: 1000, height: 1000)
        let renderer1 = ImageRenderer(content: v1)
        renderer1.scale = 2
        if let img1 = renderer1.nsImage,
           let tiff1 = img1.tiffRepresentation,
           let png1 = NSBitmapImageRep(data: tiff1)?.representation(using: .png, properties: [:]) {
            try png1.write(to: URL(fileURLWithPath: "\(outDir)/showcase_top_notch.png"))
            print("Successfully rendered showcase_top_notch.png (2000x2000)")
        }

        // 2. Detailed Multi-Model Breakdown (1000x1000 @ 2x = 2000x2000)
        let v2 = MarketingDetailView(rings: rings, activeRing: claudeRing)
            .frame(width: 1000, height: 1000)
        let renderer2 = ImageRenderer(content: v2)
        renderer2.scale = 2
        if let img2 = renderer2.nsImage,
           let tiff2 = img2.tiffRepresentation,
           let png2 = NSBitmapImageRep(data: tiff2)?.representation(using: .png, properties: [:]) {
            try png2.write(to: URL(fileURLWithPath: "\(outDir)/showcase_detail.png"))
            print("Successfully rendered showcase_detail.png (2000x2000)")
        }
    }
}

// MARK: - Marketing Showcase Views

private struct MarketingTopNotchView: View {
    let rings: [RingSnapshot]
    let activeRing: RingSnapshot

    var body: some View {
        ZStack(alignment: .top) {
            // macOS Dark Wall with subtle vignette
            LinearGradient(
                colors: [Color(hex: 0x07080B), Color(hex: 0x0E121A), Color(hex: 0x161C28)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(
                RadialGradient(
                    colors: [Color(hex: 0x38BDF8).opacity(0.12), Color.clear],
                    center: .top,
                    startRadius: 50,
                    endRadius: 420
                )
            )

            VStack(spacing: 0) {
                // Menu Bar
                HStack {
                    HStack(spacing: 16) {
                        Image(systemName: "applelogo")
                        Text("TokNotch").fontWeight(.bold)
                        Text("编辑")
                        Text("视图")
                        Text("窗口")
                    }
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.88))

                    Spacer()

                    HStack(spacing: 14) {
                        Image(systemName: "wifi")
                        Image(systemName: "battery.100")
                        Text("9月7日 周一 12:45").fontWeight(.medium)
                    }
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.85))
                }
                .padding(.horizontal, 32)
                .frame(height: 44)
                .background(Color.black.opacity(0.45))
                .overlay(Rectangle().frame(height: 0.5).foregroundColor(Color.white.opacity(0.12)), alignment: .bottom)

                // TokNotch Integrated Island
                HStack(spacing: 20) {
                    // Left rings
                    HStack(spacing: 16) {
                        if rings.indices.contains(0) { ringCell(rings[0]) }
                        if rings.indices.contains(1) { ringCell(rings[1]) }
                    }

                    // Hardware Notch
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.black)
                            .frame(width: 176, height: 38)
                        HStack(spacing: 8) {
                            Circle().fill(Color(hex: 0x111625)).frame(width: 10, height: 10)
                                .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                            Circle().fill(Color(hex: 0x22C55E)).frame(width: 4, height: 4)
                                .shadow(color: Color(hex: 0x22C55E), radius: 3)
                        }
                    }

                    // Right rings
                    HStack(spacing: 16) {
                        if rings.indices.contains(2) { ringCell(rings[2]) }
                        if rings.indices.contains(3) {
                            ringCell(rings[3])
                        } else if rings.indices.contains(0) {
                            ringCell(rings[0])
                        }
                    }
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.black)
                        .shadow(color: Color.black.opacity(0.65), radius: 24, x: 0, y: 12)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
                )

                // Tooltip Floating Under Active Ring
                TooltipCard(ring: activeRing, direction: .up, modelLimit: 6, canExpand: true)
                    .scaleEffect(1.08)
                    .shadow(color: Color.black.opacity(0.75), radius: 36, x: 0, y: 18)
                    .padding(.top, 24)

                Spacer()
            }
        }
    }

    @ViewBuilder
    private func ringCell(_ r: RingSnapshot) -> some View {
        VStack(spacing: 3) {
            UsageRing(fraction: r.fraction, glyph: r.glyph, tint: r.tint)
            Text(r.title).font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.75))
        }
    }
}

private struct MarketingDetailView: View {
    let rings: [RingSnapshot]
    let activeRing: RingSnapshot

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x08090C), Color(hex: 0x11141C), Color(hex: 0x060709)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(
                RadialGradient(
                    colors: [Color(hex: 0x818CF8).opacity(0.1), Color.clear],
                    center: .center,
                    startRadius: 80,
                    endRadius: 500
                )
            )

            HStack(spacing: 54) {
                // Left Detail
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        Circle().fill(Color(hex: 0xEA580C)).frame(width: 9, height: 9)
                        Text("全景配额与实时消耗明细")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white.opacity(0.92))
                    }

                    TooltipCard(ring: activeRing, direction: .leading, modelLimit: 8, canExpand: false)
                        .scaleEffect(1.05)
                        .shadow(color: Color.black.opacity(0.75), radius: 32, x: 0, y: 16)
                }

                // Right Side Notch
                VStack(spacing: 16) {
                    HStack(spacing: 8) {
                        Circle().fill(Color(hex: 0x70E3B5)).frame(width: 9, height: 9)
                        Text("屏幕右侧停靠形态")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white.opacity(0.92))
                    }

                    ZStack {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.black)
                            .frame(width: 74, height: 440)
                            .shadow(color: Color.black.opacity(0.65), radius: 24, x: -8, y: 0)
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                            )

                        VStack(spacing: 24) {
                            ForEach(0..<min(rings.count, 4), id: \.self) { i in
                                let r = rings[i]
                                VStack(spacing: 4) {
                                    UsageRing(fraction: r.fraction, glyph: r.glyph, tint: r.tint)
                                    Text("\(Int((r.fraction ?? 0) * 100))%")
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.88))
                                }
                            }
                            Circle()
                                .fill(Color.white.opacity(0.1))
                                .frame(width: 32, height: 32)
                                .overlay(Image(systemName: "gearshape.fill").font(.system(size: 14)).foregroundColor(.white.opacity(0.75)))
                        }
                    }
                }
            }
            .padding(48)
        }
    }
}



