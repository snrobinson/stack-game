import Foundation
import StackGameCore

/// Lifetime statistics, surfaced on the menu so progress is visible between runs.
struct RunStats: Codable, Equatable {
    var highScore: Int = 0
    var bestHeight: Int = 0
    var bestCombo: Int = 0
    var totalBlocksPlaced: Int = 0
    var totalPerfects: Int = 0
    var runsPlayed: Int = 0
    var highestTierRaw: Int = 0

    var highestTier: MaterialTier {
        MaterialTier(rawValue: highestTierRaw) ?? .concrete
    }
}

struct Settings: Codable, Equatable {
    var soundEnabled = true
    var hapticsEnabled = true
}

/// Local persistence.
///
/// `UserDefaults` is the right tool here: a few hundred bytes of scalar state,
/// no relationships, no queries. Note that this is the reason the app needs a
/// privacy manifest entry — `UserDefaults` is a required-reason API, declared in
/// `PrivacyInfo.xcprivacy` under `CA92.1`.
final class PersistenceStore {

    private enum Key {
        static let stats = "stack.stats.v1"
        static let settings = "stack.settings.v1"
        static let removeAds = "stack.removeAds.v1"
        static let dailyResults = "stack.daily.v1"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Stats

    private(set) lazy var stats: RunStats = load(Key.stats) ?? RunStats()

    /// Fold a finished run into the lifetime totals.
    ///
    /// - Returns: `true` when the run set a new high score, so the caller can
    ///   celebrate it.
    @discardableResult
    func record(_ summary: RunSummary) -> Bool {
        var updated = stats
        let isNewBest = summary.score > updated.highScore

        updated.highScore = max(updated.highScore, summary.score)
        updated.bestHeight = max(updated.bestHeight, summary.height)
        updated.bestCombo = max(updated.bestCombo, summary.bestCombo)
        updated.totalBlocksPlaced += summary.height
        updated.totalPerfects += summary.perfectCount
        updated.runsPlayed += 1
        updated.highestTierRaw = max(updated.highestTierRaw, summary.tierReached.rawValue)

        stats = updated
        save(updated, to: Key.stats)
        return isNewBest
    }

    // MARK: - Settings

    private(set) lazy var settings: Settings = load(Key.settings) ?? Settings()

    func update(_ transform: (inout Settings) -> Void) {
        var copy = settings
        transform(&copy)
        settings = copy
        save(copy, to: Key.settings)
    }

    // MARK: - Purchases

    /// Mirrors the StoreKit entitlement so the UI does not have to block on a
    /// transaction lookup at launch. StoreKit remains the source of truth; this
    /// is a cache, and `StoreService` refreshes it.
    var hasRemovedAds: Bool {
        get { defaults.bool(forKey: Key.removeAds) }
        set { defaults.set(newValue, forKey: Key.removeAds) }
    }

    // MARK: - Daily challenge

    private(set) lazy var dailyResults: [String: Int] = load(Key.dailyResults) ?? [:]

    func bestDailyScore(for identifier: String) -> Int? {
        dailyResults[identifier]
    }

    func recordDaily(score: Int, for identifier: String) {
        var results = dailyResults
        results[identifier] = max(results[identifier] ?? 0, score)

        // Keep a fortnight. The history is only used to grey out days already
        // played, so unbounded growth buys nothing.
        if results.count > 14 {
            for key in results.keys.sorted().dropLast(14) {
                results.removeValue(forKey: key)
            }
        }
        dailyResults = results
        save(results, to: Key.dailyResults)
    }

    // MARK: - Codable plumbing

    private func load<T: Decodable>(_ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, to key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
