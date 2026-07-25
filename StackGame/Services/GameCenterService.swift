import GameKit
import StackGameCore
import UIKit

/// Game Center leaderboards and achievements.
///
/// Every call is a no-op when the player is not authenticated, so the rest of the
/// app can submit unconditionally and never branch on sign-in state.
final class GameCenterService: NSObject, ObservableObject {

    enum LeaderboardID {
        static let highScore = "com.stackgame.leaderboard.highscore"
        static let longestStreak = "com.stackgame.leaderboard.streak"
        static let dailyChallenge = "com.stackgame.leaderboard.daily"
    }

    enum AchievementID {
        static let firstStreak = "com.stackgame.achievement.streak8"
        static let reachObsidian = "com.stackgame.achievement.obsidian"
        static let hundredBlocks = "com.stackgame.achievement.height100"
    }

    @Published private(set) var isAuthenticated = false

    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            if let viewController {
                Self.topViewController()?.present(viewController, animated: true)
                return
            }
            if error != nil {
                self?.isAuthenticated = false
                return
            }
            self?.isAuthenticated = GKLocalPlayer.local.isAuthenticated
        }
    }

    // MARK: - Submission

    func submit(_ summary: RunSummary) {
        guard isAuthenticated else { return }

        var boards = [LeaderboardID.highScore]
        if summary.isDailyChallenge { boards.append(LeaderboardID.dailyChallenge) }

        GKLeaderboard.submitScore(
            summary.score,
            context: 0,
            player: GKLocalPlayer.local,
            leaderboardIDs: boards
        ) { _ in }

        GKLeaderboard.submitScore(
            summary.bestCombo,
            context: 0,
            player: GKLocalPlayer.local,
            leaderboardIDs: [LeaderboardID.longestStreak]
        ) { _ in }

        reportAchievements(for: summary)
    }

    private func reportAchievements(for summary: RunSummary) {
        var achievements: [GKAchievement] = []

        // Achievements report percent-complete, so partial progress toward each
        // one shows in the Game Center UI rather than appearing from nowhere.
        achievements.append(
            achievement(
                AchievementID.firstStreak,
                percent: min(100, Double(summary.bestCombo) / 8.0 * 100)
            )
        )
        achievements.append(
            achievement(
                AchievementID.hundredBlocks,
                percent: min(100, Double(summary.height) / 100.0 * 100)
            )
        )
        achievements.append(
            achievement(
                AchievementID.reachObsidian,
                percent: min(100, Double(summary.height) / Double(MaterialTier.obsidian.firstLevel) * 100)
            )
        )

        GKAchievement.report(achievements) { _ in }
    }

    private func achievement(_ identifier: String, percent: Double) -> GKAchievement {
        let achievement = GKAchievement(identifier: identifier)
        achievement.percentComplete = percent
        achievement.showsCompletionBanner = true
        return achievement
    }

    // MARK: - Presentation

    func presentLeaderboards() {
        guard isAuthenticated else { return }
        let viewController = GKGameCenterViewController(state: .leaderboards)
        viewController.gameCenterDelegate = self
        Self.topViewController()?.present(viewController, animated: true)
    }

    func presentAchievements() {
        guard isAuthenticated else { return }
        let viewController = GKGameCenterViewController(state: .achievements)
        viewController.gameCenterDelegate = self
        Self.topViewController()?.present(viewController, animated: true)
    }

    /// Walks to whatever is actually on screen. Game Center and the ad SDKs both
    /// need a real presenting controller, which SwiftUI does not hand out.
    static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }

        var controller = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}

extension GameCenterService: GKGameCenterControllerDelegate {
    func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        gameCenterViewController.dismiss(animated: true)
    }
}
