import SpriteKit
import UIKit

/// Two-tone backdrop whose hue rotates as the tower climbs.
///
/// Built as a solid sprite plus a second sprite carrying only an alpha ramp, so
/// both stops can be recoloured with `SKAction.colorize` — smooth, animatable,
/// and no texture regeneration per frame.
final class SkyNode: SKNode {

    private let upper = SKSpriteNode()
    private let lower = SKSpriteNode(texture: SkyNode.rampTexture)
    private let vignette = SKSpriteNode(texture: SkyNode.vignetteTexture)

    private var lastAppliedHeight = Int.min

    /// The camera pulls back to 1.16x on milestones, so a sky sized exactly to
    /// the scene would let the black scene background show at the edges during
    /// the one moment the player is being invited to look around.
    private static let coverage: CGFloat = 1.6

    private static func padded(_ size: CGSize) -> CGSize {
        CGSize(width: size.width * coverage, height: size.height * coverage)
    }

    init(size rawSize: CGSize) {
        let size = Self.padded(rawSize)
        super.init()

        upper.size = size
        upper.colorBlendFactor = 1
        upper.zPosition = 0
        addChild(upper)

        lower.size = size
        lower.colorBlendFactor = 1
        lower.zPosition = 1
        addChild(lower)

        vignette.size = size
        vignette.alpha = 0.55
        vignette.zPosition = 2
        vignette.blendMode = .multiply
        addChild(vignette)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SkyNode is created in code only")
    }

    func resize(to rawSize: CGSize) {
        let size = Self.padded(rawSize)
        upper.size = size
        lower.size = size
        vignette.size = size
    }

    /// Recolour for the current tower height.
    ///
    /// Only acts when the height actually moved, so this is safe to call every
    /// frame from the update loop.
    func apply(height: Int, animated: Bool = true) {
        guard height != lastAppliedHeight else { return }
        lastAppliedHeight = height

        let colors = Palette.skyColors(forHeight: height)
        let duration: TimeInterval = animated ? 0.8 : 0

        upper.run(.colorize(with: colors.top, colorBlendFactor: 1, duration: duration))
        lower.run(.colorize(with: colors.bottom, colorBlendFactor: 1, duration: duration))
    }

    // MARK: - Shared assets

    /// Opaque at the bottom, transparent at the top.
    private static let rampTexture: SKTexture = {
        let size = CGSize(width: 4, height: 256)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let colors = [
                UIColor(white: 1, alpha: 0).cgColor,
                UIColor(white: 1, alpha: 1).cgColor
            ] as CFArray
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 1]
            ) else { return }
            context.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: 0, y: 256),
                options: []
            )
        }
        return SKTexture(image: image)
    }()

    /// Darkened corners. Pulls the eye to the middle of the frame, where the
    /// build point is.
    private static let vignetteTexture: SKTexture = {
        let size = CGSize(width: 256, height: 256)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.cgContext.fill(CGRect(origin: .zero, size: size))
            let colors = [
                UIColor(white: 1, alpha: 1).cgColor,
                UIColor(white: 0.35, alpha: 1).cgColor
            ] as CFArray
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0.45, 1]
            ) else { return }
            context.cgContext.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: 128, y: 128), startRadius: 0,
                endCenter: CGPoint(x: 128, y: 128), endRadius: 190,
                options: [.drawsAfterEndLocation]
            )
        }
        return SKTexture(image: image)
    }()
}
