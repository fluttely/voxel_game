# flutter_scene upstream proposal (PF16) — draft, 2026-09-29

> **Status: sent, 2026-09-29**, as one issue with the owner's ok on this text:
> <https://github.com/bdero/flutter_scene/issues/435> (PF16, `docs/VOXEL_PERF_PLAN_2026-09-25.md`).
> Everything below the line, up to §Follow-up, is the issue as posted. Line numbers are
> flutter_scene 0.23.0 as published on pub.dev.
>
> **§Follow-up** (lead 1 of the PF plan) is a comment on the issue, **sent 2026-09-29** with
> the owner's ok, after the phone's A/B and traces were added:
> <https://github.com/bdero/flutter_scene/issues/435#issuecomment-5898536445>. Its body is the
> comment as posted.
>
> **Outcome, read 2026-10-09.** The maintainer answered on 2026-09-29 (PRs welcome for §1
> and §2, §3 his to design, §4's doc wrong) and then wrote the changes himself:
> [#439](https://github.com/bdero/flutter_scene/pull/439) fixed §4's doc, and
> [#458](https://github.com/bdero/flutter_scene/pull/458) resolved §1, §2 and §3's public
> path, released in 0.24.0. The issue closed with #458 on 2026-10-03. What the kit does
> with it is `docs/FLUTTER_SCENE_FOLLOWUP_PLAN_2026-10-09.md` (FS).

---

## Title

Static shadow cache on a moving sun, per-draw encode cost, and a public path for custom `Geometry` (findings from a voxel game on 0.23.0)

## Body

Hi! We build a voxel sandbox kit on flutter_scene 0.23.0
([voxel_scene](https://pub.dev/packages/voxel_scene) /
[voxel_game](https://pub.dev/packages/voxel_game)) and spent a few weeks on its frame rate
on a Mac (120 Hz, Retina) and a Galaxy S24 Ultra (Adreno 750, 120 Hz). We measured with
`FLUTTER_SCENE_PROFILE`, a Dart timeline of profile builds, and the VM's allocation tracer.
Most of what we found was on our side, and we fixed it there. We now share one geometry
per rig part so draws instance, and we merge chunks into 2 × 2 regions (~100 colour draws
became ~40). The terrain uses a packed 16-byte vertex, and fixed groups of boxes are one mesh.

What is left is inside flutter_scene, so here it is, with numbers and suggestions. We are
happy to send PRs for any of these if you tell us which you would take and in what shape.

### 1. A change to the light direction rebuilds every static shadow cascade in one frame

Our day/night cycle quantises the sun: it moves 2° every 3.33 s (a 600 s day), so that
between steps the static shadow cache holds. Each step still costs one long frame.

- `DirectionalShadowCache.plan` treats any direction change over `1e-10` (squared) as a
  parameter change. It clears every entry (`render/shadow_cache.dart:101-116`), and "a
  change to the light basis ... rebuilds the cache outright" (`:91-92`).
- A fresh entry has no content, so every cascade takes the unamortized
  "must render this frame" branch (`:132-135`).
- Each cascade re-culls the whole static world (`render/shadow_pass.dart:283`).
- The new entries have `tile == null`, so every cascade also creates a fresh
  `r32Float` texture (`render/shadow_pass.dart:246`).

**Measured**
- On the S24 (2 cascades, 1024², 48 m, the whole terrain marked `shadowStatic`), every run
  shows `encode` spans of **12.5–22 ms** at each sun step, every 3.33 s. The steady encode
  is ~4 ms, and none of these frames has a GC or any other work in it (Dart timeline,
  profile build).
- At 120 Hz that is 2–3 frames missed every step. These are the phone's slowest frames
  that have no garbage collection in them.

**Suggestions** (any one helps):
- **Treat a direction change like a content change.** Mark the tiles stale instead of
  dropping them, and let the existing amortized path (`maxAmortizedRefreshes`, nearest
  first) refresh them one per frame. `plan` already returns the effective cascade each tile
  was rendered with, so a far cascade would lag the sun by a frame or two.
- **Keep the tile textures across a rebuild.** Reallocating them buys nothing when the
  resolution has not changed.
- **Make the thresholds public.** `maxAmortizedRefreshes` (and maybe an angular tolerance
  for the direction) are `static const` today (`:76-79`).

The docs recommend `cacheStaticShadows = false` for a light "whose direction changes every
frame" (`light.dart:138-143`). A stepped sun is the case in between: static for seconds at
a time, then a small jump.

### 2. The encode's CPU cost per draw, mostly allocation

On the phone the frame is the UI thread's, and the encode is roughly draws × passes.
flutter_scene's own profile gives these numbers:
- **The colour pass cost ~31 µs a draw on the S24** (95–99 draws, 3.7–4.0 ms), against
  ~4 µs on the Mac.
- **Twelve extra draws of one box each cost ~0.3 ms** on the phone.
- **The cull costs ~2 µs a node** on the phone and ~0.4 µs on the Mac.

What the UI isolate allocates while rendering:
- **Rates.** The VM's allocation tracer, over one still orbiting camera on a loaded world,
  measured **~18 MB/s** on the S24 and **~21 MB/s** on the Mac. With 40 animated creatures
  the S24 allocates ~59 MB/s.
- **Owners.** By first non-SDK library on the stack: **flutter_scene 50%, flutter_gpu 23%,
  vector_math 16%**. By call site, **60% sits under `Scene.renderViews`**. (The tracer
  samples, so these shares hold; the rates come from the timeline.)
- **Pauses.** With the creatures, scavenges run ~4 a second, each up to 2.6 ms, and some
  land inside frames.

These are the sites we found, each per draw or per node, every frame:

| Where | What |
|:--|:--|
| `node.dart:1489`, `:1509-1511` (`Node.scenePrePass`) | two capturing closures per node per frame |
| `scene_encoder.dart:700-707` → `sceneSortDepth` (`:319-328`) | per recorded draw: `PerspectiveCamera.forward` (`camera.dart:317`, two `Vector3`), `Aabb3.center` (a clone), `transformed3` (a copy), `worldCenter - cameraPosition` (a clone): five `Vector3`s and their `Float32List`s. It is computed even though, for opaque draws, depth is only the last tie-breaker (see 4) |
| `render/frame_transients.dart:336-373` (`TransientArena.emplace`) | per call: the `planEmplacement` record, two `ByteBuffer` objects, two `Uint8List` views, a `gpu.BufferView`; callers add a `ByteData.sublistView` (`render/instance_packing.dart:771`, per non-instanced draw) |
| flutter_gpu `Shader.getUniformSlot` | a new `UniformSlot` per call, not cached; called per draw by the PBR bind (`physically_based_material.dart:1620`, `:1672`, `:1760`) and by any custom `Geometry.bind` |
| `scene_encoder.dart:355` (`resolvePipeline`) | a record key per draw |
| `shader_uniform_bindings.dart:25`, `:55-66`; `sky_sources.dart:78` | `Float32List.fromList` of a spread list per bind; map-entry iteration and a default `SamplerOptions` per bind |

**The biggest single item for a custom `Geometry` is the per-draw `FrameInfo`.** The
encoder memoizes it per shader and depth bias, but only for `UnskinnedGeometry`
(`scene_encoder.dart:789-804`). Any other `Geometry` gets a full `bind` every draw
(`:805-814`), so it emplaces the same 80-byte `FrameInfo` once per draw, with a fresh
`UniformSlot` each time.

In our trace, that one site was **13% of the UI isolate's allocations**. We cannot cache
it ourselves: `TransientWriter` exposes no frame boundary, and arena blocks can recycle
mid-frame (`frame_transients.dart:404-432`).

**Suggestions:**
- Split `Geometry.bind` into `bindBuffers` and `bindFrameInfo`, or give the memo a hook,
  so a custom geometry gets the same skip `UnskinnedGeometry` has.
- Cache `UniformSlot`s per shader and name (in flutter_gpu, or a small map in flutter_scene).
- Reuse scratch vectors in `_depthOf`, and compute an item's sort depth only when the sort
  needs it.
- Make `emplace` write through one cached `Uint8List` per block.
- Walk children and components in `scenePrePass` with a loop instead of capturing closures.

### 3. A supported path for a custom `Geometry` (and fewer bytes for `MeshGeometry`)

`MeshGeometry.fromArrays` always uploads six streams, **72 bytes a vertex**, filling the
absent ones with defaults (`geometry/geometry.dart:1059-1081`,
`geometry/interleaved_layout.dart:365-380`), and keeps a CPU copy by default. Our
terrain uses position, normal, colour and two light values.

We moved it to a custom `Geometry` with two `uint32x2` streams (16 bytes) and its own
vertex and depth-only shaders:
- **RSS −15%** at a 12-chunk radius on the Mac (503 → 426 MB), and −28 to −43 MB on the
  phone at radius 6.
- **+11% fps** where the Mac draws 3.7× the faces (84 → 94 fps).
- The Mac's GPU time at `dpr` 2 did not move (it pays for pixels there).

It works, but only through internals:
- `setVertexStreams` and `bindGeometryBuffers` are `@internal`.
- `Geometry.bind` is typed with the `src/gpu/gpu.dart` shim, so we import `src/` and pin
  flutter_scene to an exact version.

**Suggestions:**
- Make the custom-`Geometry` contract public: stream setup, buffer binding, `depthOnlyVertex`
  and the standard varyings a vertex shader must write.
- Optionally, have `MeshGeometry` skip the streams it was not given, with a layout per
  combination.

### 4. Opaque draws are not front to back across geometries (a question)

The class doc says opaque draws are "sorted by pipeline ... and then front-to-back"
(`scene_encoder.dart:388-390`). The comparator's keys are pipeline, material, **geometry**
(`identityHashCode`), light list, channels and fade, and only then depth
(`scene_encoder.dart:1058-1080`).

So between different geometries (every chunk region of a world, every distinct prop), the
order follows `identityHashCode`, not distance.

We have not measured what front-to-back would buy. On Apple's GPUs (hidden-surface
removal) and Adreno (LRZ) we expect little. On an immediate-mode desktop GPU it is the
classic early-Z win.

**The question:** is depth-before-geometry intended to be traded for batching? One option
is to sort by pipeline and material, then by coarse depth buckets, then by geometry. That
keeps batching and gets most of the early-Z benefit. If you only want the doc fixed, that
is fine too.

### Not asked: pipeline warm-up

The first run after an install stops the UI thread for ~0.6 s (S24) to ~0.8 s (Mac), in
two encodes that compile pipelines. We had this down as a request, until we found
`Scene.warmUp(views, includeOffscreen: true)` (`scene.dart:1397`). That one is on us.

Thanks for flutter_scene. The numbers above come from A/B runs we can share (JSONL, per
run) if they help.

---

## Follow-up

A comment on #435, independent of its four sections. Sent 2026-09-29 (link above).

### Body

One more finding, measured after we filed this. It is separate from the four sections above.

**`TransientArena` drops and re-creates its 256 KB blocks every time the GPU queue drains,
and each new block lands straight in old space.**

On the S24, our UI isolate's old space grew by ~2.4 MB/s with an orbiting camera and ~5 MB/s
with 40 creatures, and none of it was promotion. Between two collections it grew in whole
256 kB steps. So we counted what `TransientArena` makes and drops, in a copy of 0.23.0 with a
counter and a timeline instant in `_acquireBlock` and in the shrink.

What happens:

- Each block stages its data in a `ByteData(256 * 1024)` (`render/frame_transients.dart:242`,
  `:420`). With its header, that is just over the VM's 256 KB limit for a new-space object.
  So every new block is allocated straight into old space, and only a mark-sweep frees it.
- Every submission seals the open blocks (`:427`), so an arena opens one block per pass that
  submits. In our scene that is 2 uniform blocks and 1 instance block a frame, or 3 and 2
  with the creatures.
- A sealed block comes back only when the GPU is done with it, so the pool needs
  blocks-per-frame × frames-in-flight. On the Mac, which is GPU-bound, that is 7–8 frames.
- `beginFrame` keeps only the last frame's count plus one of the finished blocks
  (`:289-302`). Each time the queue drains, the extra blocks are dropped. Each time it fills
  again, new ones are made. At the start of a frame we saw either 0–2 or 12–16 uniform blocks
  in flight, rarely anything between.

Mac (M2 Pro, 120 Hz, Retina), profile build, one timeline per run over ~14 s:

| Scene | Old space, direct growth | Blocks the arenas made | Old-gen collections | Concurrent mark + sweep |
|:--|--:|--:|--:|--:|
| Orbiting camera | 69–76 MB | 277–302 (69–76 MB) | 40–45 | 15–18 ms/s |
| 40 creatures | 93–98 MB | 366–392 (92–98 MB) | 55–61 | 24–28 ms/s |

The direct growth and the new blocks agree to the MB.

**On the S24** (Adreno 750, 120 Hz), profile, the last 12 s of each timeline, the same thing
happens. The orbiting camera makes 151–154 blocks, and 23–24 old-gen collections follow. 6–11
of their pauses land inside a frame, up to 4.1–4.7 ms, and concurrent marking costs 40–43
ms/s. With the creatures it is 285 blocks, 38 collections (15 in a frame, up to 3.3 ms) and
58 ms/s of marking.

**What we tried**, in our copy: drop a finished block only after 120 frames unused (a
`lastUsedFrame` per block, set in `_acquireBlock`), instead of counting by class. The pool
fills to the queue's depth in the first second and then stays there.

- **Blocks made in a 12 s release run:** 239–340 → 0–18 on the Mac and 187–301 → 0–4 on
  the S24, none dropped.
- **Old-gen collections:** 40–61 → 10–12 on the Mac (traced over ~14 s), and none at all on
  the S24. Concurrent marking goes to 4–5 ms/s on the Mac and to 0 on the S24.
- **RSS:** the same on the Mac, 3–4 MB more on the S24 (the pool kept at the queue's depth).
- **Release, S24, orbiting:** 113.5–117.0 → 117.1–118.8 fps, hitches 48–91 → 23–43 (three
  runs a side, alternated). With the creatures, everything is inside the spread. The Mac is
  GPU-bound and does not move.

**On the phone, the pauses move rather than vanish.** Each old-gen collection also emptied
new space, so the scavenges left over were small and ran at idle. Without the old-gen
collections, new space fills to its 16 MB and is scavenged because it is full, inside a
frame, at 4.6–6.6 ms each. With the orbiting camera, the collector's time inside frames goes
from 21–34 ms to 36–43 ms in 12 s. With the creatures it goes from 27 to 36 ms. Frames over
8.3 ms stay the same. So this fix saves the marking CPU and the mark-sweep pauses. What is
left on the phone is new-space garbage, ~18 MB/s while orbiting, which is section 2 above.

**Suggestions.** Either one ends the churn:

- **Shrink by age, not by the last frame's count.** Drop a finished block only after N frames
  unused, so the pool follows the queue's depth instead of shedding it whenever the queue
  drains. This is the version we measured.
- **Take the staging out of the block.** A block needs its CPU staging only while it is
  open, since `_seal` uploads it (`:427`). An arena could reuse one or two staging buffers
  across seals and pool only the device buffers. That keeps the Dart heap out of it even if
  the device pool still churns.

Neither one lowers the phone's pause time by itself; that comes from cutting the per-draw
allocation in section 2. Happy to send either as a PR.
