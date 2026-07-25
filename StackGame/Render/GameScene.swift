import SpriteKit
import StackGameCore

/// Read-only view of the run, pushed to SwiftUI each time it changes.
struct GameSnapshot: Equatable {
    var score: Int
    var height: Int
    var combo: Int
    var bestCombo: Int
    var tier: MaterialTier
    var isNearDeath: Bool
    var isPlaying: Bool

    static let empty = GameSnapshot(
        score: 0, height: 0, combo: 0, bestCombo: 0,
        tier: .concrete, isNearDeath: false, isPlaying: false
    )
}

/// What the run ended up being. Feeds the game-over screen, persistence, and
/// leaderboard submission.
struct RunSummary: Equatable {
    var score: Int
    var height: Int
    var bestCombo: Int
    var perfectCount: Int
    var tierReached: MaterialTier
    var continuesUsed: Int
    var isDailyChallenge: Bool
    var dailyIdentifier: String?
}

protocol GameSceneDelegate: AnyObject {
    func gameScene(_ scene: GameScene, didUpdate snapshot: GameSnapshot)
    func gameScene(_ scene: GameScene, didEndRunWith summary: RunSummary)
    /// Fired when a run ends and a rewarded continue is still available.
    func gameSceneDidOfferContinue(_ scene: GameScene)
}

/// Owns the frame loop and the visual representation of the engine's state.
///
/// This class deliberately makes **no rule decisions**. Every gameplay question —
/// did that land, what does it score, is the run over — is answered by
/// `StackEngine`. If a gameplay constant or a branch on game state shows up in
/// this file, it belongs in `Core` instead.
final class GameScene: SKScene {

    weak var gameDelegate: GameSceneDelegate?

    var audio: AudioEngine?
    var haptics: HapticsEngine?

    private(set) var engine = StackEngine()
    private var isDailyChallenge = false
    private var dailyIdentifier: String?

    private var sky: SkyNode!
    private var effects = EffectsLayer()
    private var cameraRig = CameraController()

    /// The most recent blocks, oldest first. Trails `engine.tower`, which keeps
    /// the whole history; these are only the ones still on screen.
    private var blockNodes: [BlockNode] = []
    private var movingNode: BlockNode?

    private var lastUpdateTime: TimeInterval = 0
    private var hitstopFrames = 0
    private var nearDeathAmount: Double = 0
    private var lastSnapshot = GameSnapshot.empty

    /// Blocks kept alive below the build point. Everything older is removed —
    /// an unbounded tower is the one thing that will reliably run a long run out
    /// of memory.
    private let visibleBlockWindow = 34

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = .black
        scaleMode = .resizeFill

        sky = SkyNode(size: size)
        sky.zPosition = -1000
        addChild(sky)

        effects.zPosition = 0
        addChild(effects)

        camera = cameraRig.node
        addChild(cameraRig.node)

        let ambient = effects.makeAmbientMotes(in: size)
        ambient.zPosition = -500
        ambient.targetNode = self
        cameraRig.node.addChild(ambient)

        startRun(daily: false)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        sky?.resize(to: size)
        // The sky rides with the camera, so it must cover the frame at any scale.
        sky?.position = CGPoint(x: 0, y: 0)
    }

    // MARK: - Run control

    func startRun(daily: Bool) {
        isDailyChallenge = daily
        dailyIdentifier = daily ? DailySeed.identifier() : nil

        let seed = daily ? DailySeed.seed() : UInt64.random(in: 0..<UInt64.max)
        engine = StackEngine(seed: seed)
        engine.start()

        blockNodes.forEach { $0.removeFromParent() }
        blockNodes.removeAll()
        movingNode?.removeFromParent()
        movingNode = nil
        nearDeathAmount = 0
        hitstopFrames = 0

        effects.towerLayer.removeAllChildren()
        effects.setComboIntensity(0)
        cameraRig.reset()
        sky.apply(height: 0, animated: false)

        if let foundation = engine.tower.first {
            addBlockNode(for: foundation)
        }
        syncMovingNode()
        publishSnapshot()
    }

    /// Resume after a rewarded ad. The engine restores the block; this just
    /// rebuilds the moving node and lets play continue.
    func continueRun() {
        guard engine.phase == .gameOver else { return }
        engine.continueRun()

        // The engine widened the surviving block, so its node is stale.
        if let top = engine.topBlock, let node = blockNodes.last {
            node.update(footprint: top.footprint)
        }
        syncMovingNode()
        publishSnapshot()
    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        performDrop()
    }

    private func performDrop() {
        guard engine.phase == .playing else { return }
        guard let result = engine.drop() else { return }
        apply(result)
    }

    // MARK: - Frame loop

    override func update(_ currentTime: TimeInterval) {
        // First frame, and any frame after the app was backgrounded, would
        // otherwise hand the engine a delta measured in seconds and teleport the
        // block across the tower.
        if lastUpdateTime == 0 { lastUpdateTime = currentTime }
        let rawDelta = currentTime - lastUpdateTime
        lastUpdateTime = currentTime
        let delta = min(max(rawDelta, 0), 1.0 / 20.0)

        if hitstopFrames > 0 {
            hitstopFrames -= 1
        } else {
            // Near-death slows time slightly. Small enough to feel like tension
            // rather than lag.
            let timeScale = 1.0 - nearDeathAmount * 0.08
            engine.update(deltaTime: delta * timeScale)
        }

        syncMovingNode()
        cameraRig.follow(height: engine.height)
        cameraRig.update(deltaTime: delta)
        sky.position = cameraRig.node.position
        sky.apply(height: engine.height)

        let light = MaterialLibrary.lightDirection(at: currentTime)
        movingNode?.shade(light: light, nearDeath: nearDeathAmount)
        // Only the blocks near the build point are worth re-shading every frame;
        // the light drift is far too slow to be visible on the ones fading out
        // of the bottom of the frame.
        for node in blockNodes.suffix(10) {
            node.shade(light: light, nearDeath: nearDeathAmount)
        }
    }

    // MARK: - Applying engine results

    private func apply(_ result: PlacementResult) {
        if let debris = result.debris {
            let node = DebrisNode(
                debris: debris,
                tier: MaterialTier(level: debris.level),
                light: MaterialLibrary.lightDirection(at: lastUpdateTime)
            )
            effects.towerLayer.addChild(node)
        }

        switch result.outcome {
        case .perfect:
            handlePerfect(result)
        case .sliced:
            handleSlice(result)
        case .missed:
            handleMiss(result)
            return
        }

        if let placed = result.placed {
            addBlockNode(for: placed)
        }

        nearDeathAmount = computeNearDeath()

        if let crossed = result.crossedInto {
            cameraRig.celebrateMilestone()
            audio?.playTierCrossing()
            haptics?.play(.milestone)
            for node in blockNodes.suffix(6) {
                node.transition(to: crossed)
            }
        }

        syncMovingNode()
        cullOldBlocks()
        publishSnapshot()
    }

    private func handlePerfect(_ result: PlacementResult) {
        guard let placed = result.placed else { return }

        let seam = IsoProjection.project(
            x: placed.footprint.centerX,
            y: placed.baseY,
            z: placed.footprint.centerZ
        )
        effects.perfectBurst(
            at: seam,
            combo: result.combo,
            zPosition: IsoProjection.depth(
                x: placed.footprint.centerX, y: placed.baseY, z: placed.footprint.centerZ
            )
        )
        effects.setComboIntensity(result.combo)

        // Two frames of hitstop. Enough to register as a punctuation mark,
        // short enough that it never reads as a stutter.
        hitstopFrames = 2

        audio?.playPerfect(combo: result.combo)
        haptics?.play(result.didRegrow ? .regrowth : .perfect)

        if result.didRegrow {
            audio?.playRegrowth()
        }
    }

    private func handleSlice(_ result: PlacementResult) {
        guard let debris = result.debris else { return }
        let cut = IsoProjection.project(
            x: debris.footprint.centerX,
            y: Double(debris.level) * Tuning.blockHeight,
            z: debris.footprint.centerZ
        )
        effects.sliceDust(
            at: cut,
            zPosition: IsoProjection.depth(
                x: debris.footprint.centerX,
                y: Double(debris.level) * Tuning.blockHeight,
                z: debris.footprint.centerZ
            )
        )
        effects.setComboIntensity(0)
        cameraRig.shake(intensity: 7)
        audio?.playSlice()
        haptics?.play(.slice)
    }

    private func handleMiss(_ result: PlacementResult) {
        movingNode?.removeFromParent()
        movingNode = nil
        effects.setComboIntensity(0)
        cameraRig.shake(intensity: 16)
        audio?.playGameOver()
        haptics?.play(.gameOver)

        publishSnapshot()

        let summary = RunSummary(
            score: engine.score,
            height: engine.height,
            bestCombo: engine.bestCombo,
            perfectCount: engine.perfectCount,
            tierReached: engine.currentTier,
            continuesUsed: engine.continuesUsed,
            isDailyChallenge: isDailyChallenge,
            dailyIdentifier: dailyIdentifier
        )

        // Let the collapse read before the UI covers the screen.
        run(.sequence([
            .wait(forDuration: 0.65),
            .run { [weak self] in
                guard let self else { return }
                if self.engine.continuesUsed == 0 {
                    self.gameDelegate?.gameSceneDidOfferContinue(self)
                }
                self.gameDelegate?.gameScene(self, didEndRunWith: summary)
            }
        ]))
    }

    // MARK: - Node management

    private func addBlockNode(for block: Block) {
        let node = BlockNode(footprint: block.footprint, baseY: block.baseY, tier: block.tier)
        node.comboHeat = min(1.0, Double(block.comboAtPlacement) / 8.0)
        node.shade(
            light: MaterialLibrary.lightDirection(at: lastUpdateTime),
            nearDeath: nearDeathAmount
        )
        effects.towerLayer.addChild(node)
        blockNodes.append(node)
    }

    private func syncMovingNode() {
        guard let moving = engine.moving else {
            movingNode?.removeFromParent()
            movingNode = nil
            return
        }

        if let node = movingNode, node.tier == MaterialTier(level: moving.level) {
            node.update(footprint: moving.footprint)
        } else {
            movingNode?.removeFromParent()
            let node = BlockNode(
                footprint: moving.footprint,
                baseY: Double(moving.level) * Tuning.blockHeight,
                tier: MaterialTier(level: moving.level)
            )
            node.comboHeat = min(1.0, Double(engine.combo) / 8.0)
            effects.towerLayer.addChild(node)
            movingNode = node
        }
    }

    private func cullOldBlocks() {
        while blockNodes.count > visibleBlockWindow {
            let node = blockNodes.removeFirst()
            node.removeFromParent()
        }
    }

    // MARK: - Derived state

    /// 0 when comfortable, ramping to 1 as the tower approaches unplayable.
    private func computeNearDeath() -> Double {
        guard let top = engine.topBlock else { return 0 }
        let smallest = min(top.footprint.width, top.footprint.depth)
        guard smallest < Tuning.nearDeathSize else { return 0 }
        let range = Tuning.nearDeathSize - Tuning.minimumViableSize
        guard range > 0 else { return 1 }
        return min(1, max(0, (Tuning.nearDeathSize - smallest) / range))
    }

    private func publishSnapshot() {
        let snapshot = GameSnapshot(
            score: engine.score,
            height: engine.height,
            combo: engine.combo,
            bestCombo: engine.bestCombo,
            tier: engine.currentTier,
            isNearDeath: nearDeathAmount > 0.01,
            isPlaying: engine.phase == .playing
        )
        guard snapshot != lastSnapshot else { return }
        lastSnapshot = snapshot
        gameDelegate?.gameScene(self, didUpdate: snapshot)
    }
}
