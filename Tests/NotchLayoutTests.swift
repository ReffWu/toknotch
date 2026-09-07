import XCTest
@testable import TokNotch

/// The layout is a scaled copy of `docs/design/frame-124-hover-tooltip.png`.
/// These pin the ratios the frame fixes, so a change to `Design.scale` resizes
/// everything without silently reshaping it.
final class NotchLayoutTests: XCTestCase {
    func testRingIsTheSpecAnchor() {
        XCTAssertEqual(NotchLayout.ringDiameter, 44, accuracy: 0.001)
    }

    func testProportionsMatchTheFrame() {
        // 186px body against a 117px ring.
        XCTAssertEqual(NotchLayout.bodyDepth(for: .right) / NotchLayout.ringDiameter, 186.0 / 117.0, accuracy: 0.001)
        // Cell centre to cell centre is 275px in the frame. Looser, because
        // the pitch includes a real font's line box rather than a measured
        // cap height, and SF's metrics are not the frame's to the pixel.
        XCTAssertEqual(NotchLayout.cellPitch(for: .right) / NotchLayout.ringDiameter, 275.0 / 117.0, accuracy: 0.05)
        // The card is 600px wide.
        XCTAssertEqual(NotchLayout.cardWidth / NotchLayout.ringDiameter, 600.0 / 117.0, accuracy: 0.001)
    }

    func testShapeGrowsOneCellAtATime() {
        let cell = NotchLayout.cellExtent
        let one = NotchLayout.shapeLength(cellCount: 1)
        let two = NotchLayout.shapeLength(cellCount: 2)
        XCTAssertEqual(two - one, cell + NotchLayout.cellSpacing, accuracy: 0.001)
    }

    func testRingCentresAreEvenlySpacedInsideTheBody() {
        let first = NotchLayout.ringCenter(index: 0)
        XCTAssertEqual(
            first,
            NotchLayout.curlRadius + NotchLayout.padTop + NotchLayout.ringDiameter / 2,
            accuracy: 0.001
        )
        XCTAssertEqual(
            NotchLayout.ringCenter(index: 2) - NotchLayout.ringCenter(index: 1),
            NotchLayout.cellPitch(for: .right),
            accuracy: 0.001
        )
    }

    /// A row that carries a bar is taller than one that does not, so the hover
    /// region has to grow with it or the pointer falls out of the bottom of a
    /// card it is still over.
    func testCardGrowsWithBars() {
        let flat = NotchLayout.cardHeight(rowCount: 4)
        let one = NotchLayout.cardHeight(rowCount: 4, barCount: 1)
        let two = NotchLayout.cardHeight(rowCount: 4, barCount: 2)
        XCTAssertGreaterThan(one, flat)
        XCTAssertEqual(two - one, NotchLayout.labelToBar + NotchLayout.barHeight,
                       accuracy: 0.001)
    }

    /// The caption rides on the title row, so it costs the card no height of
    /// its own. That is what lets the height be budgeted rather than measured —
    /// a caption on a line of its own could wrap, and the measurement of that
    /// wrapping disagreed with what SwiftUI actually drew.
    func testTheCaptionCostsNoHeightOfItsOwn() {
        XCTAssertEqual(NotchLayout.cardHeight(rowCount: 0),
                       2 * NotchLayout.cardPadding
                       + max(NotchLayout.glyphSize, NotchLayout.cardTitleLineHeight),
                       accuracy: 0.001)
    }

    /// The hero is the tallest single thing on a card, and it has to be
    /// budgeted for or the answer is what gets clipped.
    func testTheHeroIsBudgetedFor() {
        let plain = NotchLayout.cardHeight(rowCount: 3)
        let withHero = NotchLayout.cardHeight(rowCount: 3, hasHero: true)
        let withBar = NotchLayout.cardHeight(rowCount: 3, hasHero: true, hasHeroBar: true)
        XCTAssertGreaterThan(withHero - plain, NotchLayout.heroLineHeight)
        XCTAssertEqual(withBar - withHero,
                       NotchLayout.heroBarGap + NotchLayout.heroBarHeight, accuracy: 0.001)
    }

    /// Every cell's tooltip has to fit inside the panel, or the card would be
    /// clipped for the first and last providers.
    func testTooltipFitsThePanelForEveryCell() {
        let cells = 3
        let cardHalf = NotchLayout.cardHeight(rowCount: 2) / 2
        let panelHeight = NotchLayout.shapeLength(cellCount: cells)
            + 2 * NotchLayout.slack(for: .right)
        for index in 0..<cells {
            let centre = NotchLayout.slack(for: .right) + NotchLayout.ringCenter(index: index)
            XCTAssertGreaterThanOrEqual(centre - cardHalf, 0)
            XCTAssertLessThanOrEqual(centre + cardHalf, panelHeight)
        }
    }
}

/// The panel has to be sized for the provider list that caused the change, not
/// the one the model still holds.
///
/// `@Published` notifies subscribers in `willSet`, so a sink that reacts to
/// `rings` changing and then reads `model.rings` back sees the *previous*
/// array. That is how the panel ended up sized for zero cells while one was on
/// screen — and a panel too short for its shape clips the bottom flare, which is
/// visible as the notch looking cut off instead of curving into the bezel.
@MainActor
final class PanelSizingTests: XCTestCase {
    func testPanelGrowsWithTheProviderCount() {
        let model = NotchViewModel()
        let empty = model.panelSize(cellCount: 0).height
        let one = model.panelSize(cellCount: 1).height
        let two = model.panelSize(cellCount: 2).height
        XCTAssertGreaterThan(one, empty)
        XCTAssertGreaterThan(two, one)
    }

    /// Sizing must not depend on what `rings` happens to hold right now.
    func testSizingIgnoresTheModelsCurrentList() {
        let model = NotchViewModel()
        XCTAssertTrue(model.rings.isEmpty)
        XCTAssertEqual(
            model.panelSize(cellCount: 1).height,
            model.shapeLength(cellCount: 1) + 2 * NotchLayout.slack(for: .right),
            accuracy: 0.001
        )
    }

    /// Whatever the count, the panel always has room for the whole shape —
    /// flares included — or the ends get cut off.
    func testThePanelAlwaysFitsTheWholeShape() {
        let model = NotchViewModel()
        for count in 0...5 {
            let panel = model.panelSize(cellCount: count).height
            let shape = model.shapeLength(cellCount: count)
            XCTAssertGreaterThanOrEqual(panel, shape, "\(count) cells: panel \(panel) < shape \(shape)")
        }
    }
}

/// The notch folds away to a pill so it stops being in the way, and unfolds on
/// contact. These pin the geometry that makes that bearable to live with.
@MainActor
final class FoldedNotchTests: XCTestCase {
    private func model(cells: Int) -> NotchViewModel {
        let model = NotchViewModel()
        model.rings = (0..<cells).map {
            TestRing.make($0, rows: 0)
        }
        return model
    }

    func testFoldedIsFarSmallerThanOpen() {
        let m = model(cells: 3)
        m.isExpanded = false
        let folded = m.notchSize
        m.isExpanded = true
        let open = m.notchSize
        XCTAssertLessThan(folded.width, open.width / 2)
        XCTAssertLessThan(folded.height, open.height / 2)
    }

    /// Both states share a centre line, so folding does not slide the notch up
    /// the screen as it shrinks — it contracts in place.
    func testFoldingKeepsTheCentreLine() {
        let m = model(cells: 3)
        m.isExpanded = true
        let openCentre = m.notchLeadingInset + m.notchSize.height / 2
        m.isExpanded = false
        let foldedCentre = m.notchLeadingInset + m.notchSize.height / 2
        XCTAssertEqual(openCentre, foldedCentre, accuracy: 0.001)
    }

    /// The panel never resizes for the fold: animating a window frame is jerky,
    /// and the reserved space is transparent anyway.
    func testThePanelIsTheSameSizeEitherWay() {
        let m = model(cells: 3)
        m.isExpanded = true
        let open = m.panelSize
        m.isExpanded = false
        XCTAssertEqual(open, m.panelSize)
    }

    /// A 10pt target on a screen edge is fiddly, so the region that wakes it is
    /// deliberately bigger than the pill it surrounds.
    func testTheWakeRegionIsLargerThanThePill() {
        XCTAssertGreaterThan(NotchLayout.pillHotZone, NotchLayout.pillWidth)
    }
}

/// Motion is a vocabulary, not a pile of magic numbers.
final class NotchMotionTests: XCTestCase {
    func testTheStaggerIsBounded() {
        XCTAssertEqual(NotchMotion.stagger(index: 0), NotchMotion.contents.delay(0))
        XCTAssertEqual(NotchMotion.stagger(index: 99), NotchMotion.contents.delay(0.18))
    }

    /// Reduce Motion means no animation at all, not a faster one.
    func testReduceMotionRemovesTheAnimation() {
        XCTAssertNil(NotchMotion.respectingReduceMotion(NotchMotion.unfold, true))
        XCTAssertNotNil(NotchMotion.respectingReduceMotion(NotchMotion.unfold, false))
    }

    /// The stagger is capped, so a long provider list never feels sluggish.
}

/// The shape has to stay a notch at every size it is drawn at — including the
/// pill, which is narrower than the flare radius it was designed around.
final class SideNotchShapeTests: XCTestCase {
    private func bounds(width: CGFloat, height: CGFloat) -> CGRect {
        SideNotchShape().path(in: CGRect(x: 0, y: 0, width: width, height: height)).boundingRect
    }

    /// The bug: clamping the corner by `width - curl` collapsed it to zero as
    /// soon as the flare was as wide as the body, so the folded pill came out
    /// with square corners.
    func testTheFoldedPillKeepsItsCorners() {
        let width = NotchLayout.pillWidth
        let path = SideNotchShape().path(
            in: CGRect(x: 0, y: 0, width: width, height: NotchLayout.pillHeight)
        )
        // A square-cornered pill touches its own top-left corner; a rounded one
        // never does.
        XCTAssertFalse(path.contains(CGPoint(x: 0.5, y: 0.5)),
                       "the pill's top-left corner is square")
        XCTAssertFalse(path.contains(CGPoint(x: 0.5, y: NotchLayout.pillHeight - 0.5)),
                       "the pill's bottom-left corner is square")
    }

    /// Fixing the pill must not reshape the notch the design frame was measured
    /// from: at full width the flare is wider than half the body and must stay so.
    func testTheOpenNotchIsUnchanged() {
        let width = NotchLayout.bodyDepth(for: .right)
        let path = SideNotchShape().path(in: CGRect(x: 0, y: 0, width: width, height: 400))
        XCTAssertEqual(path.boundingRect.width, width, accuracy: 0.5)
        XCTAssertEqual(path.boundingRect.height, 400, accuracy: 0.5)

        // The flare: near the top the shape is a sliver hugging the edge, and by
        // mid-height it is the full body. Sampled rather than probed at a single
        // point — a point 1pt down sits in a flare only hundredths of a point
        // wide, which is a fact about arcs, not about the shape being wrong.
        func filled(atY y: CGFloat) -> CGFloat {
            let hits = stride(from: CGFloat(0.25), to: width, by: 0.25)
                .filter { path.contains(CGPoint(x: $0, y: y)) }
            return hits.isEmpty ? 0 : width - hits.min()!
        }
        XCTAssertLessThan(filled(atY: 4), width / 3, "no flare at the top")
        XCTAssertEqual(filled(atY: 200), width, accuracy: 1, "not full width in the body")
        XCTAssertLessThan(filled(atY: 396), width / 3, "no flare at the bottom")
    }

    /// It is drawn at every size in between while folding, so none of them may
    /// produce a degenerate path.
    func testEveryIntermediateSizeIsDrawable() {
        for step in 0...20 {
            let t = CGFloat(step) / 20
            let w = NotchLayout.pillWidth + (NotchLayout.bodyDepth(for: .right) - NotchLayout.pillWidth) * t
            let h = NotchLayout.pillHeight + (400 - NotchLayout.pillHeight) * t
            let box = bounds(width: w, height: h)
            XCTAssertFalse(box.isEmpty, "degenerate path at \(w) x \(h)")
            XCTAssertEqual(box.width, w, accuracy: 1)
        }
    }
}

/// The tooltip resizes when you move between providers, because they do not all
/// report the same number of windows. Its height is computed rather than left to
/// SwiftUI so the hover region matches — and these pin that it really does vary.
final class TooltipResizeTests: XCTestCase {
    func testHeightVariesWithTheNumberOfRows() {
        XCTAssertGreaterThan(NotchLayout.cardHeight(rowCount: 2),
                             NotchLayout.cardHeight(rowCount: 1))
    }

    /// A vendor ring's card carries two standing rows and no models; a primary
    /// with a full model table carries six rows, three of them barred. That
    /// spread is the exact case where unclipped contents used to hang outside a
    /// shorter background while the height was still animating.
    func testTheExtremesDifferEnoughToBeVisible() {
        let smallest = NotchLayout.cardHeight(rowCount: 2)
        let largest = NotchLayout.cardHeight(rowCount: NotchLayout.maxRowCount,
                                             barCount: NotchLayout.maxBarCount)
        XCTAssertGreaterThan(largest - smallest, 40,
                             "the resize is big enough that overflow would show")
    }

    func testARowlessCardStillHasARealHeight() {
        XCTAssertGreaterThan(NotchLayout.cardHeight(rowCount: 0), NotchLayout.cardPadding * 2)
    }

    /// The reserved maximum has to actually cover the worst card the builder
    /// can produce, or the panel is too short for its own contents.
    func testTheReservedMaximumCoversTheFullestCard() {
        XCTAssertGreaterThanOrEqual(
            NotchLayout.defaultMaxCardHeight,
            NotchLayout.cardHeight(rowCount: NotchLayout.maxRowCount,
                                   barCount: NotchLayout.maxBarCount)
        )
    }
}

/// The tooltip is one object: a card with a tail welded to its side. What breaks
/// that illusion is the two halves moving on different schedules.
@MainActor
final class TooltipCohesionTests: XCTestCase {
    /// The card's drawn height and its hover region come from the same call, so
    /// what you can see and what you can reach cannot drift apart.
    func testDrawnHeightMatchesTheHoverRegion() {
        for rows in 0...NotchLayout.maxRowCount {
            let ring = TestRing.make(0, rows: rows, bars: min(rows, 2))
            XCTAssertEqual(
                NotchLayout.cardHeight(
                    rowCount: ring.rows.count,
                    barCount: ring.rows.filter { $0.fraction != nil }.count
                ),
                NotchLayout.cardHeight(rowCount: rows, barCount: min(rows, 2)),
                accuracy: 0.001
            )
        }
    }

    /// The tail is centred on the card's height, so a height that jumps takes
    /// the tail with it. Every step between two providers has to be a real
    /// number for that travel to be smooth.
    func testHeightIsContinuousAcrossProviderShapes() {
        let heights = (0...3).map { NotchLayout.cardHeight(rowCount: $0) }
        for height in heights {
            XCTAssertTrue(height.isFinite && height > 0)
        }
        XCTAssertEqual(Set(heights).count, heights.count, "each shape has its own height")
    }

    /// The tail never changes size, whatever the card is doing — it is a fixed
    /// piece of the silhouette, not something that scales with the contents.
    func testTheTailIsAFixedSize() {
        XCTAssertGreaterThan(NotchLayout.tailHeight, 0)
        XCTAssertGreaterThan(NotchLayout.tailLength, 0)
        XCTAssertLessThan(NotchLayout.tailHeight, NotchLayout.cardHeight(rowCount: 1),
                          "the tail must fit inside the shortest card it can point from")
    }
}

/// The rings are buttons — clicking one refetches that provider — so the cursor
/// should say so, and only there.
@MainActor
final class PointerStateTests: XCTestCase {
    func testACellShowsThePointingHand() {
        XCTAssertTrue(NotchWindowController.wantsPointingHand(isExpanded: true, cellIndex: 0))
        XCTAssertTrue(NotchWindowController.wantsPointingHand(isExpanded: true, cellIndex: 2))
    }

    /// The gap around the cells is not a button.
    func testTheRestOfTheNotchDoesNot() {
        XCTAssertFalse(NotchWindowController.wantsPointingHand(isExpanded: true, cellIndex: nil))
    }

    /// Folded, the pill is a handle you hover rather than a button you aim at,
    /// and a pointer that flashes on the way past is noise.
    func testTheFoldedPillDoesNot() {
        XCTAssertFalse(NotchWindowController.wantsPointingHand(isExpanded: false, cellIndex: 0))
        XCTAssertFalse(NotchWindowController.wantsPointingHand(isExpanded: false, cellIndex: nil))
    }
}

/// The settings orb sits in the corner the notch's bottom flare makes, and its
/// resting arc follows that curve rather than merely sitting near it.
@MainActor
final class SettingsOrbTests: XCTestCase {
    private func centre(_ count: Int) -> CGFloat {
        NotchLayout.orbCenterAlong(cellCount: count)
    }

    private func shapeBottom(_ count: Int) -> CGFloat {
        NotchLayout.shapeLength(cellCount: count)
    }

    /// The whole point: the orb shares the flare's centre of curvature, so the
    /// two arcs are concentric and the resting stroke parallels the edge. Centre
    /// it anywhere else — on the body's axis, say — and it stops following the
    /// contour, which is exactly what went wrong first time.
    func testItSharesTheFlaresCentreOfCurvature() {
        XCTAssertEqual(NotchLayout.orbInsetFromEdge, NotchLayout.curlRadius, accuracy: 0.001)
        for count in 1...4 {
            XCTAssertEqual(centre(count), shapeBottom(count), accuracy: 0.001,
                           "\(count): the orb's centre must be the flare's centre")
        }
    }

    /// Inside the flare, with a real gap — touching it would read as a smudge on
    /// the notch rather than as a separate control.
    func testTheArcSitsInsideTheFlareWithAGap() {
        XCTAssertLessThan(NotchLayout.orbArcRadius, NotchLayout.curlRadius)
        let gap = NotchLayout.curlRadius - NotchLayout.orbArcRadius
        XCTAssertGreaterThan(gap, NotchLayout.orbStroke / 2,
                             "the stroke would touch the flare")
    }

    /// The filled disc goes inside the arc, so hovering does not push past it.
    func testTheDiscFitsWithinTheArc() {
        XCTAssertLessThan(NotchLayout.orbDiameter / 2, NotchLayout.orbArcRadius)
    }

    /// The notch itself must not grow for it — the orb is not part of the shape.
    func testTheNotchDoesNotGrowForIt() {
        let cells = NotchLayout.cellExtent
        let body = NotchLayout.bodyLength(cellCount: 2)
        let bare = NotchLayout.padTop + 2 * cells + NotchLayout.cellSpacing + NotchLayout.padBottom
        XCTAssertEqual(body, bare, accuracy: 0.001)
    }

    /// The panel has to reserve room below the shape or the orb is clipped away.
    func testThePanelHasRoomBelowTheNotch() {
        let overhang = NotchLayout.orbArcRadius + NotchLayout.orbStroke
        XCTAssertLessThanOrEqual(overhang, NotchLayout.slack(for: .right))
    }

    /// Like the pill's, the region you can hit is larger than what is drawn.
    func testTheHitRegionIsLargerThanTheOrb() {
        XCTAssertGreaterThan(NotchLayout.orbHotZone, NotchLayout.orbDiameter)
    }
}
/// Antigravity's mark is flattened from its own SVG, so what is asserted is
/// that it survived flattening: one closed loop, inside the unit box, filling
/// it. The Gemini spark it replaced was generated, and its geometry could be
/// checked exactly; this one comes from artwork and can only be checked for
/// sanity.
final class VendorMarkTests: XCTestCase {
    private var loop: [CGPoint] { GlyphOutline.antigravity[0] }

    func testItIsOneClosedLoopInTheUnitBox() {
        XCTAssertEqual(GlyphOutline.antigravity.count, 1)
        XCTAssertGreaterThan(loop.count, 50, "the curves were not flattened into enough points")
        for p in loop {
            XCTAssertTrue((0...1).contains(p.x), "x outside the unit box: \(p.x)")
            XCTAssertTrue((0...1).contains(p.y), "y outside the unit box: \(p.y)")
        }
    }

    /// Normalisation should fill the box on its longer axis, or the mark would
    /// render smaller than every other glyph for no reason.
    func testItFillsTheBox() {
        let xs = loop.map(\.x), ys = loop.map(\.y)
        let span = max(xs.max()! - xs.min()!, ys.max()! - ys.min()!)
        XCTAssertEqual(span, 1, accuracy: 0.01)
    }

    /// The two vendors whose logos are traced rather than lettered.
    func testTheTracedVendorMarksResolve() {
        XCTAssertFalse(GlyphOutline.claude.isEmpty)
        XCTAssertFalse(GlyphOutline.openai.isEmpty)
    }

    /// Every other vendor falls back to initials, so each one needs a distinct,
    /// non-empty pair — two vendors sharing "M" would be unreadable at 17pt.
    func testEveryVendorHasDistinctInitials() {
        let lettered = Vendor.allCases.filter { $0 != .anthropic && $0 != .openai }
        let initials = lettered.map(\.initials)
        XCTAssertFalse(initials.contains(where: \.isEmpty))
        XCTAssertEqual(Set(initials).count, initials.count, "two vendors share a mark")
    }
}


/// The notch's own visibility. Its default matters more than the other two
/// settings here: get it wrong and a fresh install shows nothing at all, which
/// is indistinguishable from the app failing to start.
final class NotchVisibilityTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "NotchVisibilityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @MainActor
    func testItDefaultsToHoverRatherThanHidden() {
        XCTAssertEqual(Preferences(defaults: defaults()).notchVisibility, .onHover)
    }

    @MainActor
    func testTheChoiceSurvivesARestart() {
        let defaults = defaults()
        Preferences(defaults: defaults).notchVisibility = .alwaysShow
        XCTAssertEqual(Preferences(defaults: defaults).notchVisibility, .alwaysShow)
    }

    /// A value written by a future version, or corrupted, must not hide the
    /// notch — it falls back to the visible default.
    @MainActor
    func testAnUnknownStoredValueFallsBackToVisible() {
        let defaults = defaults()
        defaults.set("teleport", forKey: "notchVisibility")
        XCTAssertEqual(Preferences(defaults: defaults).notchVisibility, .onHover)
    }

    /// Hiding removes every other way back into the app, so the option itself
    /// has to say where the door is.
    func testHidingExplainsHowToGetBack() {
        XCTAssertTrue(NotchVisibility.hidden.explanation.contains("Applications"))
    }

    func testEveryModeIsOfferedAndNamed() {
        XCTAssertEqual(NotchVisibility.allCases.count, 3)
        for mode in NotchVisibility.allCases {
            XCTAssertFalse(mode.title.isEmpty)
            XCTAssertFalse(mode.explanation.isEmpty)
        }
    }
}

/// Renaming the app renames its defaults domain, so every setting moves to a
/// new empty one unless it is carried across.
final class RenameMigrationTests: XCTestCase {
    private func suite() -> (UserDefaults, String) {
        let name = "RenameMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (defaults, name)
    }

    /// A source domain of our own, so the tests never read the real one — the
    /// first version of this did exactly that, and copied live settings into a
    /// scratch suite.
    private func oldDomain(_ contents: [String: Any]) -> String {
        let name = "RenameMigrationTests.old.\(UUID().uuidString)"
        UserDefaults.standard.setPersistentDomain(contents, forName: name)
        return name
    }

    @MainActor
    func testItCarriesSettingsAcrossTheRename() {
        let (defaults, _) = suite()
        let old = oldDomain(["enabledVendors": ["openai"], "notchVisibility": "alwaysShow"])
        defer { UserDefaults.standard.removePersistentDomain(forName: old) }

        Preferences.migrateFromPreviousName(into: defaults, from: old)

        let preferences = Preferences(defaults: defaults)
        XCTAssertTrue(preferences.showsRing(for: .openai))
        XCTAssertEqual(preferences.notchVisibility, .alwaysShow)
    }

    /// The guard that matters: a domain already in use is never overwritten, or
    /// a later launch would undo whatever the user changed after the rename.
    @MainActor
    func testItLeavesAnAlreadyUsedDomainAlone() {
        let (defaults, _) = suite()
        _ = Preferences(defaults: defaults)          // stamps hasLaunchedBefore
        defaults.set(["google"], forKey: "enabledVendors")
        let old = oldDomain(["enabledVendors": ["openai"]])
        defer { UserDefaults.standard.removePersistentDomain(forName: old) }

        Preferences.migrateFromPreviousName(into: defaults, from: old)

        XCTAssertEqual(defaults.stringArray(forKey: "enabledVendors"), ["google"])
    }

    @MainActor
    func testMigratingWithNothingToMigrateIsHarmless() {
        let (defaults, _) = suite()
        Preferences.migrateFromPreviousName(into: defaults, from: "does.not.exist")
        XCTAssertTrue(Preferences(defaults: defaults).enabledVendors.isEmpty)
    }
}
/// A tooltip is centred on the cell it belongs to, so the first and last
/// providers throw half a card past the end of the stack. Both orientations
/// need room for it — a side edge was assumed exempt because the card sits
/// beside the stack, but it sits beside it *horizontally* while being centred
/// on it *vertically*, and the title was clipped off the top.
final class TooltipEndroomTests: XCTestCase {
    func testEveryEdgeLeavesRoomForHalfACard() {
        for edge in NotchEdge.allCases {
            let needed = (edge.isVertical ? NotchLayout.defaultMaxCardHeight
                                          : NotchLayout.cardWidth) / 2
            XCTAssertGreaterThanOrEqual(
                NotchLayout.slack(for: edge), needed,
                "\(edge): the first provider's tooltip is clipped by the panel"
            )
        }
    }

    /// The dimension that crosses the ends differs by orientation — height
    /// along a side edge, width along a horizontal one. Using the wrong one is
    /// what made this look sufficient.
    func testTheRelevantDimensionDiffersByOrientation() {
        XCTAssertGreaterThanOrEqual(NotchLayout.slack(for: .right),
                                    NotchLayout.defaultMaxCardHeight / 2)
        XCTAssertGreaterThanOrEqual(NotchLayout.slack(for: .top),
                                    NotchLayout.cardWidth / 2)
    }
}
