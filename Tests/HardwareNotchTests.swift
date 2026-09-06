import SwiftUI
import XCTest
@testable import Codenotch

/// A MacBook's own notch, as this machine reports it.
private let realNotch = HardwareNotch(width: 220, height: 38)

private struct FakeScreen: ScreenDescribing {
    var frameValue: CGRect
    var visibleFrameValue: CGRect
    var hardwareNotch: HardwareNotch?
}

private let notched = FakeScreen(
    frameValue: CGRect(x: 0, y: 0, width: 1800, height: 1169),
    visibleFrameValue: CGRect(x: 0, y: 59, width: 1800, height: 1071),
    hardwareNotch: realNotch
)

private let plain = FakeScreen(
    frameValue: CGRect(x: 0, y: 0, width: 1800, height: 1169),
    visibleFrameValue: CGRect(x: 0, y: 0, width: 1800, height: 1144),
    hardwareNotch: nil
)

/// On a Mac that has a notch of its own, a top-edge Codenotch runs up to meet
/// it so the two read as one shape rather than as a bar parked underneath.
final class HardwareNotchGeometryTests: XCTestCase {
    private let size = CGSize(width: 700, height: 200)

    func testATopNotchRunsUpToTheRealTopToMeetTheHardware() {
        let frame = NotchGeometry.panelFrame(for: notched, panelSize: size, edge: .top)
        XCTAssertEqual(frame.maxY, notched.frameValue.maxY, accuracy: 0.001,
                       "it stopped below the menu bar instead of meeting the notch")
    }

    /// With nothing to merge with, covering the menu bar is pure cost.
    func testWithoutOneItStillSitsBelowTheMenuBar() {
        let frame = NotchGeometry.panelFrame(for: plain, panelSize: size, edge: .top)
        XCTAssertEqual(frame.maxY, plain.visibleFrameValue.maxY, accuracy: 0.001)
    }

    /// Only the top edge merges. The others have nothing to merge with, and a
    /// bottom notch still has a Dock to keep clear of.
    func testTheOtherEdgesAreUnaffectedByIt() {
        XCTAssertEqual(
            NotchGeometry.panelFrame(for: notched, panelSize: size, edge: .bottom).minY,
            notched.visibleFrameValue.minY, accuracy: 0.001
        )
        XCTAssertEqual(
            NotchGeometry.panelFrame(for: notched, panelSize: CGSize(width: 300, height: 700), edge: .right).maxX,
            notched.visibleFrameValue.maxX, accuracy: 0.001
        )
    }

    func testItReadsTheNotchFromTheAreasEitherSideOfIt() {
        XCTAssertEqual(realNotch.width, 220, accuracy: 0.001)
        XCTAssertEqual(realNotch.height, 38, accuracy: 0.001)
    }
}

/// Merging costs two things, and forgetting either one is what makes it look
/// broken rather than joined.
@MainActor
final class MergedTopNotchTests: XCTestCase {
    private func model(cells: Int, screen: ScreenDescribing = notched,
                       edge: NotchEdge = .top) -> NotchViewModel {
        let model = NotchViewModel()
        model.edge = edge
        model.isExpanded = true
        model.snapshots = (0..<cells).map { index in
            ProviderSnapshot(id: "p\(index)", displayName: "P", glyph: .claude,
                             fidelity: .official, status: .ok, windows: [])
        }
        model.adopt(screen: screen)
        return model
    }

    // MARK: - The band behind the hardware

    /// The first cost: the top of the shape is behind a *hole in the screen*.
    /// Anything drawn there is not dim or clipped, it is simply not there.
    func testNothingIsDrawnInsideTheHardwareNotchesOwnBand() {
        let model = model(cells: 4)
        XCTAssertGreaterThanOrEqual(
            model.contentInset, realNotch.height,
            "the rings would be drawn behind the hole in the display"
        )
    }

    /// The shape gets deeper by that band plus the gap below it, so the
    /// readings sit where they always did relative to the black around them.
    func testTheShapeGrowsByTheBandItHasToClear() {
        let merged = model(cells: 4).notchDepth
        let plainTop = model(cells: 4, screen: plain).notchDepth
        XCTAssertEqual(merged - plainTop, realNotch.height, accuracy: 0.001)
    }

    /// Folded away, it *is* the hardware notch — same width, same height.
    ///
    /// The resting pill is the wrong object here. It hangs below the hardware
    /// as a separate little tab, which is exactly the seam the whole placement
    /// exists to remove. Matching the notch instead means the app shows nothing
    /// at all at rest, and hovering makes the notch itself grow.
    func testFoldedAwayItIsExactlyTheHardwareNotch() {
        let m = model(cells: 4)
        m.isExpanded = false
        XCTAssertEqual(m.notchLength, realNotch.width, accuracy: 0.001,
                       "the resting shape is not the notch's width")
        XCTAssertEqual(m.notchDepth, realNotch.height, accuracy: 0.001,
                       "the resting shape is not the notch's height")
    }

    /// Which means nothing of it hangs below the hardware to be seen.
    func testNothingOfItShowsBelowTheHardwareAtRest() {
        let m = model(cells: 4)
        m.isExpanded = false
        XCTAssertLessThanOrEqual(m.notchDepth, realNotch.height,
                                 "part of the resting shape hangs below the hardware")
    }

    /// Opening it grows the notch rather than replacing it.
    func testOpeningGrowsItOnBothAxes() {
        let m = model(cells: 4)
        m.isExpanded = false
        let (restLength, restDepth) = (m.notchLength, m.notchDepth)
        m.isExpanded = true
        XCTAssertGreaterThan(m.notchLength, restLength)
        XCTAssertGreaterThan(m.notchDepth, restDepth)
    }

    /// A screen without one keeps the pill it always had.
    func testWithoutAHardwareNotchItStillFoldsToItsPill() {
        let m = model(cells: 4, screen: plain)
        m.isExpanded = false
        XCTAssertEqual(m.notchLength, NotchLayout.pillHeight, accuracy: 0.001)
        XCTAssertEqual(m.notchDepth, NotchLayout.pillWidth, accuracy: 0.001)
    }

    func testAScreenWithoutOneInsetsNothing() {
        XCTAssertEqual(model(cells: 4, screen: plain).contentInset, 0, accuracy: 0.001)
        for edge in [NotchEdge.right, .left, .bottom] {
            XCTAssertEqual(model(cells: 4, edge: edge).contentInset, 0, accuracy: 0.001,
                           "\(edge) has no hardware notch to clear")
        }
    }

    // MARK: - Being at least as wide as the thing it joins

    /// The second cost: a single ring makes a bar about 194pt across, and this
    /// Mac's notch is 220. Left alone the hardware would be *wider* than the
    /// shape that is supposed to be it, sticking out either side.
    ///
    /// Measured on the drawn shape rather than on the body: with the flares
    /// gone, the shape's whole length is what meets the screen's top edge, and
    /// that is what has to clear the hardware.
    func testTheDrawnBarIsNeverNarrowerThanTheHardwareNotch() {
        for count in 1...5 {
            XCTAssertGreaterThanOrEqual(
                model(cells: count).shapeLength, realNotch.width,
                "\(count) cells: the hardware notch is wider than the shape replacing it"
            )
        }
    }

    /// Widening is done evenly, so the readings stay in the middle of the bar.
    func testTheStackStaysCentredWhileTheBodyIsWidened() {
        for count in 1...5 {
            let model = model(cells: count)
            let first = model.ringCenter(index: 0)
            let last = model.ringCenter(index: count - 1)
            XCTAssertEqual(first, model.shapeLength - last, accuracy: 0.5,
                           "\(count) cells: widening pushed the stack off centre")
        }
    }

    /// Once the stack is wide enough on its own, nothing is added to it.
    ///
    /// Compared against zero rather than against an unmerged notch: the two are
    /// no longer the same length even with no widening, because a flush bar
    /// reserves only the small frame corner at its ends where a flared one
    /// reserves a whole `curlRadius`.
    func testAWideStackIsLeftAlone() {
        XCTAssertEqual(model(cells: 5).endSpread, 0, accuracy: 0.001)
        XCTAssertEqual(model(cells: 4).endSpread, 0, accuracy: 0.001)
    }

    func testASideEdgeIsNeverWidenedForIt() {
        for edge in [NotchEdge.right, .left, .bottom] {
            XCTAssertEqual(model(cells: 1, edge: edge).endSpread, 0, accuracy: 0.001, "\(edge)")
        }
    }
}

/// Where the merged shape actually puts its edges.
@MainActor
final class MergedShapeTests: XCTestCase {
    private let inset = realNotch.height

    private func model(cells: Int = 4) -> NotchViewModel {
        let model = NotchViewModel()
        model.edge = .top
        model.isExpanded = true
        model.snapshots = (0..<cells).map { index in
            ProviderSnapshot(id: "p\(index)", displayName: "P", glyph: .claude,
                             fidelity: .official, status: .ok, windows: [])
        }
        model.adopt(screen: notched)
        return model
    }

    /// The stretch that runs up behind the hardware is a straight extension of
    /// the bar, not part of its flare.
    ///
    /// Left as an ordinary deeper shape, the flares — which live in the first
    /// `curlRadius` from the bezel, and this Mac's notch is almost exactly that
    /// tall — would be drawn entirely inside the hole. The bar would emerge
    /// from the hardware with square corners, and the settings orb, which is
    /// concentric with the flare, would be invisible with it.
    /// **The bar is shaped like the Mac's own notch, only bigger.**
    ///
    /// Straight sides meeting the bezel square, two rounded corners at the
    /// bottom, nothing else. The flares are what make this shape read as
    /// growing out of an edge, and that is exactly wrong here: the hardware
    /// notch does not taper. Match it and the display's own notch stops being a
    /// separate object — it simply looks wider and deeper.
    func testItMeetsTheBezelSquareAcrossItsWholeWidth() {
        let m = model()
        let size = m.notchSize
        guard let atBezel = span(of: m, at: 0.3) else { return XCTFail("nothing at the bezel") }

        XCTAssertEqual(atBezel.lowerBound, 0, accuracy: 3,
                       "the bar does not reach the top of the screen")
        XCTAssertEqual(atBezel.upperBound, size.width - 1, accuracy: 3,
                       "the bar does not reach the top of the screen")
    }

    /// Straight-sided between its two corner details: the small one into the
    /// screen's frame at the top, and its own rounding at the bottom. Anything
    /// varying in between would read as two shapes stacked.
    func testItKeepsTheSameWidthBetweenItsCorners() {
        let m = model()
        guard let reference = span(of: m, at: NotchLayout.bezelFillet + 2) else {
            return XCTFail("nothing below the frame corner")
        }
        for across in stride(from: NotchLayout.bezelFillet + 2,
                             to: m.notchDepth - NotchLayout.cornerRadius, by: 4) {
            guard let band = span(of: m, at: across) else {
                return XCTFail("the bar has a gap at depth \(across)")
            }
            XCTAssertEqual(band.lowerBound, reference.lowerBound, accuracy: 2,
                           "the bar changes width at depth \(across)")
            XCTAssertEqual(band.upperBound, reference.upperBound, accuracy: 2,
                           "the bar changes width at depth \(across)")
        }
    }

    /// The corner into the frame is a detail, not a taper: what it takes off
    /// the bar's width is a small fraction of it.
    func testTheFrameCornerBarelyNarrowsTheBar() {
        let m = model()
        guard let atFrame = span(of: m, at: 0.5),
              let below = span(of: m, at: NotchLayout.bezelFillet + 2) else {
            return XCTFail("no shape to measure")
        }
        let lost = (below.lowerBound - atFrame.lowerBound)
            + (atFrame.upperBound - below.upperBound)
        XCTAssertLessThan(lost / (atFrame.upperBound - atFrame.lowerBound), 0.12,
                          "the corner into the frame is tapering the bar")
    }

    /// And it is rounded off at the bottom, the way the hardware notch is.
    func testItsBottomCornersAreRounded() {
        let m = model()
        guard let atBezel = span(of: m, at: 1),
              let atFoot = span(of: m, at: m.notchDepth - 2) else {
            return XCTFail("no shape to measure")
        }
        let pulledIn = (atFoot.lowerBound - atBezel.lowerBound)
        XCTAssertGreaterThan(pulledIn, NotchLayout.cornerRadius / 2,
                             "the bar has square corners at the bottom")
        XCTAssertEqual(atFoot.lowerBound - atBezel.lowerBound,
                       atBezel.upperBound - atFoot.upperBound, accuracy: 2,
                       "the bottom corners do not match each other")
    }

    /// Sampled rather than probed: a single point can land exactly on a
    /// construction line, where `contains` is a coin toss.
    private func span(of m: NotchViewModel, at across: CGFloat) -> ClosedRange<CGFloat>? {
        let size = m.notchSize
        let place = NotchPlacement(edge: .top, panelSize: size)
        let path = SideNotchShape(edge: .top, joining: m.joinedNotch)
            .path(in: CGRect(origin: .zero, size: size))
        let hits = stride(from: CGFloat(0), to: size.width, by: 1)
            .filter { path.contains(place.point(along: $0, across: across)) }
        guard let first = hits.first, let last = hits.last else { return nil }
        return first...last
    }

    /// Every other edge keeps the flares the design frame drew.
    func testTheOtherEdgesKeepTheirFlares() {
        let flared = SideNotchShape(edge: .top, joining: nil)
            .path(in: CGRect(x: 0, y: 0, width: 400, height: 140))
        let place = NotchPlacement(edge: .top, panelSize: CGSize(width: 400, height: 140))
        XCTAssertFalse(
            flared.contains(place.point(along: 2, across: NotchLayout.curlRadius + 4)),
            "the flare is missing from an ordinary notch"
        )
    }

    /// Wherever the orb ends up, all of it has to be below the hardware — the
    /// part of it inside that band is not dimmed, it is off the display.
    func testTheWholeOrbSitsBelowTheHardwareNotch() {
        let m = model()
        let radius = NotchLayout.orbArcRadius
        XCTAssertGreaterThan(m.orbInset - radius - NotchLayout.orbStroke / 2, realNotch.height,
                             "part of the resting arc is inside the hole")
    }

    /// And the card hangs off the inner face of a shape that is now deeper.
    func testTheTooltipClearsTheDeeperShape() {
        let m = model()
        XCTAssertEqual(
            m.tooltipInset, m.contentInset + NotchLayout.bodyDepth(for: .top) + NotchLayout.tailGap,
            accuracy: 0.001
        )
    }
}

/// With the flares gone there is no concave corner for the settings orb to
/// tuck into, and left where it was it becomes a dot on the bar's edge.
///
/// Same idea, turned inside out: it hugs the bar's own rounded corner from
/// *outside* instead of a flare from inside. Hugging a corner the other way
/// round is the same relationship through half a circle, which is all the
/// trim has to do.
@MainActor
final class OrbOnAFlushBarTests: XCTestCase {
    private func model(flush: Bool) -> NotchViewModel {
        let model = NotchViewModel()
        model.edge = .top
        model.isExpanded = true
        model.snapshots = (0..<4).map { index in
            ProviderSnapshot(id: "p\(index)", displayName: "P", glyph: .claude,
                             fidelity: .official, status: .ok, windows: [])
        }
        model.adopt(screen: flush ? notched : plain)
        return model
    }

    /// **The orb hangs off the bar, not inside it.**
    ///
    /// It normally nestles into the pocket the far flare cuts out of the notch —
    /// that is why it is concentric with the flare, one gap inside it. A flush
    /// bar has no pocket: its far corner is convex, so an orb centred on that
    /// corner sits *within* the black, which is where the gear was appearing.
    func testTheWholeOrbIsOutsideTheBar() {
        let m = model(flush: true)
        XCTAssertGreaterThan(m.orbAlong, m.shapeLength,
                             "the orb is not past the end of the bar")
        XCTAssertGreaterThan(m.orbInset, m.notchDepth,
                             "the orb is not below the foot of the bar")
    }

    /// Clear of the corner it hangs from by the same gap the flare version uses,
    /// so the disc never overlaps the bar it belongs to.
    func testTheDiscClearsTheCornerByTheUsualGap() {
        let m = model(flush: true)
        let corner = CGPoint(x: m.cornerCentreAlong,
                             y: m.notchDepth - m.drawnCornerRadius)
        let reach = hypot(m.orbAlong - corner.x, m.orbInset - corner.y)
        XCTAssertEqual(
            reach - m.drawnCornerRadius - NotchLayout.orbDiameter / 2,
            NotchLayout.orbGap, accuracy: 0.5,
            "the settings disc is not sitting clear of the bar's corner"
        )
    }

    /// It hangs diagonally, so it reads as belonging to the corner rather than
    /// to one edge or the other.
    func testItHangsOffTheCornerDiagonally() {
        let m = model(flush: true)
        let past = m.orbAlong - m.cornerCentreAlong
        let below = m.orbInset - (m.notchDepth - m.drawnCornerRadius)
        XCTAssertEqual(past, below, accuracy: 0.001, "the orb is off to one side")
    }

    /// And traces it one gap outside, which is the same clearance the flared
    /// version keeps from its flare.
    func testTheArcTracesTheCornerByTheUsualGap() {
        let m = model(flush: true)
        XCTAssertEqual(m.orbArcRadius - m.drawnCornerRadius,
                       NotchLayout.orbGap, accuracy: 0.001)
    }

    /// Which puts them far enough apart that one hot zone cannot cover both —
    /// the arc is what you see, the button is what you are reaching for, and
    /// the handle has to answer to either.
    func testTheArcAndTheButtonNeedSeparateHitZones() {
        let m = model(flush: true)
        let apart = hypot(m.orbArcOffset.width, m.orbArcOffset.height)
        XCTAssertGreaterThan(apart, NotchLayout.orbHotZone / 2,
                             "one zone would do; the union is unnecessary")
    }

    /// Inside a flare's pocket the two are the same object, as they always were.
    func testTheyAreConcentricWhenThereIsAFlare() {
        let m = model(flush: false)
        XCTAssertEqual(m.orbArcOffset.width, 0, accuracy: 0.001)
        XCTAssertEqual(m.orbArcOffset.height, 0, accuracy: 0.001)
    }

    /// The arc faces away from the bar on both axes — out past its end, and
    /// down past its foot. That is what makes it read as hugging the corner.
    func testTheArcFacesAwayFromTheBar() {
        let range = SettingsOrb.restingTrim(for: .top, convex: true)
        let mid = Double((range.lowerBound + range.upperBound) / 2) * 2 * .pi
        let direction = CGPoint(x: cos(mid), y: sin(mid))
        // +along is along the bar; +across is deeper into it, away from the bezel.
        XCTAssertGreaterThan(direction.x * NotchEdge.top.alongDirection.x
                             + direction.y * NotchEdge.top.alongDirection.y, 0.5,
                             "the arc does not reach past the end of the bar")
        XCTAssertGreaterThan(direction.x * -NotchEdge.top.outward.x
                             + direction.y * -NotchEdge.top.outward.y, 0.5,
                             "the arc does not reach past the foot of the bar")
    }

    /// Which is the concave arrangement through half a circle, on every edge.
    func testHuggingFromOutsideIsTheSameRelationshipTurnedAround() {
        for edge in NotchEdge.allCases {
            let concave = SettingsOrb.restingTrim(for: edge).lowerBound
            let convex = SettingsOrb.restingTrim(for: edge, convex: true).lowerBound
            let turned = (concave + 0.5).truncatingRemainder(dividingBy: 1)
            XCTAssertEqual(convex, turned, accuracy: 0.0001, "\(edge)")
        }
    }

    /// Nothing about the ordinary notch moves.
    func testAnUnmergedNotchKeepsTheOrbWhereItWas() {
        let m = model(flush: false)
        XCTAssertEqual(m.orbAlong, m.shapeLength, accuracy: 0.001)
        XCTAssertEqual(m.orbInset, NotchLayout.orbInsetFromEdge, accuracy: 0.001)
    }
}

/// Nothing of the readings may fall inside the hardware's band, and the shape
/// should meet the screen's frame with a corner rather than a raw edge.
@MainActor
final class HardwareClearanceTests: XCTestCase {
    private func model(cells: Int = 4) -> NotchViewModel {
        let model = NotchViewModel()
        model.edge = .top
        model.isExpanded = true
        model.snapshots = (0..<cells).map { index in
            ProviderSnapshot(id: "p\(index)", displayName: "P", glyph: .claude,
                             fidelity: .official, status: .ok,
                             windows: [LimitWindow(id: "w", label: "S", usedFraction: 0.4)],
                             headlineID: "w")
        }
        model.adopt(screen: notched)
        return model
    }

    /// The bug this pins: the cells were *centred* in a shape that had been made
    /// deeper, rather than pushed past the band that made it deeper. They ended
    /// up 19pt from the top instead of 38, so the top of every ring was inside
    /// the hole — which is what "the notch is blocking the rings" looks like.
    func testTheHardwaresBandHoldsNothingButBlack() {
        let m = model()
        let size = m.notchSize
        let renderer = ImageRenderer(
            content: NotchRootView(model: m).frame(width: m.panelSize.width,
                                                   height: m.panelSize.height)
        )
        renderer.scale = 1
        guard let image = renderer.cgImage, let rep = NSBitmapImageRep(cgImage: image).cgImage
        else { return XCTFail("nothing rendered") }
        let bitmap = NSBitmapImageRep(cgImage: rep)

        let place = NotchPlacement(edge: .top, panelSize: m.panelSize)
        for across in stride(from: CGFloat(1), to: realNotch.height, by: 2) {
            for along in stride(from: CGFloat(0), to: size.width, by: 3) {
                let point = place.point(along: m.slack + along, across: across)
                guard let colour = bitmap.colorAt(x: Int(point.x), y: Int(point.y)),
                      colour.alphaComponent > 0.5 else { continue }
                // Black is the notch itself. Anything else is a ring, a track
                // or a label drawn where the display has a hole in it.
                XCTAssertLessThan(
                    colour.brightnessComponent, 0.05,
                    "something is drawn inside the hardware notch at (\(along), \(across))"
                )
            }
        }
    }

    /// **The hardware's bottom edge is the bezel, as far as the readings are
    /// concerned.** So a ring sits exactly the frame's own margin from it —
    /// the same distance it sits from the screen edge on every other placement.
    ///
    /// Anything on top of that is padding twice: an earlier version added a
    /// deliberate gap as well, and the readings ended up adrift of the notch
    /// they are supposed to belong to.
    func testTheRingsSitTheFramesOwnMarginFromTheHardware() {
        let m = model()
        let ringTop = m.contentInset + NotchLayout.ringMargin(for: .top)
        XCTAssertEqual(ringTop - realNotch.height, NotchLayout.ringMargin(for: .top),
                       accuracy: 0.001,
                       "the readings are padded away from the hardware twice over")
    }

    /// Which is the same margin the ring has from the bezel anywhere else.
    func testItIsTheSameMarginEveryOtherPlacementUses() {
        XCTAssertEqual(NotchLayout.ringMargin(for: .top),
                       NotchLayout.ringMargin(for: .right), accuracy: 0.001)
    }

    /// The shape meets the screen's frame with a small inverse corner, the way
    /// the hardware notch is moulded into the bezel rather than cut out of it.
    /// Small: enough to round the join, not enough to taper the bar.
    func testItMeetsTheScreensFrameWithACorner() {
        let m = model()
        let size = m.notchSize
        let place = NotchPlacement(edge: .top, panelSize: size)
        let path = SideNotchShape(edge: .top, joining: realNotch).path(in: CGRect(origin: .zero, size: size))

        func span(at across: CGFloat) -> ClosedRange<CGFloat>? {
            let hits = stride(from: CGFloat(0), to: size.width, by: 1)
                .filter { path.contains(place.point(along: $0, across: across)) }
            guard let first = hits.first, let last = hits.last else { return nil }
            return first...last
        }
        guard let atFrame = span(at: 0.5),
              let belowIt = span(at: NotchLayout.bezelFillet + 2) else {
            return XCTFail("no shape to measure")
        }
        XCTAssertEqual(atFrame.lowerBound, 0, accuracy: 3,
                       "the shape does not reach the screen's frame")
        let pulledIn = belowIt.lowerBound - atFrame.lowerBound
        XCTAssertEqual(pulledIn, NotchLayout.bezelFillet, accuracy: 2,
                       "the corner into the frame is missing")
        XCTAssertLessThan(NotchLayout.bezelFillet, NotchLayout.cornerRadius,
                          "the corner is big enough to taper the bar")
    }
}

/// The bar should reserve no more room at its ends than it actually draws there.
@MainActor
final class BarEndMarginTests: XCTestCase {
    private func model(cells: Int = 4, screen: ScreenDescribing = notched) -> NotchViewModel {
        let model = NotchViewModel()
        model.edge = .top
        model.isExpanded = true
        model.snapshots = (0..<cells).map { index in
            ProviderSnapshot(id: "p\(index)", displayName: "P", glyph: .claude,
                             fidelity: .official, status: .ok, windows: [])
        }
        model.adopt(screen: screen)
        return model
    }

    /// The bug: `shapeLength` reserves a full `curlRadius` at each end for the
    /// flares, and a flush bar draws only the small corner into the frame. The
    /// difference — some 56pt across the pair — became dead black either side of
    /// the readings, which is what made the top bar look so wide.
    func testItReservesOnlyWhatItDraws() {
        let m = model()
        let reserved = (m.shapeLength - m.bodyLength) / 2

        let size = m.notchSize
        let place = NotchPlacement(edge: .top, panelSize: size)
        let path = SideNotchShape(edge: .top, joining: m.joinedNotch)
            .path(in: CGRect(origin: .zero, size: size))
        let probe = NotchLayout.bezelFillet + 4
        let drawn = stride(from: CGFloat(0), to: size.width, by: 1)
            .first { path.contains(place.point(along: $0, across: probe)) } ?? -1

        XCTAssertEqual(reserved, drawn, accuracy: 3,
                       "the bar reserves \(reserved)pt at each end but draws \(drawn)pt")
    }

    /// Which reads, at the ends, as a margin in proportion to the readings
    /// rather than one that dwarfs them.
    func testTheMarginBesideTheFirstRingIsProportionate() {
        let m = model()
        let ringEdge = m.ringCenter(index: 0) - NotchLayout.ringDiameter / 2
        XCTAssertLessThan(ringEdge, NotchLayout.ringDiameter * 1.2,
                          "there is more black beside the first ring than there is ring")
    }

    /// Still symmetric, and still centred.
    func testTheEndsMatchEachOther() {
        for count in 1...5 {
            let m = model(cells: count)
            XCTAssertEqual(m.ringCenter(index: 0),
                           m.shapeLength - m.ringCenter(index: count - 1),
                           accuracy: 0.5, "\\(count) cells")
        }
    }

    /// A notch that still has its flares keeps every point of the room they need.
    func testAFlaredNotchIsUnchanged() {
        let m = model(screen: plain)
        XCTAssertEqual((m.shapeLength - m.bodyLength) / 2, NotchLayout.curlRadius,
                       accuracy: 0.001)
    }
}

/// The handle answers where it is drawn, and not in the space around it.
@MainActor
final class OrbHitAccuracyTests: XCTestCase {
    private func model(flush: Bool = true) -> NotchViewModel {
        let model = NotchViewModel()
        model.edge = .top
        model.isExpanded = true
        model.snapshots = (0..<4).map { index in
            ProviderSnapshot(id: "p\(index)", displayName: "P", glyph: .claude,
                             fidelity: .official, status: .ok, windows: [])
        }
        model.adopt(screen: flush ? notched : plain)
        return model
    }

    private func arcCentre(_ m: NotchViewModel) -> CGPoint {
        CGPoint(x: m.orbAlong + m.orbArcOffset.width, y: m.orbInset + m.orbArcOffset.height)
    }

    /// You can reach the button itself.
    func testTheButtonAnswers() {
        let m = model()
        XCTAssertTrue(m.isOnOrbHandle(along: m.orbAlong, across: m.orbInset))
    }

    /// And the arc, which at rest is the only part of it you can see.
    func testTheArcAnswers() {
        let m = model()
        let centre = arcCentre(m)
        // The middle of the quadrant: out from its centre, the way the button went.
        let reach = hypot(m.orbAlong - centre.x, m.orbInset - centre.y)
        let mid = CGPoint(x: centre.x + m.orbArcRadius * (m.orbAlong - centre.x) / reach,
                          y: centre.y + m.orbArcRadius * (m.orbInset - centre.y) / reach)
        XCTAssertTrue(m.isOnOrbHandle(along: mid.x, across: mid.y),
                      "pointing at the arc does not reach the handle")
    }

    /// **But not the empty ground beside them.**
    ///
    /// The arc stayed back on the bar's corner while the button hangs off it,
    /// and a *bounding box* around the pair takes in a good deal that is near
    /// neither — which is why the button used to appear well before the pointer
    /// got anywhere close to the arc. The box's own corners are the proof: a
    /// box test accepts them, and nothing is drawn within reach of either.
    func testTheCornersOfTheBoxBetweenThemDoNotAnswer() {
        let m = model()
        let points = m.orbHandlePoints
        guard points.count == 2 else { return XCTFail("expected an arc and a button") }
        let reach = NotchLayout.orbHotZone / 2
        let box = CGRect(
            x: min(points[0].x, points[1].x) - reach,
            y: min(points[0].y, points[1].y) - reach,
            width: abs(points[0].x - points[1].x) + reach * 2,
            height: abs(points[0].y - points[1].y) + reach * 2
        )
        for corner in [CGPoint(x: box.minX, y: box.maxY), CGPoint(x: box.maxX, y: box.minY)] {
            XCTAssertFalse(
                m.isOnOrbHandle(along: corner.x, across: corner.y),
                "the handle answers at a corner of its own bounding box, where nothing is drawn"
            )
        }
    }

    /// Nor anywhere back inside the bar.
    func testItDoesNotAnswerInsideTheBar() {
        let m = model()
        XCTAssertFalse(m.isOnOrbHandle(along: m.shapeLength / 2, across: m.notchDepth / 2))
    }

    /// A flared notch is reached exactly as it always was: one zone, on the orb.
    func testAFlaredNotchAnswersOnItsOrb() {
        let m = model(flush: false)
        XCTAssertTrue(m.isOnOrbHandle(along: m.orbAlong, across: m.orbInset))
        XCTAssertFalse(m.isOnOrbHandle(along: m.orbAlong + NotchLayout.orbHotZone,
                                       across: m.orbInset))
    }
}

/// The resting arc traces the bar's corner, so it must turn about the very
/// point the *drawn* corner turns about.
@MainActor
final class ArcConcentricityTests: XCTestCase {
    private func model() -> NotchViewModel {
        let model = NotchViewModel()
        model.edge = .top
        model.isExpanded = true
        model.snapshots = (0..<4).map { index in
            ProviderSnapshot(id: "p\(index)", displayName: "P", glyph: .claude,
                             fidelity: .official, status: .ok, windows: [])
        }
        model.adopt(screen: notched)
        return model
    }

    /// Measured off the path rather than restated from the formula, because the
    /// formula was the thing that was wrong: the corner's centre is inset from
    /// the bar's end by the *frame fillet* as well as by its own radius, and
    /// leaving the fillet out slid the arc a whole 10pt down the bar. The gap
    /// then opened from 9pt at one end of the arc to 19pt at the other, which
    /// is what stopped it looking like a curve drawn around the corner.
    func testTheArcTurnsAboutTheCornerTheBarActuallyDraws() {
        let m = model()
        let size = m.notchSize
        let place = NotchPlacement(edge: .top, panelSize: size)
        let path = SideNotchShape(edge: .top, joining: realNotch)
            .path(in: CGRect(origin: .zero, size: size))
        let centre = CGPoint(x: m.orbAlong + m.orbArcOffset.width,
                             y: m.orbInset + m.orbArcOffset.height)

        for degrees in stride(from: 5.0, through: 85.0, by: 10.0) {
            let angle = degrees * .pi / 180
            var edge: CGFloat = -1
            var radius: CGFloat = 0
            while radius < 140 {
                let point = place.point(along: centre.x + cos(angle) * radius,
                                        across: centre.y + sin(angle) * radius)
                if path.contains(point) { edge = radius }
                radius += 0.25
            }
            XCTAssertEqual(
                edge, m.drawnCornerRadius, accuracy: 1.5,
                "at \(Int(degrees))° the bar's edge is \(edge)pt from the arc's centre, "
                    + "not the corner's own \(m.drawnCornerRadius)pt"
            )
        }
    }
}

/// Opening should look like the notch *stretching*, not like one shape turning
/// into another.
@MainActor
final class ExpansionShapeTests: XCTestCase {
    /// How far the shape pulls in at its foot — which is its corner radius.
    private func cornerPullIn(width: CGFloat, depth: CGFloat) -> CGFloat {
        let size = CGSize(width: width, height: depth)
        let place = NotchPlacement(edge: .top, panelSize: size)
        let path = SideNotchShape(edge: .top, joining: realNotch)
            .path(in: CGRect(origin: .zero, size: size))

        func span(at across: CGFloat) -> ClosedRange<CGFloat>? {
            let hits = stride(from: CGFloat(0), to: width, by: 0.5)
                .filter { path.contains(place.point(along: $0, across: across)) }
            guard let first = hits.first, let last = hits.last else { return nil }
            return first...last
        }
        // The straight section — below the frame fillet, above the corner —
        // against the very bottom, where the corner has run its course. Taken
        // at the same depth from the foot every time, so the figures compare
        // even though neither is the corner's radius outright.
        guard let body = span(at: NotchLayout.bezelFillet + 2),
              let foot = span(at: depth - 0.25) else { return -1 }
        return ((foot.lowerBound - body.lowerBound) + (body.upperBound - foot.upperBound)) / 2
    }

    /// The corner is the same size at rest as it is open, so the shape stretches
    /// rather than un-rounding as it grows. Left to the frame it is clamped to
    /// half the depth, which at the hardware's own 38pt makes the resting shape
    /// very nearly a pill — and opening it then reads as a rounded tab turning
    /// into a bar.
    func testTheCornerIsTheSameSizeShutAsOpen() {
        let shut = cornerPullIn(width: realNotch.width, depth: realNotch.height)
        let open = cornerPullIn(width: 336.2, depth: 135.1)
        XCTAssertGreaterThan(shut, 0, "nothing measured shut")
        XCTAssertEqual(shut, open, accuracy: 1.5,
                       "the corner is \(shut)pt shut and \(open)pt open — the shape morphs")
    }

    /// And it stays that size the whole way, so no frame of the animation
    /// rounds off more than any other.
    func testTheCornerHoldsThroughTheWholeExpansion() {
        let reference = cornerPullIn(width: realNotch.width, depth: realNotch.height)
        for step in 1...6 {
            let t = CGFloat(step) / 6
            let corner = cornerPullIn(width: realNotch.width + (336.2 - realNotch.width) * t,
                                      depth: realNotch.height + (135.1 - realNotch.height) * t)
            XCTAssertEqual(corner, reference, accuracy: 1.5,
                           "the corner changes size \(Int(t * 100))% of the way open")
        }
    }

    /// It can never be *squarer* than the hardware's own rounding, or the
    /// resting shape's corners poke out past the hole and show as two nubs.
    @MainActor
    func testTheRestingShapeCannotPokeOutOfTheHole() {
        let model = NotchViewModel()
        model.edge = .top
        model.adopt(screen: notched)
        XCTAssertGreaterThanOrEqual(model.drawnCornerRadius, realNotch.height / 2,
                                    "the resting corners are squarer than the hardware's")
    }
}
