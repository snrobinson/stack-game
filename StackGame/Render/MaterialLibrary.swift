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

    /// Colour of the key light: warm, so a lit face skews golden.
    static let keyLightColor = lumaNormalized(SIMD3(1.00, 0.93, 0.76))

    /// Colour of the ambient fill — the sky bouncing back into the faces the key
    /// light misses.
    ///
    /// Splitting the light into a warm key and a cool fill is what puts actual
    /// *hue* into a block instead of three brightnesses of the same swatch. With
    /// a white light the only difference between the top face and the shaded
    /// side is exposure, which is exactly what makes an untinted palette read as
    /// grey no matter how saturated the albedo is. With this split, the lit face
    /// runs warm and the shaded face runs blue, and the block picks up colour it
    /// never had in its albedo.
    static let ambientColor = lumaNormalized(SIMD3(0.46, 0.60, 1.00))

    /// Scale a light colour so its luminance is exactly 1.
    ///
    /// Keeps the tint knobs above orthogonal to exposure: retinting a light
    /// moves hue only, and can never quietly brighten or darken every material
    /// in the game at once.
    private static func lumaNormalized(_ color: SIMD3<Double>) -> SIMD3<Double> {
        let luma = simd_dot(color, SIMD3(0.2126, 0.7152, 0.0722))
        return luma > 0 ? color / luma : color
    }

    static func material(for tier: MaterialTier) -> Material {
        switch tier {
        case .concrete:
            // Warm sandstone rather than grey cement. The sky starts blue-violet
            // and the opening tower is the first thing anyone sees, so the
            // foundation band is deliberately the complement of its backdrop.
            return Material(
                albedo: SIMD3(0.90, 0.72, 0.50),
                specularTint: SIMD3(1.00, 0.94, 0.82),
                specularStrength: 0.12,
                specularSharpness: 8,
                ambient: 0.44,
                alpha: 1.0,
                detail: .noise,
                emissiveResponse: 0.6
            )
        case .marble:
            return Material(
                albedo: SIMD3(0.96, 0.90, 0.99),
                specularTint: SIMD3(1.00, 0.96, 1.00),
                specularStrength: 0.62,
                specularSharpness: 48,
                ambient: 0.48,
                alpha: 1.0,
                detail: .veins,
                emissiveResponse: 0.9
            )
        case .aluminum:
            return Material(
                albedo: SIMD3(0.60, 0.76, 0.94),
                specularTint: SIMD3(0.86, 0.95, 1.00),
                specularStrength: 0.80,
                specularSharpness: 22,
                ambient: 0.38,
                alpha: 1.0,
                detail: .brushed,
                emissiveResponse: 1.1
            )
        case .glass:
            return Material(
                albedo: SIMD3(0.18, 0.78, 0.80),
                specularTint: SIMD3(0.80, 1.00, 1.00),
                specularStrength: 0.95,
                specularSharpness: 90,
                ambient: 0.56,
                alpha: 0.72,
                detail: .frosted,
                emissiveResponse: 1.4
            )
        case .obsidian:
            return Material(
                albedo: SIMD3(0.16, 0.08, 0.26),
                specularTint: SIMD3(1.00, 0.72, 0.30),
                specularStrength: 1.0,
                specularSharpness: 120,
                ambient: 0.26,
                alpha: 1.0,
                detail: .glints,
                emissiveResponse: 1.7
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

        // Both light colours are luminance-normalised, so this carries the same
        // total exposure the old scalar `ambient + diffuse * (1 - ambient)` did
        // — it just spends it across three channels instead of one.
        let lit = ambientColor * material.ambient
            + keyLightColor * (diffuse * (1 - material.ambient))
        var rgb = material.albedo * lit + material.specularTint * specular

        // Combo glow: a long streak should visibly heat the tower up, not just
        // move a number on the HUD.
        if comboHeat > 0 {
            let glow = comboHeat * material.emissiveResponse * 0.34
            rgb += SIMD3(1.00, 0.68, 0.24) * glow
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

        // The two stops are pulled apart in hue as well as in brightness. A
        // gradient between two shades of one colour is a backdrop; a gradient
        // that travels is a sky.
        //
        // The bottom stop stays under ~0.7 brightness on purpose: the HUD's
        // material band sits right on top of it, and white type on a fully
        // saturated, fully bright field is where legibility goes.
        let top = UIColor(
            hue: CGFloat(hue),
            saturation: 0.80,
            brightness: 0.26,
            alpha: 1
        )
        let bottom = UIColor(
            hue: CGFloat((hue + 0.13).truncatingRemainder(dividingBy: 1.0)),
            saturation: 0.76,
            brightness: 0.68,
            alpha: 1
        )
        return (top, bottom)
    }

    static let comboGlow = UIColor(red: 1.00, green: 0.74, blue: 0.28, alpha: 1)
    static let perfectFlash = UIColor(red: 1.00, green: 0.95, blue: 0.80, alpha: 1)

    /// The colour a material band reads as, for the UI that names it.
    ///
    /// Derived from the tier's own albedo lifted to full brightness rather than
    /// hand-picked per tier, so the chip in the HUD and the blocks on screen
    /// cannot drift apart when a material is retuned.
    static func tierTint(for tier: MaterialTier) -> UIColor {
        let albedo = MaterialLibrary.material(for: tier).albedo
        let peak = max(albedo.x, max(albedo.y, albedo.z))
        let lifted = peak > 0 ? albedo / peak : albedo
        return UIColor(
            red: CGFloat(lifted.x),
            green: CGFloat(lifted.y),
            blue: CGFloat(lifted.z),
            alpha: 1
        )
    }
}
