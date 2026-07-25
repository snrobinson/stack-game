import AppTrackingTransparency
import Foundation
import UIKit

/// The app's entire view of advertising.
///
/// Everything ad-related sits behind this protocol so that **the game builds and
/// runs with no ad SDK linked at all**. `NoOpAdsProvider` is the default;
/// dropping in AdMob later means adding one conforming type and changing one
/// line in `GameCoordinator`. Development stays fast, the test target stays
/// clean, and a third-party SDK never becomes load-bearing.
protocol AdsProvider: AnyObject {
    /// Whether a rewarded ad can be shown right now.
    var isRewardedReady: Bool { get }
    func preload()
    /// - Parameter completion: `true` only if the reward was actually earned.
    func showRewarded(completion: @escaping (Bool) -> Void)
    func showInterstitial(completion: @escaping () -> Void)
}

/// Default provider. Reports nothing available, so every call site degrades to
/// the no-ads path.
final class NoOpAdsProvider: AdsProvider {
    var isRewardedReady: Bool { false }
    func preload() {}
    func showRewarded(completion: @escaping (Bool) -> Void) { completion(false) }
    func showInterstitial(completion: @escaping () -> Void) { completion() }
}

/// Decides *when* ads are allowed to appear. Kept separate from the provider so
/// the policy is testable and reviewable without an SDK in the loop.
final class AdsCoordinator {

    private let provider: AdsProvider
    private let store: PersistenceStore
    private var gameOversSinceInterstitial = 0

    /// Show an interstitial every Nth game over. Frequent enough to matter,
    /// rare enough that it does not interrupt the "one more run" loop that the
    /// whole design depends on.
    private let interstitialInterval = 3

    init(provider: AdsProvider, store: PersistenceStore) {
        self.provider = provider
        self.store = store
        provider.preload()
    }

    var isRewardedReady: Bool {
        !store.hasRemovedAds && provider.isRewardedReady
    }

    /// Offer the player their run back.
    func showRewardedContinue(completion: @escaping (Bool) -> Void) {
        guard !store.hasRemovedAds else {
            // Someone who paid to remove ads has already bought the reward.
            completion(true)
            return
        }
        provider.showRewarded(completion: completion)
    }

    func handleGameOver(completion: @escaping () -> Void) {
        guard !store.hasRemovedAds else {
            completion()
            return
        }
        gameOversSinceInterstitial += 1
        guard gameOversSinceInterstitial >= interstitialInterval else {
            completion()
            return
        }
        gameOversSinceInterstitial = 0
        provider.showInterstitial(completion: completion)
    }

    // MARK: - Tracking permission

    /// Ask for tracking permission **after the first game over**, never at launch.
    ///
    /// A player who has just finished a run understands what the app is and has
    /// some reason to say yes. The same prompt on a cold launch, before any value
    /// has been delivered, is the classic way to burn the one chance iOS gives
    /// you — the permission can only be requested once.
    func requestTrackingPermissionIfNeeded() {
        guard #available(iOS 14, *) else { return }
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }

        // The prompt is refused outright if the app is not frontmost.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard UIApplication.shared.applicationState == .active else { return }
            ATTrackingManager.requestTrackingAuthorization { _ in }
        }
    }
}
