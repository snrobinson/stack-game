import SpriteKit
import StackGameCore

/// Drives the scene camera: follows the build point, pulls back to celebrate a
/// new material band, and shakes when the tower loses a slice.
final class CameraController {

    let node = SKCameraNode()

    /// Where the camera wants to be. The camera eases toward this rather than
    /// snapping, so the tower rises smoothly instead of stepping.
    private var targetY: CGFloat = 0
    private var targetScale: CGFloat = 1
    private var shakeOffset = CGPoint.zero
    private var shakeMagnitude: CGFloat = 0

    /// Offset of the camera from the build point.
    ///
    /// The build point lands `-verticalBias` above screen centre, so a negative
    /// value lifts it and leaves the space below for the tower to fill. (An
    /// earlier comment here claimed this put the build point *below* centre —
    /// it does the opposite; the behaviour is right and the description was
    /// wrong.)
    ///
    /// Kept modest: at -120 a fresh run put the first block two-thirds of the
    /// way up an otherwise empty frame.
    private let verticalBias: CGFloat = -60

    private let baseScale: CGFloat

    init(baseScale: CGFloat = 1.0) {
        self.baseScale = baseScale
        self.targetScale = baseScale
        node.setScale(baseScale)
    }

    func reset() {
        targetY = IsoProjection.project(x: 0, y: 0, z: 0).y + verticalBias
        targetScale = baseScale
        shakeMagnitude = 0
        shakeOffset = .zero
        node.position = CGPoint(x: 0, y: targetY)
        node.setScale(baseScale)
    }

    /// Point the camera at the current top of the tower.
    func follow(height: Int) {
        let topY = IsoProjection.project(x: 0, y: Double(height) * Tuning.blockHeight, z: 0).y
        targetY = topY + verticalBias
    }

    /// Brief pull-back so the player sees how far the tower has come. Fired on
    /// material-band crossings.
    func celebrateMilestone() {
        targetScale = baseScale * 1.16
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
            guard let self else { return }
            self.targetScale = self.baseScale
        }
    }

    /// Shake is reserved for slices. Perfects deliberately get none — keeping the
    /// frame still on a perfect and rattling it on a mistake is what makes a
    /// clean placement *feel* clean.
    func shake(intensity: CGFloat) {
        shakeMagnitude = min(26, shakeMagnitude + intensity)
    }

    func update(deltaTime: TimeInterval) {
        let dt = CGFloat(min(deltaTime, 1.0 / 20.0))

        // Exponential smoothing, framerate-independent.
        let follow = 1 - pow(0.001, dt)
        let currentY = node.position.y - shakeOffset.y
        let easedY = currentY + (targetY - currentY) * follow

        let zoom = 1 - pow(0.02, dt)
        let easedScale = node.xScale + (targetScale - node.xScale) * zoom
        node.setScale(easedScale)

        if shakeMagnitude > 0.05 {
            shakeOffset = CGPoint(
                x: .random(in: -shakeMagnitude...shakeMagnitude),
                y: .random(in: -shakeMagnitude...shakeMagnitude)
            )
            shakeMagnitude *= pow(0.001, dt)
        } else {
            shakeMagnitude = 0
            shakeOffset = .zero
        }

        node.position = CGPoint(x: shakeOffset.x, y: easedY + shakeOffset.y)
    }
}
