import Foundation

public enum PlacementOutcome: String, Sendable, Hashable, Codable {
    /// Landed inside the perfect tolerance. Nothing is lost.
    case perfect
    /// Landed with partial overlap. The overhang is cut away.
    case sliced
    /// Missed the tower entirely, or left less than a viable sliver.
    case missed
}

public enum ScoreCalculator {

    /// Points awarded for a placement.
    ///
    /// A perfect is worth its combo depth on top of the base point, capped at
    /// `Tuning.maxComboBonus`. That makes score growth superlinear in streak
    /// length, so the leaderboard sorts by mastery rather than by patience: a
    /// 40-block run carrying three long streaks should — and does — beat a
    /// sloppy 60-block run.
    ///
    /// - Parameter combo: the streak length *after* this placement.
    public static func points(outcome: PlacementOutcome, combo: Int) -> Int {
        switch outcome {
        case .missed:
            return 0
        case .sliced:
            return 1
        case .perfect:
            return 1 + min(max(combo, 0), Tuning.maxComboBonus)
        }
    }

    /// Total for a whole run, used by tests and the tuning harness to compare
    /// scoring shapes without stepping the engine.
    public static func total(for outcomes: [PlacementOutcome]) -> Int {
        var combo = 0
        var score = 0
        for outcome in outcomes {
            if outcome == .perfect {
                combo += 1
            } else {
                combo = 0
            }
            score += points(outcome: outcome, combo: combo)
        }
        return score
    }
}
