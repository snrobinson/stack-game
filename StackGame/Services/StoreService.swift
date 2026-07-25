import Foundation
import StoreKit

/// StoreKit 2 wrapper for the single non-consumable, "Remove Ads".
///
/// One product, one entitlement, no subscriptions — so the whole surface is
/// load, purchase, restore, and observe.
@MainActor
final class StoreService: ObservableObject {

    static let removeAdsProductID = "com.stackgame.removeads"

    @Published private(set) var removeAdsProduct: Product?
    @Published private(set) var hasRemovedAds = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var lastError: String?

    private let store: PersistenceStore
    private var updatesTask: Task<Void, Never>?

    init(store: PersistenceStore) {
        self.store = store
        // Trust the cached flag for the first frame so the UI does not flicker
        // ads-on then ads-off while StoreKit is queried.
        self.hasRemovedAds = store.hasRemovedAds
        listenForTransactions()
    }

    deinit {
        updatesTask?.cancel()
    }

    // MARK: - Loading

    func loadProducts() async {
        do {
            let products = try await Product.products(for: [Self.removeAdsProductID])
            removeAdsProduct = products.first
        } catch {
            lastError = "Could not reach the App Store."
        }
        await refreshEntitlements()
    }

    /// StoreKit is the source of truth; the cached flag follows it.
    func refreshEntitlements() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == Self.removeAdsProductID && transaction.revocationDate == nil {
                owned = true
            }
        }
        hasRemovedAds = owned
        store.hasRemovedAds = owned
    }

    // MARK: - Purchase

    func purchaseRemoveAds() async {
        guard let product = removeAdsProduct else {
            lastError = "Product unavailable."
            return
        }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    lastError = "Could not verify that purchase."
                    return
                }
                await transaction.finish()
                await refreshEntitlements()

            case .userCancelled:
                // Not an error. Say nothing.
                break

            case .pending:
                // Ask To Buy and similar. The updates listener will pick it up
                // if and when it is approved.
                lastError = "Purchase pending approval."

            @unknown default:
                break
            }
        } catch {
            lastError = "Purchase failed. Please try again."
        }
    }

    /// Required by App Review for any non-consumable.
    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            lastError = "Could not restore purchases."
        }
    }

    // MARK: - Transaction updates

    /// Catches purchases made on another device, Ask To Buy approvals, and
    /// refunds. Without this a purchase completed elsewhere would never unlock
    /// here.
    private func listenForTransactions() {
        updatesTask = Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await transaction.finish()
                await self?.refreshEntitlements()
            }
        }
    }

    var displayPrice: String {
        removeAdsProduct?.displayPrice ?? "—"
    }
}
