import StackGameCore
import SwiftUI

struct MenuView: View {
    @EnvironmentObject private var coordinator: GameCoordinator

    private var dailyPlayed: Bool {
        coordinator.todaysDailyScore != nil
    }

    var body: some View {
        ZStack {
            // Just enough scrim to hold type legibly over a live scene.
            LinearGradient(
                colors: [.black.opacity(0.15), .black.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 10) {
                    Text("Stack")
                        .font(.system(size: 62, weight: .heavy, design: .rounded))
                        .tracking(6)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.ink)
                        .shadow(color: .black.opacity(0.55), radius: 18, y: 6)

                    Text("Precision is the only currency")
                        .font(Theme.label(12))
                        .tracking(3.2)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.inkTertiary)
                }

                if coordinator.stats.highScore > 0 {
                    VStack(spacing: 2) {
                        Text("\(coordinator.stats.highScore)")
                            .font(Theme.numeral(46))
                            .monospacedDigit()
                            .foregroundStyle(Theme.accent)
                        Text("Best")
                            .font(Theme.label(10))
                            .tracking(2.6)
                            .textCase(.uppercase)
                            .foregroundStyle(Theme.inkTertiary)
                    }
                    .padding(.top, 30)
                }

                Spacer()

                VStack(spacing: 12) {
                    Button("Play") { coordinator.startRun() }
                        .buttonStyle(PrimaryButtonStyle())

                    Button {
                        coordinator.startRun(daily: true)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "calendar")
                            Text(dailyPlayed ? "Daily · \(coordinator.todaysDailyScore ?? 0)" : "Daily Challenge")
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    HStack(spacing: 12) {
                        Button {
                            coordinator.gameCenter.presentLeaderboards()
                        } label: {
                            Image(systemName: "trophy")
                            Text("Ranks")
                        }
                        .buttonStyle(SecondaryButtonStyle())

                        Button {
                            coordinator.showSettings()
                        } label: {
                            Image(systemName: "gearshape")
                            Text("Settings")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }
                .padding(.horizontal, 32)

                if coordinator.stats.runsPlayed > 0 {
                    HStack(spacing: 0) {
                        StatBlock(
                            value: "\(coordinator.stats.bestHeight)",
                            caption: "Tallest"
                        )
                        StatBlock(
                            value: "\(coordinator.stats.bestCombo)×",
                            caption: "Best streak",
                            tint: Theme.accent
                        )
                        StatBlock(
                            value: coordinator.stats.highestTier.displayName,
                            caption: "Reached"
                        )
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 8)
                    .panelBackground()
                    .padding(.horizontal, 32)
                    .padding(.top, 22)
                }

                Spacer()
                    .frame(height: 34)
            }
        }
    }
}
