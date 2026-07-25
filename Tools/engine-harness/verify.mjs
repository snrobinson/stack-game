// Executable verification of the gameplay rules, plus the difficulty-tuning
// simulations that decide whether the numbers in Tuning are actually playable.
//
// Run: node Tools/engine-harness/verify.mjs

import { StackEngine, SeededRandom, Tuning, points, materialTier } from './engine.mjs';

let passed = 0;
let failed = 0;
const failures = [];

function check(name, condition, detail = '') {
  if (condition) {
    passed++;
  } else {
    failed++;
    failures.push(`${name}${detail ? ` — ${detail}` : ''}`);
  }
}

function near(a, b, tol = 1e-9) {
  return Math.abs(a - b) <= tol;
}

const oKey = (axis) => (axis === 'x' ? 'x' : 'z');
const eKey = (axis) => (axis === 'x' ? 'width' : 'depth');

/// Place the moving block at an exact offset from its target and drop.
/// Bypasses the sweep so placement maths can be tested in isolation.
function dropAtOffset(engine, offset) {
  const b = engine.moving;
  b.footprint[oKey(b.axis)] = b.travelCenter + offset;
  return engine.drop();
}

function freshEngine(seed = 1) {
  const e = new StackEngine(seed);
  e.start();
  return e;
}

// ---------------------------------------------------------------------------
// Placement resolution
// ---------------------------------------------------------------------------

{
  const e = freshEngine();
  const r = dropAtOffset(e, 0);
  check('exact hit is perfect', r.outcome === 'perfect', r.outcome);
  check('perfect keeps full extent', near(r.placed.footprint.width, 1.0), r.placed.footprint.width);
  check('perfect starts combo at 1', r.combo === 1, r.combo);
  check('perfect scores 2', r.scoreDelta === 2, r.scoreDelta);
}

{
  const e = freshEngine();
  const eps = Tuning.perfectEpsilon(1.0);
  const r = dropAtOffset(e, eps - 1e-12);
  check('just inside epsilon is perfect', r.outcome === 'perfect', r.outcome);
}

{
  const e = freshEngine();
  const eps = Tuning.perfectEpsilon(1.0);
  const r = dropAtOffset(e, eps + 1e-6);
  check('just outside epsilon slices', r.outcome === 'sliced', r.outcome);
  check('slice leaves overlap only', near(r.placed.footprint[eKey(r.placed.axis)], 1.0 - (eps + 1e-6), 1e-9));
}

{
  // Overhang on both sides, and conservation of material.
  for (const sign of [1, -1]) {
    const e = freshEngine();
    const offset = sign * 0.4;
    const r = dropAtOffset(e, offset);
    const axis = r.placed.axis;
    const survived = r.placed.footprint[eKey(axis)];
    const cut = r.debris ? r.debris.footprint[eKey(axis)] : 0;
    check(
      `slice conserves extent (sign ${sign})`,
      near(survived + cut, 1.0, 1e-9),
      `${survived} + ${cut}`,
    );
    check(
      `debris side correct (sign ${sign})`,
      r.debris.onFarSide === (sign > 0),
      String(r.debris.onFarSide),
    );
  }
}

{
  const e = freshEngine();
  const r = dropAtOffset(e, 1.5);
  check('total miss ends run', r.outcome === 'missed', r.outcome);
  check('miss ends phase', e.phase === 'gameOver', e.phase);
  check('miss scores nothing', r.scoreDelta === 0, r.scoreDelta);
  check('miss places no block', r.placed === null);
}

{
  // A sliver thinner than the viability threshold must fail rather than leave a
  // sub-pixel block alive. Probed with margin on both sides: testing exactly at
  // the threshold is meaningless in floating point, since `1.0 - 0.98` lands on
  // 0.020000000000000018 and reads as viable by a rounding error.
  const tooThin = freshEngine();
  const thin = dropAtOffset(tooThin, 1.0 - Tuning.minimumViableSize * 0.5);
  check('sub-viable overlap ends run', thin.outcome === 'missed', thin.outcome);

  const viable = freshEngine();
  const survives = dropAtOffset(viable, 1.0 - Tuning.minimumViableSize * 4);
  check('overlap above the threshold survives', survives.outcome === 'sliced', survives.outcome);
}

// ---------------------------------------------------------------------------
// Combo, regrowth, near-death
// ---------------------------------------------------------------------------

{
  const e = freshEngine();
  for (let i = 0; i < 5; i++) dropAtOffset(e, 0);
  check('combo accumulates', e.combo === 5, e.combo);
  const r = dropAtOffset(e, 0.5);
  check('imperfect breaks combo', e.combo === 0, e.combo);
  check('broken combo still scores 1', r.scoreDelta === 1, r.scoreDelta);
}

{
  // Narrow the tower, then verify a full streak wins extent back.
  const e = freshEngine();
  dropAtOffset(e, 0.3); // width -> 0.7
  const narrowed = e.tower[e.tower.length - 1].footprint.width;
  check('slice narrowed the block', near(narrowed, 0.7, 1e-9), narrowed);

  let regrowths = 0;
  for (let i = 0; i < 8; i++) {
    const r = dropAtOffset(e, 0);
    if (r.didRegrow) regrowths++;
  }
  check('regrowth fires once per 8 perfects', regrowths === 1, regrowths);

  const top = e.tower[e.tower.length - 1];
  const grownAxis = top.axis;
  check(
    'regrowth added the tuned amount',
    near(top.footprint[eKey(grownAxis)], 0.7 + Tuning.regrowthAmount, 1e-9),
    top.footprint[eKey(grownAxis)],
  );
}

{
  // Regrowth must never exceed the starting size.
  const e = freshEngine();
  for (let i = 0; i < 40; i++) dropAtOffset(e, 0);
  const top = e.tower[e.tower.length - 1];
  check('regrowth capped at initial size', top.footprint.width <= Tuning.initialSize + 1e-9, top.footprint.width);
  check('regrowth capped on cross axis too', top.footprint.depth <= Tuning.initialSize + 1e-9, top.footprint.depth);
}

{
  const e = freshEngine();
  const r = dropAtOffset(e, 0.85); // leaves 0.15, under nearDeathSize
  check('near-death flagged', r.isNearDeath === true, String(r.isNearDeath));
}

// ---------------------------------------------------------------------------
// Scoring shape
// ---------------------------------------------------------------------------

{
  check('combo bonus caps', points('perfect', 50) === 1 + Tuning.maxComboBonus, points('perfect', 50));
  check('slice is flat 1', points('sliced', 99) === 1);
  check('miss is 0', points('missed', 5) === 0);

  // The design claim: streaks beat endurance.
  const streakyRun = [];
  for (let i = 0; i < 3; i++) {
    for (let j = 0; j < 10; j++) streakyRun.push('perfect');
    streakyRun.push('sliced');
  }
  while (streakyRun.length < 40) streakyRun.push('sliced');

  const sloppyRun = new Array(60).fill('sliced');

  let streakyScore = 0;
  let combo = 0;
  for (const o of streakyRun) {
    combo = o === 'perfect' ? combo + 1 : 0;
    streakyScore += points(o, combo);
  }
  const sloppyScore = sloppyRun.length;

  check(
    '40-block streaky run beats 60-block sloppy run',
    streakyScore > sloppyScore,
    `${streakyScore} vs ${sloppyScore}`,
  );
}

// ---------------------------------------------------------------------------
// Difficulty curves
// ---------------------------------------------------------------------------

{
  let monotonic = true;
  for (let l = 1; l <= 200; l++) {
    if (Tuning.speed(l) < Tuning.speed(l - 1) - 1e-12) monotonic = false;
  }
  check('speed is monotonic', monotonic);
  check('speed plateaus at maxSpeed', near(Tuning.speed(500), Tuning.maxSpeed), Tuning.speed(500));
  check('speed starts at baseSpeed', near(Tuning.speed(0), Tuning.baseSpeed));

  check('epsilon floors', near(Tuning.perfectEpsilon(0.1), Tuning.minEpsilon), Tuning.perfectEpsilon(0.1));
  check(
    'epsilon never exceeds 60% of a sliver',
    Tuning.perfectEpsilon(0.03) <= 0.03 * Tuning.maxEpsilonFraction + 1e-12,
    Tuning.perfectEpsilon(0.03),
  );

  // The headline playability constraint: the hardest window a player can reach
  // must stay above human timing precision.
  const hardest = Tuning.perfectWindowSeconds(200, Tuning.nearDeathSize);
  check(
    'hardest reachable perfect window > 20ms',
    hardest > 0.020,
    `${(hardest * 1000).toFixed(1)}ms`,
  );
  const easiest = Tuning.perfectWindowSeconds(0, Tuning.initialSize);
  check('opening window is forgiving (>60ms)', easiest > 0.060, `${(easiest * 1000).toFixed(1)}ms`);
}

// ---------------------------------------------------------------------------
// Material tiers
// ---------------------------------------------------------------------------

{
  check('tier 0', materialTier(0) === 'concrete');
  check('tier boundary 14/15', materialTier(14) === 'concrete' && materialTier(15) === 'marble');
  check('tier boundary 29/30', materialTier(29) === 'marble' && materialTier(30) === 'aluminum');
  check('tier boundary 49/50', materialTier(49) === 'aluminum' && materialTier(50) === 'glass');
  check('tier boundary 74/75', materialTier(74) === 'glass' && materialTier(75) === 'obsidian');

  const e = freshEngine();
  let crossings = 0;
  for (let i = 0; i < 80; i++) {
    const r = dropAtOffset(e, 0);
    if (r.crossedInto) crossings++;
  }
  check('exactly four tier crossings in 80 levels', crossings === 4, crossings);
}

// ---------------------------------------------------------------------------
// Determinism
// ---------------------------------------------------------------------------

{
  const a = new SeededRandom(20260725);
  const b = new SeededRandom(20260725);
  const c = new SeededRandom(20260726);
  const seqA = Array.from({ length: 200 }, () => a.next().toString());
  const seqB = Array.from({ length: 200 }, () => b.next().toString());
  const seqC = Array.from({ length: 200 }, () => c.next().toString());
  check('same seed gives same sequence', seqA.join() === seqB.join());
  check('different seed diverges', seqA.join() !== seqC.join());

  const inRange = Array.from({ length: 10000 }, () => new SeededRandom(7).nextUnitDouble());
  const one = new SeededRandom(7);
  const many = Array.from({ length: 10000 }, () => one.nextUnitDouble());
  check('unit doubles stay in [0,1)', many.every((v) => v >= 0 && v < 1));
  const mean = many.reduce((s, v) => s + v, 0) / many.length;
  check('unit doubles are roughly uniform', Math.abs(mean - 0.5) < 0.02, mean.toFixed(4));
  check('sequence is repeatable', inRange[0] === inRange[1]);

  // Two engines on the same seed must produce identical spawn sides.
  const e1 = freshEngine(20260725);
  const e2 = freshEngine(20260725);
  let identical = true;
  for (let i = 0; i < 200; i++) {
    if (e1.moving.phase !== e2.moving.phase) identical = false;
    dropAtOffset(e1, 0);
    dropAtOffset(e2, 0);
  }
  check('daily-challenge runs are identical across engines', identical);
}

// ---------------------------------------------------------------------------
// Difficulty simulation
// ---------------------------------------------------------------------------
//
// Models a player whose drop timing is normally distributed with standard
// deviation sigma. Because the target sits at the fastest point of the sweep,
// a timing error of tau seconds lands the block roughly peakSpeed * tau away
// from the target — so sigma in milliseconds maps directly onto world units.

function gaussian(rng) {
  // Box-Muller.
  let u = 0;
  let v = 0;
  while (u === 0) u = rng.nextUnitDouble();
  while (v === 0) v = rng.nextUnitDouble();
  return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
}

function simulateRun(sigmaSeconds, rng, { allowContinue = false } = {}) {
  const e = new StackEngine(Math.floor(rng.nextUnitDouble() * 1e9));
  e.start();
  let usedContinue = false;

  for (let i = 0; i < 1000; i++) {
    const b = e.moving;
    if (!b) break;
    const tau = gaussian(rng) * sigmaSeconds;
    const offset = b.peakSpeed * tau;
    const r = dropAtOffset(e, offset);
    if (!r) break;
    if (r.outcome === 'missed') {
      if (allowContinue && !usedContinue) {
        usedContinue = true;
        e.continueRun();
        continue;
      }
      break;
    }
  }
  return { height: e.height, score: e.score, bestCombo: e.bestCombo, perfects: e.perfectCount };
}

function summarize(label, sigmaMs, runs = 4000, opts = {}) {
  const rng = new SeededRandom(99);
  const results = [];
  for (let i = 0; i < runs; i++) results.push(simulateRun(sigmaMs / 1000, rng, opts));

  const heights = results.map((r) => r.height).sort((a, b) => a - b);
  const scores = results.map((r) => r.score).sort((a, b) => a - b);
  const combos = results.map((r) => r.bestCombo).sort((a, b) => a - b);
  const pct = (arr, p) => arr[Math.min(arr.length - 1, Math.floor(arr.length * p))];
  const mean = (arr) => arr.reduce((s, v) => s + v, 0) / arr.length;

  return {
    label,
    sigmaMs,
    medianHeight: pct(heights, 0.5),
    p90Height: pct(heights, 0.9),
    maxHeight: heights[heights.length - 1],
    medianScore: pct(scores, 0.5),
    p90Score: pct(scores, 0.9),
    meanBestCombo: mean(combos).toFixed(1),
    // ~2.2s per placement cycle at the opening speed, less as it accelerates.
    medianRunSeconds: (pct(heights, 0.5) * 1.6).toFixed(0),
  };
}

console.log('\n=== Placement / rules ===');
console.log(`${passed} passed, ${failed} failed`);
if (failures.length) {
  console.log('\nFailures:');
  for (const f of failures) console.log(`  ✗ ${f}`);
}

console.log('\n=== Perfect timing windows (full width, ms) ===');
console.log('level   speed   size=1.00   size=0.50   size=0.22');
for (const level of [0, 10, 25, 50, 75, 100, 200]) {
  const row = [1.0, 0.5, Tuning.nearDeathSize]
    .map((s) => (Tuning.perfectWindowSeconds(level, s) * 1000).toFixed(1).padStart(11))
    .join('');
  console.log(`${String(level).padEnd(8)}${Tuning.speed(level).toFixed(2).padEnd(8)}${row}`);
}

console.log('\n=== Simulated player outcomes (4000 runs each) ===');
const profiles = [
  ['casual      ', 60],
  ['average     ', 42],
  ['skilled     ', 28],
  ['elite       ', 16],
];
console.log('profile        sigma   medHeight  p90Height  maxHeight  medScore  p90Score  meanStreak  ~medRun');
for (const [label, sigma] of profiles) {
  const s = summarize(label, sigma);
  console.log(
    `${s.label}  ${String(s.sigmaMs).padStart(4)}ms` +
      `${String(s.medianHeight).padStart(11)}${String(s.p90Height).padStart(11)}${String(s.maxHeight).padStart(11)}` +
      `${String(s.medianScore).padStart(10)}${String(s.p90Score).padStart(10)}` +
      `${String(s.meanBestCombo).padStart(12)}${String(s.medianRunSeconds + 's').padStart(9)}`,
  );
}

console.log('\n=== Rewarded-continue lift (skilled profile) ===');
const withoutContinue = summarize('no continue', 28, 4000);
const withContinue = summarize('continue', 28, 4000, { allowContinue: true });
const lift = ((withContinue.medianHeight / withoutContinue.medianHeight - 1) * 100).toFixed(0);
console.log(`median height ${withoutContinue.medianHeight} -> ${withContinue.medianHeight} (+${lift}%)`);

console.log('');
process.exit(failed === 0 ? 0 : 1);
