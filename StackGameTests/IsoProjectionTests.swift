import XCTest
import StackGameCore
import simd
@testable import StackGame

/// Geometry regression tests.
///
/// These exist because this exact maths was already got wrong once, in the icon
/// generator: its canvas has +y pointing down rather than up, which silently put
/// the camera in the opposite octant and made every block render as a flat plate
/// with stray wings. The projection is easy to write, easy to break, and
/// impossible to eyeball from the code — so it gets asserted.
final class IsoProjectionTests: XCTestCase {

    private let footprint = Footprint.centered(width: 1, depth: 1)

    func testOriginProjectsToOrigin() {
        let point = IsoProjection.project(x: 0, y: 0, z: 0)
        XCTAssertEqual(point.x, 0, accuracy: 1e-9)
        XCTAssertEqual(point.y, 0, accuracy: 1e-9)
    }

    func testAxisDirections() {
        // +x goes right and away, +z goes left and away, +y goes straight up.
        let origin = IsoProjection.project(x: 0, y: 0, z: 0)

        let alongX = IsoProjection.project(x: 1, y: 0, z: 0)
        XCTAssertGreaterThan(alongX.x, origin.x)
        XCTAssertGreaterThan(alongX.y, origin.y)

        let alongZ = IsoProjection.project(x: 0, y: 0, z: 1)
        XCTAssertLessThan(alongZ.x, origin.x)
        XCTAssertGreaterThan(alongZ.y, origin.y)

        let up = IsoProjection.project(x: 0, y: 1, z: 0)
        XCTAssertEqual(up.x, origin.x, accuracy: 1e-9)
        XCTAssertGreaterThan(up.y, origin.y)
    }

    func testProjectionIsTwoToOne() {
        // The defining property of a 2:1 isometric grid: one world unit is twice
        // as wide on screen as it is tall.
        let origin = IsoProjection.project(x: 0, y: 0, z: 0)
        let alongX = IsoProjection.project(x: 1, y: 0, z: 0)
        XCTAssertEqual((alongX.x - origin.x) / (alongX.y - origin.y), 2, accuracy: 1e-9)
    }

    func testSideFacesShareEdgesWithTop() {
        let top = IsoProjection.corners(of: footprint, baseY: 0, height: 0.2, face: .top)
        let left = IsoProjection.corners(of: footprint, baseY: 0, height: 0.2, face: .left)
        let right = IsoProjection.corners(of: footprint, baseY: 0, height: 0.2, face: .right)

        XCTAssertEqual(top.count, 4)

        // A side face must hang from an edge of the top face. If these drift
        // apart the block develops a visible seam.
        XCTAssertEqual(left[0], top[0])
        XCTAssertEqual(left[1], top[3])
        XCTAssertEqual(right[0], top[0])
        XCTAssertEqual(right[1], top[1])
    }

    func testSideFacesHangBelowTheTop() {
        let left = IsoProjection.corners(of: footprint, baseY: 0, height: 0.2, face: .left)
        let right = IsoProjection.corners(of: footprint, baseY: 0, height: 0.2, face: .right)

        XCTAssertLessThan(left[3].y, left[0].y)
        XCTAssertLessThan(left[2].y, left[1].y)
        XCTAssertLessThan(right[3].y, right[0].y)
        XCTAssertLessThan(right[2].y, right[1].y)
    }

    func testVisibleFacesFaceTheCamera() {
        // The camera sits in the (-x, +y, -z) octant, so every visible face's
        // normal must point at least partly toward it. This is precisely the
        // invariant the icon generator violated.
        for face in IsoProjection.Face.allCases {
            XCTAssertGreaterThan(
                simd_dot(face.normal, MaterialLibrary.viewDirection), 0,
                "\(face) faces away from the camera and should not be drawn"
            )
        }
    }

    func testTopFaceIsADiamond() {
        let top = IsoProjection.corners(of: footprint, baseY: 0, height: 0.2, face: .top)
        // Front and back corners share an x; left and right corners share a y.
        XCTAssertEqual(top[0].x, top[2].x, accuracy: 1e-9)
        XCTAssertEqual(top[1].y, top[3].y, accuracy: 1e-9)
    }

    func testHigherBlocksDrawInFront() {
        let low = IsoProjection.depth(x: 0, y: 0, z: 0)
        let high = IsoProjection.depth(x: 0, y: 1, z: 0)
        XCTAssertGreaterThan(high, low)
    }

    func testNearerBlocksDrawInFront() {
        // The camera is at (-x, +y, -z), so the near corner of the world is the
        // one with the *smallest* x + z. A depth key that grew with x + z would
        // sort the tower back to front.
        let origin = IsoProjection.depth(x: 0, y: 0, z: 0)
        XCTAssertGreaterThan(IsoProjection.depth(x: -1, y: 0, z: 0), origin)
        XCTAssertGreaterThan(IsoProjection.depth(x: 0, y: 0, z: -1), origin)
        XCTAssertLessThan(IsoProjection.depth(x: 1, y: 0, z: 0), origin)
        XCTAssertLessThan(IsoProjection.depth(x: 0, y: 0, z: 1), origin)
    }

    func testDepthAgreesWithTheProjectionAboutWhatIsNear() {
        // Tie the ordering to the projection rather than to a hand-picked sign:
        // whichever of two ground points lands *lower* on screen is the one in
        // front of the other, because screen-down is toward the camera here.
        let originPoint = IsoProjection.project(x: 0, y: 0, z: 0)
        let originDepth = IsoProjection.depth(x: 0, y: 0, z: 0)

        for (x, z) in [(1.0, 0.0), (0.0, 1.0), (0.7, -0.3), (-1.35, 0.0)] {
            let point = IsoProjection.project(x: x, y: 0, z: z)
            let depth = IsoProjection.depth(x: x, y: 0, z: z)
            XCTAssertEqual(
                point.y < originPoint.y, depth > originDepth,
                "(\(x), \(z)) sorts against the direction the projection puts it"
            )
        }
    }

    func testStackedBlockOutranksItsSupportAcrossTheWholeSweep() {
        // The regression this file exists for. The sweeping block sits one level
        // above the block it will land on, and the rules guarantee the two
        // overlap, so it must draw in front at *every* point of its travel — not
        // just on the half of the sweep that happens to move it away from the
        // camera. Ranking by ground position alone let the foundation paint over
        // it on the near half, which showed up as a notch bitten out of the
        // moving block.
        let support = IsoProjection.depth(x: 0, y: 0, z: 0)

        for step in 0...64 {
            let phase = Double(step) / 64 * 2 * .pi
            let offset = Tuning.travelAmplitude * sin(phase)
            let moving = IsoProjection.depth(x: offset, y: Tuning.blockHeight, z: 0)
            XCTAssertGreaterThan(
                moving, support,
                "moving block at x offset \(offset) sorts behind the block below it"
            )
        }
    }

    func testEveryTowerLevelOutranksTheOneBelowIt() {
        // Same invariant with the lean a long run accumulates, walked in the
        // worst direction for the sort — away from the camera, where the ground
        // term works against altitude on every single level. Placement
        // alternates axes and adjacent levels can be offset by at most one block
        // extent, since a placement that misses entirely ends the run.
        var previous = -CGFloat.greatestFiniteMagnitude
        var x = 0.0
        var z = 0.0

        for level in 0..<40 {
            if level.isMultiple(of: 2) { x += 0.9 } else { z += 0.9 }
            let depth = IsoProjection.depth(
                x: x, y: Double(level) * Tuning.blockHeight, z: z
            )
            XCTAssertGreaterThan(depth, previous, "level \(level) sorts behind level \(level - 1)")
            previous = depth
        }
    }

    func testShadowTracksFootprint() {
        let narrow = Footprint.centered(width: 0.3, depth: 0.3)
        let wide = Footprint.centered(width: 1.0, depth: 1.0)

        let narrowRect = IsoProjection.groundEllipseRect(of: narrow, atY: 0)
        let wideRect = IsoProjection.groundEllipseRect(of: wide, atY: 0)

        XCTAssertLessThan(narrowRect.width, wideRect.width)
        XCTAssertEqual(narrowRect.midX, wideRect.midX, accuracy: 1e-9)
    }
}
