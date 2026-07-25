import Foundation

/// The piece cut off by an imperfect placement, handed to the renderer so it can
/// be thrown into the world as physics debris.
public struct Debris: Sendable, Hashable {
    public var footprint: Footprint
    public var level: Int
    public var axis: Axis
    /// True when the overhang was on the far side of the travel axis. The
    /// renderer uses this to pick which way the piece tumbles.
    public var onFarSide: Bool
}

/// Everything that happened as a result of one drop.
public struct PlacementResult: Sendable, Hashable {
    public var outcome: PlacementOutcome
    /// The block that entered the tower, or `nil` on a miss.
    public var placed: Block?
    public var debris: Debris?
    /// Streak length after this placement. Zero on anything but a perfect.
    public var combo: Int
    /// True when this placement hit the regrowth interval and won extent back.
    public var didRegrow: Bool
    public var scoreDelta: Int
    public var totalScore: Int
    /// Set when this placement moved the tower into a new material band.
    public var crossedInto: MaterialTier?
    /// True when the surviving block is narrow enough for the near-death
    /// treatment.
    public var isNearDeath: Bool
}

/// The rules of the game.
///
/// Deliberately free of any Apple framework: no SpriteKit, no UIKit, no
/// SwiftUI. A run is a pure function of its seed and the timings of its drops,
/// which is what lets the daily challenge be fair across devices and lets the
/// whole rule set be tested without a simulator.
///
/// The renderer owns the frame loop and calls `update(deltaTime:)` and `drop()`.
/// It must never make a rule decision of its own — if gameplay logic ends up in
/// the render layer, that is a bug.
public struct StackEngine: Sendable {

    public enum Phase: String, Sendable, Hashable {
        case ready
        case playing
        case gameOver
    }

    // MARK: - State

    public private(set) var tower: [Block] = []
    public private(set) var moving: MovingBlock?
    public private(set) var phase: Phase = .ready
    public private(set) var score: Int = 0
    public private(set) var combo: Int = 0
    public private(set) var bestCombo: Int = 0
    public private(set) var perfectCount: Int = 0
    public private(set) var continuesUsed: Int = 0

    public let seed: UInt64
    private var rng: SeededRandom

    /// Number of blocks placed above the foundation. This is the "height" the
    /// player sees, and the value material tiers key off.
    public var height: Int {
        max(0, tower.count - 1)
    }

    public var currentTier: MaterialTier {
        MaterialTier(level: height)
    }

    /// The block the next drop will land on.
    public var topBlock: Block? {
        tower.last
    }

    public init(seed: UInt64 = 0) {
        self.seed = seed
        self.rng = SeededRandom(seed: seed)
    }

    // MARK: - Lifecycle

    public mutating func start() {
        rng = SeededRandom(seed: seed)
        tower = [
            Block(
                footprint: .centered(width: Tuning.initialSize, depth: Tuning.initialSize),
                level: 0,
                axis: .z
            )
        ]
        score = 0
        combo = 0
        bestCombo = 0
        perfectCount = 0
        continuesUsed = 0
        phase = .playing
        spawnNextMovingBlock()
    }

    /// Resume a failed run from where it died. Backs the rewarded-ad continue.
    ///
    /// The surviving block is widened back to `Tuning.continueRestoreSize` on
    /// both axes — resuming onto the sliver that just killed you would make the
    /// reward worthless.
    public mutating func continueRun() {
        guard phase == .gameOver, var restored = tower.last else { return }

        restored.footprint = Self.widened(
            restored.footprint,
            toAtLeast: Tuning.continueRestoreSize
        )
        tower[tower.count - 1] = restored

        combo = 0
        continuesUsed += 1
        phase = .playing
        spawnNextMovingBlock()
    }

    // MARK: - Frame loop

    /// Advance the sweep.
    ///
    /// Position is `travelCenter + amplitude * sin(phase)`, so the block eases
    /// through its turnarounds and runs fastest across the middle. Linear travel
    /// was the alternative and it reads as mechanical — and, because it spends
    /// no extra time near the extremes, it gives the player less of a rhythm to
    /// lock onto.
    public mutating func update(deltaTime: Double) {
        guard phase == .playing, var block = moving, deltaTime > 0 else { return }

        let angularSpeed = block.peakSpeed / block.amplitude
        block.phase += angularSpeed * deltaTime

        // Keep the phase bounded; an hour-long idle would otherwise erode
        // precision in the sine.
        let twoPi = 2 * Double.pi
        if block.phase > twoPi || block.phase < -twoPi {
            block.phase = block.phase.truncatingRemainder(dividingBy: twoPi)
        }

        let offset = block.amplitude * sin(block.phase)
        block.footprint.setOrigin(block.travelCenter + offset, along: block.axis)
        moving = block
    }

    /// Place the moving block at an exact offset from its landing target,
    /// bypassing the sweep.
    ///
    /// Testing placement by stepping `update` until the block happens to be near
    /// the target can only ever assert "close enough", which is useless for the
    /// boundary cases that matter most. This is also what a replay verifier
    /// would use to re-run a submitted daily-challenge score.
    public mutating func positionMovingBlock(offsetFromTarget offset: Double) {
        guard var block = moving else { return }
        block.footprint.setOrigin(block.travelCenter + offset, along: block.axis)
        // Keep the phase consistent with the position so a later `update` does
        // not snap the block somewhere unrelated.
        let ratio = max(-1, min(1, offset / block.amplitude))
        block.phase = asin(ratio)
        moving = block
    }

    /// Lock the moving block in place and resolve the placement.
    @discardableResult
    public mutating func drop() -> PlacementResult? {
        guard phase == .playing, let block = moving, let base = tower.last else { return nil }

        let axis = block.axis
        let movingOrigin = block.footprint.origin(along: axis)
        let movingExtent = block.footprint.extent(along: axis)
        let baseOrigin = base.footprint.origin(along: axis)
        let baseExtent = base.footprint.extent(along: axis)

        let overlapStart = max(movingOrigin, baseOrigin)
        let overlapEnd = min(movingOrigin + movingExtent, baseOrigin + baseExtent)
        let overlap = overlapEnd - overlapStart

        // MARK: Miss

        if overlap <= Tuning.minimumViableSize {
            phase = .gameOver
            let lost = Debris(
                footprint: block.footprint,
                level: block.level,
                axis: axis,
                onFarSide: movingOrigin > baseOrigin
            )
            moving = nil
            return PlacementResult(
                outcome: .missed,
                placed: nil,
                debris: lost,
                combo: 0,
                didRegrow: false,
                scoreDelta: 0,
                totalScore: score,
                crossedInto: nil,
                isNearDeath: false
            )
        }

        let previousTier = MaterialTier(level: height)
        let offsetFromTarget = abs(movingOrigin - baseOrigin)
        let isPerfect = offsetFromTarget <= Tuning.perfectEpsilon(forSize: baseExtent)

        var landed = block.footprint
        var debris: Debris?
        var didRegrow = false

        if isPerfect {
            // Snap hard onto the block below. Leaving a sub-epsilon offset in
            // place would let tiny errors accumulate into a visible lean over a
            // long streak.
            landed.setOrigin(baseOrigin, along: axis)
            landed.setExtent(baseExtent, along: axis)

            combo += 1
            perfectCount += 1
            bestCombo = max(bestCombo, combo)

            if combo % Tuning.comboRegrowthInterval == 0 {
                let grown = min(baseExtent + Tuning.regrowthAmount, Tuning.initialSize)
                let growth = grown - baseExtent
                if growth > 0 {
                    landed.setExtent(grown, along: axis)
                    landed.setOrigin(baseOrigin - growth / 2, along: axis)
                    didRegrow = true
                }
            }
        } else {
            landed.setOrigin(overlapStart, along: axis)
            landed.setExtent(overlap, along: axis)

            // The overhang is whatever of the moving block fell outside the
            // overlap, on whichever side it stuck out.
            let overhangOnFarSide = movingOrigin > baseOrigin
            var cut = block.footprint
            if overhangOnFarSide {
                cut.setOrigin(overlapEnd, along: axis)
                cut.setExtent(movingOrigin + movingExtent - overlapEnd, along: axis)
            } else {
                cut.setOrigin(movingOrigin, along: axis)
                cut.setExtent(overlapStart - movingOrigin, along: axis)
            }

            if cut.extent(along: axis) > 0 {
                debris = Debris(
                    footprint: cut,
                    level: block.level,
                    axis: axis,
                    onFarSide: overhangOnFarSide
                )
            }

            combo = 0
        }

        let outcome: PlacementOutcome = isPerfect ? .perfect : .sliced
        let placed = Block(
            footprint: landed,
            level: block.level,
            axis: axis,
            wasPerfect: isPerfect,
            comboAtPlacement: combo
        )
        tower.append(placed)

        let awarded = ScoreCalculator.points(outcome: outcome, combo: combo)
        score += awarded

        let newTier = MaterialTier(level: height)
        let crossed = newTier != previousTier ? newTier : nil

        spawnNextMovingBlock()

        let smallestExtent = min(landed.width, landed.depth)
        return PlacementResult(
            outcome: outcome,
            placed: placed,
            debris: debris,
            combo: combo,
            didRegrow: didRegrow,
            scoreDelta: awarded,
            totalScore: score,
            crossedInto: crossed,
            isNearDeath: smallestExtent < Tuning.nearDeathSize
        )
    }

    // MARK: - Helpers

    private mutating func spawnNextMovingBlock() {
        guard let base = tower.last else { return }

        let axis = base.axis.other
        let level = base.level + 1
        let travelCenter = base.footprint.origin(along: axis)

        // Enter from a randomly chosen extreme. Always starting on the same side
        // would let players pre-load the rhythm and turn the game into a
        // metronome test rather than a timing one.
        let startPhase = rng.nextUnitDouble() < 0.5 ? -Double.pi / 2 : Double.pi / 2

        var footprint = base.footprint
        footprint.setOrigin(
            travelCenter + Tuning.travelAmplitude * sin(startPhase),
            along: axis
        )

        moving = MovingBlock(
            footprint: footprint,
            axis: axis,
            level: level,
            travelCenter: travelCenter,
            amplitude: Tuning.travelAmplitude,
            phase: startPhase,
            peakSpeed: Tuning.speed(atLevel: level)
        )
    }

    /// Grow a footprint outward from its centre until both extents clear a
    /// minimum, never exceeding the starting block size.
    private static func widened(_ footprint: Footprint, toAtLeast minimum: Double) -> Footprint {
        var result = footprint
        for axis in [Axis.x, Axis.z] {
            let extent = result.extent(along: axis)
            guard extent < minimum else { continue }
            let target = min(minimum, Tuning.initialSize)
            let growth = target - extent
            result.setExtent(target, along: axis)
            result.setOrigin(result.origin(along: axis) - growth / 2, along: axis)
        }
        return result
    }
}
