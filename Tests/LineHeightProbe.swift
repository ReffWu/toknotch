import XCTest
import SwiftUI
@testable import TokNotch

/// The card's height is budgeted from font metrics rather than measured, so the
/// budget's idea of a line has to be what SwiftUI actually draws. When it is
/// not, every card carries the difference as dead black at the bottom — times
/// the number of lines on it.
@MainActor
final class LineHeightProbeTests: XCTestCase {
    private func renderedHeight(_ view: some View) -> CGFloat {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return renderer.nsImage?.size.height ?? 0
    }

    func testTheBudgetedBodyLineMatchesADrawnOne() {
        let drawn = renderedHeight(Text("测试 Ag").font(Typography.cardBody).lineLimit(1))
        XCTAssertEqual(drawn, NotchLayout.cardBodyLineHeight, accuracy: 0.5)
    }

    func testTheBudgetedTitleLineMatchesADrawnOne() {
        let drawn = renderedHeight(Text("测试 Ag").font(Typography.cardTitle).lineLimit(1))
        XCTAssertEqual(drawn, NotchLayout.cardTitleLineHeight, accuracy: 0.5)
    }
}
