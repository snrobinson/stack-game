import Foundation

/// Every number that decides how the game feels, in one place.
///
/// Treat this as the tuning rig. Nothing else in the engine should hard-code a
/// gameplay constant, so that retuning feel is a single-file operation.
///
/// ## Why the speeds are lower than they look
///
/// The perfect window is centred on the block below, which is also where the
/// sinusoidal sweep is moving *fastest*. So the real difficulty of a perfect is
/// not the epsilon in world units — it is the time window in milliseconds:
///
///     window = 2 * epsilon / peakSpeed        (seconds, full width)
///
/// Trained players hold roughly +/-30ms of timing precision; +/-15ms is at the
/// edge of human. That upper bound is what sets `maxSpeed` here, and it is much
/// slower than it first seems it should be. At the originally sketched 6.5
/// units/sec a perfect would have needed a 13ms *full-width* window — under one
/// frame at 60Hz, which is not a difficulty curve, it is a coin flip.
///
/// The resulting windows:
///
/// | Level | Speed | Size | Epsilon | Window (full) |
/// |-------|-------|------|---------|---------------|
/// | 0     | 1.10  | 1.00 | 0.045   | ~82ms         |
/// | 25    | 1.60  | 1.00 | 0.045   | ~56ms         |
/// | 75+   | 2.60  | 1.00 | 0.045   | ~35ms         |
/// | 75+   | 2.60  | 0.40 | 0.030   | ~23ms         |
///
/// Verify with `Tuning.perfectWindowSeconds(atLevel:size:)` — there is a test
/// asserting the hardest reachable window stays above the human floor.
public enum Tuning {

    // MARK: - Geometry

    /// Footprint extent of the foundation block, in world units.
    public static let initialSize: Double = 1.0
    /// Vertical extent of every block.
    public static let blockHeight: Double = 0.2
    /// Half-width of the sweep. Wide enough that the block clearly enters from
    /// off-target, narrow enough that waiting for the pass is not tedious.
    public static let travelAmplitude: Double = 1.35

    // MARK: - Speed

    public static let baseSpeed: Double = 1.10
    public static let maxSpeed: Double = 2.60
    public static let speedGrowthPerLevel: Double = 0.020

    // MARK: - Precision

    /// Perfect tolerance as a fraction of the current block size.
    public static let relativeEpsilon: Double = 0.045
    /// Absolute floor on the perfect tolerance.
    ///
    /// This floor is what keeps the comeback loop alive. If tolerance scaled
    /// down with the block forever, a narrowed tower could never earn a perfect
    /// again, so it could never regrow — the run would be mathematically dead
    /// while still nominally playable. That dead zone is exactly what ends
    /// sessions, so the floor is a retention mechanic, not a mercy.
    public static let minEpsilon: Double = 0.030
    /// Tolerance never exceeds this fraction of the block, so slivers do not
    /// degenerate into "any overlap counts".
    public static let maxEpsilonFraction: Double = 0.6

    // MARK: - Combo

    /// Consecutive perfects required to grow the block back.
    public static let comboRegrowthInterval: Int = 8
    /// How much extent a regrowth grants, split evenly across both edges.
    public static let regrowthAmount: Double = 0.08
    /// Combo bonus stops compounding here so scores stay comparable.
    public static let maxComboBonus: Int = 8

    // MARK: - Failure

    /// Overlap at or below this ends the run. Guards against sub-pixel slivers
    /// that are technically alive but not actually playable.
    public static let minimumViableSize: Double = 0.02
    /// Below this the presentation layer shifts into its near-death treatment.
    public static let nearDeathSize: Double = 0.22
    /// Size the block is restored to when a run is continued via rewarded ad.
    public static let continueRestoreSize: Double = 0.35

    // MARK: - Derived curves

    /// Peak sweep speed at a given tower level, rising then plateauing so that
    /// deep runs stay decided by skill rather than by reflex ceiling.
    public static func speed(atLevel level: Int) -> Double {
        min(baseSpeed + Double(max(0, level)) * speedGrowthPerLevel, maxSpeed)
    }

    /// Perfect tolerance for a block of the given extent.
    public static func perfectEpsilon(forSize size: Double) -> Double {
        let scaled = relativeEpsilon * size
        let floored = max(scaled, minEpsilon)
        return min(floored, size * maxEpsilonFraction)
    }

    /// Full width, in seconds, of the timing window for a perfect placement.
    ///
    /// Exposed so tests and the tuning harness can assert the game stays inside
    /// human reaction limits instead of us guessing.
    public static func perfectWindowSeconds(atLevel level: Int, size: Double) -> Double {
        let peak = speed(atLevel: level)
        guard peak > 0 else { return .infinity }
        return 2 * perfectEpsilon(forSize: size) / peak
    }
}

/// Material bands, derived from height. Crossing one is the visible progress
/// beat that pulls a player toward "just reach the next material".
public enum MaterialTier: Int, Sendable, Hashable, Codable, CaseIterable {
    case concrete = 0
    case marble = 1
    case aluminum = 2
    case glass = 3
    case obsidian = 4

    public init(level: Int) {
        switch level {
        case ..<15: self = .concrete
        case ..<30: self = .marble
        case ..<50: self = .aluminum
        case ..<75: self = .glass
        default: self = .obsidian
        }
    }

    /// First tower level that belongs to this tier.
    public var firstLevel: Int {
        switch self {
        case .concrete: return 0
        case .marble: return 15
        case .aluminum: return 30
        case .glass: return 50
        case .obsidian: return 75
        }
    }

    public var displayName: String {
        switch self {
        case .concrete: return "Concrete"
        case .marble: return "Marble"
        case .aluminum: return "Aluminum"
        case .glass: return "Glass"
        case .obsidian: return "Obsidian"
        }
    }
}
