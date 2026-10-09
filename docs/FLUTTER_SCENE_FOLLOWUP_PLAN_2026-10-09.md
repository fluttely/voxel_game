# The flutter_scene follow-up plan (FS) — 2026-10-09

**Question.** On 2026-09-29 the kit sent `flutter_scene` four findings and a follow-up
([bdero/flutter_scene#435](https://github.com/bdero/flutter_scene/issues/435),
`docs/FLUTTER_SCENE_PROPOSAL_2026-09-29.md`). Its maintainer answered the same day and
asked for PRs on sections 1 and 2. What is left for the kit to send, and what does the
kit do with what came back?

**Answer, in one line.** Nothing of #435 is left to send. The maintainer wrote the PRs
himself, so the kit adopts them in VD4 and moves its terrain onto the new public geometry
path. Two things may still go upstream, each only on evidence: an issue for the `src/`
imports the kit cannot drop, and a measured per-draw cost, if one is left after VD4.

Every fact below was read on 2026-10-09: the issue's full thread and timeline, PRs #439 and
#458, and `github.com/bdero/flutter_scene` at the `flutter_scene-0.24.3` tag. Re-check a
`file:line` before a step starts; upstream moves daily.

---

## Progress

| Step | State | Gate |
|:---|:---|:---|
| FS0 #435's outcome on record | **done** 2026-10-09: this plan; the proposal's status block says what came back | the proposal doc links #439 and #458 |
| FS1 The terrain on the public geometry path | pending; **runs as part of VD4** (`docs/VOXEL_DEPS_PLAN_2026-10-06.md`) | VD4's gates; `terrain_geometry.dart` imports nothing under `flutter_scene/src/` |
| FS2 The `src/` imports that remain, asked upstream | pending; after VD4; **the owner posts or gives the word** | an issue open on `bdero/flutter_scene`, linked from `KL-027`'s closing line or a new ledger entry |
| FS3 The UI isolate's allocation on 0.24.3, measured | pending; **only if the owner asks for numbers** (CLAUDE.md §Benchmarks) | one Mac and one S24 trace on 0.24.3 against the 0.23 traces of #435 §2, filed under `docs/perf/` |
| FS4 A PR, if FS3 finds a flutter_scene site worth one | pending; gated on FS3 and on the owner's word | an issue with the numbers, then one PR per change from a fork |

Effort per step: FS1 `xhigh` (it is VD4's shader work), FS2 `medium` (an issue's text from
code already read), FS3 `high` (a measurement with a method to follow), FS4 `high` (a
change in someone else's engine, held to their CI).

---

## What came back (read before FS1)

- **The thread.** Issue body and the follow-up comment are ours (2026-09-29). The
  maintainer (bdero) answered at 23:00Z the same day:
  - **Follow-up** (`TransientArena` churn): already fixed in #437, blocks recycled by idle
    age (240 frames), the approach we measured.
  - **§1, shadow cache on a stepped sun:** "we'd take a PR"; route a turn through the
    amortized refresh, keep tile textures at the same resolution, keep
    `maxAmortizedRefreshes` and the tolerance internal.
  - **§2, per-draw allocation:** yes to PRs for the mechanical items, one per PR with
    before/after numbers; the `FrameInfo` memo for custom geometry waits on §3.
  - **§3, custom `Geometry`:** he designs it; asked for its own issue.
  - **§4, opaque sort order:** geometry before depth is intended; the doc was wrong; depth
    buckets only if someone measures a win on a GPU where early-Z matters.
- **What he did next** (timeline):
  - [#439](https://github.com/bdero/flutter_scene/pull/439), merged 2026-09-29: the
    encoder's doc describes the order it uses (§4).
  - [#458](https://github.com/bdero/flutter_scene/pull/458), merged 2026-10-03, "Resolves
    #435", in 0.24.0: §1 as proposed (`maxDirectionLagDegrees = 5`, both constants
    internal, textures kept unless the resolution changes); every §2 item; and §3's
    public path (`Geometry.uploadVertexStreams`, `Geometry.setDepthOnlyVertex`, a
    public `package:flutter_scene/gpu.dart`, shared defaults for absent `MeshGeometry`
    streams). In his 290-draw bench the UI isolate's allocation rate halved.
  - The issue closed with #458's merge, 2026-10-03T16:40Z. No issue for §3 is needed now.
- **What the kit still reaches into** (`grep -rn "flutter_scene/src/" packages`):
  - `voxel_scene/lib/src/terrain_geometry.dart:12`: the gpu shim, for `Geometry.bind`'s
    types, plus `setVertexStreams` and `bindGeometryBuffers` (`@internal`). FS1 removes all
    three.
  - `voxel_scene/lib/src/terrain_material.dart:9`: the gpu shim, for `gpu.RenderPass` in
    `bind` (`:77`). 0.24.3's public `gpu.dart` does not export `RenderPass`.
  - `voxel_scene/lib/src/gpu_paced_scene.dart:9` and
    `voxel_game/lib/src/loop/measured_scene.dart:10`: `rendererSubmissions`, still in
    `src/render/frame_transients.dart`. `measured_scene.dart:13` also takes the gpu shim.
- **Why the `FrameInfo` memo is no longer a PR.** The encoder binds `FrameInfo` once per
  shader only for an `UnskinnedGeometry` (`scene_encoder.dart:1547`). #435 measured 13% of
  the UI isolate's allocations on that site because `TerrainGeometry` is a plain
  `Geometry`. On the public path it is an `UnskinnedGeometry`, so it gets the memo
  without a change upstream.
- **How upstream takes a change** (for FS4): one workspace, `packages/flutter_scene`; the
  `Flutter CI` workflow runs `dart analyze packages examples apps`, `dart format` and each
  package's tests; `smoke_render` renders on five backends and Argos diffs the images;
  the maintainer approves Argos changes himself. Commits are one sentence in the
  imperative, ending in a full stop. The root `AGENTS.md` is about using the engine, not
  developing it.

## Decisions

| ID | Decision | Why |
|:---|:---|:---|
| FSD1 | **No fork, no PR now.** | Every item that was ours to send landed in #458. A PR without a gap to close is noise in a maintainer's queue. |
| FSD2 | **FS1 runs inside VD4**, not as its own step. | VD4 already re-derives `terrain.vert` and `terrain_depth.vert` for 0.24's `FrameInfo`; moving the geometry to the engine's `FrameInfo` is the same edit. Doing it twice costs a second shader rebuild and a second visual check. |
| FSD3 | **FS2 asks; it does not propose an API.** | §3 showed the maintainer designs public API himself. The issue states what the kit reads and why, and asks how he wants it reached. |
| FSD4 | **FS3 and FS4 wait on the owner's word for numbers.** | CLAUDE.md §Benchmarks. The maintainer asked for before/after numbers per PR, so FS4 cannot go without FS3. |

## Steps

### FS0 · #435's outcome on record

`docs/FLUTTER_SCENE_PROPOSAL_2026-09-29.md` (status block), this plan, `CLAUDE.md`'s map,
`docs/VOXEL_DEPS_PLAN_2026-10-06.md` (VD4 retargeted). Commit `docs:`.

### FS1 · The terrain on the public geometry path

Specified in VD4 (`docs/VOXEL_DEPS_PLAN_2026-10-06.md`, §VD4, "The terrain's geometry on
the public path"). Its row here flips with VD4's commit.

### FS2 · The `src/` imports that remain, asked upstream

After VD4, from the code as it stands then.

- List each `src/` import left in `packages/` (`grep -rn "flutter_scene/src/" packages`)
  and, for each, the member read and what for:
  - `gpu.RenderPass`: a `PhysicallyBasedMaterial` subclass overrides `bind` to add its own
    uniform blocks (`terrain_material.dart:77`), and `bind` is typed with it.
  - `rendererSubmissions`: `ScenePacer` holds a frame until the GPU has finished the one
    before (`gpu_paced_scene.dart:66-70`), and `MeasuredScene` counts frames by it. Say
    whether 0.24's own pacing (`maxGpuFramesInFlight`) answers the first; VDD5 keeps ours
    for now.
- The cost to ask about: an exact pin, so each `flutter_scene` release costs the kit
  pub.dev points 30 days later until the kit follows (`KL-027`).
- Draft the issue in `docs/FLUTTER_SCENE_PROPOSAL_2026-09-29.md` under a new
  `## Follow-up 2` heading: short, the two members, the use, the question. No API sketch
  (FSD3).
- **Gate:** the owner reads the draft and posts it, or gives the word to post it (`gh
  issue create -R bdero/flutter_scene`). It is outward-facing.
- Ledger: the issue's link on `KL-027`'s closing line, or a new entry if `KL-027` is
  already closed with no room for it. Commit `docs:`.

### FS3 · The UI isolate's allocation on 0.24.3, measured

Only in a session where the owner asked for numbers.

- Same method as #435 §2: the VM's allocation tracer over one orbiting camera on a loaded
  world, Mac and S24, profile build; rate from the timeline, owners by first non-SDK
  library and by call site. The S24 waits for the battery under 36 °C (the runner's
  `--max-temp`).
- Compare with #435 §2's 0.23 numbers (~18 MB/s S24, ~21 MB/s Mac; flutter_scene 50%,
  flutter_gpu 23%, vector_math 16%; 60% under `Scene.renderViews`).
- File the traces under `docs/perf/` and a paragraph under this step: what fell, and the
  three largest flutter_scene call sites left, with their share.
- **Gate:** a site in flutter_scene above ~5% of the UI isolate's allocation, per draw or
  per node, that the kit cannot avoid from its side. Without one, FS4 closes as not
  needed.

### FS4 · A PR, if FS3 finds a flutter_scene site worth one

- **Issue first**, with FS3's numbers and the site, in the shape of #435: what, where
  (`file:line` at the tag measured), the number, one suggestion. Owner's word to post.
- **Then a PR only if the maintainer says he would take one.** For each:
  - Fork `bdero/flutter_scene` to `kevinkobori/flutter_scene` (`gh repo fork`), branch from
    `master`, one change per branch.
  - Before pushing: `flutter pub get`, `flutter config --enable-native-assets
    --enable-dart-data-assets`, `dart analyze packages examples apps`, `dart format
    --output none --set-exit-if-changed` on the changed files, and the package's tests.
  - A test for the change, next to the engine's own (e.g. the allocation checks of
    `examples/smoke_render`'s warmed-up scenes).
  - The PR body: the site, before/after from the tracer, the test, "Related to #<issue>".
  - **Gate:** the owner reads the PR before `gh pr create`. No AI attribution in the
    commits or the body (CLAUDE.md).
- The kit adopts the release that carries it in its own step, as VD4 did.

## Out of scope

- §4's coarse depth buckets: they need a GPU where early-Z matters (an immediate-mode
  desktop GPU), and the owner's machines are an Apple GPU and an Adreno. `KL-004`'s
  Windows or Linux machine would be the place.
- Making the stepped sun continuous. With #458 each step refreshes one cascade per frame
  for up to 5°, so the 2° step stops costing a burst of frames; a continuous sun would
  refresh a cascade every frame. Changing the step is frame work and the owner's call.
- Adopting 0.24's own GPU pacing over `ScenePacer` (VDD5).
