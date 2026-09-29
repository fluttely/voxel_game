# flutter_scene upstream proposal (PF16) — draft, 2026-09-29

> **Status: sent, 2026-09-29**, as one issue with the owner's ok on this text:
> <https://github.com/bdero/flutter_scene/issues/435> (PF16, `docs/VOXEL_PERF_PLAN_2026-09-25.md`).
> Everything below the line is the issue as posted. Line numbers are flutter_scene 0.23.0
> as published on pub.dev.

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
