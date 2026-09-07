@testable import TokNotch

/// A ring of a known shape, for the geometry tests.
///
/// The layout tests care only about how many cells there are and how tall a
/// card is; building a real digest for each of them would tie geometry
/// assertions to whatever the aggregation happens to produce.
enum TestRing {
    static func make(_ index: Int, rows: Int = 3, bars: Int = 0) -> RingSnapshot {
        RingSnapshot(
            kind: .vendor(Vendor.allCases[index % Vendor.allCases.count]),
            title: "R\(index)",
            caption: "范围",
            glyph: .today,
            headline: "1.0万",
            hero: "1.0万",
            heroCaption: "对比 40%",
            heroTint: Palette.ample,
            heroFraction: 0.4,
            fraction: 0.4,
            tint: Palette.ample,
            rows: (0..<rows).map {
                MetricRow(id: "r\($0)", label: "L", value: "V",
                          fraction: $0 < bars ? 0.5 : nil)
            }
        )
    }
}
