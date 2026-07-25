// A line-for-line port of Packages/StackGameCore into JavaScript.
//
// Why this exists: the Swift toolchain cannot be installed in the development
// container (download.swift.org is blocked by network policy), so the Swift
// tests cannot be executed until someone opens the project on a Mac. This port
// lets the *rules* — which is where the real design risk lives — be executed and
// asserted right now.
//
// It verifies the algorithm, not the Swift. When you change one, change both,
// and keep verify.mjs green.

export const Tuning = {
  initialSize: 1.0,
  blockHeight: 0.2,
  travelAmplitude: 1.35,

  baseSpeed: 1.10,
  maxSpeed: 2.60,
  speedGrowthPerLevel: 0.020,

  relativeEpsilon: 0.045,
  minEpsilon: 0.030,
  maxEpsilonFraction: 0.6,

  comboRegrowthInterval: 8,
  regrowthAmount: 0.08,
  maxComboBonus: 8,

  minimumViableSize: 0.02,
  nearDeathSize: 0.22,
  continueRestoreSize: 0.35,

  speed(level) {
    return Math.min(
      Tuning.baseSpeed + Math.max(0, level) * Tuning.speedGrowthPerLevel,
      Tuning.maxSpeed,
    );
  },

  perfectEpsilon(size) {
    const scaled = Tuning.relativeEpsilon * size;
    const floored = Math.max(scaled, Tuning.minEpsilon);
    return Math.min(floored, size * Tuning.maxEpsilonFraction);
  },

  perfectWindowSeconds(level, size) {
    const peak = Tuning.speed(level);
    if (peak <= 0) return Infinity;
    return (2 * Tuning.perfectEpsilon(size)) / peak;
  },
};

export function materialTier(level) {
  if (level < 15) return 'concrete';
  if (level < 30) return 'marble';
  if (level < 50) return 'aluminum';
  if (level < 75) return 'glass';
  return 'obsidian';
}

// SplitMix64 over BigInt so the sequence matches Swift's UInt64 arithmetic
// exactly. Number would silently lose the low bits.
const MASK = (1n << 64n) - 1n;

export class SeededRandom {
  constructor(seed) {
    this.state = (BigInt(seed) + 0x9e3779b97f4a7c15n) & MASK;
  }

  next() {
    this.state = (this.state + 0x9e3779b97f4a7c15n) & MASK;
    let z = this.state;
    z = ((z ^ (z >> 30n)) * 0xbf58476d1ce4e5b9n) & MASK;
    z = ((z ^ (z >> 27n)) * 0x94d049bb133111ebn) & MASK;
    return (z ^ (z >> 31n)) & MASK;
  }

  nextUnitDouble() {
    return Number(this.next() >> 11n) / 9007199254740992;
  }
}

export function points(outcome, combo) {
  if (outcome === 'missed') return 0;
  if (outcome === 'sliced') return 1;
  return 1 + Math.min(Math.max(combo, 0), Tuning.maxComboBonus);
}

const originKey = (axis) => (axis === 'x' ? 'x' : 'z');
const extentKey = (axis) => (axis === 'x' ? 'width' : 'depth');
const other = (axis) => (axis === 'x' ? 'z' : 'x');

export class StackEngine {
  constructor(seed = 0) {
    this.seed = seed;
    this.rng = new SeededRandom(seed);
    this.tower = [];
    this.moving = null;
    this.phase = 'ready';
    this.score = 0;
    this.combo = 0;
    this.bestCombo = 0;
    this.perfectCount = 0;
    this.continuesUsed = 0;
  }

  get height() {
    return Math.max(0, this.tower.length - 1);
  }

  start() {
    this.rng = new SeededRandom(this.seed);
    this.tower = [
      {
        footprint: {
          x: -Tuning.initialSize / 2,
          z: -Tuning.initialSize / 2,
          width: Tuning.initialSize,
          depth: Tuning.initialSize,
        },
        level: 0,
        axis: 'z',
        wasPerfect: false,
        comboAtPlacement: 0,
      },
    ];
    this.score = 0;
    this.combo = 0;
    this.bestCombo = 0;
    this.perfectCount = 0;
    this.continuesUsed = 0;
    this.phase = 'playing';
    this.#spawn();
  }

  update(deltaTime) {
    if (this.phase !== 'playing' || !this.moving || deltaTime <= 0) return;
    const b = this.moving;
    const angularSpeed = b.peakSpeed / b.amplitude;
    b.phase += angularSpeed * deltaTime;

    const twoPi = 2 * Math.PI;
    if (b.phase > twoPi || b.phase < -twoPi) b.phase = b.phase % twoPi;

    b.footprint[originKey(b.axis)] =
      b.travelCenter + b.amplitude * Math.sin(b.phase);
  }

  drop() {
    if (this.phase !== 'playing' || !this.moving) return null;
    const block = this.moving;
    const base = this.tower[this.tower.length - 1];

    const axis = block.axis;
    const oKey = originKey(axis);
    const eKey = extentKey(axis);

    const movingOrigin = block.footprint[oKey];
    const movingExtent = block.footprint[eKey];
    const baseOrigin = base.footprint[oKey];
    const baseExtent = base.footprint[eKey];

    const overlapStart = Math.max(movingOrigin, baseOrigin);
    const overlapEnd = Math.min(movingOrigin + movingExtent, baseOrigin + baseExtent);
    const overlap = overlapEnd - overlapStart;

    if (overlap <= Tuning.minimumViableSize) {
      this.phase = 'gameOver';
      this.moving = null;
      return {
        outcome: 'missed',
        placed: null,
        debris: { footprint: { ...block.footprint }, level: block.level, axis, onFarSide: movingOrigin > baseOrigin },
        combo: 0,
        didRegrow: false,
        scoreDelta: 0,
        totalScore: this.score,
        crossedInto: null,
        isNearDeath: false,
      };
    }

    const previousTier = materialTier(this.height);
    const offsetFromTarget = Math.abs(movingOrigin - baseOrigin);
    const isPerfect = offsetFromTarget <= Tuning.perfectEpsilon(baseExtent);

    const landed = { ...block.footprint };
    let debris = null;
    let didRegrow = false;

    if (isPerfect) {
      landed[oKey] = baseOrigin;
      landed[eKey] = baseExtent;

      this.combo += 1;
      this.perfectCount += 1;
      this.bestCombo = Math.max(this.bestCombo, this.combo);

      if (this.combo % Tuning.comboRegrowthInterval === 0) {
        const grown = Math.min(baseExtent + Tuning.regrowthAmount, Tuning.initialSize);
        const growth = grown - baseExtent;
        if (growth > 0) {
          landed[eKey] = grown;
          landed[oKey] = baseOrigin - growth / 2;
          didRegrow = true;
        }
      }
    } else {
      landed[oKey] = overlapStart;
      landed[eKey] = overlap;

      const overhangOnFarSide = movingOrigin > baseOrigin;
      const cut = { ...block.footprint };
      if (overhangOnFarSide) {
        cut[oKey] = overlapEnd;
        cut[eKey] = movingOrigin + movingExtent - overlapEnd;
      } else {
        cut[oKey] = movingOrigin;
        cut[eKey] = overlapStart - movingOrigin;
      }
      if (cut[eKey] > 0) {
        debris = { footprint: cut, level: block.level, axis, onFarSide: overhangOnFarSide };
      }

      this.combo = 0;
    }

    const outcome = isPerfect ? 'perfect' : 'sliced';
    const placed = {
      footprint: landed,
      level: block.level,
      axis,
      wasPerfect: isPerfect,
      comboAtPlacement: this.combo,
    };
    this.tower.push(placed);

    const awarded = points(outcome, this.combo);
    this.score += awarded;

    const newTier = materialTier(this.height);
    const crossed = newTier !== previousTier ? newTier : null;

    this.#spawn();

    return {
      outcome,
      placed,
      debris,
      combo: this.combo,
      didRegrow,
      scoreDelta: awarded,
      totalScore: this.score,
      crossedInto: crossed,
      isNearDeath: Math.min(landed.width, landed.depth) < Tuning.nearDeathSize,
    };
  }

  continueRun() {
    if (this.phase !== 'gameOver' || this.tower.length === 0) return;
    const top = this.tower[this.tower.length - 1];
    for (const axis of ['x', 'z']) {
      const eKey = extentKey(axis);
      const oKey = originKey(axis);
      if (top.footprint[eKey] >= Tuning.continueRestoreSize) continue;
      const target = Math.min(Tuning.continueRestoreSize, Tuning.initialSize);
      const growth = target - top.footprint[eKey];
      top.footprint[eKey] = target;
      top.footprint[oKey] -= growth / 2;
    }
    this.combo = 0;
    this.continuesUsed += 1;
    this.phase = 'playing';
    this.#spawn();
  }

  #spawn() {
    const base = this.tower[this.tower.length - 1];
    if (!base) return;

    const axis = other(base.axis);
    const level = base.level + 1;
    const travelCenter = base.footprint[originKey(axis)];
    const startPhase = this.rng.nextUnitDouble() < 0.5 ? -Math.PI / 2 : Math.PI / 2;

    const footprint = { ...base.footprint };
    footprint[originKey(axis)] =
      travelCenter + Tuning.travelAmplitude * Math.sin(startPhase);

    this.moving = {
      footprint,
      axis,
      level,
      travelCenter,
      amplitude: Tuning.travelAmplitude,
      phase: startPhase,
      peakSpeed: Tuning.speed(level),
    };
  }
}

/// Drive the engine to the next moment the block is within `tolerance` world
/// units of the target, stepping at a fixed frame rate, then drop. Models a
/// player whose timing is off by `errorSeconds`.
export function simulateDrop(engine, { errorSeconds = 0, fps = 60, maxSeconds = 20 } = {}) {
  const dt = 1 / fps;
  const b = engine.moving;
  if (!b) return null;

  // Advance until the block crosses the target origin.
  let elapsed = 0;
  let previous = b.footprint[originKey(b.axis)] - b.travelCenter;
  while (elapsed < maxSeconds) {
    engine.update(dt);
    elapsed += dt;
    const current = engine.moving.footprint[originKey(engine.moving.axis)] - engine.moving.travelCenter;
    if (previous === 0 || previous * current <= 0) break;
    previous = current;
  }

  if (errorSeconds !== 0) engine.update(Math.abs(errorSeconds));
  return engine.drop();
}
