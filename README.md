# Stack

A precision-stacking arcade game for iOS. Native SwiftUI + SpriteKit, isometric,
built to ship on the App Store.

Drop blocks onto the tower. Land one dead centre and you keep your full width and
climb the scale; miss and the overhang is sliced away for good. Eight perfects in
a row wins width back.

---

## Status

| Area | State |
|---|---|
| Core rules engine | Complete, **49 assertions passing** |
| Renderer, audio, haptics, UI | Complete, **not yet compiled** — see *Verification* |
| Game Center, StoreKit 2, persistence | Complete, **not yet compiled** |
| Ad integration | Protocol + no-op only; no SDK linked yet |
| App Store scaffolding | Icon, privacy manifest, entitlements, Info.plist in place |

**Nothing Swift in this repository has been compiled.** It was written in a Linux
container with no Swift toolchain and no Xcode, and `download.swift.org` is
blocked by the environment's network policy, so `swift build` was never an
option. Expect to fix compile errors on the first build. The gameplay *rules* are
separately verified — see below.

---

## Build

The `.xcodeproj` is generated, not committed, so it never conflicts on a branch:

```bash
brew install xcodegen
xcodegen generate
open StackGame.xcodeproj
```

Requires Xcode 15+, iOS 17 deployment target, iPhone only, portrait only.

To run just the rules engine with no project generation at all:

```bash
open Packages/StackGameCore/Package.swift   # then ⌘U
```

---

## Verification

Three layers, only two of which currently run.

**1. The Node harness — runs today, and does the load-bearing work.**

```bash
node Tools/engine-harness/verify.mjs
```

`Tools/engine-harness/engine.mjs` is a faithful port of `Packages/StackGameCore`.
It exists because the Swift tests could not be executed in the container, and the
rules are where the real design risk lives. It asserts placement maths, combo and
regrowth, scoring shape, difficulty curves, tier boundaries, and RNG determinism
— 49 checks — then runs 16,000 simulated runs to sanity-check the tuning.

It verifies the **algorithm**, not the Swift. When you change one, change both.

**2. `Packages/StackGameCore/Tests` — mirrors the harness in XCTest.** Runs on
your Mac with ⌘U. This is the real test suite; the harness is its stand-in.

**3. `StackGameTests` — app-layer tests.** Projection geometry and persistence.

### What the simulation says about the tuning

Player timing modelled as a normal distribution; σ is drop-timing precision.

| Profile | σ | Median height | p90 | Median score | Mean best streak |
|---|---|---|---|---|---|
| Casual | 60ms | 28 | 34 | 41 | 2.8 |
| Average | 42ms | 40 | 47 | 69 | 4.4 |
| Skilled | 28ms | 60 | 70 | 146 | 8.3 |
| Elite | 16ms | 118 | 138 | 479 | 24.7 |

Rewarded continue lifts a skilled player's median height by **+18%** — which is
the honest argument for that ad placement, rather than a guess.

---

## Architecture

```
Packages/StackGameCore/     Foundation only. No SpriteKit, no UIKit.
  StackEngine               Placement resolution and the state machine
  Tuning                    Every gameplay constant, in one file
  ScoreCalculator           Scoring and combo rules
  SeededRandom              SplitMix64, for the daily challenge

StackGame/
  App/                      SwiftUI entry point, GameCoordinator
  Render/                   Isometric renderer, materials, camera, effects
  Services/                 Audio, haptics, persistence, Game Center, ads, StoreKit
  UI/                       Menu, HUD, game over, settings

Tools/engine-harness/       JS port of the engine + tuning simulations
Tools/icon-generator/       Renders the 1024px app icon from source
```

The organising rule: **`Core` makes every gameplay decision, and imports no Apple
framework.** `GameScene` owns the frame loop and reads input, but never decides
whether a placement landed. A gameplay constant in `Render/` is a bug.

That constraint is what makes the rules testable without a simulator, and what
makes the daily challenge fair — a run is a pure function of its seed and its
input timings.

### Two deliberate deviations from the original plan

**1. Speeds are far lower than first specified.** The perfect window is centred
on the block below, which is also where the sweep moves *fastest*, so what the
player must hit is a time window, not a distance:

```
window = 2 × epsilon / peakSpeed
```

At the originally sketched 6.5 units/sec a perfect needed a **13ms full-width
window — under one frame at 60Hz.** That is a coin flip, not a difficulty curve.
`maxSpeed` is now 2.6, which puts the hardest reachable window at ~23ms, just
inside trained human timing precision. There is a test asserting it stays there.

**2. No `SKLightNode` and no normal maps.** An isometric block face is a
parallelogram, and SpriteKit sprites cannot be sheared — `SKNode` exposes scale
and rotation, not a full affine transform. Using sprites would have meant giving
up correct geometry.

But each face is flat, the key light is directional, and the camera is
orthographic — under those conditions per-face and per-pixel lighting are
*identical*. So faces are `SKShapeNode`s with analytically shaded fills, and the
normal map's real job (veining, brushing, glints) is baked into a procedural fill
texture. Same look, correct geometry, no untestable shader. If shape nodes ever
profile badly, the upgrade is `SKSpriteNode` + `SKWarpGeometryGrid`.

---

## Tuning the feel

Everything that decides how the game plays lives in
`Packages/StackGameCore/Sources/StackGameCore/Tuning.swift`. Change a value
there, mirror it in `Tools/engine-harness/engine.mjs`, and re-run the harness to
see what it does to the difficulty curve before you build.

The value that matters most is `perfectEpsilon`. It is deliberately slightly more
generous than the visual seam suggests — players should occasionally feel like
they got away with one. Do not tune it to be "fair".

`minEpsilon` is the second: it stops tolerance shrinking with the block, which is
what keeps the comeback loop reachable. Without it a narrowed tower could never
perfect again, so it could never regrow, and the run would be mathematically dead
while still nominally playable. That dead zone is what ends sessions.

---

## Before submitting to the App Store

- [ ] **Apple Developer Program membership** ($99/yr) and a signing team
- [ ] Set `DEVELOPMENT_TEAM` and a real bundle ID in `project.yml`
- [ ] Create the Game Center leaderboards and achievements in App Store Connect,
      matching the IDs in `GameCenterService`
- [ ] Create the `com.stackgame.removeads` non-consumable
- [ ] **Host a privacy policy** and replace the placeholder URL in `SettingsView`
- [ ] Link AdMob, swap `NoOpAdsProvider` for the real provider in
      `GameCoordinator`, and populate `SKAdNetworkItems` in `Info.plist`
- [ ] **Update `PrivacyInfo.xcprivacy`** — with an ad SDK linked,
      `NSPrivacyTracking` must become `true` and the tracking domains and
      collected data types must be filled in. Shipping ads against the manifest
      as written would be a false declaration.
- [ ] Screenshots at 6.9" (1320×2868)
- [ ] Test on a physical device — haptics and true frame pacing do not exist in
      the Simulator

---

## Regenerating the icon

```bash
node Tools/icon-generator/generate-icon.mjs
```

Renders `StackGame/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png`
using the same projection and face shading as the game, so the icon and the first
frame of gameplay agree with each other.
