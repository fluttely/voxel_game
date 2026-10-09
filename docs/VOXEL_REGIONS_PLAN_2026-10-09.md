# The settled-regions plan (SR) — 2026-10-09

**Question.** OC0 counted that drawing the terrain in 4 × 4-chunk regions instead of
PF14's 2 × 2 would leave 56.3 region draws in the frustum at `orbit:12` where there are
134.3 (−58.1%), and −51.0% at `fly`. On the phone at radius 12, the UI thread is bound by
flutter_scene's encode at ~31 µs a draw (PF17). Can the kit take that cut without bringing
back the hitch PF14 measured for regions of 4, and without losing what OC3's cave cull hides
underground?

**Answer, in brief.**

- **PF14's verdict on regions of 4 is stale.** It measured a 24.5 ms step p99 at `fly`
  (`docs/perf/pf14_s24_phone_r4_regions{2,4}.jsonl`) on a tree that had no greedy meshing
  (PF15), still packed floats into every rebuild (before PF13's pack-once), and rebuilt a
  region at every chunk's arrival with no budget (before PF2). All three landed after it.
  What a 16-chunk rebuild costs today has not been measured.
- **Two shapes are on the table.** In **P (plain)**, `regionChunks` becomes 4: a one-line
  change, but every edit and every streamed chunk rebuilds 16 chunks' geometry. In
  **S (settled)**, the view draws 2 × 2 as it does today, and merges a 4 × 4 only once its
  16 chunks have all arrived and stayed unchanged for a while. An edit then costs what it
  costs today. S is more code. It is the lead only if P's cost does not fit the frame.
- **SR0 decides, offline and without a device.** It recounts OC0's draws under the settle
  rule (only complete 4 × 4s merge), counts the draws OC3's cull still hides underground,
  sizes every complete 4 × 4's geometry, and times a 16-chunk merge on the Mac. It sends no
  run to the phone (CLAUDE.md §Benchmarks).
- **The phone A/B waits for the owner.** So does OC's, which has not run either. If the
  owner asks for both, OC's runs first, so that SR's before is OC3's tree.

Every `file:line` below was read on 2026-10-09 at `0bd57ba`, flutter_scene at the
`0.24.3` pub tag. Re-check a reference before a step starts.

---

## Progress

| Step | State | Gate |
|:---|:---|:---|
| SR0 What 4 × 4 regions would cost and save, counted offline | **done 2026-10-09** at `9290233`, no device. **The harness** (a throwaway `flutter test` under the example, not committed): seed 2024, spawn (6.5, 48, −4.5) in chunk (0, −1), the 625 chunks generated and meshed with light by the real mesher, each surface's bounds from its vertices' heights as `_bounds` takes them, `MirroredCamera` at fov 72°, far 208 m, 1600 × 900, tested as flutter_scene's BVH tests a world AABB (`Frustum.intersectsWithAabb3`). It reproduces OC0 before anything else: 373 region draws (2 × 2) in the window, **134.25 in the frustum at `orbit:12`** (eye y 65.62), 153 at `fly`, 120.0 at under2 with 16 chunks reached. **Layouts in the window:** 2 × 2 is 169 regions, 373 draws; P (4 × 4 everywhere) is 49 regions, 123 draws; S is 36 complete 4 × 4s (576 chunks, the 6 × 6 the plan predicted) and 25 edge 2 × 2s, so 61 regions and 143 draws. **Draws in the frustum** (2 × 2 · P · S): `orbit:12` mean of 8 yaws 134.25 · 51.0 (−62.0%) · **56.25 (−58.1%)**; `fly` t = 0 153 · 64 · 75. S matches OC0's C (56.3, 75) to the draw at both poses, so OC0's C was already the settle rule's count, despite what §What the code says states. **Vertices in the frustum:** `orbit:12` 1,075,340 · 1,268,172 (+17.9%) · 1,262,318 (+17.4%); `fly` 1,311,580 · 1,484,792 · 1,484,792 (+13.2%). **Underground, with the real `SectionOcclusion`** over the meshes' `ChunkVisibility`: under2 (`Bench.caveEye`, 8 yaws, pitch 0) shows 4.5 · 4.0 · **4.0** draws, but 60,005 · 167,625 · 167,625 vertices (S draws 2.8× the geometry where the cave hides the rest). The sample: 64 cells drawn with `Random(2024)` from the 5,261 air cells with sky light 0 within 32 m of the spawn **horizontally** (OC0's 32 m was horizontal: under2 is 21 m from the spawn in x–z and 43 m in 3D). OC0's own 64 are not recoverable; this sample's 2 × 2 hidden share is mean 85.6%, median 95.5%, ≥ 50% in 57 of 64, against OC0's 82.1%, 96.3% and 55. Draws shown, mean / median / worst: 2 × 2 17.9 / 5.25 / 127.1; P 9.0 / 4.25 / 50.1; S 9.5 / **4.25** / 54.75. S shows more than 2 × 2 in 12 of 64 cells, by at most 1.4 draws. **Each complete 4 × 4:** 35,348 to 119,948 vertices, median 67,964; the largest is 2.62 MB on the GPU. **16-bit indices:** the solid surface of 19 of the 36 passes 65,536 vertices and takes 32-bit indices; no cutout, glow or liquid surface does. **The window's GPU bytes** (16 B a lit vertex, 72 B a glow vertex, indices at their width): 2 × 2 53.49 MB; P 58.43 MB (+9.2%, the 32-bit indices); S alone 58.43 MB; S with keep-beside 106.82 MB, **53.34 MB extra** (50.9 MiB). **The merge:** `PackedSurface.merge` for the three lit surfaces plus `MergedSurface.of` for the glow, in an AOT executable (`dart compile exe`) on the Mac (M2 Pro, load average ~6 on 12 cores from other work while it ran), over synthetic surfaces with each member chunk's counted sizes, median of 300 runs, two runs: largest 4 × 4 (119,948 vertices) 1.23–1.32 ms; median 4 × 4 0.61–0.63 ms; largest 2 × 2 (35,488) 0.33–0.34 ms; median 2 × 2 (16,088) 0.13 ms. That is 8–11 ns a vertex, and 15.6 ns with PF2's upload share, which agrees with PF2's 16 ns a vertex for merge and upload. **Estimates, not measurements**, at PF2's upload share (19 : 34 of the merge) and PF2's phone factor (4× the Mac), merge plus upload on the phone: largest 4 × 4 ~8.0 ms; median 4 × 4 ~3.9 ms; largest 2 × 2 ~2.1 ms (today's worst region is already at the budget); median 2 × 2 ~0.8 ms. For SR1: a chunk's share of the largest 4 × 4 merge is ~0.3 ms on the phone (est.), but uploading its solid surface (113,352 vertices) in one frame is ~2.6 ms (est.), over the budget alone. **Gates.** **G1 passes**: S is 41.9% of the 2 × 2 count, under 75%. **G2 passes**: under2 4.0 ≤ 4.5, sample median 4.25 ≤ 5.25 (12 cells of 64 show up to 1.4 more). **G3 fails, so S**: the largest 4 × 4 is ~8.0 ms on the phone (est.), 4× `rebuildBudgetUsec`; even the median 4 × 4 is ~3.9 ms. **G4 fails, so rebuild-then-swap**: keep-beside holds 53.3 MB more, over 32 MB. The counts stayed local | **G1**: at `orbit:12`, mean of 8 yaws, the draws in the frustum under the settle rule are ≤ 75% of the 2 × 2 count (OC0's 25% bar). Missing it ends the plan. **G2**: at under2 and at the median of OC0's 64 dark-air cells, with OC3's cull, S shows no more draws than 2 × 2 does. **G3**, which picks P or S: the largest complete 4 × 4 in the window, merged on the Mac in AOT, × 4 for the phone (PF2's ratio), plus the upload at PF2's share, fits in `rebuildBudgetUsec` (2 ms). If it fits, P; if not, S. **G4**, which picks how S splits: the extra GPU bytes S keeps at radius 12 if a settled 4 × 4 keeps its four 2 × 2s beside it ≤ 32 MB |
| SR1 The design, from SR0's numbers | **next** | this plan's §Design rewritten as decided, every fork closed; the owner reads it before SR2 |
| SR2 Regions of two sizes in `VoxelChunkView` (S only) | waits on SR1 | `voxel_scene` tests below; the suite green; nothing settles yet, so the view draws exactly as today |
| SR3 Settling and splitting (S) · or the default of 4 (P) | waits on SR1 (S: on SR2) | `voxel_scene` and `voxel_game` tests below; the suite green; seen on the Mac |
| SR4 The merge off the frame (S, only if SR0's merge does not fit the budget whole) | waits on SR0 | its own tests; the suite green |
| SR5 The A/B | **only when the owner asks** | `orbit:12`, `fly:12`, `cave:12`, and `orbit:12 -- --edits=8` on the S24 against SR3's parent |

Effort per step: SR0 `high` (a throwaway count that must agree with the view's real bounds
and OC3's real search), SR1 `high` (the forks decide what can pop or hitch), SR2 `medium`,
SR3 `high` (state across frames, a visual check), SR4 `high`, SR5 `medium`, and only on the
owner's word.

---

## What the code says (read before SR0)

**The view.** `VoxelChunkView` (`packages/voxel_scene/lib/src/voxel_chunk_view.dart`):

- `regionChunks` is a constructor argument, default 2 (`:40`). It is asserted to keep a
  region under 256 m a side (`:42–45`), which 4 × 16 = 64 m does. `GameWorld` builds the view
  with the default (`packages/voxel_game/lib/src/world/game_world.dart:64`). No game passes
  another size. The `regionChunks` of `StructureSpec` is the structure grid's, unrelated.
- One `Node` per region, keyed by the region's position (`:94`); `regionOf` floors by
  `regionChunks` (`:132`). The view keeps every chunk's surfaces (`_chunks`, `:91`), the
  lit ones packed once on first read (`_ViewChunk.pack`, `:374`).
- `apply` and `remove` only mark the region dirty (`:137`, `:146`). `rebuild(near)` builds
  the dirty regions nearest first, while the next region's predicted cost fits in 2 ms; the
  **first region of a frame is built whatever it costs** (`:222`). Under P, then, an edit
  beside the player costs one 16-chunk build in that frame, however large it is.
- `_build` (`:254`) merges every member's packed surface into one `TerrainGeometry` per lit
  surface (`PackedSurface.merge`, `packed_surface.dart:65`), the glow into one
  `MeshGeometry` (`MergedSurface.of`), with `shadowStatic = true` on each (`:306`, `:324`).
  `merge` writes 16-bit indices while the region's vertices fit in 65,536, and 32-bit ones
  after (`packed_surface.dart:74`). A 4 × 4 may cross that line; SR0 counts it.
- `_bounds` (`:295`) and `_reached` (`:186`) read `regionChunks`: one size for every region.
- `cull(eye)` (`:159`) shows a region when any of its chunks with a mesh was reached
  (`_reached`). A 4 × 4 shows when any of its 16 chunks is, so it hides less underground.

**The geometry of a settle rule.** The streamer's window at radius 12 is 25 × 25 chunks, and
4 × 4 regions are aligned to multiples of 4. Any 25 consecutive chunks hold 5 or 6 whole
aligned runs of 4, so the window holds **25 to 36 complete 4 × 4s (400 to 576 of its 625
chunks)**, depending on where the focus stands. The rest, at the edge, stays 2 × 2. At the
benchmark's spawn (chunk (0, −1)), the window spans x −12…12 and z −13…11, which gives 6 × 6
= 36 complete 4 × 4s. OC0's C count did not apply this rule; SR0 recounts with it.

**The static shadow cache** (`~/.pub-cache/hosted/pub.dev/flutter_scene-0.24.3/lib/src/`):

- The signature hashes every visible static caster's geometry, material and position
  (`scene.dart:3324–3355`). It is recomputed when the scene's structure or a static flag
  changes.
- Any change marks **every** cascade tile stale. Stale tiles refresh amortized, a bounded
  number a frame (`render/shadow_cache.dart:172–181`).
- Today every region rebuild already changes the signature. A settle or a split is one more
  rebuild of that kind, no different in what it costs the cache. At `fly:12`, a column of
  25 chunks enters every second, ~25 region rebuilds a second (PF2's design); one complete
  column of 4 × 4s every 4 s adds ~1.5 settles a second.
- A tile refresh draws every static caster in its cascade. With 4 × 4 regions it draws fewer,
  larger casters: the same cut as in the colour pass, applied to the shadow pass's encode
  whenever a tile refreshes.

**Measurements that exist.** PF2's probe, on the Mac at `72e53e9`: a region's rebuild was
40% packing, 34% merging and 19% upload, with merge and upload together at 16 ns a vertex.
Pack-once (PF13) has since moved packing to a chunk's first read. On the phone, CPU work
ran about 4× slower than on the Mac (PF2's design: "the Mac, four times faster"). Those two
figures are all SR0 can use to estimate the phone without a run, and SR0 says so wherever
it uses them.

---

## Design, as it stands before SR0

SR1 rewrites this section with SR0's numbers. What follows are the lead and the forks that
SR0 closes.

**P, if G3 passes.** `GameWorld` builds `VoxelChunkView(regionChunks: 4)`, or the default
becomes 4. Nothing else changes: the budget, pack-once and the cull already work at any
size. An edit, or a streamed chunk, rebuilds 16 chunks, at most once a frame per region.

**S, if G3 fails.**

- **Two sizes.** The view keeps 2 × 2 regions as its unit of building and adds a settled
  layer of 4 × 4 regions over it. The settled size is a constructor argument
  (`settledRegionChunks`, a multiple of `regionChunks`), as `regionChunks` is. There is no
  `GraphicsSpec` knob (OCD6: the A/B compares commits).
- **The settle rule.** A 4 × 4 settles when all 16 of its chunks have a mesh and none was
  applied or removed for a quiet time. The lead value is 2 s, measured by a `Stopwatch`, not
  in frames, since frame counts vary with the display rate. Two seconds keeps PF11's
  `--edits` cube, toggled every second, unsettled; SR1 confirms the value. An incomplete
  4 × 4, at the window's edge, never settles.
- **Settling is optional work.** It runs in `rebuild` after every dirty 2 × 2, and only in
  what is left of the budget. It is never the frame's forced first region, because the
  2 × 2s still draw while it waits.
- **The merge can be resumed.** The 16 chunks' packed words are immutable once packed:
  `apply` replaces a `_ViewChunk` and never writes into one. So the merge can copy chunk by
  chunk into preallocated lists over several frames, abandon the work if a member changes,
  and upload one surface a frame. The swap happens when all four surfaces are up. SR4 moves
  the copy to a worker isolate only if SR0 shows that even one chunk's share does not fit.
- **Splitting on a change (the G4 fork).**
  - **Lead, keep-beside:** a settled 4 × 4 keeps its four 2 × 2 nodes built but out of the
    scene. A change detaches the 4 × 4 and attaches the four 2 × 2s in the same `rebuild`,
    and the dirty one rebuilds as today. An edit costs exactly what it costs today. The price
    is GPU memory: the settled area's geometry is held twice. Detached nodes are not in the
    render scene, so they are neither encoded nor part of the shadow signature.
  - **If G4 fails, rebuild-then-swap:** a change marks the four quadrants dirty and keeps
    the 4 × 4 drawn until all four are built, then swaps. The edit then shows a few frames
    late on the phone. SR1 weighs that delay against building the four quadrants in the
    edit's frame.
- **The cull.** A settled 4 × 4 is shown when any of its 16 chunks is reached. A new node,
  whether settled or split, takes the last search's state, as `_build` gives a new region
  today. `cull` never touches `visible`, `shadowCastingMode` or `shadowStatic` (OCD1 holds).

---

## Steps

### SR0 — what 4 × 4 regions would cost and save, counted offline

There is no device and no benchmark. Only headless counts run, on the Mac. The count stays
local, as OC0's did, and only its numbers are committed, in SR0's Progress row.

- **The world.** As OC0 and OC4 built it: the example's spec, seed 2024, the radius-12
  window around the spawn, generated and meshed in a `flutter test` under
  `packages/voxel_game/example/`. The meshes come from the real mesher, and the bounds from
  the real `PackedSurface` minY/maxY, as `_bounds` uses them.
- **The poses.** OC0's own: `orbit:12` (8 yaws), `fly` at t = 0, under2 (`Bench.caveEye`),
  and the 64 dark-air cells within 32 m. Camera as OC0 had it: `MirroredCamera`, 1600 × 900.
- **What it counts.**
  - **Draws in the frustum** at each pose, for three layouts:
    - 2 × 2 everywhere (to reproduce OC0's 134.3, which checks the harness);
    - 4 × 4 everywhere (P; OC0's 56.3);
    - S: complete 4 × 4s, with 2 × 2 at the edges.
  - **Vertices in the frustum** for the same three layouts. A bigger box drags more geometry
    past flutter_scene's frustum test (`node.dart:132`). Not gated; it is the Mac GPU's side
    of the trade.
  - **Underground, with the cull:** the real `SectionOcclusion` from the real
    `ChunkVisibility`, then the draws shown for each layout at under2 and across the
    sample (mean, median, worst).
  - **Each complete 4 × 4:** lit and glow vertices, indices, whether 16-bit indices still
    fit, and GPU bytes (16 B a packed vertex, the glow's at flutter_scene's 72, indices at
    their width). Also the window's total bytes for 2 × 2, for P, and for S with keep-beside
    (G4).
  - **The merge time.** `PackedSurface.merge` of the largest and the median complete 4 × 4,
    and of a 2 × 2 for comparison. Timed in an AOT executable (`dart compile exe`), because
    `flutter test` runs JIT with asserts on. `packed_surface.dart` imports only
    `dart:typed_data` and `voxel_engine`, so a script can use it. Merge time depends only
    on the sizes, so the script merges synthetic surfaces of the counted sizes. The upload
    is estimated at PF2's ratio (19 : 34 of the merge), and the phone at 4× the Mac. Both
    estimates are named as such in the row.
- **The gates** are in the Progress table. G1 decides whether the plan goes on; G2 must hold
  for S; G3 picks P or S; G4 picks how S splits.

### SR1 — the design, from SR0's numbers

- Rewrite §Design as decided: P or S; for S, the quiet time, keep-beside or
  rebuild-then-swap, and whether SR4 is needed.
- A settled 4 × 4 that holds the focus's chunk: if SR0 shows the near edits would keep it
  splitting, it never settles. SR1 decides, with SR0's churn arithmetic.
- The owner reads the section before SR2.

### SR2 — regions of two sizes in `VoxelChunkView` (S only)

- Each region node carries its size. `_bounds`, `_reached` and `_show` take the size from
  the node, not from the view.
- The node map holds both sizes, keyed so a 2 × 2 and a 4 × 4 at the same corner cannot
  collide.
- `settledRegionChunks` is a new constructor argument, asserted to be a multiple of
  `regionChunks` and under the 256 m limit. Nothing settles in this step.
- Tests (`packages/voxel_scene/test/voxel_chunk_view_test.dart`, no GPU, empty surfaces as
  the existing ones use): a 4 × 4 node built by hand has the right bounds and reached state;
  `cull` shows it when any of its 16 chunks is reached; the cull leaves `visible`,
  `shadowCastingMode` and `shadowStatic` alone on both sizes.
- `voxel_scene/CHANGELOG.md`.

### SR3 — settling and splitting (S) · or the default of 4 (P)

**Under S:**

- The settle rule, the resumable merge, and the split as SR1 decided them.
- `pendingRegions` and `GameWorld.isIdle` do not wait for a settle. Settling is optional,
  and the benchmark's fill must not wait on it.
- **Tests:**
  - 16 chunks applied, then the quiet time, then `rebuild`: one 4 × 4 node, no 2 × 2 node
    in the scene;
  - an incomplete 4 × 4 never settles;
  - an `apply` into a settled region shows four 2 × 2s within the same `rebuild`, with the
    dirty one rebuilt;
  - a `remove` (the window leaving) splits the region with no merge work;
  - a settle never runs as a frame's forced first region, and stays inside what is left of
    the budget;
  - a member changing mid-merge abandons the merge;
  - a settled node takes the last cull's state;
  - every node has `shadowStatic`.
- **`voxel_game`:** `isIdle` is reached with settles still pending.

**Under P:** the default changes, and the test that builds `regionChunks: 4` becomes the
default's. PF14's region tests are re-read for the size they assume.

**Both:**

- Visual check on the Mac (`cd packages/voxel_game/example && flutter run -d macos`):
  - fly along a settle boundary;
  - break and place blocks in a settled area: the edit shows at once, no hole, no
    z-fighting during the swap;
  - water seen through water across a former 2 × 2 border (one blended draw now holds more
    faces);
  - a cave, as OC3's check had it;
  - a shadow cast across a settled region's edge.
- `CHANGELOG.md` of `voxel_scene`, and of `voxel_game` if `GameWorld` changed. Under S,
  `README.md` mentions the new argument.

### SR4 — the merge off the frame (S, only if SR0 says so)

- If one chunk's share of a 4 × 4 merge, plus one surface's upload, does not fit what the
  budget usually leaves: the copy moves to a worker isolate, and the words go out as
  `TransferableTypedData`. `packed_surface.dart` is pure Dart, so it runs there (rule 3
  holds for the code, not the package).
- Only the upload and the swap stay on the UI thread. Tests: a merge done on the worker
  matches a merge done inline, word for word.

### SR5 — the A/B (only when the owner asks)

- Galaxy S24, phone preset, three rounds alternated, the base at 36 °C. SR3's commit runs
  against its parent at `orbit:12` and `fly:12` (the draws and the streaming), `cave:12`
  (the cull's granularity), and `orbit:12 -- --edits=8` (edits once a second: the cube's own 4 × 4 must stay split while its neighbours settle).
- **Judged by:** encode and UI p50 at `orbit:12`, step p99 and hitches at `fly:12`, step
  p99 with edits, RSS everywhere.
- Each line records the machine's load (PFD1).

---

## Out of scope

- **Regions larger than 4 × 4.** At radius 12 the window holds at most 36 complete ones;
  8 × 8 would leave most of the window at the edge rule. Revisit only if a larger radius
  becomes a target.
- **Splitting meshes per section.** It adds draws (OC plan, OCD2).
- **flutter_scene's per-draw cost.** That is upstream's, followed in PF16's issue
  (bdero/flutter_scene#435) and the FS plan.
- **Any benchmark run.** It waits for the owner's word, as SR5 does.
