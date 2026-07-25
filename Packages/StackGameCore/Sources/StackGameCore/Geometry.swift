import Foundation

/// The horizontal axis a block travels along.
///
/// Placement alternates every block. That alternation is the whole reason the
/// tower reads as three-dimensional rather than as a flat column — cutting
/// always on the same axis would let the tower narrow in one direction only.
public enum Axis: String, Sendable, Hashable, Codable {
    case x
    case z

    public var other: Axis {
        self == .x ? .z : .x
    }
}

/// A block's footprint on the ground plane.
///
/// `x`/`z` are the minimum corner, `width`/`depth` the extents. Everything in
/// the engine works in these world units, where the starting block is 1x1.
public struct Footprint: Sendable, Hashable, Codable {
    public var x: Double
    public var z: Double
    public var width: Double
    public var depth: Double

    public init(x: Double, z: Double, width: Double, depth: Double) {
        self.x = x
        self.z = z
        self.width = width
        self.depth = depth
    }

    /// A footprint centred on the origin.
    public static func centered(width: Double, depth: Double) -> Footprint {
        Footprint(x: -width / 2, z: -depth / 2, width: width, depth: depth)
    }

    // MARK: - Axis-relative access
    //
    // The placement maths is identical on both axes, so the engine reads and
    // writes through these accessors rather than branching on the axis
    // everywhere. Exactly one place needs to know which field an axis maps to.

    public func origin(along axis: Axis) -> Double {
        axis == .x ? x : z
    }

    public func extent(along axis: Axis) -> Double {
        axis == .x ? width : depth
    }

    public mutating func setOrigin(_ value: Double, along axis: Axis) {
        if axis == .x { x = value } else { z = value }
    }

    public mutating func setExtent(_ value: Double, along axis: Axis) {
        if axis == .x { width = value } else { depth = value }
    }

    public func origin(_ value: Double, along axis: Axis) -> Footprint {
        var copy = self
        copy.setOrigin(value, along: axis)
        return copy
    }

    // MARK: - Derived

    public var centerX: Double { x + width / 2 }
    public var centerZ: Double { z + depth / 2 }
    public var area: Double { width * depth }

    public func center(along axis: Axis) -> Double {
        origin(along: axis) + extent(along: axis) / 2
    }
}
