import CoreGraphics
import Foundation
import StackGameCore
import simd

/// The one place that knows how world space becomes screen space.
///
/// Standard 2:1 isometric. `x` runs down-right, `z` runs down-left, `y` is up.
/// Nothing else in the render layer should do this maths — if two files disagree
/// about the projection, blocks and their shadows drift apart.
enum IsoProjection {

    /// Screen width of one world unit along a ground axis.
    ///
    /// Bounded by the sweep, not by taste. A block's furthest screen extent is
    /// `tileWidth * (travelAmplitude + 1) / 2`; with amplitude 1.35 that is
    /// `tileWidth * 1.175`, which has to stay inside a phone's half-width —
    /// ~187pt on a 375pt device. Hence 155.
    ///
    /// Letting the block leave the frame would be defensible with linear travel,
    /// but the sweep is sinusoidal: it decelerates into the turnarounds, so an
    /// oversized tile parks the block off-screen exactly where it moves slowest
    /// and the player is left waiting on something they cannot see.
    static let tileWidth: CGFloat = 155
    /// Screen height of one world unit of altitude.
    ///
    /// Held at ~0.71x `tileWidth` — that ratio is what makes the blocks read as
    /// slabs rather than cubes.
    static let heightScale: CGFloat = 111

    static func project(x: Double, y: Double, z: Double) -> CGPoint {
        CGPoint(
            x: (CGFloat(x) - CGFloat(z)) * tileWidth * 0.5,
            y: (CGFloat(x) + CGFloat(z)) * tileWidth * 0.25 + CGFloat(y) * heightScale
        )
    }

    /// The three faces of a block that face the camera.
    ///
    /// The camera sits in the `(-x, +y, -z)` octant, so the visible sides are the
    /// ones at minimum x and minimum z, plus the top.
    enum Face: CaseIterable {
        case top
        /// The face at minimum x, receding to the upper-left.
        case left
        /// The face at minimum z, receding to the upper-right.
        case right

        /// Outward world-space normal.
        var normal: SIMD3<Double> {
            switch self {
            case .top: return SIMD3(0, 1, 0)
            case .left: return SIMD3(-1, 0, 0)
            case .right: return SIMD3(0, 0, -1)
            }
        }
    }

    /// Corner ring for one face of a block, in screen space, wound consistently
    /// so the resulting path is always convex and non-self-intersecting.
    static func corners(
        of footprint: Footprint,
        baseY: Double,
        height: Double,
        face: Face
    ) -> [CGPoint] {
        let x0 = footprint.x
        let x1 = footprint.x + footprint.width
        let z0 = footprint.z
        let z1 = footprint.z + footprint.depth
        let yLow = baseY
        let yHigh = baseY + height

        switch face {
        case .top:
            return [
                project(x: x0, y: yHigh, z: z0),
                project(x: x1, y: yHigh, z: z0),
                project(x: x1, y: yHigh, z: z1),
                project(x: x0, y: yHigh, z: z1)
            ]
        case .left:
            return [
                project(x: x0, y: yHigh, z: z0),
                project(x: x0, y: yHigh, z: z1),
                project(x: x0, y: yLow, z: z1),
                project(x: x0, y: yLow, z: z0)
            ]
        case .right:
            return [
                project(x: x0, y: yHigh, z: z0),
                project(x: x1, y: yHigh, z: z0),
                project(x: x1, y: yLow, z: z0),
                project(x: x0, y: yLow, z: z0)
            ]
        }
    }

    static func path(
        of footprint: Footprint,
        baseY: Double,
        height: Double,
        face: Face
    ) -> CGPath {
        let points = corners(of: footprint, baseY: baseY, height: height, face: face)
        let path = CGMutablePath()
        path.addLines(between: points)
        path.closeSubpath()
        return path
    }

    /// Flat ellipse approximating the block's footprint on the ground, used for
    /// the contact shadow.
    static func groundEllipseRect(of footprint: Footprint, atY y: Double) -> CGRect {
        let center = project(x: footprint.centerX, y: y, z: footprint.centerZ)
        let width = (CGFloat(footprint.width) + CGFloat(footprint.depth)) * tileWidth * 0.5
        let height = (CGFloat(footprint.width) + CGFloat(footprint.depth)) * tileWidth * 0.25
        return CGRect(
            x: center.x - width / 2,
            y: center.y - height / 2,
            width: width,
            height: height
        )
    }

    /// Draw order key. Larger draws in front.
    static func depth(x: Double, y: Double, z: Double) -> CGFloat {
        CGFloat(x + z + y * 2)
    }
}
