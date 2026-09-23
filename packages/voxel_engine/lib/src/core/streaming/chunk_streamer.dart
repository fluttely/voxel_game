import 'dart:typed_data';

import '../grid/chunk_size.dart';
import '../grid/voxel_block_table.dart';
import '../math/ivec3.dart';
import '../mesh/chunk_mesher.dart';

/// A chunk column position, in chunks.
typedef ChunkPos = ({int x, int z});

/// (sky, block) light of a cell, 0..15 each.
typedef CellLight = ({int sky, int block});

/// What a [ChunkJobs] fails a job with when it drops the job on purpose (a
/// disposed pool). The streamer ignores it; any other job error is a bug and
/// [ChunkStreamer.update] rethrows it.
class ChunkJobCancelled implements Exception {
  /// A cancellation, and why.
  const ChunkJobCancelled(this.message);

  /// Why the job was dropped.
  final String message;

  @override
  String toString() => 'ChunkJobCancelled: $message';
}

/// Where generation and meshing jobs run. [ChunkWorkerPool] is the isolate
/// implementation; a test can answer synchronously.
abstract interface class ChunkJobs {
  /// The block volume of chunk ([cx], [cz]) in [dimension], [ChunkSize.volume] bytes.
  Future<Uint8List> generate(int cx, int cz, [int dimension = 0]);

  /// The mesh of chunk ([cx], [cz]); [ring] is as [ChunkMesher.build] reads it.
  Future<ChunkMeshResult> mesh(int cx, int cz, List<Uint8List?> ring);
}

/// What the streamer hands finished meshes to: a renderer, or a test.
abstract interface class ChunkMeshSink {
  /// A chunk's mesh is ready (a first mesh or a remesh that replaces the last).
  void apply(ChunkPos pos, ChunkMeshResult result);

  /// A chunk that had a mesh left the window.
  void remove(ChunkPos pos);
}

/// Chunk streaming around a centre, without a renderer: the load window, the
/// generation and mesh jobs, edits and their remesh rule, per-dimension edit
/// deltas and the light volumes each mesh job returns. Finished meshes go to
/// [sink] within a per-frame budget.
class ChunkStreamer {
  /// A streamer for [table]'s blocks that hands meshes to [sink]. Nothing
  /// streams until [jobs] is set and [updateAround] names a centre.
  ChunkStreamer({required this.table, required this.sink, this.loadRadius = 8}) : unloadRadius = loadRadius + 2;

  /// Microseconds [update] may spend handing meshes to the sink per frame.
  static const int frameBudgetUsec = 7000;

  /// A chunk and its eight neighbours, in the order a mesh job reads them.
  static const List<ChunkPos> ring = [
    (x: 0, z: 0), (x: -1, z: 0), (x: 1, z: 0), (x: 0, z: -1), (x: 0, z: 1),
    (x: -1, z: -1), (x: 1, z: -1), (x: -1, z: 1), (x: 1, z: 1),
  ];

  /// The chunk holding cell [b].
  static ChunkPos chunkOf(IVec3 b) => chunkOfXZ(b.x, b.z);

  /// The chunk holding the column at world ([x], [z]).
  static ChunkPos chunkOfXZ(int x, int z) => (x: (x / ChunkSize.sizeX).floor(), z: (z / ChunkSize.sizeZ).floor());

  /// What each block id is: which edits change light and remesh the ring.
  final VoxelBlockTable table;

  /// Where finished meshes go.
  final ChunkMeshSink sink;

  /// Chunks meshed on each side of the centre: a (2r + 1)² window.
  int loadRadius;

  /// A mesh further than this from the centre is removed; the gap above
  /// [loadRadius] keeps a walk along a border from reloading chunks.
  int unloadRadius;

  /// Jobs dispatched and not yet returned, at most.
  int maxInflight = 24;

  /// Where jobs run; nothing dispatches while it is null. Replacing it drops
  /// the results of jobs the old one still owes.
  ChunkJobs? jobs;

  /// Generated chunk volumes: the window plus the ring generated around it.
  final Map<ChunkPos, Uint8List> chunks = {};
  /// Meshes handed to the sink, remeshes included.
  int get chunksBuilt => _chunksBuilt;

  /// Faces in every mesh handed to the sink, remeshes included.
  int get facesEmitted => _facesEmitted;

  /// The mesh jobs' own clocks ([ChunkMeshResult.ms]), summed.
  double get meshMsTotal => _meshMsTotal;

  /// Remeshes queued by edits.
  int get remeshesQueued => _remeshesQueued;

  int _chunksBuilt = 0;
  int _facesEmitted = 0;
  double _meshMsTotal = 0.0;
  int _remeshesQueued = 0;

  final Set<ChunkPos> _meshed = {};
  final List<ChunkPos> _pending = [];
  ChunkPos _center = (x: 999999, z: 999999);

  final Map<ChunkPos, Uint8List> _lightSky = {};
  final Map<ChunkPos, Uint8List> _lightBlock = {};
  final Map<ChunkPos, int> _aoVerts = {};

  /// The one dimension the streamer holds. A switch keeps the live edits under
  /// [_editsByDimension] for the dimension left, drops every chunk and
  /// regenerates; jobs started before it carry a stale [_genEpoch] and are dropped.
  int dimension = 0;
  final Map<int, Map<ChunkPos, Map<int, int>>> _editsByDimension = {};
  Map<ChunkPos, Map<int, int>> _edits = {};
  int _genEpoch = 0;

  final Set<ChunkPos> _genInflight = {};
  final Set<ChunkPos> _meshInflight = {};
  final Map<ChunkPos, ChunkMeshResult> _surfaceReady = {};

  /// Chunks edited while a mesh job for them was already in flight (or its
  /// result waiting): that job meshed the old blocks, so landing it must not
  /// clear the request.
  final Set<ChunkPos> _remeshAgain = {};

  /// The first job that failed since the last [update], other than a
  /// [ChunkJobCancelled]. [update] throws it.
  (Object, StackTrace)? _jobError;

  /// Nothing pending, in flight or waiting for the sink.
  bool get isIdle => _pending.isEmpty && _genInflight.isEmpty && _meshInflight.isEmpty && _surfaceReady.isEmpty;

  /// Generated chunk volumes held, the ring around the window included.
  int get loadedChunkCount => chunks.length;

  /// Chunks waiting for a mesh, remeshes included.
  int get pendingCount => _pending.length;

  /// Chunks with a mesh handed to the sink.
  int get meshCount => _meshed.length;

  // --- light ----------------------------------------------------------------------

  /// (sky, block) light of a cell as the last mesh job of its chunk computed it.
  /// A cell whose chunk has no mesh yet reads as open sky.
  CellLight lightAt(IVec3 b) {
    if (b.y < 0 || b.y >= ChunkSize.sizeY) return (sky: 15, block: 0);
    final pos = chunkOf(b);
    final sky = _lightSky[pos];
    if (sky == null) return (sky: 15, block: 0);
    final i = ChunkSize.index(b.x - pos.x * ChunkSize.sizeX, b.y, b.z - pos.z * ChunkSize.sizeZ);
    return (sky: sky[i], block: _lightBlock[pos]![i]);
  }

  /// Vertices of the chunk's last mesh whose AO is below 1.
  int aoVertsOf(ChunkPos pos) => _aoVerts[pos] ?? 0;

  /// Keep what a mesh job learnt about its chunk's light.
  void storeLight(ChunkPos pos, ChunkMeshResult surface) {
    _meshMsTotal += surface.ms;
    _lightSky[pos] = surface.sky;
    _lightBlock[pos] = surface.block;
    _aoVerts[pos] = surface.aoVerts;
  }

  // --- window ---------------------------------------------------------------------

  /// Centres the window on [centre]. Cheap when the centre has not changed.
  void updateAround(ChunkPos centre) {
    if (centre == _center) return;
    _center = centre;
    _refreshWindow();
  }

  /// Forget the centre, so the next [updateAround] rebuilds the window.
  void refresh() => _center = (x: 999999, z: 999999);

  /// A smaller [loadRadius] takes effect at once: everything past it goes now
  /// instead of waiting for the centre to walk out of the unload band.
  void trimWindow() {
    for (final pos in _meshed.toList()) {
      if ((pos.x - _center.x).abs() > loadRadius || (pos.z - _center.z).abs() > loadRadius) _unload(pos);
    }
    for (final pos in chunks.keys.toList()) {
      if ((pos.x - _center.x).abs() > loadRadius + 1 || (pos.z - _center.z).abs() > loadRadius + 1) chunks.remove(pos);
    }
  }

  void _refreshWindow() {
    // A remesh still queued for a chunk that has a mesh (an edit not dispatched
    // yet) survives the window moving; clearing it would leave that chunk with
    // its pre-edit mesh and light for good.
    final remeshes = [
      for (final p in _pending)
        if (_meshed.contains(p) && (p.x - _center.x).abs() <= unloadRadius && (p.z - _center.z).abs() <= unloadRadius) p,
    ];
    _pending.clear();
    for (var dz = -loadRadius; dz <= loadRadius; dz++) {
      for (var dx = -loadRadius; dx <= loadRadius; dx++) {
        final pos = (x: _center.x + dx, z: _center.z + dz);
        if (!_meshed.contains(pos)) _pending.add(pos);
      }
    }
    int d2(ChunkPos p) => (p.x - _center.x) * (p.x - _center.x) + (p.z - _center.z) * (p.z - _center.z);
    _pending.sort((a, b) => d2(a).compareTo(d2(b)));
    _pending.insertAll(0, remeshes);
    for (final pos in _meshed.toList()) {
      if ((pos.x - _center.x).abs() > unloadRadius || (pos.z - _center.z).abs() > unloadRadius) _unload(pos);
    }
    for (final pos in chunks.keys.toList()) {
      if ((pos.x - _center.x).abs() > unloadRadius + 1 || (pos.z - _center.z).abs() > unloadRadius + 1) chunks.remove(pos);
    }
  }

  /// Once per frame: hand finished meshes to the sink within the frame budget,
  /// then dispatch more work.
  ///
  /// Throws the error of a job that failed since the last call (a generator or
  /// mesher bug). The failed chunk is dispatched again on a later call.
  void update() {
    final failed = _jobError;
    if (failed != null) {
      _jobError = null;
      Error.throwWithStackTrace(failed.$1, failed.$2);
    }
    final sw = Stopwatch()..start();
    final applied = <ChunkPos>[];
    for (final e in _surfaceReady.entries) {
      if (chunks.containsKey(e.key)) _apply(e.key, e.value);
      applied.add(e.key);
      if (sw.elapsedMicroseconds >= frameBudgetUsec) break;
    }
    for (final pos in applied) {
      _surfaceReady.remove(pos);
      // Edited after that job started: stay pending for a fresh mesh.
      if (!_remeshAgain.remove(pos)) _pending.remove(pos);
    }
    _dispatch();
  }

  void _dispatch() {
    final j = jobs;
    if (j == null) return;
    for (final pos in List.of(_pending)) {
      if (_genInflight.length + _meshInflight.length >= maxInflight) return;
      if (_meshInflight.contains(pos) || _surfaceReady.containsKey(pos)) continue;
      var ringReady = true;
      for (final o in ring) {
        final n = (x: pos.x + o.x, z: pos.z + o.z);
        if (chunks.containsKey(n)) continue;
        ringReady = false;
        if (!_genInflight.contains(n)) {
          _genInflight.add(n);
          final epoch = _genEpoch;
          j.generate(n.x, n.z, dimension).then((blocks) {
            if (epoch != _genEpoch) return; // generated for the dimension we left
            _genInflight.remove(n);
            if (jobs != j) return;
            _applyEdits(n, blocks);
            chunks[n] = blocks;
          }).catchError((Object e, StackTrace st) {
            if (epoch == _genEpoch) _genInflight.remove(n);
            _jobFailed(e, st);
          });
        }
      }
      if (!ringReady) continue;
      _meshInflight.add(pos);
      final vols = [for (final o in ring) chunks[(x: pos.x + o.x, z: pos.z + o.z)]];
      final epoch = _genEpoch;
      j.mesh(pos.x, pos.z, vols).then((surface) {
        if (epoch != _genEpoch) return;
        _meshInflight.remove(pos);
        if (jobs != j) return;
        _surfaceReady[pos] = surface;
      }).catchError((Object e, StackTrace st) {
        if (epoch == _genEpoch) _meshInflight.remove(pos);
        _jobFailed(e, st);
      });
    }
  }

  void _jobFailed(Object e, StackTrace st) {
    if (e is ChunkJobCancelled) return;
    _jobError ??= (e, st);
  }

  void _apply(ChunkPos pos, ChunkMeshResult surface) {
    _chunksBuilt += 1;
    _facesEmitted += surface.faces;
    storeLight(pos, surface);
    sink.apply(pos, surface);
    _meshed.add(pos);
  }

  void _unload(ChunkPos pos) {
    if (_meshed.remove(pos)) sink.remove(pos);
    _lightSky.remove(pos);
    _lightBlock.remove(pos);
    _aoVerts.remove(pos);
  }

  void _applyEdits(ChunkPos pos, Uint8List blocks) {
    final edits = _edits[pos];
    if (edits == null) return;
    for (final e in edits.entries) {
      blocks[e.key] = e.value;
    }
  }

  // --- blocks ---------------------------------------------------------------------

  /// The block id at a world cell; air outside the height range or in a chunk
  /// that is not generated.
  int getBlockXYZ(int x, int y, int z) {
    if (y < 0 || y >= ChunkSize.sizeY) return VoxelBlockTable.air;
    final pos = chunkOfXZ(x, z);
    final blocks = chunks[pos];
    if (blocks == null) return VoxelBlockTable.air;
    return blocks[ChunkSize.index(x - pos.x * ChunkSize.sizeX, y, z - pos.z * ChunkSize.sizeZ)];
  }

  /// Writes [id] at [b], records the edit and queues the remeshes it needs.
  /// False when nothing changed: outside 1..sizeY-1, an ungenerated chunk, or
  /// the same id already there.
  bool setBlock(IVec3 b, int id) {
    if (b.y < 1 || b.y >= ChunkSize.sizeY) return false;
    final pos = chunkOf(b);
    final blocks = chunks[pos];
    if (blocks == null) return false;
    final lx = b.x - pos.x * ChunkSize.sizeX;
    final lz = b.z - pos.z * ChunkSize.sizeZ;
    final i = ChunkSize.index(lx, b.y, lz);
    final old = blocks[i];
    if (old == id) return false;
    blocks[i] = id;
    (_edits[pos] ??= {})[i] = id;
    _queueRemesh(pos);
    // A block that stops or makes light changes the light of the chunks around
    // it, so the whole 3x3 ring remeshes; anything else only touches a
    // neighbour when it sits on the border.
    if (table.isOpaque(old) || table.isOpaque(id) || table.emissionOf(old) > 0 || table.emissionOf(id) > 0) {
      for (final o in ring) {
        if (o.x != 0 || o.z != 0) _queueRemesh((x: pos.x + o.x, z: pos.z + o.z));
      }
    } else {
      final dx = lx == 0 ? -1 : (lx == ChunkSize.sizeX - 1 ? 1 : 0);
      final dz = lz == 0 ? -1 : (lz == ChunkSize.sizeZ - 1 ? 1 : 0);
      if (dx != 0) _queueRemesh((x: pos.x + dx, z: pos.z));
      if (dz != 0) _queueRemesh((x: pos.x, z: pos.z + dz));
      if (dx != 0 && dz != 0) _queueRemesh((x: pos.x + dx, z: pos.z + dz));
    }
    return true;
  }

  /// Writes [id] at [b] now when its chunk is loaded ([setBlock]); otherwise
  /// records the edit, and it lands when the chunk generates. For an edit
  /// that must not be lost (one from another player).
  void storeEdit(IVec3 b, int id) {
    if (b.y < 1 || b.y >= ChunkSize.sizeY) return;
    final pos = chunkOf(b);
    if (chunks.containsKey(pos)) {
      setBlock(b, id);
      return;
    }
    (_edits[pos] ??= {})[ChunkSize.index(b.x - pos.x * ChunkSize.sizeX, b.y, b.z - pos.z * ChunkSize.sizeZ)] = id;
  }

  void _queueRemesh(ChunkPos pos) {
    if (!chunks.containsKey(pos) || !_meshed.contains(pos)) return;
    if (_meshInflight.contains(pos) || _surfaceReady.containsKey(pos)) _remeshAgain.add(pos);
    if (!_pending.contains(pos)) {
      _pending.insert(0, pos);
      _remeshesQueued += 1;
    }
  }

  /// Drops every chunk, mesh and light volume of the live dimension; its edits stay.
  void reset() {
    for (final pos in _meshed) {
      sink.remove(pos);
    }
    _meshed.clear();
    _lightSky.clear();
    _lightBlock.clear();
    _aoVerts.clear();
    _remeshAgain.clear();
    chunks.clear();
    _pending.clear();
    _surfaceReady.clear();
    _center = (x: 999999, z: 999999);
  }

  // --- dimensions and edits -------------------------------------------------------

  /// Leave every chunk of the current dimension behind (its edits kept under its
  /// own key) and start streaming [d]. Jobs in flight keep the old epoch and are
  /// dropped when they land.
  void switchDimension(int d) {
    if (d == dimension) return;
    _editsByDimension[dimension] = _edits;
    _edits = _editsByDimension[d] ?? {};
    _editsByDimension[d] = _edits;
    dimension = d;
    _genEpoch += 1;
    _genInflight.clear();
    _meshInflight.clear();
    reset();
  }

  /// Edited cells of dimension [d].
  int editCountIn(int d) {
    final edits = d == dimension ? _edits : (_editsByDimension[d] ?? const {});
    return edits.values.fold(0, (a, e) => a + e.length);
  }

  /// Edited cells of the live dimension.
  int get editCount => _edits.values.fold(0, (a, e) => a + e.length);

  /// An edit for a dimension that is not the live one: it waits in that
  /// dimension's delta and lands when its chunk generates there.
  void storeEditElsewhere(int d, IVec3 b, int id) {
    if (d == dimension) throw ArgumentError.value(d, 'd', 'the live dimension edits through setBlock');
    final edits = _editsByDimension[d] ??= {};
    final pos = chunkOf(b);
    (edits[pos] ??= {})[ChunkSize.index(b.x - pos.x * ChunkSize.sizeX, b.y, b.z - pos.z * ChunkSize.sizeZ)] = id;
  }

  /// Every dimension's edit delta, the live one included: dimension -> chunk ->
  /// (cell index -> id). Live maps, for a save codec to read.
  Map<int, Map<ChunkPos, Map<int, int>>> get editsByDimension {
    _editsByDimension[dimension] = _edits;
    return _editsByDimension;
  }

  /// Replaces every dimension's edit delta, as a save codec read it.
  void replaceEdits(Map<int, Map<ChunkPos, Map<int, int>>> all) {
    _editsByDimension
      ..clear()
      ..addAll(all);
    _edits = _editsByDimension[dimension] ?? {};
    _editsByDimension[dimension] = _edits;
  }
}
