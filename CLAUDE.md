# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Cube One — a Rubik's cube play/solve app for iOS, iPadOS, and macOS 26+ (SwiftUI + RealityKit, Liquid Glass UI). Private repo: https://github.com/cypherair/CubeOne.

## Commands

```sh
# Engine tests (pure-Swift package; run from CubeKit/)
cd CubeKit && swift test                 # debug
cd CubeKit && swift test -c release      # required for perf-sensitive checks
swift test --filter SolverTests          # one suite (also: BeginnerSolverTests, SliceMoveTests, ...)

# App builds (scheme: cubeone)
xcodebuild -project cubeone.xcodeproj -scheme cubeone -destination 'platform=macOS' build
xcodebuild -project cubeone.xcodeproj -scheme cubeone -destination 'generic/platform=iOS Simulator' build

# Headless table bake (CI or scripted local use)
swift run -c release --package-path CubeKit cubekit-bake 7 /tmp/pdb

# Run on iPhone simulator
xcrun simctl boot <device-udid>
xcrun simctl install <device-udid> <DerivedData>/Build/Products/Debug-iphonesimulator/cubeone.app
xcrun simctl launch <device-udid> com.chentianren.cube
xcrun simctl io <device-udid> screenshot /tmp/shot.png   # no screen-recording permission needed
```

Debug builds run the solver and its table generation ~10–30× slower (first-launch table generation: ~20 s debug vs ~0.2 s release). That is not a hang. Always validate performance claims with `-c release`.

Optimal-solver pattern databases are baked in-app (Settings › Solving): the 7-edge tier (~0.5 GB) takes ~2 min on an M5, the 8-edge tier (~5.15 GB) ~75 min, both cached in the app container. The gitignored `Seeds/` folder at the repo root is bundled **only by the `cubeone-seeded` scheme** (its `Release-Seeded` configuration sets `INCLUDE_PDB_SEEDS=YES`); the regular `cubeone` scheme skips the ~2.3 GB copy so daily builds stay small. Archive with `cubeone-seeded` to ship bundled tables. Both schemes are shared (`xcshareddata/xcschemes`) — Xcode no longer auto-generates schemes for this project. Tables are reproducible artifacts — never commit them (the `bake-tables.yml` workflow can rebuild seeds on CI; cross-machine bakes verified byte-identical).

## Architecture

Two layers with a hard boundary:

- **CubeKit/** — local Swift package, zero UI dependencies, all cube logic. `CubeState` is the cubie-level source of truth (corner/edge permutation + orientation, centers fixed). `FaceletCube` is the 54-sticker view with legality validation. Solvers: `KociembaSolver` (two-phase, coordinate tables cached on disk, time-budgeted search), `ThistlethwaiteSolver` (four-phase group reduction, greedy descent over BFS distance tables, each phase provably shortest), and `BeginnerSolver` (layer-by-layer). The staged solvers return a `StagedSolution<StageKind>` (generic over the stage enum). Everything here is unit-tested; UI code never mutates cube state directly.
- **cube/** — the app target (folder-synchronized Xcode group; new files under `cube/` join the target automatically). `AppModel` owns the logical state; `CubeSceneController` owns the RealityKit scene. The scene *renders and animates*; every completed turn flows back through `onMoveCommitted` into `AppModel.commit`, which is the only place `cubeState` advances.

Key mechanisms to understand before touching play/scene code:

- **Intent-tagged commits**: every queued animation carries a `MoveIntent` (user/undo/redo/scramble/solutionForward/...) in a FIFO parallel to the scene queue. The commit handler switches on the intent to update history, cursor, timer, and solve-session state. If you enqueue an animation without appending an intent (or vice versa), history corrupts silently.
- **Sticker rendering invariant**: sticker colors render the "base state" set by the last `rebase(to:)`; cubelet transforms carry the moves since. Transforms are re-quantized after every turn (`snapTransform`) so float drift cannot accumulate. The editor only works on a rebased scene (home transforms), where sticker entity ↔ facelet index is one-to-one.
- **Slice moves (M/E/S)**: `CubeState` keeps centers fixed, so a slice turn is its outer-turn pair plus a whole-cube reorientation (`SliceMove.equivalentOuterMoves`, e.g. M ≙ L′ R + x′). The scene animates the true middle slice, then atomically rotates `cubeRoot` and counter-rotates every cubelet (net visual no-op). Solvers and scrambles emit outer turns only — keep it that way.
- **Scene completion order**: the animation completion settles the queue (`isAnimating = false; processQueue()`) *before* calling `onMoveCommitted`, so commit handlers can chain the next move. Reordering this stalls solution playback.

## Conventions that must not drift

- CubeKit uses the standard Kociemba conventions everywhere: corner order URF…DRB, edge order UR…BR (slice edges last), facelet indexing U0–B53, and his exact basic-move tables. The solver coordinates, facelet maps, and tests are mutually dependent on this; never "fix" one table in isolation. The anchor tests (superflip, (R U) order 105) pin the convention.
- Geometry: x → R, y → U, z → F; a face's clockwise turn is a **negative** rotation about its outward normal. `FaceletGeometry` (app) and `Face.normal` encode this; drag resolution and slice math depend on it.
- The beginner solver's corner-permutation stage uses parity-constrained U alignment (3-cycles cannot fix a transposition). Its tests verify a per-stage invariant after every stage over 200 seeded states — keep that test shape when changing stages.
- `SettingsStore`/`StatsStore` persist JSON in Application Support with all-optional snapshot fields for forward/backward tolerance; add new settings as optionals with defaults.

## Project decisions

- `ENABLE_ENHANCED_SECURITY = NO` is deliberate (user-approved): with it on, Xcode 26 builds the app arm64e but Swift packages arm64, breaking every build that uses CubeKit. Re-evaluate at release time.
- Workflow: each work chunk on a branch → PR → merge immediately. PR descriptions carry the design record (see #2 onward for the full history).
- CI (GitHub Actions, `macos-26` runners): every push/PR runs the release test suite and both app builds (unsigned). `bake-tables.yml` is a manual workflow that bakes PDB seeds on a runner for download into `Seeds/`. The repo is public under GPLv3 — keep license headers/notices intact.
- Verification habit: beyond unit tests, changes to play/scene behavior are verified interactively (launch the macOS app and drive it; `simctl` screenshots for iOS layout). macOS swallows the first click on an unfocused window — click once to focus before clicking buttons.
