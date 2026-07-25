import SwiftUI

/// Shared visual language for everything outside the SpriteKit scene.
///
/// The rule the UI follows: the tower is the subject, so the interface stays out
/// of its way. Type is thin and letterspaced, panels are dark glass, and exactly
/// one accent colour — the gold from the obsidian tier — carries every moment
/// that matters. One accent used sparingly reads as expensive; three read as a
/// toy.
enum Theme {

    static let accent = Color(red: 1.00, green: 0.76, blue: 0.34)
    static let danger = Color(red: 0.96, green: 0.36, blue: 0.32)
    static let ink = Color.white
    static let inkSecondary = Color.white.opacity(0.62)
    static let inkTertiary = Color.white.opacity(0.38)

    static let panel = Color.white.opacity(0.07)
    static let panelStroke = Color.white.opacity(0.14)

    /// Big numerals. Rounded and heavy so the score reads instantly at a glance
    /// mid-run, which is the only time anyone looks at it.
    static func numeral(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }

    /// Small uppercase labels.
    static func label(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension View {
    /// Dark glass card used for every panel in the app.
    func panelBackground(cornerRadius: CGFloat = 24) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Theme.panel)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Theme.panelStroke, lineWidth: 1)
                )
        )
    }

    func letterspaced(_ amount: CGFloat = 2.4) -> some View {
        tracking(amount)
    }
}

/// The app's one prominent button.
struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.label(17, weight: .bold))
            .tracking(2.4)
            .textCase(.uppercase)
            .foregroundStyle(Color.black.opacity(0.88))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                Capsule(style: .continuous)
                    .fill(tint)
                    .shadow(color: tint.opacity(0.45), radius: 22, y: 8)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Quieter sibling for secondary actions.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.label(15, weight: .semibold))
            .tracking(2.0)
            .textCase(.uppercase)
            .foregroundStyle(Theme.ink.opacity(0.9))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                Capsule(style: .continuous)
                    .fill(Theme.panel)
                    .overlay(Capsule(style: .continuous).strokeBorder(Theme.panelStroke, lineWidth: 1))
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// A labelled figure, used everywhere stats appear.
struct StatBlock: View {
    let value: String
    let caption: String
    var tint: Color = Theme.ink

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(Theme.numeral(26))
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(caption)
                .font(Theme.label(10))
                .tracking(1.6)
                .textCase(.uppercase)
                .foregroundStyle(Theme.inkTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}
