import XCTest
import StackGameCore
@testable import StackGame

/// Tests for the node that is *reused* rather than rebuilt.
///
/// Every block in the tower is created once and never touched again, so its
/// geometry cannot go stale. The moving block is the exception: one node is kept
/// alive for as long as its material band lasts and re-pointed at each new
/// preview, which makes it the only place in the renderer where forgetting to
/// push a change through is possible at all. It has happened twice — first the
/// footprint, then the altitude — so the reuse path gets asserted directly.
final class BlockNodeTests: XCTestCase {

    private let footprint = Footprint.centered(width: 1, depth: 1)

    private func node(atLevel level: Int) -> BlockNode {
        BlockNode(
            footprint: footprint,
            baseY: Double(level) * Tuning.blockHeight,
            tier: .concrete
        )
    }

    func testUpdatedNodeMatchesOneBuiltAtTheSameAltitude() {
        // The invariant that actually matters: a node moved to a level is
        // indistinguishable from a node born at it. Comparing drawn frames
        // rather than the stored property is deliberate — the bug was that the
        // paths kept their original altitude, so only the geometry can tell.
        let climbed = node(atLevel: 1)
        climbed.update(footprint: footprint, baseY: 6 * Tuning.blockHeight)

        let built = node(atLevel: 6)

        XCTAssertEqual(climbed.baseY, built.baseY, accuracy: 1e-9)
        XCTAssertEqual(
            climbed.accumulatedFrame.midY, built.accumulatedFrame.midY, accuracy: 1e-6
        )
        XCTAssertEqual(
            climbed.accumulatedFrame.height, built.accumulatedFrame.height, accuracy: 1e-6
        )
        // Draw order has to follow it up the tower too, or the preview sorts
        // itself back into the middle of the stack it is hovering over.
        XCTAssertEqual(climbed.zPosition, built.zPosition, accuracy: 1e-6)
    }

    func testClimbingActuallyMovesTheBlockUpTheScreen() {
        let low = node(atLevel: 1)
        let lowMidY = low.accumulatedFrame.midY

        low.update(footprint: footprint, baseY: 6 * Tuning.blockHeight)

        XCTAssertGreaterThan(
            low.accumulatedFrame.midY, lowMidY,
            "the block gained five levels without moving on screen"
        )
        XCTAssertGreaterThan(low.zPosition, node(atLevel: 5).zPosition)
    }

    func testNarrowingAtAFixedAltitudeStillRebuilds() {
        // The original reason `update` exists. Guard against a fix to the
        // altitude path quietly regressing the footprint path.
        let block = node(atLevel: 3)
        let wideWidth = block.accumulatedFrame.width

        block.update(
            footprint: .centered(width: 0.3, depth: 0.3),
            baseY: 3 * Tuning.blockHeight
        )

        XCTAssertLessThan(block.accumulatedFrame.width, wideWidth)
    }
}
