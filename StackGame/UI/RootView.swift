import SpriteKit
import SwiftUI
import UIKit

/// Hosts the scene and layers whichever screen is current on top of it.
///
/// The scene is never torn down between screens — the menu and the game-over
/// card both sit over a live, gently drifting tower. Cutting to a flat colour
/// would throw away the best-looking thing in the app.
struct RootView: View {
    @EnvironmentObject private var coordinator: GameCoordinator

    var body: some View {
        ZStack {
            SpriteView(
                scene: coordinator.scene,
                options: [.ignoresSiblingOrder],
                debugOptions: []
            )
            .ignoresSafeArea()

            switch coordinator.screen {
            case .playing:
                HUDView(snapshot: coordinator.snapshot)
                    .transition(.opacity)

            case .menu:
                MenuView()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))

            case .gameOver(let summary):
                GameOverView(summary: summary)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))

            case .settings:
                SettingsView()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: coordinator.screen)
        .preferredColorScheme(.dark)
    }
}

/// In-run overlay. Deliberately sparse: score, streak, and material band.
struct HUDView: View {
    let snapshot: GameSnapshot

    var body: some View {
        VStack {
            Text("\(snapshot.score)")
                .font(Theme.numeral(76))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: snapshot.score)
                .padding(.top, 12)

            // The combo pill only exists while a streak does. Persistent chrome
            // showing "0" would make the streak feel like a stat instead of an
            // event.
            if snapshot.combo > 1 {
                ComboPill(combo: snapshot.combo)
                    .transition(.scale.combined(with: .opacity))
            }

            Spacer()

            HStack(spacing: 10) {
                // The one place the UI names a material is the one place it is
                // allowed to borrow that material's colour — it turns the band
                // you are in into something you can see at a glance rather than
                // a word you have to read.
                Text(snapshot.tier.displayName)
                    .font(Theme.label(11))
                    .tracking(2.4)
                    .textCase(.uppercase)
                    .foregroundStyle(Color(Palette.tierTint(for: snapshot.tier)))

                Text("·")
                    .foregroundStyle(Theme.inkTertiary)

                Text("\(snapshot.height)")
                    .font(Theme.label(11, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.inkSecondary)

                Text("blocks")
                    .font(Theme.label(11))
                    .tracking(2.0)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.inkTertiary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .panelBackground(cornerRadius: 18)
            .padding(.bottom, 28)
        }
        .animation(.easeInOut(duration: 0.5), value: snapshot.tier)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: snapshot.combo)
        .allowsHitTesting(false)
    }
}

private struct ComboPill: View {
    let combo: Int

    private var isRegrowthImminent: Bool {
        combo % 8 == 7
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "flame.fill")
                .font(.system(size: 13, weight: .bold))
            Text("\(combo)×")
                .font(Theme.numeral(19))
                .monospacedDigit()
            // Telegraph the regrowth one step early. Knowing the reward is one
            // placement away is what makes the eighth perfect worth holding your
            // breath for.
            if isRegrowthImminent {
                Text("next grows")
                    .font(Theme.label(10, weight: .bold))
                    .tracking(1.4)
                    .textCase(.uppercase)
            }
        }
        .foregroundStyle(Color.black.opacity(0.85))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(Theme.accent)
                .shadow(color: Theme.accent.opacity(0.6), radius: 16, y: 4)
        )
        .padding(.top, 6)
    }
}
