import XCTest
@testable import StackGameCore

/// Mirrors `Tools/engine-harness/verify.mjs`. If you change a rule, change it in
/// three places: the engine, this file, and the harness.
final class StackEngineTests: XCTestCase {

    // MARK: - Helpers

    private func freshEngine(seed: UInt64 = 1) -> StackEngine {
        var engine = StackEngine(seed: seed)
        engine.start()
        return engine
    }

    @discardableResult
    private func drop(_ engine: inout StackEngine, offset: Double) -> PlacementResult? {
        engine.positionMovingBlock(offsetFromTarget: offset)
        return engine.drop()
    }

    private func extent(_ footprint: Footprint, _ axis: Axis) -> Double {
        footprint.extent(along: axis)
    }

    // MARK: - Placement resolution

    func testExactHitIsPerfect() throws {
        var engine = freshEngine()
        let result = try XCTUnwrap(drop(&engine, offset: 0))

        XCTAssertEqual(result.outcome, .perfect)
        XCTAssertEqual(result.combo, 1)
        XCTAssertEqual(result.scoreDelta, 2, "base point plus a combo-of-1 bonus")
        XCTAssertEqual(try XCTUnwrap(result.placed).footprint.width, Tuning.initialSize, accuracy: 1e-9)
        XCTAssertNil(result.debris)
    }

    func testEpsilonBoundary() throws {
        let epsilon = Tuning.perfectEpsilon(forSize: Tuning.initialSize)

        var inside = freshEngine()
        let insideResult = try XCTUnwrap(drop(&inside, offset: epsilon - 1e-9))
        XCTAssertEqual(insideResult.outcome, .perfect)

        var outside = freshEngine()
        let outsideResult = try XCTUnwrap(drop(&outside, offset: epsilon + 1e-6))
        XCTAssertEqual(outsideResult.outcome, .sliced)
    }

    func testPerfectSnapsAwayResidualOffset() throws {
        // A sub-epsilon offset must not be preserved, or a long streak would
        // accumulate the errors into a visible lean.
        var engine = freshEngine()
        let epsilon = Tuning.perfectEpsilon(forSize: Tuning.initialSize)
        let result = try XCTUnwrap(drop(&engine, offset: epsilon * 0.9))
        let base = try XCTUnwrap(engine.tower.first)
        let placed = try XCTUnwrap(result.placed)

        XCTAssertEqual(placed.footprint.x, base.footprint.x, accuracy: 1e-12)
    }

    func testSliceConservesExtentOnBothSides() throws {
        for sign in [1.0, -1.0] {
            var engine = freshEngine()
            let result = try XCTUnwrap(drop(&engine, offset: sign * 0.4))
            let placed = try XCTUnwrap(result.placed)
            let debris = try XCTUnwrap(result.debris)
            let axis = placed.axis

            XCTAssertEqual(
                extent(placed.footprint, axis) + extent(debris.footprint, axis),
                Tuning.initialSize,
                accuracy: 1e-9,
                "surviving block plus debris must equal the block that was dropped"
            )
            XCTAssertEqual(debris.onFarSide, sign > 0)
        }
    }

    func testTotalMissEndsRun() throws {
        var engine = freshEngine()
        let result = try XCTUnwrap(drop(&engine, offset: 1.5))

        XCTAssertEqual(result.outcome, .missed)
        XCTAssertEqual(engine.phase, .gameOver)
        XCTAssertEqual(result.scoreDelta, 0)
        XCTAssertNil(result.placed)
        XCTAssertNil(engine.moving)
    }

    func testSubViableSliverEndsRun() throws {
        // Probed with margin rather than exactly at the threshold: in floating
        // point `1.0 - 0.98` is 0.020000000000000018, so a boundary-exact test
        // asserts nothing but the rounding mode.
        var thin = freshEngine()
        let thinResult = try XCTUnwrap(drop(&thin, offset: Tuning.initialSize - Tuning.minimumViableSize * 0.5))
        XCTAssertEqual(thinResult.outcome, .missed)

        var viable = freshEngine()
        let viableResult = try XCTUnwrap(drop(&viable, offset: Tuning.initialSize - Tuning.minimumViableSize * 4))
        XCTAssertEqual(viableResult.outcome, .sliced)
    }

    func testPlacementAlternatesAxis() throws {
        var engine = freshEngine()
        var axes: [Axis] = []
        for _ in 0..<6 {
            let result = try XCTUnwrap(drop(&engine, offset: 0))
            axes.append(try XCTUnwrap(result.placed).axis)
        }
        XCTAssertEqual(axes, [.x, .z, .x, .z, .x, .z])
    }

    // MARK: - Combo and regrowth

    func testComboAccumulatesAndBreaks() throws {
        var engine = freshEngine()
        for _ in 0..<5 { drop(&engine, offset: 0) }
        XCTAssertEqual(engine.combo, 5)
        XCTAssertEqual(engine.bestCombo, 5)

        let broken = try XCTUnwrap(drop(&engine, offset: 0.5))
        XCTAssertEqual(engine.combo, 0)
        XCTAssertEqual(broken.scoreDelta, 1)
        XCTAssertEqual(engine.bestCombo, 5, "best combo survives the break")
    }

    func testRegrowthFiresOncePerInterval() throws {
        var engine = freshEngine()
        drop(&engine, offset: 0.3)
        let narrowed = try XCTUnwrap(engine.topBlock).footprint.width
        XCTAssertEqual(narrowed, 0.7, accuracy: 1e-9)

        var regrowths = 0
        for _ in 0..<Tuning.comboRegrowthInterval {
            if try XCTUnwrap(drop(&engine, offset: 0)).didRegrow { regrowths += 1 }
        }
        XCTAssertEqual(regrowths, 1)

        let top = try XCTUnwrap(engine.topBlock)
        XCTAssertEqual(
            extent(top.footprint, top.axis),
            0.7 + Tuning.regrowthAmount,
            accuracy: 1e-9
        )
    }

    func testRegrowthNeverExceedsInitialSize() throws {
        var engine = freshEngine()
        for _ in 0..<40 { drop(&engine, offset: 0) }
        let top = try XCTUnwrap(engine.topBlock)

        XCTAssertLessThanOrEqual(top.footprint.width, Tuning.initialSize + 1e-9)
        XCTAssertLessThanOrEqual(top.footprint.depth, Tuning.initialSize + 1e-9)
    }

    func testRegrowthStaysCentred() throws {
        // Growth must be split across both edges, otherwise a regrowing tower
        // would drift sideways.
        var engine = freshEngine()
        drop(&engine, offset: 0.3)
        let beforeCentre = try XCTUnwrap(engine.topBlock).footprint.centerX

        for _ in 0..<Tuning.comboRegrowthInterval { drop(&engine, offset: 0) }
        let grown = try XCTUnwrap(engine.tower.last { $0.axis == .x })

        XCTAssertEqual(grown.footprint.centerX, beforeCentre, accuracy: 1e-9)
    }

    func testNearDeathIsFlagged() throws {
        var engine = freshEngine()
        let result = try XCTUnwrap(drop(&engine, offset: 0.85))
        XCTAssertTrue(result.isNearDeath, "0.15 wide is under the near-death threshold")
    }

    // MARK: - Continue

    func testContinueRestoresPlayableWidth() throws {
        var engine = freshEngine()
        drop(&engine, offset: 0.8)
        drop(&engine, offset: 0.8)
        drop(&engine, offset: 1.5)
        XCTAssertEqual(engine.phase, .gameOver)

        let heightAtDeath = engine.height
        engine.continueRun()

        XCTAssertEqual(engine.phase, .playing)
        XCTAssertEqual(engine.height, heightAtDeath, "continue resumes, it does not rewind")
        XCTAssertEqual(engine.continuesUsed, 1)
        XCTAssertNotNil(engine.moving)

        let top = try XCTUnwrap(engine.topBlock)
        XCTAssertGreaterThanOrEqual(top.footprint.width, Tuning.continueRestoreSize - 1e-9)
        XCTAssertGreaterThanOrEqual(top.footprint.depth, Tuning.continueRestoreSize - 1e-9)
    }

    func testContinueIsInertWhileAlive() {
        var engine = freshEngine()
        engine.continueRun()
        XCTAssertEqual(engine.continuesUsed, 0)
    }

    // MARK: - Tiers

    func testTierCrossingsAreReportedOnce() throws {
        var engine = freshEngine()
        var crossings: [MaterialTier] = []
        for _ in 0..<80 {
            if let crossed = try XCTUnwrap(drop(&engine, offset: 0)).crossedInto {
                crossings.append(crossed)
            }
        }
        XCTAssertEqual(crossings, [.marble, .aluminum, .glass, .obsidian])
    }

    // MARK: - Sweep

    func testUpdateSweepsWithinAmplitude() throws {
        var engine = freshEngine()
        let target = try XCTUnwrap(engine.moving).travelCenter

        var minimum = Double.infinity
        var maximum = -Double.infinity
        for _ in 0..<600 {
            engine.update(deltaTime: 1.0 / 60.0)
            let origin = try XCTUnwrap(engine.moving).origin
            minimum = min(minimum, origin)
            maximum = max(maximum, origin)
        }

        XCTAssertGreaterThanOrEqual(minimum, target - Tuning.travelAmplitude - 1e-9)
        XCTAssertLessThanOrEqual(maximum, target + Tuning.travelAmplitude + 1e-9)
        XCTAssertLessThan(minimum, target, "sweep must cross the target from both sides")
        XCTAssertGreaterThan(maximum, target)
    }

    func testUpdateIsInertAfterGameOver() throws {
        var engine = freshEngine()
        drop(&engine, offset: 1.5)
        engine.update(deltaTime: 1.0)
        XCTAssertNil(engine.moving)
        XCTAssertEqual(engine.phase, .gameOver)
    }

    // MARK: - Determinism

    func testSameSeedProducesIdenticalRuns() throws {
        var first = freshEngine(seed: 20_260_725)
        var second = freshEngine(seed: 20_260_725)

        for _ in 0..<200 {
            XCTAssertEqual(
                try XCTUnwrap(first.moving).phase,
                try XCTUnwrap(second.moving).phase,
                "the daily challenge depends on identical spawn sides"
            )
            drop(&first, offset: 0)
            drop(&second, offset: 0)
        }
        XCTAssertEqual(first.score, second.score)
    }

    func testDifferentSeedsDiverge() throws {
        var a = freshEngine(seed: 1)
        var b = freshEngine(seed: 2)
        var phasesA: [Double] = []
        var phasesB: [Double] = []
        for _ in 0..<60 {
            phasesA.append(try XCTUnwrap(a.moving).phase)
            phasesB.append(try XCTUnwrap(b.moving).phase)
            drop(&a, offset: 0)
            drop(&b, offset: 0)
        }
        XCTAssertNotEqual(phasesA, phasesB)
    }
}
