# The occlusion plan (OC) — 2026-10-09

**Question.** The phone at radius 12 is bound by flutter_scene's per-draw encode on the UI
thread (~31 µs a draw, PF17). Which terrain draws can the CPU prove the camera cannot see,
and hide them without disturbing the static shadow cache and PF14's regions?

**Answer, in brief.**

- **Cave culling (the lead, track A) cuts draws only underground.** A chunk here is a full
  16 × 16 × 128 column. Above ground, the sky's air touches every side of every column, so
  a search over open space reaches every region. The PF17 scenarios (`orbit`, `fly`,
  `mobs`) all run above ground, and A leaves their numbers unchanged. Its win is a player
  in a cave or a mine, which no benchmark measures today.
- **Above ground, two other candidates** may cut draws: horizon occlusion over the terrain's
  heights (track B), and merging settled far regions into 4 × 4 (track C, a plan of its own).
  Neither is designed yet.
- **OC0 decides, offline and without a device.** It counts, on the example world at the
  benchmark's poses and two underground ones, how many in-frustum draws each track would
  hide. A track whose count misses its gate stops there.
- **A hidden draw is `Node.layers = 0`.** flutter_scene 0.24.3 skips it in the colour and
  depth passes. It still casts into the shadow map and leaves the static shadow cache
  alone (§What the code says).

Every `file:line` below was read on 2026-10-09 at `f5f97f5`, flutter_scene at the
`0.24.3` pub tag. Re-check a reference before a step starts.

---

## Progress

| Step | State | Gate |
|:---|:---|:---|
| OC0 What each track would hide, counted offline | **done 2026-10-09** at `2a4a4f7`. Seed 2024, spawn (6, −5), 625 chunks, 373 region draws (2 × 2) in the window. Draws in the frustum and the share hidden, the underground poses averaged over 8 yaws at pitch 0. **`orbit:12`** (eye y 65.6, mean of 8 yaws): 134.3 in frustum; A 0%; B 6.5% (0.9–13.1%); C 56.3 (−58.1%). **`fly`** at t = 0 is `orbit`'s yaw −90°: 153; A 0%; B 13.1%; C 75 (−51.0%). **under1** (y 44, 4 m under the spawn's ground): 126.3; A **0%**: the cell is dark by light falloff only, its air joins the open sky, so the search reaches all 625 chunks. **under2** (the largest dark-air component within 32 m, 1,562 cells; pose (16, 10, 14)): 120.0; A **96.3%**, 16 chunks reached. **64 random dark-air cells within 32 m**: A mean 82.1%, median 96.3%, ≥ 50% in 55 of 64. A ceiling from 13 × 13 rays per box face through opaque cells: `orbit` 14.1%, under1 98.4%, under2 99.2%. Starting the search from the camera cell's own component (Minecraft's start) changes none of these by more than one draw. B as counted: per 4 × 4-column cell, the topmost run of layers opaque in all 16 columns and at least 2 deep, as an elevation band per azimuth bin (4,096), hiding a box whose whole elevation range lies inside the bands of cells nearer than it; this is sound where the outline's min-height is not. **Gates: A split** (under2 and the sample pass; under1 fails; the two poses' mean is 48.1%), the owner's call. **B failed** (6.5%, and the ray ceiling is 14.1%). **C 58.1% ≥ 25%: opens its own plan** (§Out of scope). The prototype stayed local | the counts in this table's row; gate A: ≥ 50% of in-frustum region draws hidden at the underground poses; gate B: ≥ 25% at `orbit:12` averaged over 8 yaws |
| OC1 Section connectivity at mesh time | **done 2026-10-09** (the owner counted gate A as passed: a cave open to the sky is out of any connectivity cull's reach; the sample of 64 passes). `ChunkVisibility` numbers the faces −x, +x, −y, +y, −z, +z (0–5, opposite = `face ^ 1`); `connects` throws on `faceIn == faceOut`, which OC2's rule never asks. For OC2: with the plan's start rule a dark cave open to the sky reaches every chunk, which is correct; starting from the camera cell's own component changed nothing in OC0 | `voxel_engine` tests below; the suite green |
| OC2 The section search from the camera | **done 2026-10-09**. `update(camera, section, min:, max:)` takes the window as inclusive chunk corners and returns whether it ran; the window's change is an input as the section's is. The start section's six neighbours are always reached, so a sealed cave keeps its own chunk and its four side neighbours (the walls it sees). `sectionAt(y)` clamps an eye above or below the world into sections 7 and 0. The U-tunnel test pins the rule. OC3 feeds it the eye, not the player's position | `voxel_engine` tests below; the suite green |
| OC3 The view hides unreached regions | **done 2026-10-09**. `VoxelChunkView.cull(eye)` sets `layers` on the region node and each of its surfaces (the region node has no mesh, so its own layers draw nothing; they make the state readable without Flutter GPU, which a test cannot build surfaces on). The search's window is the corners of the chunks the view keeps, widened to the eye's chunk, recomputed only when a chunk comes or goes. `VoxelGame.warmedUp` (set by `VoxelGameWidget` after `Scene.warmUp`) gates it; `VoxelGame.cullEye` is the camera's eye. A throwaway headless check on the example world (radius 8, 110 poses, 80 of them in dark air within 32 m of the spawn, 6,000 rays each through non-opaque cells) found **no chunk a ray hits that the search did not reach**; dark poses hid 70.5 of 81 regions on average. Not committed. OC2's visit-once rule left no hole there. Seen by the owner on the Mac: a cave dug into and turned in, a shaft climbed out of, a section boundary, third person in a tunnel; no hole, no late region | `voxel_scene` and `voxel_game` tests below; the suite green; seen underground on the Mac |
| OC4 A `cave` benchmark scenario (code, no run) | **done 2026-10-09**, no run. `Scenario.cave` puts the eye at the centre of cell `Bench.caveEye` = (16, 10, 14), OC0's **under2**, not the first underground pose the step names: under1's air joins the open sky, so the view hides nothing there and `cave` would measure what `orbit` does. Pitch 0, as OC0 counted; the look turns it once over the recording, as `orbit`'s. `tool/run_benchmark.dart` needed no change: `--runs cave:12` already passes any `scenario:radius` through; `cave` is not in its default runs. The test floods the eye's open cells headless (a headless world bakes no light, so sky light cannot be read): 1,576 cells, all under their column's ground and inside the loaded window; under1's pose fails it, opening to the sky at (5, 46, −15). Next, only when the owner asks: the A/B of `0fcb0bc` against its parent at `cave:12` and `orbit:12` on the S24 | `benchmark.dart --scenario=cave` boots headless in its test; **run only when the owner asks** |
| OC5 Horizon occlusion above ground | **stopped**: OC0 failed gate B | its own design section in this plan before code |

Effort per step: OC0 `high` (a throwaway prototype of two culls that must agree with the
real geometry), OC1 `medium` (a flood fill specified here), OC2 `high` (the search rule
decides what can pop), OC3 `high` (three packages, a visual check), OC4 `medium`, OC5
`high`.

---

## What the code says (read before OC0)

**The wall.** PF17 (`docs/VOXEL_PERF_PLAN_2026-09-25.md`, "The final measurement"):
`orbit:12` on the S24 runs at 80 fps with UI p50 7.5 ms, of which encode is 7.0. The
colour pass costs ~31 µs a draw on that phone (PF14's row). 25% of the draws is about
1.75 ms, the margin between 80 fps and the display's 120.

**The geometry.**

- A chunk is a column of 16 × 16 × 128 cells
  (`packages/voxel_engine/lib/src/core/grid/chunk_size.dart`). The streamer loads a
  square window (`chunk_streamer.dart:228`): 25 × 25 = 625 chunks at radius 12.
- `VoxelChunkView` draws 2 × 2 chunks as one region
  (`packages/voxel_scene/lib/src/voxel_chunk_view.dart:31`). Each region is one node,
  with up to four child draws (solid, cutout, glow, liquid). Every child is `shadowStatic`
  (`:226`, `:244`). At radius 12 that is 13 × 13 to 14 × 14 regions.
- `ChunkMesher` decides which faces it draws from `_opaque`, one flag per block id
  (`chunk_mesher.dart:236–251`). A cell that hides its neighbour's face also hides
  whatever lies behind it, so connectivity uses the same flag.
- `GameWorld.update(focus)` streams and rebuilds once a frame
  (`packages/voxel_game/lib/src/world/game_world.dart:195`), called from
  `VoxelGame.frame` with the player's position (`voxel_game.dart:1043`). The camera's eye
  can differ from the player's position (third person). `VoxelGameWidget` warms up with
  `Scene.warmUp([RenderView(camera: …)], includeOffscreen: true)`
  (`voxel_game_widget.dart:373`).

**How flutter_scene 0.24.3 can hide a draw**
(`~/.pub-cache/hosted/pub.dev/flutter_scene-0.24.3/lib/src/`):

| Way | Colour pass | Shadow map | Static shadow cache |
|:---|:---|:---|:---|
| `Node.visible = false` (`node.dart:111`) | skipped | **skipped** (`render/shadow_encoder.dart:48`) | **the caster leaves the signature** (`scene.dart:3334`): every tile goes stale and refreshes, and the region's shadow disappears |
| `shadowCastingMode = shadowsOnly` (`node.dart:222`) | skipped (`render/render_scene.dart:160–163`) | cast | each toggle calls `markStaticShadowDirty` (`components/mesh_component.dart:236–246`), which recomputes the signature over every item; the mode is not hashed, so no tile refreshes, but the walk is paid on every frame that toggles |
| **`Node.layers = 0`** (`node.dart:140`) | **skipped** at the encoder (`scene_encoder.dart:916`), the depth prepass (`render/depth_prepass.dart:280`, `:439`) and the velocity pass | **cast**: `shadowCasterAccepted` never reads layers (`render/shadow_encoder.dart:36–49`) | **untouched**: layers are not in `staticShadowChanged` (`components/mesh_component.dart:236–246`) |

flutter_scene already culls each item against the frustum (`node.dart:132`,
`frustumCulled`). The kit never sets `layers` today. Its only view is the main one, with
`layerMask` `kRenderLayerAll` (`render/render_layers.dart:12`), and it never calls
`Scene.raycast` on terrain.

**Why column-level cave culling hides nothing.** The usual algorithm (Tommaso Checchi's,
the one Minecraft uses) has two parts. At mesh time, each chunk records which pairs of its
six faces are joined by open cells. At draw time, a breadth-first search from the camera's
chunk crosses only joined faces and never steps back against a direction it has already
taken. With full-height columns, the air above the terrain joins every pair of side faces
in every column, so the search reaches everything.

Two changes make it useful:

- **Finer connectivity, same draws.** The graph splits each column into 16-tall sections
  (8 per column), so a cave's air and the sky's air become separate nodes. The draws stay
  per region: splitting meshes per section would add draws, which is the cost being cut.
- **Underground only.** A region is hidden only when none of its chunks' sections is
  reached. Above ground, every column's top section is reached, so nothing hides. Below
  ground, in a cave sealed from the surface, the search stays inside the cave, and
  regions with no reached section hide.

---

## Decisions

| ID | Decision | Why |
|:---|:---|:---|
| OCD1 | **A hidden region sets `layers = 0` on its surface nodes and nothing else.** `visible` and `shadowCastingMode` are never touched by the cull. | The table above: layers are the only way that skips the colour and depth passes, keeps the shadow, and leaves the static cache alone. A hill hidden behind the camera still shades what is in view. |
| OCD2 | **Connectivity in 16-tall sections; draws stay per PF14 region.** | Sections separate a cave's air from the sky's (§Why). Splitting the meshes would add draws, which are the cost. |
| OCD3 | **The search has no frustum term, and reruns only when its inputs change**: the camera enters another section, or a chunk in the window gets or loses its connectivity. | flutter_scene already frustum-culls each item every frame. Without the frustum, the result depends only on the camera's section and the data, so a frame that crosses no section costs nothing. A per-frame search over 5,000 sections would cost UI-thread time on the same thread whose time the cull is meant to free. |
| OCD4 | **A chunk with no mesh yet counts as fully open.** | It has no geometry to occlude anything. This is the definition of an empty chunk, not a fallback (rule 5): there is no missing data to patch over. |
| OCD5 | **The data and the search live in `voxel_engine` (`core/occlusion/`); `voxel_scene` only writes `layers`.** | Pure Dart under `dart test`, runnable on a worker isolate (rule 3). The folder names its domain (rule 10). It stays inside `core`, so `architecture_test.dart` needs no new edge. |
| OCD6 | **No `GraphicsSpec` knob.** The A/B compares commits, as every PF step did. | A knob would be a second code path to keep correct, for a cull that is exact by construction (OCD4, OC2's tests). Add one only if OC3's visual check finds a case that needs it switched off. |
| OCD7 | **The cull starts after `VoxelGameWidget`'s warm-up.** | Warm-up must see every terrain pipeline (open question 3 of the hand-off, on mid-frame pipeline builds). A node hidden before it would hide a pipeline from it. |

---

## Steps

### OC0 — what each track would hide, counted offline

There is no device and no benchmark (CLAUDE.md §Benchmarks): only a headless count on the
Mac.

- **The world.** Build the example's `VoxelGameSpec`
  (`packages/voxel_game/example/lib/main.dart`, the seed `benchmark.dart` uses). Generate
  and mesh the radius-12 window around the spawn in a `flutter test` under
  `packages/voxel_game/example/`.
- **The poses.**
  - `orbit`: ground + 16, pitch −0.35, 8 yaws (`benchmark.dart:260`, `:269`).
  - `fly`: as `orbit`, yaw east.
  - **Two underground poses:**
    - the first air cell with sky light 0 found scanning down from the spawn;
    - a cell in the largest cave component within 32 m.

  Camera FOV and aspect as the kit's `MirroredCamera` builds them for a 1600 × 900 window.
- **The count.** For each pose:
  - the region surface draws whose bounds intersect the frustum (`Camera.getFrustum`, the
    same bounds `VoxelChunkView._bounds` gives);
  - of those, how many each candidate hides:
    - **A**: a local prototype of OC1 + OC2;
    - **B**: a 2.5D horizon test, conservative occluders only (§OC5's outline);
    - **C**: draws if settled regions were 4 × 4. This is a count, not a cull.
- **What is committed.** Only the counts, in OC0's Progress row. The prototype stays
  local; OC1–OC3 write the real code with their own tests.
- **The gates.** Track A continues only at **≥ 50%** of in-frustum draws hidden at the
  underground poses. Track B continues only at **≥ 25%** at `orbit:12` averaged over the 8
  yaws. A C count of ≥ 25% opens a plan of its own (§Out of scope).

### OC1 — section connectivity at mesh time (`voxel_engine`)

- `ChunkVisibility` (`lib/src/core/occlusion/chunk_visibility.dart`):
  - `sectionHeight = 16` and `sections = ChunkSize.sizeY ~/ sectionHeight`, which is 8;
  - a `Uint16List(sections)` holding, per section, a 15-bit mask of which face pairs open
    cells join (6 faces give 15 pairs);
  - `connects(int section, int faceIn, int faceOut)`;
  - `ChunkVisibility.open`, every bit set, used for OCD4.
- `ChunkMesher` fills it after `_copyChunk`. It flood-fills each section's open cells
  (`!_opaque[id]`) over the chunk's own 16 × 16 × 16 cells, not the padding. Each fill
  records the faces its component touches, then ORs the pairs. A per-isolate scratch
  queue serves it, like `_tBlocks`.
- `ChunkMeshResult.visibility` carries it to the main isolate.
- Tests (`test/core/occlusion/chunk_visibility_test.dart`):
  - all air: every pair set;
  - all stone: none;
  - a sealed pocket: none;
  - a straight x tunnel: only `(−x, +x)`;
  - an L tunnel: only its two faces;
  - liquid and a non-opaque cutout count as open;
  - a vertical shaft crossing two sections: `(−y, +y)` in both;
  - re-meshing an edited chunk changes the mask.
- Cost: the flood runs on a worker, and the result's `ms` already includes it. No frame
  pays it.
- `voxel_engine/CHANGELOG.md`.

### OC2 — the section search from the camera (`voxel_engine`)

- `SectionOcclusion` (`lib/src/core/occlusion/section_occlusion.dart`):
  - **Input.** A lookup `ChunkPos → ChunkVisibility?` (a null is open, OCD4), the window's
    bounds, and the camera's chunk and section.
  - **Output.** The set of reached chunks. That is enough for regions: a chunk is reached
    when any of its sections is.
  - **The rule** (Checchi): the start section is reached through every face.
    - From section S entered by face `in`, leave by face `out` when `S.connects(in, out)`.
    - `out` must not oppose any direction already in the path's 6-bit direction set.
    - Each section is visited once; the first visit wins.
    - Above `y = 128` and below 0, nothing is drawn, so the search stops there.
  - **Reruns** only when the camera's section changes or `markChanged(ChunkPos)` was
    called since the last run (OCD3).
- Tests:
  - an open world reaches every chunk;
  - a sealed cave reaches only its own chunks;
  - a cave with a shaft to the surface reaches everything through it;
  - a missing chunk is crossed;
  - the camera's section is reached even when it is solid stone (a third-person camera
    inside a hill);
  - the same section twice in a row does not rerun;
  - a `markChanged` does rerun;
  - a U tunnel does not see past its bend. This last test pins the search rule, so a
    later change of rule shows up in the suite.
- Risk, named: the visit-once rule can miss a section a second path would reach. That is
  a hole in the world for a frame or more. OC3's visual check looks for it, and a fix is
  OC2's to make, never a workaround in the view.

### OC3 — the view hides unreached regions (`voxel_scene`, `voxel_game`)

- `VoxelChunkView`:
  - keeps each chunk's `ChunkVisibility` from `apply`, and drops it in `remove`, both
    calling `markChanged`;
  - adds `cull(Vector3 eye)`, which runs `SectionOcclusion` when its inputs changed and
    sets each region's surface nodes to `layers = kRenderLayerDefault` when any member
    chunk was reached, `0` when none was;
  - `_build` gives a new region the state of the last cull.
- `GameWorld` adds `cull(Vector3 eye)`. `VoxelGame.frame` calls it with the camera's eye,
  not the player's position, after `world.update`, and only once warm-up is done (OCD7).
- Tests:
  - `voxel_scene`: a sealed camera hides the right region nodes; a rebuilt region keeps its
    state; the cull never changes `visible`, `shadowCastingMode` or `shadowStatic` on any
    node (OCD1 as a test);
  - `voxel_game`: `frame` culls by the camera's eye in third person, and not before
    warm-up.
- Visual check on the Mac (`cd packages/voxel_game/example && flutter run -d macos`):
  - dig down into a cave and turn around: no hole, no region popping in late;
  - climb out through a shaft;
  - stand at a section boundary;
  - third person in a tunnel.
- `CHANGELOG.md` of `voxel_engine`, `voxel_scene` and `voxel_game`. Each `README.md` only if
  the public API moved (`cull`).

### OC4 — a `cave` benchmark scenario (code only)

- `Scenario.cave` in `packages/voxel_game/example/lib/benchmark.dart`:
  - places the camera at OC0's first underground pose and turns it as `orbit` does;
  - `tool/run_benchmark.dart` passes it through.
- Its test boots the scenario headless, as the others'.
- **No run.** The A/B of OC3's commit against its parent, at `cave:12` and `orbit:12` on
  the S24, waits for the owner to ask (§Method of the PF plan).

### OC5 — horizon occlusion above ground (only if OC0 passes gate B)

Outline, to be turned into a design section here before any code:

- **Occluders.** At mesh time, each 4 × 4-column cell of a chunk records a conservative
  height. It is the lowest, over the cell's columns, top of the topmost opaque run at
  least two cells deep, read from the skylight pass (`chunk_mesher.dart:465`). A ray from
  above enters terrain just under its surface, so a ray below that height in that cell
  crosses opaque cells.
- **The test.** From the camera, the region grid is swept outward with the highest
  occluder elevation per azimuth. A region whose box top lies below that horizon across its
  whole azimuth span is hidden.
- **Where it runs.** It reruns when the eye moves by a cell or turns past a sector, and only
  with the camera under open sky. Below ground it is track A's job. It hides through
  OCD1's `layers` like track A.

---

## Out of scope

- **Settled 4 × 4 regions (track C).** PF14 measured regions of 4: encode −25%, but a 24 ms
  step at every streamed chunk (`docs/perf/pf14_s24_phone_r4_regions{2,4}.jsonl`).
  Merging only regions whose 16 chunks have all arrived and stayed unchanged would keep
  the encode cut and drop the hitch. Where the 4 × 4 merge's time goes (word copy against
  GPU upload) is the open question. If OC0's count clears 25%, this gets its own plan.
- **Splitting meshes per section.** It adds draws (OCD2).
- **GPU occlusion queries or a hierarchical depth buffer.** Flutter GPU has no queries, no
  compute and no indirect draws (PF plan, "What was known before measuring").
- **Culling shadow casters.** A caster hidden from the camera can still shade what it sees
  (OCD1), and the static cache already makes terrain shadows nearly free between refreshes.
- **Any benchmark run.** That waits for the owner's word, as in OC4.
