import XCTest
@testable import StackGameCore

final class TuningTests: XCTestCase {

    func testSpeedRisesThenPlateaus() {
        var previous = Tuning.speed(atLevel: 0)
        for level in 1...300 {
            let current = Tuning.speed(atLevel: level)
            XCTAssertGreaterThanOrEqual(current, previous - 1e-12, "speed must never drop")
            previous = current
        }
        XCTAssertEqual(Tuning.speed(atLevel: 0), Tuning.baseSpeed, accuracy: 1e-12)
        XCTAssertEqual(Tuning.speed(atLevel: 500), Tuning.maxSpeed, accuracy: 1e-12)
    }

    func testEpsilonFloorHolds() {
        // Below roughly 0.67 wide the tolerance stops shrinking. This is what
        // keeps the comeback loop reachable: without the floor a narrowed tower
        // could never perfect again, so it could never regrow, and the run would
        // be mathematically dead while still nominally playable.
        XCTAssertEqual(Tuning.perfectEpsilon(forSize: 0.10), Tuning.minEpsilon, accuracy: 1e-12)
        XCTAssertEqual(Tuning.perfectEpsilon(forSize: 0.22), Tuning.minEpsilon, accuracy: 1e-12)
        XCTAssertGreaterThan(Tuning.perfectEpsilon(forSize: 1.0), Tuning.minEpsilon)
    }

    func testEpsilonNeverSwallowsASliver() {
        for size in [0.01, 0.02, 0.03, 0.04] {
            XCTAssertLessThanOrEqual(
                Tuning.perfectEpsilon(forSize: size),
                size * Tuning.maxEpsilonFraction + 1e-12,
                "tolerance must not degenerate into 'any overlap counts'"
            )
        }
    }

    func testPerfectWindowStaysHuman() {
        // The headline playability constraint. The target sits at the fastest
        // point of the sweep, so what the player actually has to hit is a time
        // window, not a distance. Trained timing precision is around 30ms; below
        // roughly 20ms a perfect stops being a skill and becomes a coin flip.
        let hardest = Tuning.perfectWindowSeconds(atLevel: 300, size: Tuning.nearDeathSize)
        XCTAssertGreaterThan(
            hardest, 0.020,
            "hardest reachable window is \(String(format: "%.1f", hardest * 1000))ms"
        )

        let opening = Tuning.perfectWindowSeconds(atLevel: 0, size: Tuning.initialSize)
        XCTAssertGreaterThan(opening, 0.060, "the first blocks should feel generous")

        XCTAssertLessThan(hardest, opening, "difficulty must actually increase")
    }

    func testMaterialTierBoundaries() {
        XCTAssertEqual(MaterialTier(level: 0), .concrete)
        XCTAssertEqual(MaterialTier(level: 14), .concrete)
        XCTAssertEqual(MaterialTier(level: 15), .marble)
        XCTAssertEqual(MaterialTier(level: 29), .marble)
        XCTAssertEqual(MaterialTier(level: 30), .aluminum)
        XCTAssertEqual(MaterialTier(level: 49), .aluminum)
        XCTAssertEqual(MaterialTier(level: 50), .glass)
        XCTAssertEqual(MaterialTier(level: 74), .glass)
        XCTAssertEqual(MaterialTier(level: 75), .obsidian)
        XCTAssertEqual(MaterialTier(level: 10_000), .obsidian)
    }

    func testTierFirstLevelAgreesWithLookup() {
        for tier in MaterialTier.allCases {
            XCTAssertEqual(MaterialTier(level: tier.firstLevel), tier)
            if tier.firstLevel > 0 {
                XCTAssertNotEqual(MaterialTier(level: tier.firstLevel - 1), tier)
            }
        }
    }
}

final class ScoreCalculatorTests: XCTestCase {

    func testBasicAwards() {
        XCTAssertEqual(ScoreCalculator.points(outcome: .missed, combo: 5), 0)
        XCTAssertEqual(ScoreCalculator.points(outcome: .sliced, combo: 99), 1)
        XCTAssertEqual(ScoreCalculator.points(outcome: .perfect, combo: 1), 2)
        XCTAssertEqual(ScoreCalculator.points(outcome: .perfect, combo: 3), 4)
    }

    func testComboBonusCaps() {
        XCTAssertEqual(
            ScoreCalculator.points(outcome: .perfect, combo: 500),
            1 + Tuning.maxComboBonus
        )
    }

    func testStreaksBeatEndurance() {
        // The core scoring claim: a shorter run carrying real streaks should
        // outscore a longer run of sloppy placements, so the leaderboard sorts
        // by mastery rather than by patience.
        var streaky: [PlacementOutcome] = []
        for _ in 0..<3 {
            streaky.append(contentsOf: Array(repeating: .perfect, count: 10))
            streaky.append(.sliced)
        }
        while streaky.count < 40 { streaky.append(.sliced) }

        let sloppy = Array(repeating: PlacementOutcome.sliced, count: 60)

        XCTAssertGreaterThan(
            ScoreCalculator.total(for: streaky),
            ScoreCalculator.total(for: sloppy)
        )
    }

    func testTotalMatchesStepwiseAccumulation() {
        let run: [PlacementOutcome] = [.perfect, .perfect, .sliced, .perfect, .sliced]
        // 2 + 3 + 1 + 2 + 1
        XCTAssertEqual(ScoreCalculator.total(for: run), 9)
    }
}

final class SeededRandomTests: XCTestCase {

    func testSameSeedRepeats() {
        var a = SeededRandom(seed: 20_260_725)
        var b = SeededRandom(seed: 20_260_725)
        for _ in 0..<200 {
            XCTAssertEqual(a.next(), b.next())
        }
    }

    func testDifferentSeedsDiverge() {
        var a = SeededRandom(seed: 20_260_725)
        var b = SeededRandom(seed: 20_260_726)
        var differences = 0
        for _ in 0..<200 where a.next() != b.next() { differences += 1 }
        XCTAssertGreaterThan(differences, 190)
    }

    func testUnitDoublesAreInRangeAndRoughlyUniform() {
        var rng = SeededRandom(seed: 7)
        var sum = 0.0
        let count = 20_000
        for _ in 0..<count {
            let value = rng.nextUnitDouble()
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThan(value, 1)
            sum += value
        }
        XCTAssertEqual(sum / Double(count), 0.5, accuracy: 0.02)
    }

    func testDailySeedIsStableWithinADayAndChangesAcross() {
        let morning = Date(timeIntervalSince1970: 1_784_000_000)
        let laterSameDay = morning.addingTimeInterval(60 * 60)
        let nextWeek = morning.addingTimeInterval(60 * 60 * 24 * 7)

        XCTAssertEqual(DailySeed.seed(for: morning), DailySeed.seed(for: laterSameDay))
        XCTAssertNotEqual(DailySeed.seed(for: morning), DailySeed.seed(for: nextWeek))
        XCTAssertEqual(DailySeed.identifier(for: morning).count, 10)
    }
}
