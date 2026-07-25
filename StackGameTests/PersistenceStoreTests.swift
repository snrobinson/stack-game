import XCTest
import StackGameCore
@testable import StackGame

final class PersistenceStoreTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: PersistenceStore!

    override func setUp() {
        super.setUp()
        // An isolated suite per test, so these never touch the real app's data
        // and never leak into each other.
        suiteName = "stack.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = PersistenceStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func summary(score: Int, height: Int = 10, combo: Int = 3, perfects: Int = 5) -> RunSummary {
        RunSummary(
            score: score,
            height: height,
            bestCombo: combo,
            perfectCount: perfects,
            tierReached: MaterialTier(level: height),
            continuesUsed: 0,
            isDailyChallenge: false,
            dailyIdentifier: nil
        )
    }

    func testFirstRunSetsAHighScore() {
        XCTAssertTrue(store.record(summary(score: 40)))
        XCTAssertEqual(store.stats.highScore, 40)
        XCTAssertEqual(store.stats.runsPlayed, 1)
    }

    func testOnlyBetterRunsReportANewBest() {
        _ = store.record(summary(score: 40))
        XCTAssertFalse(store.record(summary(score: 20)))
        XCTAssertEqual(store.stats.highScore, 40, "a worse run must not lower the best")
        XCTAssertTrue(store.record(summary(score: 41)))
    }

    func testTotalsAccumulateWhileBestsTakeTheMaximum() {
        _ = store.record(summary(score: 40, height: 20, combo: 6, perfects: 9))
        _ = store.record(summary(score: 10, height: 5, combo: 2, perfects: 1))

        XCTAssertEqual(store.stats.runsPlayed, 2)
        XCTAssertEqual(store.stats.totalBlocksPlaced, 25)
        XCTAssertEqual(store.stats.totalPerfects, 10)
        XCTAssertEqual(store.stats.bestHeight, 20)
        XCTAssertEqual(store.stats.bestCombo, 6)
    }

    func testStatsSurviveANewStoreInstance() {
        _ = store.record(summary(score: 77, height: 30))
        let reloaded = PersistenceStore(defaults: defaults)
        XCTAssertEqual(reloaded.stats.highScore, 77)
        XCTAssertEqual(reloaded.stats.highestTier, MaterialTier(level: 30))
    }

    func testSettingsRoundTrip() {
        store.update { $0.soundEnabled = false }
        XCTAssertFalse(store.settings.soundEnabled)
        XCTAssertTrue(store.settings.hapticsEnabled)

        let reloaded = PersistenceStore(defaults: defaults)
        XCTAssertFalse(reloaded.settings.soundEnabled)
    }

    func testDailyScoresKeepTheBestPerDay() {
        store.recordDaily(score: 30, for: "2026-07-25")
        store.recordDaily(score: 12, for: "2026-07-25")
        XCTAssertEqual(store.bestDailyScore(for: "2026-07-25"), 30)
        XCTAssertNil(store.bestDailyScore(for: "2026-07-24"))
    }

    func testDailyHistoryIsBounded() {
        for day in 1...25 {
            store.recordDaily(score: day, for: String(format: "2026-07-%02d", day))
        }
        XCTAssertLessThanOrEqual(store.dailyResults.count, 14)
        XCTAssertNotNil(store.bestDailyScore(for: "2026-07-25"), "the newest day must survive")
    }

    func testRemoveAdsFlagPersists() {
        XCTAssertFalse(store.hasRemovedAds)
        store.hasRemovedAds = true
        XCTAssertTrue(PersistenceStore(defaults: defaults).hasRemovedAds)
    }
}
