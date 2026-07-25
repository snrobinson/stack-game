import SpriteKit
import StackGameCore
import UIKit

/// One block in the tower: three shaded faces and a soft contact shadow.
///
/// Face paths are built in absolute projected coordinates with the node itself
/// parked at the origin, so a block's geometry never depends on its parent's
/// transform. The camera does all the moving.
final class BlockNode: SKNode {

    private let topFace = SKShapeNode()
    private let leftFace = SKShapeNode()
    private let rightFace = SKShapeNode()
    private let shadow = SKSpriteNode(texture: BlockNode.shadowTexture)

    private(set) var footprint: Footprint
    private(set) var tier: MaterialTier
    private let baseY: Double

    /// 0...1 emissive boost carried from the combo that placed this block. Decays
    /// so the glow trails off up the tower instead of banding hard.
    var comboHeat: Double = 0

    init(footprint: Footprint, baseY: Double, tier: MaterialTier) {
        self.footprint = footprint
        self.tier = tier
        self.baseY = baseY
        super.init()

        let texture = MaterialLibrary.detailTexture(for: tier)
        for face in [topFace, leftFace, rightFace] {
            face.lineWidth = 0
            face.fillTexture = texture
            face.isAntialiased = true
            addChild(face)
        }

        // Faces are listed back-to-front. leftFace and rightFace must NOT share a
        // zPosition: the SpriteView is created with .ignoresSiblingOrder for
        // performance, and Apple documents that under that option, sibling nodes
        // with an identical zPosition get an undefined draw order. leftFace and
        // rightFace share an edge (the block's near vertical edge), so a tied,
        // unstable draw order there is exactly what produces a flickering seam
        // gap along that edge — a small notch of background showing through
        // right where the two faces meet. The epsilon is tiny enough (1000x
        // smaller than the gap between adjacent tower levels) that it cannot
        // affect ordering against any other block.
        leftFace.zPosition = 0
        rightFace.zPosition = 0.001
        topFace.zPosition = 1

        shadow.zPosition = -1
        // Deliberately not .multiply: the gradient's RGB is black everywhere and
        // only its alpha fades out, but multiply blend ignores alpha and just
        // multiplies RGB channel-by-channel — multiplying by black zeroes the
        // destination out completely, rendering the sprite's full rectangular
        // bounds as a solid black box instead of a soft-edged shadow. Default
        // alpha blending respects the texture's alpha channel correctly.
        shadow.alpha = 0.55
        addChild(shadow)

        rebuildGeometry()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("BlockNode is created in code only")
    }

    // MARK: - Geometry

    /// Rebuild the paths. Only call when the footprint actually changed —
    /// `CGPath` construction is the expensive part of drawing a block, and the
    /// settled tower never needs it.
    func update(footprint: Footprint) {
        guard footprint != self.footprint else { return }
        self.footprint = footprint
        rebuildGeometry()
    }

    private func rebuildGeometry() {
        topFace.path = IsoProjection.path(
            of: footprint, baseY: baseY, height: Tuning.blockHeight, face: .top
        )
        leftFace.path = IsoProjection.path(
            of: footprint, baseY: baseY, height: Tuning.blockHeight, face: .left
        )
        rightFace.path = IsoProjection.path(
            of: footprint, baseY: baseY, height: Tuning.blockHeight, face: .right
        )

        let rect = IsoProjection.groundEllipseRect(of: footprint, atY: baseY)
        shadow.position = CGPoint(x: rect.midX, y: rect.midY - 6)
        shadow.size = CGSize(width: rect.width * 1.25, height: rect.height * 1.35)

        zPosition = IsoProjection.depth(
            x: footprint.centerX, y: baseY, z: footprint.centerZ
        )
    }

    // MARK: - Shading

    /// Recompute face colours for the current light. Cheap — three colour
    /// assignments, no geometry work.
    func shade(light: SIMD3<Double>, nearDeath: Double) {
        let material = MaterialLibrary.material(for: tier)
        topFace.fillColor = MaterialLibrary.shade(
            material: material, face: .top, light: light,
            comboHeat: comboHeat, nearDeath: nearDeath
        )
        leftFace.fillColor = MaterialLibrary.shade(
            material: material, face: .left, light: light,
            comboHeat: comboHeat, nearDeath: nearDeath
        )
        rightFace.fillColor = MaterialLibrary.shade(
            material: material, face: .right, light: light,
            comboHeat: comboHeat, nearDeath: nearDeath
        )
    }

    /// Cross-fade into a new material band rather than popping.
    func transition(to newTier: MaterialTier, duration: TimeInterval = 0.4) {
        guard newTier != tier else { return }
        tier = newTier
        let texture = MaterialLibrary.detailTexture(for: newTier)
        for face in [topFace, leftFace, rightFace] {
            face.run(.sequence([
                .fadeAlpha(to: 0.55, duration: duration / 2),
                .run { face.fillTexture = texture },
                .fadeAlpha(to: 1.0, duration: duration / 2)
            ]))
        }
    }

    // MARK: - Shared assets

    /// Soft radial falloff for contact shadows. A hard-edged ellipse reads as a
    /// sticker; the gradient is what makes the block feel like it is resting on
    /// something.
    private static let shadowTexture: SKTexture = {
        let size = CGSize(width: 128, height: 128)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let colors = [
                UIColor(white: 0, alpha: 0.95).cgColor,
                UIColor(white: 0, alpha: 0.0).cgColor
            ] as CFArray
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 1]
            ) else { return }
            context.cgContext.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: 64, y: 64), startRadius: 0,
                endCenter: CGPoint(x: 64, y: 64), endRadius: 64,
                options: []
            )
        }
        return SKTexture(image: image)
    }()
}

/// The offcut from an imperfect placement, thrown into the world to tumble away.
///
/// Built with paths relative to its own centre so it can be freely rotated and
/// translated — unlike `BlockNode`, which is pinned to absolute coordinates.
final class DebrisNode: SKNode {

    init(debris: Debris, tier: MaterialTier, light: SIMD3<Double>) {
        super.init()

        let baseY = Double(debris.level) * Tuning.blockHeight
        let centre = IsoProjection.project(
            x: debris.footprint.centerX,
            y: baseY,
            z: debris.footprint.centerZ
        )
        let material = MaterialLibrary.material(for: tier)
        let texture = MaterialLibrary.detailTexture(for: tier)

        for face in IsoProjection.Face.allCases {
            let node = SKShapeNode(
                path: recentre(
                    IsoProjection.path(
                        of: debris.footprint,
                        baseY: baseY,
                        height: Tuning.blockHeight,
                        face: face
                    ),
                    by: centre
                )
            )
            node.lineWidth = 0
            node.fillTexture = texture
            node.fillColor = MaterialLibrary.shade(material: material, face: face, light: light)
            // Same tie as BlockNode's leftFace/rightFace — .left and .right must
            // not share a zPosition under .ignoresSiblingOrder. See the comment
            // there for why.
            switch face {
            case .top: node.zPosition = 1
            case .left: node.zPosition = 0
            case .right: node.zPosition = 0.001
            }
            addChild(node)
        }

        position = centre
        // Half a level in front of the block it was cut from, so the offcut
        // always clears the block it is peeling away from without reaching the
        // level above.
        zPosition = IsoProjection.depth(
            x: debris.footprint.centerX, y: baseY, z: debris.footprint.centerZ
        ) + IsoProjection.depthPerLevel * 0.5

        run(fallAction(towardFarSide: debris.onFarSide))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("DebrisNode is created in code only")
    }

    private func recentre(_ path: CGPath, by offset: CGPoint) -> CGPath {
        var transform = CGAffineTransform(translationX: -offset.x, y: -offset.y)
        return path.copy(using: &transform) ?? path
    }

    /// Tumble out and down, then remove itself. Runs on the presentation layer
    /// only — the engine has already written this piece off.
    private func fallAction(towardFarSide: Bool) -> SKAction {
        let direction: CGFloat = towardFarSide ? 1 : -1
        let drift = SKAction.moveBy(
            x: direction * CGFloat.random(in: 60...130),
            y: -CGFloat.random(in: 900...1300),
            duration: 1.5
        )
        drift.timingMode = .easeIn

        let spin = SKAction.rotate(
            byAngle: direction * CGFloat.random(in: 1.6...3.4),
            duration: 1.5
        )
        let fade = SKAction.sequence([
            .wait(forDuration: 0.9),
            .fadeOut(withDuration: 0.6)
        ])

        return .sequence([
            .group([drift, spin, fade]),
            .removeFromParent()
        ])
    }
}
