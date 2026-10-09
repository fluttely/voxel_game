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
- **SR1 decided S** (§Design): 4 × 4s merge only once settled, outside a clear zone around
  the focus, in parts of at most 65,536 vertices a draw, over several frames; a change splits
  one by rebuilding its four 2 × 2s while it stays drawn. SR4 is dropped.
- **The phone A/B waits for the owner.** So does OC's, which has not run either. If the
  owner asks for both, OC's runs first, so that SR's before is OC3's tree.

Every `file:line` below was read on 2026-10-09 at `0bd57ba`, flutter_scene at the
`0.24.3` pub tag. Re-check a reference before a step starts.

---

## Progress

| Step | State | Gate |
|:---|:---|:---|
| SR0 What 4 × 4 regions would cost and save, counted offline | **done 2026-10-09** at `9290233`, no device. **The harness** (a throwaway `flutter test` under the example, not committed): seed 2024, spawn (6.5, 48, −4.5) in chunk (0, −1), the 625 chunks generated and meshed with light by the real mesher, each surface's bounds from its vertices' heights as `_bounds` takes them, `MirroredCamera` at fov 72°, far 208 m, 1600 × 900, tested as flutter_scene's BVH tests a world AABB (`Frustum.intersectsWithAabb3`). It reproduces OC0 before anything else: 373 region draws (2 × 2) in the window, **134.25 in the frustum at `orbit:12`** (eye y 65.62), 153 at `fly`, 120.0 at under2 with 16 chunks reached. **Layouts in the window:** 2 × 2 is 169 regions, 373 draws; P (4 × 4 everywhere) is 49 regions, 123 draws; S is 36 complete 4 × 4s (576 chunks, the 6 × 6 the plan predicted) and 25 edge 2 × 2s, so 61 regions and 143 draws. **Draws in the frustum** (2 × 2 · P · S): `orbit:12` mean of 8 yaws 134.25 · 51.0 (−62.0%) · **56.25 (−58.1%)**; `fly` t = 0 153 · 64 · 75. S matches OC0's C (56.3, 75) to the draw at both poses, so OC0's C was already the settle rule's count, despite what §What the code says stated until SR1. **Vertices in the frustum:** `orbit:12` 1,075,340 · 1,268,172 (+17.9%) · 1,262,318 (+17.4%); `fly` 1,311,580 · 1,484,792 · 1,484,792 (+13.2%). **Underground, with the real `SectionOcclusion`** over the meshes' `ChunkVisibility`: under2 (`Bench.caveEye`, 8 yaws, pitch 0) shows 4.5 · 4.0 · **4.0** draws, but 60,005 · 167,625 · 167,625 vertices (S draws 2.8× the geometry where the cave hides the rest). The sample: 64 cells drawn with `Random(2024)` from the 5,261 air cells with sky light 0 within 32 m of the spawn **horizontally** (OC0's 32 m was horizontal: under2 is 21 m from the spawn in x–z and 43 m in 3D). OC0's own 64 are not recoverable; this sample's 2 × 2 hidden share is mean 85.6%, median 95.5%, ≥ 50% in 57 of 64, against OC0's 82.1%, 96.3% and 55. Draws shown, mean / median / worst: 2 × 2 17.9 / 5.25 / 127.1; P 9.0 / 4.25 / 50.1; S 9.5 / **4.25** / 54.75. S shows more than 2 × 2 in 12 of 64 cells, by at most 1.4 draws. **Each complete 4 × 4:** 35,348 to 119,948 vertices, median 67,964; the largest is 2.62 MB on the GPU. **16-bit indices:** the solid surface of 19 of the 36 passes 65,536 vertices and takes 32-bit indices; no cutout, glow or liquid surface does. **The window's GPU bytes** (16 B a lit vertex, 72 B a glow vertex, indices at their width): 2 × 2 53.49 MB; P 58.43 MB (+9.2%, the 32-bit indices); S alone 58.43 MB; S with keep-beside 106.82 MB, **53.34 MB extra** (50.9 MiB). **The merge:** `PackedSurface.merge` for the three lit surfaces plus `MergedSurface.of` for the glow, in an AOT executable (`dart compile exe`) on the Mac (M2 Pro, load average ~6 on 12 cores from other work while it ran), over synthetic surfaces with each member chunk's counted sizes, median of 300 runs, two runs: largest 4 × 4 (119,948 vertices) 1.23–1.32 ms; median 4 × 4 0.61–0.63 ms; largest 2 × 2 (35,488) 0.33–0.34 ms; median 2 × 2 (16,088) 0.13 ms. That is 8–11 ns a vertex, and 15.6 ns with PF2's upload share, which agrees with PF2's 16 ns a vertex for merge and upload. **Estimates, not measurements**, at PF2's upload share (19 : 34 of the merge) and PF2's phone factor (4× the Mac), merge plus upload on the phone: largest 4 × 4 ~8.0 ms; median 4 × 4 ~3.9 ms; largest 2 × 2 ~2.1 ms (today's worst region is already at the budget); median 2 × 2 ~0.8 ms. For SR1: a chunk's share of the largest 4 × 4 merge is ~0.3 ms on the phone (est.), but uploading its solid surface (113,352 vertices) in one frame is ~2.6 ms (est.), over the budget alone. **Gates.** **G1 passes**: S is 41.9% of the 2 × 2 count, under 75%. **G2 passes**: under2 4.0 ≤ 4.5, sample median 4.25 ≤ 5.25 (12 cells of 64 show up to 1.4 more). **G3 fails, so S**: the largest 4 × 4 is ~8.0 ms on the phone (est.), 4× `rebuildBudgetUsec`; even the median 4 × 4 is ~3.9 ms. **G4 fails, so rebuild-then-swap**: keep-beside holds 53.3 MB more, over 32 MB. The counts stayed local | **G1**: at `orbit:12`, mean of 8 yaws, the draws in the frustum under the settle rule are ≤ 75% of the 2 × 2 count (OC0's 25% bar). Missing it ends the plan. **G2**: at under2 and at the median of OC0's 64 dark-air cells, with OC3's cull, S shows no more draws than 2 × 2 does. **G3**, which picks P or S: the largest complete 4 × 4 in the window, merged on the Mac in AOT, × 4 for the phone (PF2's ratio), plus the upload at PF2's share, fits in `rebuildBudgetUsec` (2 ms). If it fits, P; if not, S. **G4**, which picks how S splits: the extra GPU bytes S keeps at radius 12 if a settled 4 × 4 keeps its four 2 × 2s beside it ≤ 32 MB |
| SR1 The design, from SR0's numbers | **done 2026-10-09**, no code, no device. **S, split by rebuild-then-swap**, every fork closed in §Design. **The upload** cannot be split across frames: `uploadVertexStreams` allocates, writes and binds in one call, and `setVertexStreams` is `@internal` (flutter_scene `geometry.dart:641`, `:261`). So a settled 4 × 4 draws each lit surface in parts of ≤ 65,536 vertices, ≤ ~1.5 ms to upload on the phone (est.), which also keeps every index 16-bit: S's window is 2 × 2's 53.49 MB on the GPU, not 58.43. **SR4 dropped**: a worker would move the copy (~0.3 ms a chunk, est., it fits) and not the upload. **Quiet time** 2 s by one `Stopwatch` (liquids step every 0.25 s / 0.6 s; streaming does not remesh a meshed chunk). **The clear zone**: no 4 × 4 within 2 chunks of the focus settles (`1 + ⌈reach / 16⌉`; an edit remeshes its 3 × 3 ring), so the player's own edits go today's path; it is always 2 × 2 of the 4 × 4s, ~+25 draws (est. from SR0's averages). **A split** keeps the 4 × 4 drawn until its four quadrants are built, then swaps in one `rebuild`: 3 frames later than today at the largest, 1–3 at the median (est.); only far changes wait on it. **G1 with zone and parts** ~88 of 134.25 (~66%, est.), not counted | this plan's §Design rewritten as decided, every fork closed; the owner reads it before SR2 |
| SR2 Regions of two sizes in `VoxelChunkView` | **next**, once the owner has read §Design | `voxel_scene` tests below; the suite green; nothing settles yet, so the view draws exactly as today |
| SR3 Settling and splitting | waits on SR2 | `voxel_scene` and `voxel_game` tests below; the suite green; seen on the Mac |
| SR4 The merge off the frame | **dropped by SR1**: the copy fits a chunk at a time, and the step over budget, the upload, cannot leave the UI thread | — |
| SR5 The A/B | **only when the owner asks** | `orbit:12`, `fly:12`, `cave:12`, and `orbit:12 -- --edits=8` on the S24 against SR3's parent |

Effort per step: SR0 `high` (a throwaway count that must agree with the view's real bounds
and OC3's real search), SR1 `high` (the forks decide what can pop or hitch), SR2 `medium`,
SR3 `high` (state across frames, a visual check), SR5 `medium`, and only on the owner's
word. SR4 was dropped by SR1.

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
= 36 complete 4 × 4s. OC0's C count was already this rule's count: SR0's S matches it to the
draw (56.25 at `orbit:12`, 75 at `fly`).

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

## Design (decided in SR1, 2026-10-09)

**S, split by rebuild-then-swap.** Every phone figure below is an estimate SR0 derived
from PF2's two ratios (the upload at 19 : 34 of the merge, the phone at 4× the Mac), never a
measurement; nothing ran on a device. The rates they come to: a merge ~43 ns a vertex on the
phone (SR0's 1.23–1.32 ms for 119,948 on the Mac, × 4), an upload ~23 ns (SR0's 2.6 ms for
113,352), both ~67 ns (SR0's 8.0 ms for 119,948). The code references were re-read at
`afbdbc2`, which changed no code since `0bd57ba`; flutter_scene's at the `0.24.3` tag.

What SR0 closed: **P is out** (G3: a plain 4 × 4 rebuilds in ~8.0 ms at the largest and
~3.9 ms at the median, and under P an edit pays one, forced, in its frame,
`voxel_chunk_view.dart:222`). **Keep-beside is out** (G4: 53.3 MB more at radius 12). The
plan goes on (G1: 56.25 of 134.25 draws at `orbit:12`), and S's cull holds (G2).

### Two sizes

- The view keeps 2 × 2 regions as its unit of building and adds a settled layer of 4 × 4
  regions over it. A 4 × 4 is drawn either as itself or as its four 2 × 2 quadrants, never
  both and never neither.
- Three constructor arguments, as `regionChunks` is one (`:40`): `settledRegionChunks`
  (default 4, a multiple of `regionChunks`, under the 256 m limit: 64 m), `settleAfter`
  (default 2 s; tests pass `Duration.zero`) and `settleClear` (default 2 chunks). There is no
  `GraphicsSpec` knob (OCD6: the A/B compares commits).

### The settle rule

A 4 × 4 settles when all of these hold:

1. all 16 of its chunks have a mesh: an incomplete one, at the window's edge, never settles;
2. none of them was applied or removed for `settleAfter`, measured by one `Stopwatch` the
   view owns, not in frames, which vary with the display rate;
3. none of its quadrants is dirty;
4. it holds no chunk within `settleClear` chunks (on either axis) of the focus, the `near`
   that `rebuild` is given (`GameWorld.update` passes the focus's chunk,
   `game_world.dart:199`).

**Why 2 s.** It is the shortest quiet time that outlasts the churn the kit makes:

- Streaming makes none. A chunk is meshed only once its 3 × 3 ring is generated
  (`chunk_streamer.dart:278–285`), so a neighbour arriving later does not remesh it, and a
  4 × 4 at the leading edge settles 2 s after its last chunk lands.
- A flowing liquid steps every 0.25 s (water) or 0.6 s (lava) (`game_world.dart:19`, `:31`):
  its 4 × 4 stays split while it flows and settles 2 s after it stops.
- PF11's `--edits` cube toggles every second, but it never reaches a settled 4 × 4: its
  chunk, (2, −1) (`benchmark.dart:321–330`), shares the 4 × 4 of the focus's chunk (0, −1),
  which the clear zone keeps unsettled.
- A change far from the focus (another player's, an explosion's) splits a 4 × 4 once. The
  quiet time then keeps a steady builder's area split, instead of settling and splitting at
  every block.

A quiet time under 1 s would settle between two steps of a 1 Hz churn. A longer one only
delays the first settles after a fill, which change nothing on screen.

### The clear zone: the focus's 4 × 4 never settles

- **The rule.** No 4 × 4 holding a chunk within `settleClear` chunks of the focus's chunk
  settles, and a settled one that comes within it splits.
- **Why 2.** `PlayerSpec.reach` is 5 m by default (`player_spec.dart:19`), so the player's
  edit lands in the focus's chunk or one beside it. An opaque or light-changing edit remeshes
  its chunk's whole 3 × 3 ring (`chunk_streamer.dart:410–413`), so the player's own edits
  remesh chunks up to 2 from the focus. `VoxelGame` passes `1 + ⌈reach / 16⌉` to
  `GameWorld`, which builds the view (`voxel_game.dart:265`, `game_world.dart:64`).
- **What it buys.** Every edit the player makes, and every remesh it causes, goes the 2 × 2
  path it goes today: same cost, same frame, no swap. Rebuild-then-swap's delay (below)
  reaches only changes beyond the zone.
- **Its size.** Five consecutive chunks always span exactly two aligned runs of 4, so the zone
  is always 2 × 2 of the 4 × 4s, 64 of the 576 chunks SR0 found settled at the spawn.
- **Its price.** The zone's sixteen 2 × 2s draw where four 4 × 4s would. By SR0's averages over
  the window (373 draws over 169 2 × 2s, 2.21 each; 123 over P's 49 4 × 4s, 2.51 each), that
  is about 4 × (4 × 2.21 − 2.51) ≈ **+25 draws** (est.). The zone surrounds the orbit's
  centre, so take all 25 as in the frustum at `orbit:12`: ~81 of 134.25 at most (~60%,
  est.). SR0's harness was not
  kept, so this is not counted.
- **Underground it helps.** In the cave scenario the feet stand under `Bench.caveEye`
  (`benchmark.dart:270–273`), in chunk (1, 0), whose zone holds the chunks x −4…3,
  z −4…3: around the eye, S draws 2 × 2s. SR0's under2 count (S 4.0 draws and 167,625
  vertices, against 2 × 2's 4.5 and 60,005, i.e. 2.8× the geometry) had no zone. How much of
  that 2.8× the zone takes back is not counted.
- **Moving.** A 4 × 4 that enters the zone splits, with nothing changed on screen; one left
  behind settles 2 s later. At `fly:12` (16 m/s, a chunk column a second) the zone crosses a
  64 m run every 4 s: two splits and two settles every 4 s, beside the ~25 region rebuilds a
  second that streaming already makes (PF2) and the ~1.5 settles a second of the 4 × 4
  columns entering the window (§What the code says).

### Settling: a resumable merge, 65,536 vertices a draw at most

**The upload cannot be split.** `TerrainGeometry` uploads at construction
(`terrain_geometry.dart:38–43`) through `uploadVertexStreams` (flutter_scene
`geometry/geometry.dart:641`), which allocates, writes and binds in one call. The call that
binds buffers a caller wrote, `setVertexStreams` (`:260–261`), is `@internal`. Writing one
surface over several frames would need an upstream API; with the cap below it is not
needed.

**SR4 is dropped.** A worker isolate would move the copy, which already fits a chunk at a
time (~0.3 ms at the largest 4 × 4, est.). It cannot move the upload, the step over budget,
which is a Flutter GPU call on the UI thread.

**The cap.** A settled 4 × 4 draws each lit surface in parts of at most 65,536 vertices:

- **The split.** Its 16 members, in a fixed order, fill a part until the next would carry it
  past 65,536, and then open the next one.
- **The upload.** A part uploads in ~1.5 ms at most (65,536 vertices at ~23 ns, est.),
  inside the 2 ms budget on its own, where the largest solid surface whole is ~2.6 ms.
- **The indices.** Every part keeps 16-bit indices (`packed_surface.dart:74`). S's window then
  holds on the GPU what 2 × 2's holds, 53.49 MB (the same vertices at the same index width),
  not 58.43 MB: the 32-bit indices SR0 found on the solid surface of 19 of the 36 never reach
  the GPU.
- **The draws it adds.** Only those 19 solid surfaces pass 65,536 (SR0: no cutout, glow or
  liquid surface does). Each draws in two parts. Three would take a member's solid surface
  over 17,720 vertices (2 × 65,536 − 113,352), and SR0 did not record a chunk's own count.
  At two parts each that is at most +19 draws in the window. At S's share of its draws in
  the frustum at `orbit:12` (56.25 of 143), about +7 there (est.). With the zone, **~88 of
  134.25 (~66%, est.)**: under G1's 75%, but the cut falls from 58% to about a third. SR5
  measures it.
- **The glow** merges in the engine's vertex through `MergedSurface.of`, whole, as today.

**The steps.** A settle is a list of steps, one or more run in each `rebuild` after the dirty
2 × 2s, while the next step's predicted cost fits what they left of the budget:

- copy one member's words into its part's lists, allocated once for the part's counted
  sizes (~0.3 ms a chunk, est.);
- upload one finished part (≤ ~1.5 ms, est.), or the glow;
- the swap, once every part is up. The four quadrants leave `root` and the 4 × 4 node joins
  it in the same call. It takes the last cull's state, as `_build` gives a new region
  (`voxel_chunk_view.dart:284`).

The predictions come from two rates the view measures as it measures its build rate today
(`:112`, `:252`, `:291`): copy and upload, in microseconds a vertex.

- **Never forced.** A settle never runs as the frame's forced first region (`:222`). A step
  predicted over what is left waits for a later frame. A step predicted over the whole budget
  never runs, and its 4 × 4 stays 2 × 2: settling is never worse than today.
- **One at a time.** One settle runs at a time, the nearest candidate to the focus first. Its
  lists and finished parts are the only memory it adds: one 4 × 4's geometry, 2.62 MB at
  the largest.
- **Abandoned** when a member is applied or removed, or when the 4 × 4 enters the clear zone;
  its finished parts are dropped. `apply` replaces a `_ViewChunk` and never writes into one
  (`:139`), so a member's identity tells whether it changed.
- **Packed already.** A candidate's members are packed: they were drawn in their 2 × 2s,
  which pack a chunk on first read (`:257–261`). The settle asserts it.
- **The code.** `packed_surface.dart` gains a resumable form of `merge`: allocate for the
  counted sizes, add members one at a time, finish. `merge` (`:65`) becomes that form run to
  the end, so the two cannot disagree. It is pure Dart, tested without a GPU.
- **How long it takes** (est.). The largest 4 × 4 is ~5.1 ms of copy and ~2.8 ms of upload,
  so at least 4 frames of an idle budget; the steps' grain makes it ~6 to 8. A filled
  window's 36 come to about 36 × 67,964 (the median) × 67 ns ≈ 164 ms of work. At 2 ms a
  frame, that is ~82 idle frames once the quiet time is over: ~0.7 s at 120 Hz, ~1.4 s at
  60 Hz.

### Splitting: rebuild-then-swap

**How a split runs.**

- **The start.** A change on a settled 4 × 4 (an `apply` or `remove` of a member), or the
  4 × 4 entering the clear zone, splits it: its four quadrants go into `_dirty`, and the
  4 × 4 stays drawn.
- **The build.** The quadrants build in the ordinary order: nearest first, the frame's first
  region forced, the rest within the budget. A built quadrant waits out of the scene. A
  quadrant left with no chunk is ready at once, with no build.
- **The swap.** It happens when all four quadrants are ready, each built once since the split
  or empty. The 4 × 4 leaves `root` and the built quadrants join it in the same `rebuild`,
  each taking the last cull's state. No frame draws both or neither: no hole, no z-fighting.
- **No starving.** A quadrant changed again after it was built does not hold the swap back.
  It joins, and its newer change rebuilds it as any 2 × 2 is rebuilt today.

**How late a change shows** (est.).

- **The cost.** The four quadrants carry the 4 × 4's vertices: ~8.0 ms at the largest, ~3.9 ms
  at the median.
- **The frames.** The budget builds about one ~2 ms quadrant a frame, since a second never
  fits after the first has spent ~2 ms (`:222`). So the largest swaps in its 4th frame, 3
  frames after the 2 × 2 path would have shown the change. The median swaps 1 to 3 frames
  after, depending on whether its ~1 ms quadrants pair up in a frame.
- **In milliseconds.** 3 frames are 25 ms at 120 Hz and 50 ms at 60 Hz.
- **Streaming.** Regions streaming in nearer than the split come first in the order, and add
  their own frames.

**The changed quadrant is not built ahead.** Its remesh lands from a worker some frames after
the change anyway, and building it first would show nothing until the other three are
built. What waits on a split is never the player's own edit, because of the clear zone. It
is a change far from the focus: another player's, an explosion's beyond the zone, a
liquid's. It is also a `remove` at the window's far edge, where the 4 × 4 keeps drawing the
leaving chunk for those frames. A dimension switch removes every chunk, so every quadrant is
empty and every 4 × 4 leaves in the next `rebuild`, with no build.

**Memory.** A split in flight holds its built quadrants beside the 4 × 4 until the swap: one
4 × 4's geometry, at most 2.62 MB, for a few frames. G4's 53.3 MB was the whole window held
twice, for good.

### The cull, the shadow cache, idle

- **The cull.** A settled node shows when any of its 16 chunks is reached. Its parts are
  children like any surface (`_show`, `:199`). `cull` never touches `visible`,
  `shadowCastingMode` or `shadowStatic` (OCD1 holds). Every part is built with
  `shadowStatic = true`, as surfaces are today (`:306`, `:324`).
- **The shadow cache.** A settle's swap or a split's swap changes the static shadow signature
  once, as any region rebuild does today (§What the code says).
- **Idle.** `pendingRegions` counts the dirty 2 × 2s, a split's quadrants among them, and
  never a settle. So `GameWorld.isIdle` (`game_world.dart:210–213`) waits for a split but
  never for a settle: the benchmark's fill must not wait on optional work.

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

### SR1 — the design, from SR0's numbers (done)

- §Design rewritten as decided: S; the quiet time; rebuild-then-swap; SR4 dropped; the
  65,536-vertex cap on a settled draw; the clear zone around the focus.
- The owner reads §Design before SR2.

### SR2 — regions of two sizes in `VoxelChunkView`

- Each region node carries its size. `_bounds`, `_reached` and `_show` take the size from
  the node, not from the view.
- The node map holds both sizes, keyed so a 2 × 2 and a 4 × 4 at the same corner cannot
  collide.
- `settledRegionChunks` is a new constructor argument, default 4, asserted to be a multiple
  of `regionChunks` and under the 256 m limit. Nothing settles in this step.
- A settled node may hold several children per surface (§Design's parts); `_show` already
  walks every child.
- Tests (`packages/voxel_scene/test/voxel_chunk_view_test.dart`, no GPU, empty surfaces as
  the existing ones use):
  - a 4 × 4 node built by hand has the right bounds and reached state;
  - `cull` shows it when any of its 16 chunks is reached;
  - the cull leaves `visible`, `shadowCastingMode` and `shadowStatic` alone on both sizes.
- `voxel_scene/CHANGELOG.md`.

### SR3 — settling and splitting

- **What it builds**, as §Design decides:
  - the settle rule, with `settleAfter` and `settleClear`;
  - the resumable merge in parts of at most 65,536 vertices, and its two measured rates;
  - rebuild-then-swap.
- **`packed_surface.dart`** gains the resumable form of `merge`, and `merge` runs through it.
- **`voxel_game`.** `VoxelGame` passes `settleClear = 1 + ⌈reach / 16⌉` through `GameWorld`
  to the view. `pendingRegions` and `GameWorld.isIdle` never wait for a settle.
- **Tests, `voxel_scene`:**
  - the resumable merge, fed member by member, matches `merge` word for word;
  - a part never passes 65,536 vertices and keeps 16-bit indices, and a surface that needs
    three parts gets three;
  - 16 chunks applied, `settleAfter: Duration.zero`, `rebuild` until done: one 4 × 4 node
    and none of its 2 × 2s in `root`, and no `rebuild` leaves both or neither;
  - these never settle: an incomplete 4 × 4, and one within `settleClear` of `near`;
  - a settled 4 × 4 that comes within `settleClear` splits;
  - an `apply` into a settled 4 × 4: it stays in `root` until its four quadrants are built,
    then they swap in one `rebuild`;
  - a quadrant changed again after its build does not hold the swap back;
  - a `remove`: the same, and a quadrant left empty is ready with no build;
  - removing every chunk drops every 4 × 4 in one `rebuild`;
  - the budget:
    - a settle step never runs as a frame's forced first region;
    - it stays inside what the dirty 2 × 2s left;
    - a step predicted over the whole budget never runs;
  - a member changing mid-merge abandons the merge;
  - a settled node and a swapped-in quadrant take the last cull's state;
  - every node and part has `shadowStatic`.
- **Tests, `voxel_game`:** `isIdle` is reached with settles still pending, and the view is
  built with the `settleClear` that `PlayerSpec.reach` gives.
- **Visual check on the Mac** (`cd packages/voxel_game/example && flutter run -d macos`):
  - fly along a settle boundary;
  - walk into a settled 4 × 4: its split, as the clear zone reaches it, shows nothing;
  - break and place blocks: the edit shows at once (it is in the clear zone);
  - a split by a change in a settled area: no hole, no z-fighting at the swap. Run it with
    `settleClear: 0` in a local edit of `GameWorld`, not committed, since no player edit
    reaches a settled 4 × 4 otherwise;
  - water seen through water across a former 2 × 2 border (one blended draw now holds more
    faces);
  - a cave, as OC3's check had it;
  - a shadow cast across a settled region's edge.
- `CHANGELOG.md` of `voxel_scene` and of `voxel_game`; `voxel_scene`'s `README.md`
  mentions the three new arguments.

### SR4 — the merge off the frame (dropped by SR1)

SR4 would have moved the copy to a worker isolate. The copy fits a chunk at a time (~0.3 ms,
est.). The step that does not fit is the upload of a whole surface, which stays a Flutter
GPU call on the UI thread wherever the copy runs. §Design's 65,536-vertex parts bring each
upload under the budget instead.

### SR5 — the A/B (only when the owner asks)

- Galaxy S24, phone preset, three rounds alternated, the base at 36 °C. SR3's commit runs
  against its parent at `orbit:12` and `fly:12` (the draws and the streaming), `cave:12`
  (the cull's granularity), and `orbit:12 -- --edits=8` (edits once a second). The cube's chunk, (2, −1), shares the focus's 4 × 4, which the
  clear zone never settles. So the edits run checks that the edit path is today's; no
  scenario makes a change far from the focus, and no run times a split.
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
- **One surface uploaded over several frames.** It needs flutter_scene to bind buffers a
  caller wrote, and `setVertexStreams` (`geometry/geometry.dart:261`) is `@internal`.
  §Design's parts make it unnecessary. It could join the FS plan's upstream list if a
  surface ever has to stay whole.
