import AppKit
import XCTest
@testable import TokNotch

private struct FakeScreen: ScreenDescribing {
    var frameValue: CGRect
    var visibleFrameValue: CGRect
    var hardwareNotch: HardwareNotch?
}

/// A 14-inch MacBook Pro, as this machine reports itself.
private let notched = FakeScreen(
    frameValue: CGRect(x: 0, y: 0, width: 1728, height: 1117),
    visibleFrameValue: CGRect(x: 0, y: 0, width: 1728, height: 1079),
    hardwareNotch: HardwareNotch(width: 185, height: 38)
)

private let plain = FakeScreen(
    frameValue: CGRect(x: 0, y: 0, width: 1728, height: 1117),
    visibleFrameValue: CGRect(x: 0, y: 0, width: 1728, height: 1079),
    hardwareNotch: nil
)

/// Reported as: hover in from the side, and now and then the notch stays open
/// for good — only restarting TokNotch puts it away.
///
/// The open notch's hit region was `notchRect.union(handleRect)`, and a union
/// of rects is their bounding box. On a top notch joining the display's own,
/// the settings handle hangs below the bar's far corner, so the box took in a
/// band under the whole bar where nothing is drawn. Resting there held the
/// notch open; clicking there — a browser's tabs sit exactly there — was
/// swallowed and fell through to `togglePinned()`. A pin with no sign of
/// itself, released only by clicking that same invisible band again.
@MainActor
final class PhantomHitRegionTests: XCTestCase {
    private func openModel(on screen: FakeScreen, edge: NotchEdge, cells: Int = 6) -> NotchViewModel {
        let model = NotchViewModel()
        model.edge = edge
        model.rings = (0..<cells).map { TestRing.make($0, rows: 1) }
        model.adopt(screen: screen)
        model.isExpanded = true
        return model
    }

    /// The handle's square hot zones, as the old code drew them.
    private func handleBoxes(_ model: NotchViewModel) -> [CGRect] {
        let place = model.placement
        let side = NotchLayout.orbHotZone
        return model.orbHandlePoints.map { point in
            let centre = place.point(along: model.slack + point.x, across: point.y)
            return CGRect(x: centre.x - side / 2, y: centre.y - side / 2, width: side, height: side)
        }
    }

    /// Points under the middle of the bar, clear of the handle, that the old
    /// bounding box covered and nothing on screen does.
    private func bandUnderTheBar(_ model: NotchViewModel) -> [CGPoint] {
        let place = model.placement
        let bar = model.notchRect(in: place)
        let reach = handleBoxes(model).map(\.maxY).max() ?? bar.maxY
        return stride(from: bar.maxY + 1, to: reach, by: 4).flatMap { y in
            stride(from: bar.minX + 4, to: bar.midX, by: 24).map { CGPoint(x: $0, y: y) }
        }.filter { !model.isOverHandle($0, in: place) }
    }

    func testTheOldBoundingBoxReallyCoveredABandUnderTheBar() {
        // Guards the premise of the test below: if the geometry ever changes so
        // the handle no longer hangs past the bar, the band is empty and the
        // real test would pass for the wrong reason.
        let model = openModel(on: notched, edge: .top)
        let old = handleBoxes(model).reduce(model.notchRect(in: model.placement)) { $0.union($1) }
        let band = bandUnderTheBar(model)
        XCTAssertGreaterThan(band.count, 20, "no band under the bar to test")
        XCTAssertTrue(band.allSatisfy(old.contains), "the old union did not cover the band")
    }

    func testNothingUnderTheBarHoldsAJoinedTopNotchOpen() {
        let model = openModel(on: notched, edge: .top)
        let place = model.placement
        for point in bandUnderTheBar(model) {
            XCTAssertFalse(model.isLive(point, in: place),
                           "\(point) is empty screen under the bar, yet it holds the notch open")
        }
    }

    /// The handle is still reachable — fixing the band must not cost the gear.
    func testTheHandleIsStillLiveOnEveryEdge() {
        for screen in [notched, plain] {
            for edge in NotchEdge.allCases {
                let model = openModel(on: screen, edge: edge)
                let place = model.placement
                for point in model.orbHandlePoints {
                    let centre = place.point(along: model.slack + point.x, across: point.y)
                    XCTAssertTrue(model.isLive(centre, in: place),
                                  "\(edge): the settings handle stopped answering")
                }
            }
        }
    }

    /// Anything that holds the notch open is on the bar or on a handle circle —
    /// on every edge, with and without a display notch to join.
    func testEveryLivePointIsOnSomethingDrawn() {
        for screen in [notched, plain] {
            for edge in NotchEdge.allCases {
                let model = openModel(on: screen, edge: edge)
                let place = model.placement
                let bar = model.notchRect(in: place)
                let radius = NotchLayout.orbHotZone / 2
                let handles = model.orbHandlePoints.map {
                    place.point(along: model.slack + $0.x, across: $0.y)
                }
                for x in stride(from: 0, to: place.panelSize.width, by: 6) {
                    for y in stride(from: 0, to: place.panelSize.height, by: 6) {
                        let p = CGPoint(x: x, y: y)
                        guard model.isLive(p, in: place) else { continue }
                        let onHandle = handles.contains { hypot(p.x - $0.x, p.y - $0.y) <= radius + 0.5 }
                        XCTAssertTrue(bar.contains(p) || onHandle,
                                      "\(edge): \(p) holds the notch open with nothing there")
                    }
                }
            }
        }
    }
}

/// A pin made by hand has to be undoable by something a person would actually
/// do — not only by finding the one spot on the bar that toggles it.
@MainActor
final class PinReleaseTests: XCTestCase {
    private func pump(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func pinnedController() -> NotchWindowController {
        let controller = NotchWindowController()
        controller.show()
        controller.apply(.onHover)
        controller.togglePinned()
        XCTAssertTrue(controller.model.isPinned)
        return controller
    }

    /// A click anywhere else lets go, the way it closes any popover.
    func testAClickElsewhereReleasesAPin() throws {
        let controller = pinnedController()
        defer { controller.stop() }
        try XCTSkipIf(controller.isPointerOnNotchForTesting, "the pointer is on the notch")

        // Posted into this app's own queue: nothing outside it sees the click,
        // and the real pointer does not move.
        let click = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        NSApp.postEvent(click, atStart: false)
        // Drained the way the app drains it, so the local monitor sees it.
        let deadline = Date().addingTimeInterval(1)
        while controller.model.isPinned, Date() < deadline {
            if let event = NSApp.nextEvent(matching: .any, until: Date().addingTimeInterval(0.02),
                                           inMode: .default, dequeue: true) {
                NSApp.sendEvent(event)
            }
        }
        XCTAssertFalse(controller.model.isPinned, "a click elsewhere left the pin in place")
    }

    /// Nobody comes back from lunch expecting a notch they held open to still
    /// be in the way.
    func testTheDisplaySleepingReleasesAPin() {
        let controller = pinnedController()
        defer { controller.stop() }
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidSleepNotification,
                                                   object: NSWorkspace.shared)
        XCTAssertFalse(controller.model.isPinned)
    }

    /// Always show is a setting, not a pin, and outlives both.
    func testAlwaysShowIsNotReleasedByEither() {
        let controller = NotchWindowController()
        controller.show()
        defer { controller.stop() }
        controller.apply(.alwaysShow)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidSleepNotification,
                                                   object: NSWorkspace.shared)
        XCTAssertTrue(controller.model.staysOpen)
    }

    /// A click on the open notch that is on none of its parts is not a request
    /// to pin it. With the pointer away from the notch, that is every click.
    func testAClickOffTheBarDoesNotPin() throws {
        let controller = NotchWindowController()
        controller.show()
        defer { controller.stop() }
        try XCTSkipIf(controller.isPointerOnNotchForTesting, "the pointer is on the notch")
        controller.model.isExpanded = true

        controller.handleClick()
        XCTAssertFalse(controller.model.isPinned, "a click beside the notch pinned it open")
    }
}

/// Two quick moves and back must land where Settings says.
@MainActor
final class EdgeRaceTests: XCTestCase {
    private func pump(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    func testThereAndBackAgainLandsBack() {
        let controller = NotchWindowController()
        controller.show()
        defer { controller.stop() }
        let home = controller.model.edge
        let away: NotchEdge = home == .top ? .bottom : .top

        controller.apply(edge: away)
        pump(0.04)
        controller.apply(edge: home)   // before the first crossing has landed
        pump(1.0)

        XCTAssertEqual(controller.model.edge, home,
                       "the notch ended on an edge it had been moved off again")
        XCTAssertEqual(controller.panelAlphaForTesting, 1, accuracy: 0.01)
    }
}

/// A stopped controller has nothing following the pointer, so a panel it put
/// back up would never fold.
@MainActor
final class StoppedControllerTests: XCTestCase {
    func testAStoppedControllerNeverPutsAPanelBackUp() {
        let controller = NotchWindowController()
        controller.show()
        controller.stop()

        controller.relocate()
        controller.model.rings = (0..<5).map { TestRing.make($0) }
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification,
                                        object: NSApp)
        XCTAssertNil(controller.panelContentViewForTesting, "a stopped notch came back")
    }
}
