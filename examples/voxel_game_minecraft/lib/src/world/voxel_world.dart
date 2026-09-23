import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

import '../core/blocks.dart';
import 'package:voxel_engine/core.dart';
import '../game/circuits.dart';
import 'terrain_generator.dart';
import 'package:voxel_scene/voxel_scene.dart';

typedef BlockChanged = void Function(IVec3 block, int oldId, int newId);
typedef StructureAt = ({int x, int y, int z, int type});

/// The POC's world facade. Chunk streaming, jobs, edits and light live in
/// voxel_core's [ChunkStreamer] (VP1.6); the chunk nodes and terrain materials
/// live in voxel_scene's [VoxelChunkView] (VP2.2), the streamer's sink. This
/// class keeps what is the game's: the terrain generator, liquid flow,
/// circuits, dimension rules and the save format.
class VoxelWorld implements VoxelEditor {
  VoxelWorld({required this.seedValue, int loadRadius = 8, bool playground = false}) {
    _streamer = ChunkStreamer(table: Blocks.table, sink: _view, loadRadius: loadRadius);
    _generator = TerrainGenerator(ids: Blocks.generatorIds(), seed: seedValue, playground: playground);
    circuits = Circuits(this);
  }

  final VoxelChunkView _view = VoxelChunkView();

  static const int sizeX = ChunkSize.sizeX;
  static const int sizeZ = ChunkSize.sizeZ;
  static const int sizeY = ChunkSize.sizeY;
  static const int volume = ChunkSize.volume;
  static const int frameBudgetUsec = ChunkStreamer.frameBudgetUsec;
  static const List<ChunkPos> ring = ChunkStreamer.ring;

  late final ChunkStreamer _streamer;

  /// The chunk nodes, under voxel_scene's view.
  Node get root => _view.root;
  int seedValue;

  /// Stage 33: the generator flattens the playground's plaza.
  bool get playground => _generator.playground;
  BlockChanged? onBlockChanged;

  int get loadRadius => _streamer.loadRadius;
  set loadRadius(int value) => _streamer.loadRadius = value;
  int get unloadRadius => _streamer.unloadRadius;
  set unloadRadius(int value) => _streamer.unloadRadius = value;
  int get maxInflight => _streamer.maxInflight;
  set maxInflight(int value) => _streamer.maxInflight = value;

  Map<ChunkPos, Uint8List> get chunks => _streamer.chunks;
  int get chunksBuilt => _streamer.chunksBuilt;
  int get facesEmitted => _streamer.facesEmitted;
  double get meshMsTotal => _streamer.meshMsTotal;
  int get remeshesQueued => _streamer.remeshesQueued;

  late TerrainGenerator _generator;
  ChunkWorkerPool? _pool;

  /// Stage 31: [lightingEnabled] false is `--no-light` (set before [start]).
  bool lightingEnabled = true;

  /// Stage 31: how much of the baked skylight shows (1.0 noon, 0.35 night, 0.0
  /// underworld), read by the three terrain materials when they bind.
  void setSkyIntensity(double value) => _view.setSkyIntensity(value);

  /// Stage 31: (sky, block) light of a cell, 0..15 each, as the last mesh job of
  /// its chunk computed it. A cell whose chunk has no mesh yet reads as open sky.
  CellLight lightAt(IVec3 b) => _streamer.lightAt(b);

  /// Stage 31: vertices of the chunk's last mesh whose AO is below 1.
  int aoVertsOf(ChunkPos pos) => _streamer.aoVertsOf(pos);

  /// Stage 31: keep what a mesh job learnt about its chunk's light.
  void storeLight(ChunkPos pos, ChunkMeshResult surface) => _streamer.storeLight(pos, surface);

  /// Stage 27: redstone-lite, host-only like the flow ([flowEnabled] gates both).
  /// Stage 29: rebuilt on a dimension switch, so not final.
  late Circuits circuits;

  /// Stage 29: the ONE dimension this world holds (0 overworld, 1 underworld).
  static const int dimOverworld = 0;
  static const int dimUnderworld = 1;
  static const int structFortress = 9;
  int get dimension => _streamer.dimension;

  /// VP1.5: made in a static so the closure sent to the worker isolates
  /// captures only [ids] and [seed], never this world and its scene nodes.
  static ChunkGeneratorFactory _generatorFactory(Map<String, int> ids, int seed, bool playground) =>
      () => TerrainGenerator(ids: ids, seed: seed, playground: playground);

  Future<void> start() async {
    _pool?.dispose();
    final pool = ChunkWorkerPool(ChunkWorkerConfig(
      generator: _generatorFactory(Blocks.generatorIds(), seedValue, playground),
      table: Blocks.table,
      lighting: lightingEnabled,
    ));
    await pool.start();
    _pool = pool;
    _streamer.jobs = pool;
  }

  void dispose() {
    _pool?.dispose();
    _pool = null;
    _streamer.jobs = null;
  }

  TerrainGenerator get generator => _generator;

  Future<void> setWorldSeed(int value) async {
    seedValue = value;
    _generator.setSeed(value);
    await start();
  }

  /// Everything the generator reads, the seed and the plaza: a client whose
  /// world was built before the host's hello takes the host's whole.
  Future<void> setWorldShape(int seed, {required bool playground}) async {
    seedValue = seed;
    _generator = TerrainGenerator(ids: Blocks.generatorIds(), seed: seed, playground: playground)..setDimension(dimension);
    await start();
  }

  int surfaceHeight(int x, int z) => _generator.surfaceHeight(x, z);
  int biomeAt(int x, int z) => _generator.biomeAt(x, z);

  static ChunkPos chunkOfVec(Vector3 v) => (x: (v.x / sizeX).floor(), z: (v.z / sizeZ).floor());

  static ChunkPos chunkOf(IVec3 b) => ChunkStreamer.chunkOf(b);
  static ChunkPos chunkOfXZ(int x, int z) => ChunkStreamer.chunkOfXZ(x, z);
  static int index(int x, int y, int z) => ChunkSize.index(x, y, z);

  bool get isIdle => _streamer.isIdle;
  int get loadedChunkCount => _streamer.loadedChunkCount;
  int get pendingCount => _streamer.pendingCount;

  void updateAround(Vector3 worldPosition) => _streamer.updateAround(chunkOfVec(worldPosition));

  void refresh() => _streamer.refresh();

  /// Chunks with a mesh in the scene: the window `loadRadius` fills ([chunks]
  /// also holds the generated ring around it).
  int get meshCount => _streamer.meshCount;

  /// Stage 24: a smaller render distance takes effect at once.
  void trimWindow() => _streamer.trimWindow();

  /// Once per frame: upload finished surfaces within the frame budget, then
  /// dispatch more work.
  void update() => _streamer.update();

  // --- block access -------------------------------------------------------------

  int getBlock(IVec3 b) => getBlockXYZ(b.x, b.y, b.z);

  /// VP1.8: bodies and rays read the world through voxel_core's [VoxelQuery].
  @override
  VoxelBlockTable get table => Blocks.table;

  @override
  int getBlockXYZ(int x, int y, int z) => _streamer.getBlockXYZ(x, y, z);

  bool isLoaded(IVec3 b) => chunks.containsKey(chunkOf(b));

  bool isSolid(IVec3 b) => isSolidXYZ(b.x, b.y, b.z);

  bool isSolidXYZ(int x, int y, int z) {
    if (y < 0) return true;
    return Blocks.isSolid(getBlockXYZ(x, y, z));
  }

  bool isLiquid(IVec3 b) => Blocks.isLiquid(getBlock(b));

  @override
  bool setBlock(IVec3 b, int id) {
    final old = getBlock(b);
    if (!_streamer.setBlock(b, id)) return false;
    flow.touch(this, b, old, id);
    if (flowEnabled) circuits.touch(b, old, id);
    onBlockChanged?.call(b, old, id);
    return true;
  }

  // --- liquid flow (stage 22; VK1.6: voxel_core's LiquidFlow) ---------------------

  /// Host-only cellular flow, seeded by edits alone. Water steps every 0.25 s
  /// and spreads 4, lava every 0.6 s and spreads 2 (kinds in
  /// [Blocks.liquidKinds] order); lava touching water hardens, a source into
  /// obsidian when the pack has it, otherwise cobblestone.
  late final LiquidFlow flow = LiquidFlow(
    table: Blocks.table,
    rules: [
      LiquidRule(flowingId: Blocks.flowOf('water'), period: 0.25, reach: 4),
      LiquidRule(flowingId: Blocks.flowOf('lava'), period: 0.6, reach: 2),
    ],
    canEnter: Blocks.isReplaceable,
    contact: _liquidContact,
  );

  static final int _water = Blocks.liquidKinds.indexOf('water');
  static final int _lava = Blocks.liquidKinds.indexOf('lava');

  static int? _liquidContact(int kind, bool source, int touching) {
    if (kind != _lava || touching != _water) return null;
    return Blocks.indexOf(source && Blocks.has('obsidian') ? 'obsidian' : 'cobblestone');
  }

  /// A flowing cell loaded from a save: it re-derives its distance when touched.
  static const int flowUnknown = LiquidFlow.unknown;

  /// False on a client: the host owns the flow and every cell it writes
  /// arrives as a plain block edit. Gates the circuits too.
  bool get flowEnabled => flow.enabled;
  set flowEnabled(bool value) => flow.enabled = value;

  /// Cells written by the flow, for the probe.
  int get flowUpdates => flow.updates;

  int get flowPending => flow.pending;

  /// The recorded distance of a cell, or [fallback] when it has none.
  int flowDistOf(IVec3 b, [int fallback = 0]) => flow.distOf(b, fallback);

  /// Once per simulation tick on the host / solo.
  void tickFlow(double dt) => flow.tick(this, dt);

  /// Highest solid block y at a column among LOADED chunks, or the generator's guess.
  int groundHeight(int x, int z) {
    final pos = chunkOfXZ(x, z);
    final blocks = chunks[pos];
    if (blocks == null) return surfaceHeight(x, z);
    final lx = x - pos.x * sizeX;
    final lz = z - pos.z * sizeZ;
    for (var y = sizeY - 1; y > 0; y--) {
      if (Blocks.isSolid(blocks[index(lx, y, lz)])) return y + 1;
    }
    return 1;
  }

  void reset() => _streamer.reset();

  List<StructureAt> structuresNear(ChunkPos pos) => _generator.structuresNearIn(pos.x, pos.z, dimension);

  // --- stage 29: dimensions ---------------------------------------------------------

  /// Leave every chunk of the current dimension behind (its edits kept under
  /// its own key) and start generating [d]. Jobs in flight keep the old epoch
  /// and are dropped when they land.
  void switchDimension(int d) {
    if (d == dimension) return;
    _generator.setDimension(d);
    flow.clear();
    final onTnt = circuits.onTntPowered;
    circuits = Circuits(this)..onTntPowered = onTnt;
    _streamer.switchDimension(d);
  }

  /// Edited cells of dimension [d] (the live one reads the live map).
  int editCountIn(int d) => _streamer.editCountIn(d);

  /// An edit for a dimension that is not loaded (a host broadcast while this
  /// peer is elsewhere): it waits in that dimension's delta and lands when its
  /// chunk generates.
  void storeEdit(int d, IVec3 b, int id) {
    if (d == dimension) {
      setBlock(b, id);
      return;
    }
    _streamer.storeEditElsewhere(d, b, id);
  }

  // --- persistence (edit delta) ---------------------------------------------------

  static const int saveMagic = 0x4342574F; // "CBWO"

  /// Version 2 (stage 29): the edit delta of every dimension, one block per
  /// dimension after the seed. Version 1 (one delta) still loads as dimension 0.
  static const int saveVersion = 2;
  static const int saveDimensions = 2;

  /// VP1.7: the byte layout lives in voxel_core's [EditDeltaCodec]; the POC
  /// supplies its magic, its version and the version-1 files it still reads.
  static const EditDeltaCodec saveCodec = EditDeltaCodec(
    magic: saveMagic,
    version: saveVersion,
    dimensions: saveDimensions,
    legacySingleDimensionVersion: 1,
  );

  Uint8List editsToBytes() => saveCodec.encode(seedValue, _streamer.editsByDimension);

  /// Returns the seed the edits were made against. Unreadable bytes throw
  /// (voxel_core's [EditDeltaCodec.decode], VP4.1).
  int loadEditsFromBytes(Uint8List bytes) {
    final read = saveCodec.decode(bytes);
    _streamer.replaceEdits(read.edits);
    return read.seed;
  }

  Future<void> saveEdits(String path) async {
    final f = File(path);
    await f.parent.create(recursive: true);
    await f.writeAsBytes(editsToBytes(), flush: true);
  }

  Future<bool> loadEdits(String path) async {
    final f = File(path);
    if (!await f.exists()) return false;
    final seed = loadEditsFromBytes(await f.readAsBytes());
    if (seed != seedValue) await setWorldSeed(seed);
    return true;
  }

  int get editCount => _streamer.editCount;

  @visibleForTesting
  double debugWindowFill() => math.min(1.0, meshCount / math.pow(loadRadius * 2 + 1, 2));
}
