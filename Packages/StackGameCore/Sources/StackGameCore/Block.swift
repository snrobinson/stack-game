import Foundation

/// A block that has been locked into the tower.
public struct Block: Sendable, Hashable, Codable {
    /// Footprint on the ground plane.
    public var footprint: Footprint
    /// Index from the base of the tower; the foundation block is 0.
    public var level: Int
    /// The axis this block travelled along before it was dropped.
    public var axis: Axis
    /// Whether this block landed as a perfect placement.
    public var wasPerfect: Bool
    /// The combo streak in effect when this block landed. Drives how hot the
    /// renderer makes its emissive response.
    public var comboAtPlacement: Int

    public init(
        footprint: Footprint,
        level: Int,
        axis: Axis,
        wasPerfect: Bool = false,
        comboAtPlacement: Int = 0
    ) {
        self.footprint = footprint
        self.level = level
        self.axis = axis
        self.wasPerfect = wasPerfect
        self.comboAtPlacement = comboAtPlacement
    }

    /// The material tier this block renders with, derived purely from height so
    /// the renderer never has to track it separately.
    public var tier: MaterialTier {
        MaterialTier(level: level)
    }

    /// World-space Y of this block's underside.
    public var baseY: Double {
        Double(level) * Tuning.blockHeight
    }
}

/// The block currently sweeping back and forth, awaiting a drop.
///
/// Motion lives in the engine rather than the renderer so that a run is fully
/// determined by its seed and its input timings — which is what makes the daily
/// challenge fair and the tests meaningful.
public struct MovingBlock: Sendable, Hashable {
    public var footprint: Footprint
    public var axis: Axis
    public var level: Int

    /// Centre of the oscillation, inherited from the block below so the sweep
    /// always passes over the landing target.
    public var travelCenter: Double
    /// Half-width of the sweep in world units.
    public var amplitude: Double
    /// Phase of the sine that drives the sweep, in radians.
    public var phase: Double
    /// Peak speed in world units per second, reached at the centre of the sweep.
    public var peakSpeed: Double

    /// Current position of the block's *leading corner* along its travel axis.
    public var origin: Double {
        footprint.origin(along: axis)
    }

    /// Signed velocity in world units per second. Zero at the turnarounds.
    public var velocity: Double {
        peakSpeed * cos(phase)
    }
}
