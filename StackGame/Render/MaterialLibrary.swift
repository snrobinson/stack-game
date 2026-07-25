import SpriteKit
import StackGameCore
import UIKit
import simd

/// Surface definition for one material band.
struct Material {
    var albedo: SIMD3<Double>
    /// Specular colour. Dielectrics reflect white; metals tint by their albedo,
    /// which is most of what separates aluminum from marble to the eye.
    var specularTint: SIMD3<Double>
    var specularStrength: Double
    /// Blinn-Phong exponent. Higher is a tighter, glossier highlight.
    var specularSharpness: Double
    var ambient: Double
    var alpha: Double
    var detail: DetailPattern
    /// How strongly this material picks up the combo glow.
    var emissiveResponse: Double

    enum DetailPattern {
        case noise
        case veins
        case brushed
        case frosted
        case glints
    }
}

/// Materials, lighting, and the procedural surface detail that sells them.
///
/// ## Why there is no SKLightNode here
///
/// The plan called for `SKLightNode` against normal maps. That works for
/// sprites, but an isometric block face is a *parallelogram*, and SpriteKit
/// sprites cannot be sheared — `SKNode` exposes scale and rotation, not a full
/// affine transform. Drawing the faces as sprites would mean giving up correct
/// geometry, which is not a trade worth making.
///
/// The saving grace: each face is flat, the key light is directional, and the
/// camera is orthographic. Under those three conditions the diffuse and
/// specular terms are *constant across the whole face* — per-pixel lighting and
/// per-face lighting produce identical output. So the faces are `SKShapeNode`s
/// with analytically shaded fill colours, and the normal map's real job (surface
/// detail: veining, brushing, glints) is baked into a procedural fill texture.
///
/// Same look, correct geometry, and no shader that cannot be unit-tested.
/// If profiling ever shows shape nodes to be the bottleneck, the upgrade path is
/// `SKSpriteNode` with `SKWarpGeometryGrid` rather than reintroducing lighting.
enum MaterialLibrary {

    /// Direction *toward* the key light. Sits up and to the front-left so all
    /// three visible faces catch different amounts of it.
    static let baseLightDirection = simd_normalize(SIMD3<Double>(-0.50, 0.85, -0.35))

    /// Direction from a surface *toward* the camera, matching the projection's
    /// `(-x, +y, -z)` viewpoint.
    static let viewDirection = simd_normalize(SIMD3<Double>(-1, 1, -1))

    static func material(for tier: MaterialTier) -> Material {
        switch tier {
        case .concrete:
            return Material(
                albedo: SIMD3(0.72, 0.70, 0.66),
                specularTint: SIMD3(1, 1, 1),
                specularStrength: 0.05,
                specularSharpness: 6,
                ambient: 0.42,
                alpha: 1.0,
                detail: .noise,
                emissiveResponse: 0.5
            )
        case .marble:
            return Material(
                albedo: SIMD3(0.94, 0.94, 0.96),
                specularTint: SIMD3(1, 1, 1),
                specularStrength: 0.55,
                specularSharpness: 48,
                ambient: 0.46,
                alpha: 1.0,
                detail: .veins,
                emissiveResponse: 0.8
            )
        case .aluminum:
            return Material(
                albedo: SIMD3(0.76, 0.78, 0.82),
                specularTint: SIMD3(0.95, 0.97, 1.0),
                specularStrength: 0.72,
                specularSharpness: 22,
                ambient: 0.34,
                alpha: 1.0,
                detail: .brushed,
                emissiveResponse: 1.0
            )
        case .glass:
            return Material(
                albedo: SIMD3(0.38, 0.54, 0.62),
                specularTint: SIMD3(1, 1, 1),
                specularStrength: 0.90,
                specularSharpness: 90,
                ambient: 0.55,
                alpha: 0.72,
                detail: .frosted,
                emissiveResponse: 1.3
            )
        case .obsidian:
            return Material(
                albedo: SIMD3(0.10, 0.10, 0.13),
                specularTint: SIMD3(1.00, 0.82, 0.42),
                specularStrength: 1.0,
                specularSharpness: 120,
                ambient: 0.22,
                alpha: 1.0,
                detail: .glints,
                emissiveResponse: 1.6
            )
        }
    }

    /// Light direction at a given moment.
    ///
    /// The key light drifts slowly around the vertical axis so highlights travel
    /// across surfaces. A static light makes even a good material read as
    /// painted-on; movement is most of what sells "physical".
    static func lightDirection(at time: TimeInterval) -> SIMD3<Double> {
        let angle = sin(time * 0.18) * 0.35
        let base = baseLightDirection
        let cosA = cos(angle)
        let sinA = sin(angle)
        return simd_normalize(
            SIMD3(
                base.x * cosA - base.z * sinA,
                base.y,
                base.x * sinA + base.z * cosA
            )
        )
    }

    /// Analytic Blinn-Phong for one flat face.
    ///
    /// - Parameter comboHeat: 0...1 emissive boost, driven by streak length.
    /// - Parameter nearDeath: 0...1 desaturation, driven by how close the tower
    ///   is to failing.
    static func shade(
        material: Material,
        face: IsoProjection.Face,
        light: SIMD3<Double>,
        comboHeat: Double = 0,
        nearDeath: Double = 0
    ) -> UIColor {
        let normal = face.normal
        let diffuse = max(0, simd_dot(normal, light))
        let half = simd_normalize(light + viewDirection)
        let specular = pow(max(0, simd_dot(normal, half)), material.specularSharpness)
            * material.specularStrength

        let lit = material.ambient + diffuse * (1 - material.ambient)
        var rgb = material.albedo * lit + material.specularTint * specular

        // Combo glow: a long streak should visibly heat the tower up, not just
        // move a number on the HUD.
        if comboHeat > 0 {
            let glow = comboHeat * material.emissiveResponse * 0.28
            rgb += SIMD3(1.00, 0.72, 0.30) * glow
        }

        // Near death drains the colour out of the world.
        if nearDeath > 0 {
            let luma = simd_dot(rgb, SIMD3(0.2126, 0.7152, 0.0722))
            rgb = simd_mix(rgb, SIMD3(repeating: luma), SIMD3(repeating: min(1, nearDeath * 0.55)))
        }

        return UIColor(
            red: CGFloat(min(1, max(0, rgb.x))),
            green: CGFloat(min(1, max(0, rgb.y))),
            blue: CGFloat(min(1, max(0, rgb.z))),
            alpha: CGFloat(material.alpha)
        )
    }

    // MARK: - Procedural detail textures

    private static var textureCache: [MaterialTier: SKTexture] = [:]

    /// Surface detail for a tier, generated once and reused.
    ///
    /// These are near-white by design: `SKShapeNode` modulates `fillTexture` by
    /// `fillColor`, so the texture supplies detail and the shaded colour supplies
    /// the material.
    static func detailTexture(for tier: MaterialTier) -> SKTexture {
        if let cached = textureCache[tier] { return cached }
        let texture = SKTexture(image: renderDetail(material(for: tier).detail))
        texture.filteringMode = .linear
        textureCache[tier] = texture
        return texture
    }

    private static func renderDetail(_ pattern: Material.DetailPattern) -> UIImage {
        let size = CGSize(width: 256, height: 256)
        let renderer = UIGraphicsImageRenderer(size: size)

        // Seeded so the art is identical on every launch and every device — a
        // material that reshuffles itself between sessions reads as noise.
        var rng = SeededRandom(seed: 0xB10C)

        return renderer.image { context in
            let cg = context.cgContext
            UIColor.white.setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            switch pattern {
            case .noise:
                for _ in 0..<2600 {
                    let x = rng.nextDouble(in: 0..<256)
                    let y = rng.nextDouble(in: 0..<256)
                    let shade = rng.nextDouble(in: 0.80..<0.98)
                    let dot = rng.nextDouble(in: 0.6..<2.2)
                    UIColor(white: CGFloat(shade), alpha: 0.55).setFill()
                    cg.fillEllipse(in: CGRect(x: x, y: y, width: dot, height: dot))
                }

            case .veins:
                for _ in 0..<9 {
                    let path = UIBezierPath()
                    var point = CGPoint(x: rng.nextDouble(in: -40..<256), y: rng.nextDouble(in: 0..<256))
                    path.move(to: point)
                    for _ in 0..<5 {
                        let next = CGPoint(
                            x: point.x + rng.nextDouble(in: 30..<80),
                            y: point.y + rng.nextDouble(in: -46..<46)
                        )
                        let control = CGPoint(
                            x: (point.x + next.x) / 2 + rng.nextDouble(in: -22..<22),
                            y: (point.y + next.y) / 2 + rng.nextDouble(in: -22..<22)
                        )
                        path.addQuadCurve(to: next, controlPoint: control)
                        point = next
                    }
                    UIColor(white: CGFloat(rng.nextDouble(in: 0.62..<0.84)), alpha: 0.5).setStroke()
                    path.lineWidth = CGFloat(rng.nextDouble(in: 0.7..<2.6))
                    path.stroke()
                }

            case .brushed:
                // Fine horizontal streaks. Anisotropy is the whole tell for
                // brushed metal.
                for y in stride(from: 0.0, to: 256.0, by: 1.0) {
                    let shade = rng.nextDouble(in: 0.86..<1.0)
                    UIColor(white: CGFloat(shade), alpha: 0.6).setFill()
                    cg.fill(CGRect(x: 0, y: y, width: 256, height: 1))
                }
                for _ in 0..<70 {
                    let y = rng.nextDouble(in: 0..<256)
                    UIColor(white: CGFloat(rng.nextDouble(in: 0.70..<0.86)), alpha: 0.35).setFill()
                    cg.fill(CGRect(x: 0, y: y, width: 256, height: rng.nextDouble(in: 0.5..<1.6)))
                }

            case .frosted:
                let colors = [
                    UIColor(white: 1.0, alpha: 1.0).cgColor,
                    UIColor(white: 0.86, alpha: 1.0).cgColor
                ] as CFArray
                if let gradient = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: colors,
                    locations: [0, 1]
                ) {
                    cg.drawLinearGradient(
                        gradient,
                        start: CGPoint(x: 0, y: 0),
                        end: CGPoint(x: 256, y: 256),
                        options: []
                    )
                }

            case .glints:
                UIColor(white: 0.90, alpha: 1.0).setFill()
                cg.fill(CGRect(origin: .zero, size: size))
                for _ in 0..<60 {
                    let x = rng.nextDouble(in: 0..<256)
                    let y = rng.nextDouble(in: 0..<256)
                    let r = rng.nextDouble(in: 0.6..<2.4)
                    UIColor(white: 1.0, alpha: CGFloat(rng.nextDouble(in: 0.5..<1.0))).setFill()
                    cg.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
                }
            }
        }
    }
}

// MARK: - Palette

/// Background and UI colours, keyed off tower height.
enum Palette {

    /// The sky shifts hue as the tower climbs, so a long run visibly travels
    /// somewhere rather than looping the same frame.
    static func skyColors(forHeight height: Int) -> (top: UIColor, bottom: UIColor) {
        let progress = Double(height) / 120.0
        let hue = (0.62 + progress * 0.55).truncatingRemainder(dividingBy: 1.0)

        let top = UIColor(
            hue: CGFloat(hue),
            saturation: 0.55,
            brightness: 0.20,
            alpha: 1
        )
        let bottom = UIColor(
            hue: CGFloat((hue + 0.08).truncatingRemainder(dividingBy: 1.0)),
            saturation: 0.42,
            brightness: 0.52,
            alpha: 1
        )
        return (top, bottom)
    }

    static let comboGlow = UIColor(red: 1.00, green: 0.76, blue: 0.34, alpha: 1)
    static let perfectFlash = UIColor(red: 1.00, green: 0.94, blue: 0.78, alpha: 1)
}
