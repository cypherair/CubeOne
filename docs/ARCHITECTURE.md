# Cube One — Architecture

Two layers with a hard boundary: **CubeKit** (a local Swift package holding every piece of cube logic, with no UI imports) and the **app target** (SwiftUI + RealityKit presentation). The scene renders and animates; the model decides. This document covers the parts that take more than one file to understand.

## CubeKit

### The cube model

`CubeState` represents a position at the *cubie* level, the standard Kociemba way:

- 8 corner slots: which piece occupies each slot (`cornerPermutation`) and its twist 0–2 (`cornerOrientation`)
- 12 edge slots: piece (`edgePermutation`) and flip 0–1 (`edgeOrientation`)
- Centers are fixed by definition — they define the frame.

Moves compose by permutation algebra (`composed(with:)`); the six basic face turns are Kociemba's canonical tables. Conventions (corner order URF…DRB, edge order UR…BR with slice edges last, facelet indices U0–B53) are load-bearing: solver coordinates, the facelet maps, and the tests all assume them. The test suite pins the exact convention with two anchors — the 20-move superflip must flip all 12 edges in place, and (R U) must have order 105.

`FaceletCube` is the 54-sticker view used by the editor and renderer. Converting stickers → cubies doubles as **legality validation**, with a specific error for each impossibility: wrong color counts, moved centers, impossible piece, duplicate piece, twist sum ≢ 0 (mod 3), odd flip count, mismatched permutation parity. This is what lets the editor say *why* a painted cube can't exist.

Scrambles are random *states* (uniform over all ~4.3×10¹⁹ legal positions, like official WCA scrambles), not random move sequences; the animated scramble sequence is the inverse of a solution for that state.

### KociembaSolver (the "Fast" method)

Two-phase search. Phase 1 reaches the subgroup G1 = ⟨U, D, R2, L2, F2, B2⟩ (all orientations zero, slice edges in the slice); phase 2 finishes inside G1, where only 10 moves apply.

States project onto small integer **coordinates** — phase 1: corner twist (3⁷ = 2187), edge flip (2¹¹ = 2048), slice-edge locations (C(12,4) = 495); phase 2: corner permutation (8! = 40320), U/D-edge permutation (8!), slice-edge permutation (4!). Move tables map (coordinate, move) → coordinate; pruning tables hold exact BFS distances in two projected spaces per phase, used as an admissible IDA* heuristic (take the max of the pair).

All tables (~5.5 MB) generate in ~0.2 s (release) and cache as a binary blob in Application Support. The search is **time-budgeted but soft**: the first solution found is never abandoned; the budget (default 120 ms) only caps how long the solver keeps looking for shorter ones. Typical output: 19–22 moves. The canonical move-ordering rules (never the same face twice; opposite faces only in one fixed order; phase-1 solutions must not end in a phase-2 move) keep the search non-redundant — and are themselves asserted by a test on the emitted solutions.

### BeginnerSolver (the "human" method)

The classic layer-by-layer method, seven stages, each emitting its moves into a `StagedSolution` so the UI can label playback ("Bottom cross — stage 1 of 7"):

1. **Bottom cross** — no hand-written case tables: a small BFS over *tracked pieces only* (the target edge plus already-solved cross edges, each a (slot, orientation) in a 24-state space) finds a move sequence that homes the target while returning the solved ones home. State space ≤ 24⁴.
2. **Bottom corners** — pop stuck corners with that slot's trigger, park above the slot, repeat the sexy-move insert (order 6 bounds the loop).
3. **Middle edges** — search again, but over a macro alphabet: U turns plus the eight standard left/right inserts (y-conjugated per slot). Macros that would evict an already-solved slot are excluded from the alphabet.
4. **Top cross** — F R U R' U' F' with dot/L/line alignment.
5. **Corner permutation** — an outer-turn A-perm (verified corners-only). The subtle part: 3-cycles can never fix a swapped pair, so the U-alignment that precedes each application is **parity-constrained** (turn count parity must match the permutation's parity). This is the bug the invariant tests caught.
6. **Corner orientation** — (R' D' R D) pairs at URF with U advances; the bottom layers look scrambled mid-stage but provably restore when the total twist returns to 0 (mod 3); a final U realigns.
7. **Edge permutation** — an outer-turn Ua-perm, conjugated by U^k so the preserved edge sits at the back, repeated to completion.

Algorithm conventions are *self-calibrating* where possible (e.g. the A-perm's fixed corner is computed from the cube algebra at startup, not assumed). Every loop has an iteration guard that throws instead of hanging. The test sweep solves 200 seeded random states and asserts the stage invariant after **every** stage, not just the end state.

### ThistlethwaiteSolver (four-phase group reduction)

Thistlethwaite's 1981 algorithm: restrict the move set in four steps, each landing the cube in a smaller subgroup — G0 ⊃ G1 = ⟨U, D, L, R, F2, B2⟩ ⊃ G2 = ⟨U, D, R2, L2, F2, B2⟩ ⊃ G3 = ⟨U2, D2, R2, L2, F2, B2⟩ ⊃ solved. Each phase has its own exact BFS distance table over a small coordinate, so solving is a **greedy descent**: from distance d, apply any allowed move whose table entry reads d − 1. Every phase move set is closed under inverses, so the move graph is undirected and such a move always exists — each phase comes out provably shortest for its goal. The known worst cases are 7 + 10 + 13 + 15 = 45 moves (the test suite pins all four maxima); typical solves run ~30–45.

Per-phase coordinates: ① edge flip (2048); ② corner twist × slice-edge locations (2187 × 495); ③ corner permutation × M-edge separation (40320 × C(8,4)); ④ within the square group, the 96 half-turn-reachable corner permutations × the three within-slice edge permutations (96 × 24³, of which exactly half is reachable — half turns are even permutations).

Phase 3's goal is the subtle one (Thistlethwaite's "tetrad twist" condition). Instead of deriving it by hand, the table seeds a **multi-source BFS from the whole goal coset**: every half-turn-reachable corner permutation with the M edges home is distance 0. That is provably the exact G3 membership test for a G2 state — legality ties edge parity to corner parity, and 96 × 6912 matches the square group's order exactly.

All four tables (~5 MB) generate in about a second (release) and cache as `thistlethwaite-tables.bin` in Application Support, built lazily on the first Thistlethwaite solve. Playback shows the four named stages just like the beginner method (`StagedSolution` is generic over the stage kind: `StagedSolution<ThistlethwaiteStage>`).

### OptimalSolver (proven-shortest solutions)

Korf-style IDA* over **pattern databases**: nibble-packed tables holding the exact solve distance of three projections — all corner configurations (88M entries), and two overlapping edge subsets (7-edge tier: 2×511M entries ≈ 0.5 GB; 8-edge tier: 2×5.1B entries ≈ 4.8 GB). The heuristic is the max of the three lookups (admissible), so the first solution found by per-bound exhaustive deepening is provably optimal.

Generation is a parallel scan BFS over a memory-mapped byte-per-entry scratch file (the OS pages it; no multi-GB allocations): forward passes expand entries at the current depth via per-move transforms hoisted per piece-arrangement, with the orientation transform reduced to a single XOR for edge tables. Same-value byte races between workers are benign; completeness is verified by an exact final scan. Tables are then nibble-packed with a versioned header and mmapped read-only for lookups — file-backed clean pages, so even the 8-edge tier is safe (if not fast) under iOS memory limits (the app carries the increased-memory-limit and extended-virtual-addressing entitlements).

The search runs on a SIMD-backed `FastCube` with table-driven move application; canonical 3-move prefixes feed a shared work queue across the cores (one is left free for the UI) with an abort flag and per-bound barriers. The existing two-phase solver provides an instant upper bound: exhausting every depth below it proves *its* solution optimal.

**Measured on the 16 GB M5 MacBook Air (release build, June 2026):**

| What | Result |
|---|---|
| 7-edge bake (one-time) | ~2 min, 555 MB |
| 8-edge bake (one-time) | ~75 min, 5.15 GB |
| Search throughput | ~30–35M positions/s sustained |
| Random cube, optimal 17, 7-edge tier | proven in ~1 min |
| Random cube, optimal 18, 8-edge tier | d17 exhausted in ~5 min (9.5B positions); solution found and proven at ~15–20 min total |

Memory stays healthy throughout: the tables are file-backed clean pages, so the app's footprint is the OS page cache doing its job, not dirty memory.

Compressed LZFSE *seeds* of the tables can ship inside the app bundle (a build phase copies any present in the gitignored `Seeds/` folder); the loader installs from seeds before offering generation.

### SliceMove (M/E/S)

`CubeState` fixes centers, but a real middle-slice turn moves them. The resolution: each slice move is defined by its **fixed-center equivalence** — an outer-turn pair plus a whole-cube reorientation:

| Slice | Outer pair | Frame rotation |
|-------|-----------|----------------|
| M (follows L) | L′ R | x′ |
| E (follows D) | U D′ | y′ |
| S (follows F) | F′ B | z |

Applying a slice to the model means applying the outer pair; the reorientation lives purely in the renderer (below). Solvers and scrambles keep emitting outer turns only.

## The app

### State flow

`AppModel` owns the logical `CubeState` and is the only thing that mutates it. The 3D scene animates turns from a queue and reports each completed turn through one callback; `AppModel.commit` applies it to the state. Every enqueued animation is paired with a **`MoveIntent`** (user / undo / redo / scramble / solutionForward / solutionBack) in a FIFO parallel to the scene queue — the commit handler switches on the intent to update undo history, the move counter, timer phases, or solve-session progress. This one mechanism keeps history correct across every flow that animates moves.

Modes (solve playback, sticker editor, timer) are session structs on `AppModel`; entering one disables direct turns in the scene and swaps the bottom panel in `PlayView`.

### The 3D scene

`CubeSceneController` builds 26 cubelet entities; the 54 sticker entities (the only collision/hit-testable surfaces) carry their facelet index and home normal. Two invariants make the rendering robust:

- **Base state + transforms**: sticker colors always render the state at the last `rebase(to:)`; cubelet transforms encode the moves performed since. The editor runs on a rebased scene so sticker-entity ↔ facelet-index is one-to-one.
- **Snap after every turn**: positions re-quantize to the grid and orientations to the nearest 90° basis after each animation, so floating-point drift can never accumulate.

A face turn re-parents its 9 cubelets under a pivot, animates 90°, snaps, and reports. A **slice turn** animates the true middle nine (centers move on screen), then atomically re-expresses the result in fixed-center terms: rotate `cubeRoot` by the slice rotation and counter-rotate every cubelet — a net visual no-op after which the slice's own cubelets are back at their home transforms (centers never move in the model) and the outer layers sit exactly where the equivalent outer pair would have put them.

One ordering rule: the animation completion settles the queue (clears `isAnimating`, processes the next item) *before* reporting the commit, so a commit handler may immediately enqueue a follow-up (this is what drives solution autoplay).

### Gestures

A drag starting on a sticker resolves to a turn by physics, not heuristics about faces: for each candidate rotation axis perpendicular to the sticker's current normal, compute the sticker's velocity under that rotation (axis × position), project it to screen space through the current cube orientation and camera, and pick the axis/direction whose projection best matches the drag. Outer layers produce face moves; the middle layer (including center stickers) produces slice moves.

Orbiting only ever *begins* on empty space (a latch decided at gesture start), with a three-way lock mode (free / layers-only / view-only — in view-only the whole cube surface becomes an orbit handle). On iOS, an optional two-finger mode routes both the orbit pan and pinch zoom through UIKit recognizers sharing a simultaneous-recognition delegate (SwiftUI's pinch won't share two-finger touches with a UIKit pan). The camera auto-fits the viewport aspect so the cube fits any window or device; pinch zoom is a clamped multiplier on the fit distance.

### Persistence

Three small JSON files in Application Support: solver tables aside, `state.json` (current cube state, restored at launch), `stats.json` (timed-solve records), `settings.json` (preferences; snapshot fields are all optional with defaults so older files always load). Sounds are synthesized at runtime (a filtered noise click) — no audio assets.
