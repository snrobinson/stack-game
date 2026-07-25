import SpriteKit
import StackGameCore
import SwiftUI

/// Owns the services and mediates between the SpriteKit scene and SwiftUI.
///
/// The scene knows nothing about screens; this decides what the player sees.
@MainActor
final class GameCoordinator: ObservableObject {

    enum Screen: Equatable {
        case menu
        case playing
        case gameOver(RunSummary)
        case settings
    }

    @Published private(set) var screen: Screen = .menu
    @Published private(set) var snapshot = GameSnapshot.empty
    @Published private(set) var stats: RunStats
    @Published private(set) var canContinue = false
    @Published private(set) var isNewHighScore = false
    @Published var settings: Settings

    let store: PersistenceStore
    let gameCenter = GameCenterService()
    let storeService: StoreService

    private let audio = AudioEngine()
    private let haptics = HapticsEngine()
    private let ads: AdsCoordinator

    lazy var scene: GameScene = {
        let scene = GameScene()
        scene.scaleMode = .resizeFill
        scene.gameDelegate = self
        scene.audio = audio
        scene.haptics = haptics
        return scene
    }()

    init(store: PersistenceStore = PersistenceStore()) {
        self.store = store
        self.stats = store.stats
        self.settings = store.settings
        self.storeService = StoreService(store: store)

        // Swap `NoOpAdsProvider()` for the AdMob provider when the SDK is added.
        // Nothing else in the app changes.
        self.ads = AdsCoordinator(provider: NoOpAdsProvider(), store: store)

        applySettings()
        gameCenter.authenticate()

        Task { await storeService.loadProducts() }
    }

    // MARK: - Navigation

    func startRun(daily: Bool = false) {
        isNewHighScore = false
        canContinue = false
        scene.startRun(daily: daily)
        screen = .playing
    }

    func showMenu() {
        screen = .menu
    }

    func showSettings() {
        screen = .settings
    }

    func retry() {
        startRun(daily: false)
    }

    // MARK: - Continue

    /// Watch a rewarded ad to resume the run.
    func watchAdToContinue() {
        guard canContinue else { return }
        canContinue = false

        ads.showRewardedContinue { [weak self] earned in
            Task { @MainActor in
                guard let self else { return }
                guard earned else { return }
                self.scene.continueRun()
                self.screen = .playing
            }
        }
    }

    // MARK: - Settings

    func updateSettings(_ transform: (inout Settings) -> Void) {
        transform(&settings)
        store.update { $0 = self.settings }
        applySettings()
    }

    private func applySettings() {
        audio.isMuted = !settings.soundEnabled
        haptics.isEnabled = settings.hapticsEnabled
    }

    // MARK: - Purchases

    func purchaseRemoveAds() {
        Task { await storeService.purchaseRemoveAds() }
    }

    func restorePurchases() {
        Task { await storeService.restorePurchases() }
    }

    // MARK: - Daily challenge

    var dailyIdentifier: String { DailySeed.identifier() }

    var todaysDailyScore: Int? {
        store.bestDailyScore(for: dailyIdentifier)
    }
}

// MARK: - GameSceneDelegate

extension GameCoordinator: GameSceneDelegate {

    nonisolated func gameScene(_ scene: GameScene, didUpdate snapshot: GameSnapshot) {
        Task { @MainActor in
            self.snapshot = snapshot
        }
    }

    nonisolated func gameSceneDidOfferContinue(_ scene: GameScene) {
        Task { @MainActor in
            self.canContinue = self.ads.isRewardedReady
        }
    }

    nonisolated func gameScene(_ scene: GameScene, didEndRunWith summary: RunSummary) {
        Task { @MainActor in
            self.isNewHighScore = self.store.record(summary)
            self.stats = self.store.stats

            if summary.isDailyChallenge, let identifier = summary.dailyIdentifier {
                self.store.recordDaily(score: summary.score, for: identifier)
            }

            self.gameCenter.submit(summary)

            // First game over is where the tracking prompt belongs — the player
            // has now seen what the app is.
            self.ads.requestTrackingPermissionIfNeeded()

            self.ads.handleGameOver {
                Task { @MainActor in
                    self.screen = .gameOver(summary)
                }
            }
        }
    }
}
