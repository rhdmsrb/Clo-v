import XCTest
@testable import CLOV

/// `FlowLayout` wraps chips into rows. Measuring and placing must agree on where a
/// row breaks, or the container is shorter than its chips and they draw over
/// whatever sits below (the Explore photo grid).
final class FlowLayoutTests: XCTestCase {
    private let spacing: CGFloat = 8

    private func chip(_ width: CGFloat, height: CGFloat = 40) -> CGSize {
        CGSize(width: width, height: height)
    }

    func testChipsThatFitOnOneRowShareIt() {
        // 100 + 8 + 100 = 208 fits exactly in 208.
        let result = FlowLayout.arrange(sizes: [chip(100), chip(100)], maxWidth: 208, spacing: spacing)

        XCTAssertEqual(result.origins, [CGPoint(x: 0, y: 0), CGPoint(x: 108, y: 0)])
        XCTAssertEqual(result.size.height, 40)
    }

    func testChipWrapsWhenOnlyTheGapPushesItOver() {
        // The widths alone (200) fit in 205, but the 8 pt gap makes it 208, so the second chip wraps.
        let result = FlowLayout.arrange(sizes: [chip(100), chip(100)], maxWidth: 205, spacing: spacing)

        XCTAssertEqual(result.origins[1], CGPoint(x: 0, y: 48))
        XCTAssertEqual(result.size.height, 88, "height must include the wrapped row")
    }

    func testReportedHeightReachesTheBottomOfTheLastChipAtEveryWidth() {
        let sizes = (0..<7).map { chip(CGFloat(60 + $0 * 17)) }

        for width in stride(from: 150, through: 400, by: 7) {
            let result = FlowLayout.arrange(sizes: sizes, maxWidth: CGFloat(width), spacing: spacing)
            let lowestEdge = zip(result.origins, sizes).map { $0.y + $1.height }.max() ?? 0
            XCTAssertEqual(result.size.height, lowestEdge, "width \(width)")
        }
    }

    func testNoChipIsPlacedPastTheRightEdge() {
        let sizes = (0..<9).map { chip(CGFloat(55 + $0 * 13)) }

        for width in stride(from: 120, through: 390, by: 5) {
            let result = FlowLayout.arrange(sizes: sizes, maxWidth: CGFloat(width), spacing: spacing)
            for (origin, size) in zip(result.origins, sizes) where size.width <= CGFloat(width) {
                XCTAssertLessThanOrEqual(origin.x + size.width, CGFloat(width), "width \(width)")
            }
        }
    }

    func testChipWiderThanTheRowGetsItsOwnRow() {
        let result = FlowLayout.arrange(sizes: [chip(300), chip(50)], maxWidth: 200, spacing: spacing)

        XCTAssertEqual(result.origins, [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 48)])
    }

    func testRowHeightIsTheTallestChipInTheRow() {
        let sizes = [chip(100, height: 30), chip(100, height: 50), chip(100, height: 20)]

        let result = FlowLayout.arrange(sizes: sizes, maxWidth: 220, spacing: spacing)

        XCTAssertEqual(result.origins[2], CGPoint(x: 0, y: 58))
        XCTAssertEqual(result.size.height, 78)
    }

    func testNoChipsHaveNoHeight() {
        let result = FlowLayout.arrange(sizes: [], maxWidth: 300, spacing: spacing)

        XCTAssertTrue(result.origins.isEmpty)
        XCTAssertEqual(result.size.height, 0)
    }

    func testReportedWidthIsTheProposedWidth() {
        let result = FlowLayout.arrange(sizes: [chip(80)], maxWidth: 320, spacing: spacing)

        XCTAssertEqual(result.size.width, 320)
    }
}
