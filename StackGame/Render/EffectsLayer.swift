import SpriteKit
import StackGameCore
import UIKit

/// Particles, bloom, and hitstop — everything that makes a placement land.
final class EffectsLayer: SKNode {

    /// Blocks live inside this so bloom can be applied to the tower without
    /// smearing the HUD.
    let towerLayer = SKEffectNode()

    private var bloomFilter: CIFilter?

    override init() {
        super.init()

        // Bloom is off until a streak earns it. `shouldEnableEffects = false`
        // makes an SKEffectNode a pass-through with no render-target cost, which
        // matters because full-scene bloom is expensive on older devices and the
        // common case is combo zero.
        bloomFilter = CIFilter(name: "CIBloom", parameters: [
            kCIInputRadiusKey: 14.0,
            kCIInputIntensityKey: 0.0
        ])
        towerLayer.filter = bloomFilter
        towerLayer.shouldEnableEffects = false
        towerLayer.shouldRasterize = false
        addChild(towerLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("EffectsLayer is created in code only")
    }

    // MARK: - Bloom

    /// Drive glow from streak length, so a long run literally makes the screen
    /// brighter.
    func setComboIntensity(_ combo: Int) {
        let normalized = min(1.0, Double(combo) / 10.0)
        guard normalized > 0.01 else {
            towerLayer.shouldEnableEffects = false
            return
        }
        towerLayer.shouldEnableEffects = true
        bloomFilter?.setValue(normalized * 1.1, forKey: kCIInputIntensityKey)
        bloomFilter?.setValue(10 + normalized * 16, forKey: kCIInputRadiusKey)
    }

    // MARK: - Bursts

    /// Expanding ring at the seam. The signature reward for a perfect.
    func perfectBurst(at point: CGPoint, combo: Int, zPosition: CGFloat) {
        let ring = SKShapeNode(circleOfRadius: 12)
        ring.position = point
        ring.zPosition = zPosition + 5
        ring.strokeColor = Palette.perfectFlash
        ring.lineWidth = 4
        ring.fillColor = .clear
        ring.alpha = 0.95
        addChild(ring)

        let grow = SKAction.scale(to: 4.5 + CGFloat(min(combo, 8)) * 0.4, duration: 0.45)
        grow.timingMode = .easeOut
        ring.run(.sequence([
            .group([grow, .fadeOut(withDuration: 0.45)]),
            .removeFromParent()
        ]))

        let sparks = SKEmitterNode()
        sparks.particleTexture = EffectsLayer.dotTexture
        sparks.position = point
        // +5.5, not +5: tied with ring's zPosition would leave their draw order
        // undefined under .ignoresSiblingOrder (see BlockNode's leftFace comment
        // for the general issue). Lower stakes here since both are transient,
        // but free to fix while touching this class of bug.
        sparks.zPosition = zPosition + 5.5
        sparks.particleBirthRate = 900
        sparks.numParticlesToEmit = 14 + min(combo, 8) * 3
        sparks.particleLifetime = 0.55
        sparks.particleLifetimeRange = 0.25
        sparks.particleSpeed = 190
        sparks.particleSpeedRange = 120
        sparks.emissionAngleRange = .pi * 2
        sparks.particleAlpha = 0.9
        sparks.particleAlphaSpeed = -1.8
        sparks.particleScale = 0.22
        sparks.particleScaleRange = 0.12
        sparks.particleScaleSpeed = -0.25
        sparks.particleColor = Palette.comboGlow
        sparks.particleColorBlendFactor = 1
        sparks.particleBlendMode = .add
        sparks.yAcceleration = -320
        addChild(sparks)
        sparks.run(.sequence([.wait(forDuration: 1.2), .removeFromParent()]))
    }

    /// Dust at the cut line when a slice is taken.
    func sliceDust(at point: CGPoint, zPosition: CGFloat) {
        let dust = SKEmitterNode()
        dust.particleTexture = EffectsLayer.dotTexture
        dust.position = point
        dust.zPosition = zPosition + 4
        dust.particleBirthRate = 400
        dust.numParticlesToEmit = 18
        dust.particleLifetime = 0.9
        dust.particleLifetimeRange = 0.4
        dust.particleSpeed = 70
        dust.particleSpeedRange = 50
        dust.emissionAngleRange = .pi * 2
        dust.particleAlpha = 0.42
        dust.particleAlphaSpeed = -0.5
        dust.particleScale = 0.5
        dust.particleScaleRange = 0.3
        dust.particleScaleSpeed = 0.35
        dust.particleColor = UIColor(white: 0.85, alpha: 1)
        dust.particleColorBlendFactor = 1
        dust.yAcceleration = -60
        addChild(dust)
        dust.run(.sequence([.wait(forDuration: 1.6), .removeFromParent()]))
    }

    /// Slow ambient drift, for parallax and to keep the frame alive between
    /// placements.
    func makeAmbientMotes(in size: CGSize) -> SKEmitterNode {
        let motes = SKEmitterNode()
        motes.particleTexture = EffectsLayer.dotTexture
        motes.particleBirthRate = 6
        motes.particleLifetime = 14
        motes.particlePositionRange = CGVector(dx: size.width * 1.4, dy: size.height * 1.4)
        motes.particleSpeed = 10
        motes.particleSpeedRange = 8
        motes.emissionAngle = .pi / 2
        motes.emissionAngleRange = .pi
        motes.particleAlpha = 0.16
        motes.particleAlphaRange = 0.1
        motes.particleScale = 0.13
        motes.particleScaleRange = 0.09
        motes.particleColor = .white
        motes.particleColorBlendFactor = 1
        motes.particleBlendMode = .add
        motes.advanceSimulationTime(8)
        return motes
    }

    // MARK: - Shared assets

    static let dotTexture: SKTexture = {
        let size = CGSize(width: 32, height: 32)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let colors = [
                UIColor(white: 1, alpha: 1).cgColor,
                UIColor(white: 1, alpha: 0).cgColor
            ] as CFArray
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 1]
            ) else { return }
            context.cgContext.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: 16, y: 16), startRadius: 0,
                endCenter: CGPoint(x: 16, y: 16), endRadius: 16,
                options: []
            )
        }
        return SKTexture(image: image)
    }()
}
