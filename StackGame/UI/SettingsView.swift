import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var coordinator: GameCoordinator

    /// Replace with your hosted policy before submission — App Review requires a
    /// reachable privacy policy for any app that serves ads.
    private let privacyPolicyURL = URL(string: "https://example.com/stack-privacy")!

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.black.opacity(0.35), .black.opacity(0.88)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(spacing: 14) {
                        VStack(spacing: 0) {
                            SettingsToggleRow(
                                title: "Sound",
                                systemImage: "speaker.wave.2.fill",
                                isOn: Binding(
                                    get: { coordinator.settings.soundEnabled },
                                    set: { value in
                                        coordinator.updateSettings { $0.soundEnabled = value }
                                    }
                                )
                            )
                            SettingsDivider()
                            SettingsToggleRow(
                                title: "Haptics",
                                systemImage: "iphone.radiowaves.left.and.right",
                                isOn: Binding(
                                    get: { coordinator.settings.hapticsEnabled },
                                    set: { value in
                                        coordinator.updateSettings { $0.hapticsEnabled = value }
                                    }
                                )
                            )
                        }
                        .panelBackground()

                        PurchaseSection(
                            store: coordinator.storeService,
                            onPurchase: { coordinator.purchaseRemoveAds() },
                            onRestore: { coordinator.restorePurchases() }
                        )

                        VStack(spacing: 0) {
                            Button {
                                coordinator.gameCenter.presentLeaderboards()
                            } label: {
                                SettingsRow(title: "Leaderboards", systemImage: "trophy")
                            }
                            SettingsDivider()
                            Button {
                                coordinator.gameCenter.presentAchievements()
                            } label: {
                                SettingsRow(title: "Achievements", systemImage: "rosette")
                            }
                        }
                        .panelBackground()

                        Link(destination: privacyPolicyURL) {
                            SettingsRow(title: "Privacy policy", systemImage: "hand.raised")
                        }
                        .panelBackground()

                        lifetimeStats
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .padding(.bottom, 40)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Button {
                coordinator.showMenu()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
            }
            Spacer()
            Text("Settings")
                .font(Theme.label(13, weight: .bold))
                .tracking(3.0)
                .textCase(.uppercase)
                .foregroundStyle(Theme.ink)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private var lifetimeStats: some View {
        VStack(spacing: 14) {
            Text("Lifetime")
                .font(Theme.label(10))
                .tracking(2.6)
                .textCase(.uppercase)
                .foregroundStyle(Theme.inkTertiary)

            HStack(spacing: 0) {
                StatBlock(value: "\(coordinator.stats.runsPlayed)", caption: "Runs")
                StatBlock(value: "\(coordinator.stats.totalBlocksPlaced)", caption: "Blocks")
                StatBlock(
                    value: "\(coordinator.stats.totalPerfects)",
                    caption: "Perfects",
                    tint: Theme.accent
                )
            }
        }
        .padding(.vertical, 18)
        .panelBackground()
    }
}

/// Split into its own view so it can hold `StoreService` as an `@ObservedObject`.
///
/// `GameCoordinator` owns the store, but SwiftUI does not propagate changes from
/// a nested `ObservableObject` through its parent — read through the coordinator
/// and the price, spinner, and purchased state would all render once and then
/// silently never update again.
private struct PurchaseSection: View {
    @ObservedObject var store: StoreService
    let onPurchase: () -> Void
    let onRestore: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 0) {
                if store.hasRemovedAds {
                    SettingsRow(
                        title: "Ads removed",
                        systemImage: "checkmark.seal.fill",
                        tint: Theme.accent,
                        showsChevron: false
                    )
                } else {
                    Button(action: onPurchase) {
                        SettingsRow(
                            title: "Remove ads",
                            systemImage: "sparkles",
                            trailing: store.isPurchasing ? nil : store.displayPrice,
                            isBusy: store.isPurchasing
                        )
                    }
                    .disabled(store.isPurchasing)
                    SettingsDivider()
                }

                Button(action: onRestore) {
                    SettingsRow(title: "Restore purchases", systemImage: "arrow.clockwise")
                }
            }
            .panelBackground()

            if let error = store.lastError {
                Text(error)
                    .font(Theme.label(12, weight: .regular))
                    .foregroundStyle(Theme.danger)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

// MARK: - Shared rows

struct SettingsRow: View {
    let title: String
    let systemImage: String
    var tint: Color = Theme.ink
    var trailing: String?
    var isBusy = false
    var showsChevron = true

    var body: some View {
        HStack(spacing: 14) {
            SettingsIcon(systemImage, tint: tint == Theme.ink ? Theme.inkSecondary : tint)
            Text(title)
                .font(Theme.label(15, weight: .medium))
                .foregroundStyle(tint)
            Spacer()
            if isBusy {
                ProgressView().tint(Theme.inkSecondary)
            } else if let trailing {
                Text(trailing)
                    .font(Theme.label(14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.inkTertiary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }
}

struct SettingsToggleRow: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            SettingsIcon(systemImage)
            Text(title)
                .font(Theme.label(15, weight: .medium))
                .foregroundStyle(Theme.ink)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Theme.accent)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.panelStroke)
            .frame(height: 1)
            .padding(.leading, 52)
    }
}

private struct SettingsIcon: View {
    let systemImage: String
    var tint: Color = Theme.inkSecondary

    init(_ systemImage: String, tint: Color = Theme.inkSecondary) {
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 22)
    }
}
