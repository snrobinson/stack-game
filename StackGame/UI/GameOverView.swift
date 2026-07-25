import StackGameCore
import SwiftUI

struct GameOverView: View {
    let summary: RunSummary
    @EnvironmentObject private var coordinator: GameCoordinator

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.black.opacity(0.35), .black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 18) {
                    if coordinator.isNewHighScore {
                        Text("New Best")
                            .font(Theme.label(11, weight: .bold))
                            .tracking(3.2)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.black.opacity(0.85))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Theme.accent))
                    } else {
                        Text(summary.isDailyChallenge ? "Daily Challenge" : "Run Over")
                            .font(Theme.label(11))
                            .tracking(3.2)
                            .textCase(.uppercase)
                            .foregroundStyle(Theme.inkTertiary)
                    }

                    Text("\(summary.score)")
                        .font(Theme.numeral(82))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                        .shadow(color: .black.opacity(0.5), radius: 16, y: 6)

                    HStack(spacing: 0) {
                        StatBlock(value: "\(summary.height)", caption: "Blocks")
                        StatBlock(
                            value: "\(summary.bestCombo)×",
                            caption: "Best streak",
                            tint: Theme.accent
                        )
                        StatBlock(value: "\(summary.perfectCount)", caption: "Perfects")
                    }
                    .padding(.vertical, 18)
                    .panelBackground()
                }
                .padding(.horizontal, 32)

                Spacer()

                VStack(spacing: 12) {
                    // Offered only once per run, and only when an ad is actually
                    // ready. A "continue" button that fails to deliver is worse
                    // than no button.
                    if coordinator.canContinue {
                        Button {
                            coordinator.watchAdToContinue()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "play.rectangle.fill")
                                Text("Continue this run")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())

                        Button("Retry") { coordinator.retry() }
                            .buttonStyle(SecondaryButtonStyle())
                    } else {
                        Button("Retry") { coordinator.retry() }
                            .buttonStyle(PrimaryButtonStyle())
                    }

                    Button("Menu") { coordinator.showMenu() }
                        .buttonStyle(SecondaryButtonStyle())
                }
                .padding(.horizontal, 32)

                Spacer()
                    .frame(height: 34)
            }
        }
    }
}
