import 'dart:math' as math;

import 'package:flutter/foundation.dart' show TargetPlatform, ValueNotifier, defaultTargetPlatform;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';
import 'package:sound_recipes/sound_recipes.dart';
import 'package:voxel_engine/content.dart';
import 'package:voxel_engine/net.dart' show NetHost;
import 'package:voxel_engine/core.dart';
import 'package:voxel_scene/voxel_scene.dart';
import 'package:voxel_engine/signals.dart';

import '../camera/first_person_view.dart';
import '../camera/view_camera.dart';
import '../entities/game_entity.dart';
import '../entities/item_pickup.dart';
import '../entities/projectile.dart';
import '../entities/target.dart';
import '../input/input_map.dart';
import '../input/voxel_action.dart';
import '../loop/fixed_step_loop.dart';
import '../loop/frame_stats.dart';
import '../loop/measured_scene.dart';
import '../mobs/mob.dart';
import '../mobs/mob_spec.dart';
import '../mobs/spawner.dart';
import '../net/remote_player.dart';
import '../net/sessions.dart';
import '../player/player_entity.dart';
import '../spec/graphics_spec.dart';
import '../spec/signal_spec.dart';
import '../spec/voxel_game_spec.dart';
import '../world/game_world.dart';
import '../world/world_save.dart';

/// A running game made from a [VoxelGameSpec]: the world, the player, the
/// creatures and items in it, the clock and the sky. [frame] advances it by
/// real time in fixed steps; everything a game hooks into is reachable from
/// here.
///
/// Headless ([VoxelGame.startHeadless]) it has no scene, no worker isolates and no
/// visuals, and steps as fast as it is asked: tests, bots and servers.
class VoxelGame {
  VoxelGame._(this.spec, this.blocks, this.items, this.world, {required this.headless, this.authority = true})
    : random = math.Random(spec.seed),
      input = InputMap<VoxelAction>(VoxelAction.defaultBindings),
      recipes = RecipeBook(spec.recipes),
      timeOfDay = spec.sky.startTime {
    pathCosts = blocks.pathCosts(avoidLiquids: const {'lava'});
    player = PlayerEntity(
      spec.player,
      Inventory(stackSize: (id) => items[id].stack, maxDurability: (id) => items[id].durability),
    );
    spawner = MobSpawner(this);
    if (!authority) {
      // A client: the host runs the liquids, the circuits and the spawning.
      world.flow.enabled = false;
      spawner.enabled = false;
      return;
    }
    final s = spec.signals;
    if (s != null) {
      final net = signals = SignalNetwork(world, _signalRules(s));
      world.addListener(net.touch);
      _plates = {for (final p in s.plates) blocks.indexOf(p)};
    }
  }

  SignalRules _signalRules(SignalSpec s) {
    int id(String name) => blocks.indexOf(name);
    final reactions = <int, SignalReaction>{};
    for (final e in s.lamps.entries) {
      final r = SignalReactions.swap(id(e.key), id(e.value));
      reactions[id(e.key)] = r;
      reactions[id(e.value)] = r;
    }
    if (s.doors.isNotEmpty) {
      final pairs = {for (final e in s.doors.entries) id(e.key): id(e.value)};
      final door = SignalReactions.door(
        pairs,
        onSwing: (c) => playSound('door', at: Vector3(c.x + 0.5, c.y + 1.0, c.z + 0.5), volumeDb: -6),
      );
      for (final e in pairs.entries) {
        reactions[e.key] = door;
        reactions[e.value] = door;
      }
    }
    for (final e in s.explosives.entries) {
      reactions[id(e.key)] = SignalReactions.trigger((c) {
        world.setBlock(c, BlockRegistry.air);
        explode(Vector3(c.x + 0.5, c.y + 0.5, c.z + 0.5), radius: e.value, damage: e.value * 4.0);
      });
    }
    return SignalRules(
      wireOff: id(s.wire.$1),
      wireOn: id(s.wire.$2),
      sources: {
        for (final l in s.levers.values) id(l),
        for (final b in s.buttons.values) id(b.$1),
        for (final x in s.sources) id(x),
      },
      pressSources: {for (final p in s.plates) id(p)},
      toggles: {
        for (final e in s.levers.entries) ...{id(e.key): id(e.value), id(e.value): id(e.key)},
      },
      buttons: {for (final e in s.buttons.entries) id(e.key): (pressed: id(e.value.$1), seconds: e.value.$2)},
      reactions: reactions,
    );
  }

  /// The circuits; null when the spec declares none.
  SignalNetwork? signals;

  Set<int> _plates = const {};

  /// A game with a scene and worker isolates; await it before the first
  /// [frame]. The static resources of flutter_scene and the terrain shader
  /// must be loaded first (`VoxelGameWidget` does both).
  ///
  /// With [save] the world is the saved one: its seed, its edits, its clock
  /// and its player.
  static Future<VoxelGame> start(VoxelGameSpec spec, {SavedWorld? save, bool authority = true}) async {
    final blocks = spec.buildBlocks();
    final world = GameWorld(
      blocks,
      spec.world,
      save?.seed ?? spec.seed,
      loadRadius: spec.renderDistance,
      liquids: spec.liquids,
    );
    final game = VoxelGame._(spec, blocks, spec.buildItems(blocks), world, headless: false, authority: authority);
    final g = game.graphics, shadows = g.shadows;
    game.scene = MeasuredScene(game.stats)
      ..antiAliasingMode = g.antiAliasing
      ..renderScale = g.renderScale;
    game.sky = DayNightSky(
      game.scene!,
      shadows: shadows.enabled,
      shadowCascades: shadows.cascades,
      shadowResolution: shadows.resolution,
      shadowDistance: shadows.distance,
      sunStepDegrees: shadows.sunStepDegrees,
    );
    game.scene!.add(world.root!);
    game._begin(save);
    game.firstPerson = FirstPersonView(game);
    await world.start();
    return game;
  }

  /// A game with no renderer and no isolates: chunks are generated as they
  /// are needed, on this isolate. [loadRadius] chunks around the player.
  static Future<VoxelGame> startHeadless(
    VoxelGameSpec spec, {
    int loadRadius = 2,
    SavedWorld? save,
    bool authority = true,
  }) async {
    final blocks = spec.buildBlocks();
    final world = GameWorld.headless(
      blocks,
      spec.world,
      save?.seed ?? spec.seed,
      loadRadius: loadRadius,
      liquids: spec.liquids,
    );
    final game = VoxelGame._(spec, blocks, spec.buildItems(blocks), world, headless: true, authority: authority);
    game._begin(save);
    await world.start();
    return game;
  }

  void _begin(SavedWorld? save) {
    if (save != null) world.replaceEdits(save.edits);
    player.attach(this);
    scene?.add(player.node);
    // The spawn: the nearest dry column to the origin along a spiral.
    final g = world.generator;
    var spawn = (x: 0, z: 0);
    for (var r = 0; r < 400; r += 8) {
      final a = r * 0.7;
      final x = (math.cos(a) * r).round(), z = (math.sin(a) * r).round();
      if (g.surfaceHeight(x, z) > spec.world.seaLevel + 1) {
        spawn = (x: x, z: z);
        break;
      }
    }
    _spawnColumn = spawn;
    player.position = Vector3(spawn.x + 0.5, g.surfaceHeight(spawn.x, spawn.z).toDouble(), spawn.z + 0.5);
    if (save != null) WorldSaves.restore(this, save);
  }

  /// Hosts this game on [port] (0 picks a free one): other games join it with
  /// [joinGame]. Returns the session; its host's `port` is the one bound.
  Future<HostSession> host({int port = 7777}) async {
    final s = HostSession(this, await NetHost.bind(port: port));
    session = s;
    return s;
  }

  /// Joins the game hosted at [address]:[port]: its world, its players, its
  /// mobs. [headless] for a test or a bot.
  static Future<VoxelGame> joinGame(
    VoxelGameSpec spec,
    String address, {
    int port = 7777,
    bool headless = false,
  }) async {
    final hello = await joinHost(address, port: port);
    final game = headless
        ? await startHeadless(spec, save: hello.world, authority: false)
        : await start(spec, save: hello.world, authority: false);
    game.player.restore(hello.spawn, hello.spawn);
    game.session = ClientSession(game, hello.connection, hello.peer);
    return game;
  }

  /// The network side of the game, or null for a game of one.
  GameSession? session;

  /// Whether this game decides (a lone game, or the host); a client follows.
  final bool authority;

  int _nextNetId = 1;

  /// What was declared.
  final VoxelGameSpec spec;

  /// The blocks, air first.
  final BlockRegistry<BlockType> blocks;

  /// The items: one per holdable block, plus the spec's.
  final ItemRegistry<ItemType> items;

  /// The world.
  final GameWorld world;

  /// Whether there is no scene and no visuals.
  final bool headless;

  /// The scene; null headless.
  Scene? scene;

  /// The sky, sun and fog; null headless.
  DayNightSky? sky;

  /// The player's controls. A widget feeds it; code can [InputMap.hold].
  final InputMap<VoxelAction> input;

  /// Crafting.
  final RecipeBook recipes;

  /// How long blocks take to break.
  MiningRules get mining => spec.mining;

  /// The game's own random numbers, seeded by the world seed.
  final math.Random random;

  /// The path policy of every walking creature: lava is never entered.
  late final PathCosts pathCosts;

  /// A* searches this step may still run: [Mob.searchesPerStep] at its start.
  /// A mob whose plan is due when none is left plans on a later step.
  int searchesLeft = 0;

  /// The player.
  late final PlayerEntity player;

  /// Natural spawning.
  late final MobSpawner spawner;

  /// The living creatures.
  final List<Mob> mobs = [];

  /// Everything else that moves: items on the ground, projectiles.
  final List<GameEntity> entities = [];

  /// The camera's rig.
  final ViewCamera view = ViewCamera();

  /// The hand and the mining crack; null headless.
  FirstPersonView? firstPerson;

  /// What plays the sounds: silent until the widget opens the audio device.
  SoundPlayer sounds = SilentSounds();

  final Map<int, String> _families = {};

  /// The material family block [id] sounds like (see `SoundSpec`).
  String soundFamily(int id) => _families.putIfAbsent(id, () {
    final t = blocks[id];
    for (final tag in t.tags) {
      if (tag.startsWith('sound:')) return tag.substring(6);
    }
    if (t.isLiquid) return SoundFamily.liquid;
    if (t.tool == 'axe') return SoundFamily.wood;
    if (t.tool == 'shovel') return SoundFamily.earth;
    if (t.shape == BlockShape.cross || t.shape == BlockShape.flower || (!t.solid && t.tool == null)) {
      return SoundFamily.plant;
    }
    if (t.solid && t.alpha < 1.0) return SoundFamily.glass;
    if (!t.opaque && t.solid && t.tool == null) return SoundFamily.plant;
    return SoundFamily.stone;
  });

  /// Plays [name] as heard from [at] by the player: quieter with distance,
  /// nothing past 32 m; at the player when [at] is null.
  void playSound(String name, {Vector3? at, double volumeDb = 0.0, double pitch = 1.0}) {
    if (!spec.sounds.enabled) return;
    var db = volumeDb;
    if (at != null) {
      final d = at.distanceTo(player.eyePosition);
      if (d > 32.0) return;
      if (d > 3.0) db -= 20.0 * math.log(d / 3.0) / math.ln10;
    }
    sounds.play(name, volumeDb: db, pitch: pitch);
  }

  final FixedStepLoop _loop = FixedStepLoop();
  ({int x, int z}) _spawnColumn = (x: 0, z: 0);

  /// Seconds of game time.
  double time = 0.0;

  /// 0 midnight, 0.25 sunrise, 0.5 noon, 0.75 sunset.
  double timeOfDay;

  /// Whether the player reads the controls (false while a menu is open).
  bool gameplay = true;

  /// Play without the mouse captured: a demo, a bot or a scripted run driving
  /// [input] from code. The widget otherwise pauses the controls until a click
  /// captures the pointer.
  bool playWithoutCapture = false;

  /// The screen the player asked for: null for none, `''` for the bag, a
  /// block id for that station's crafting (a crafting table, a furnace). The
  /// widget shows it; set it to null to close.
  final ValueNotifier<String?> openScreen = ValueNotifier(null);

  /// Every station some recipe names.
  late final Set<String> stations = {
    for (final r in spec.recipes)
      if (r.station.isNotEmpty) r.station,
  };

  /// Whether the player stands in a loaded world yet.
  bool get ready => player.placed;

  /// 0 at night, 1 at noon: how much the sky's light counts.
  double get daylight {
    final elevation = math.sin((timeOfDay - 0.25) * math.pi * 2);
    return (elevation * 3.0 + 0.15).clamp(0.0, 1.0);
  }

  /// Advances by [dt] seconds of real time: whole fixed steps, the chunk
  /// streaming, the sky.
  ///
  /// A frame that runs no step does **not** drain the one-shot presses: a tap
  /// or a click set between two frames waits for the step that reads it. The
  /// drain used to live here, and above 60 fps — where a frame that has just
  /// spent the bank runs no step — it threw away roughly half of every
  /// player's presses before anything could see them.
  void frame(double dt) {
    _frameWatch
      ..reset()
      ..start();
    final steps = _loop.advance(dt, step);
    world.update(player.position);
    firstPerson?.update(dt);
    final s = sky;
    if (s != null) {
      final intensity = s.update(timeOfDay, fogDistance: viewDistance);
      world.setSkyIntensity(intensity);
    }
    _frameWatch.stop();
    stats.addFrame(simMs: _frameWatch.elapsedMicroseconds / 1000.0, steps: steps);
  }

  final Stopwatch _frameWatch = Stopwatch();

  /// How the world is drawn: the spec's, or the preset of this platform.
  late final GraphicsSpec graphics =
      spec.graphics ??
      (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android
          ? GraphicsSpec.phone
          : GraphicsSpec.desktop);

  /// Metres to the edge of the loaded chunks: where the fog is full and the
  /// camera's far plane ends, so nothing past it is drawn.
  double get viewDistance => world.loadRadius * 16.0;

  /// Draws the world at [graphics]' scale on a screen of [devicePixelRatio].
  void fitPixelRatio(double devicePixelRatio) => scene?.renderScale = graphics.sceneScale(devicePixelRatio);

  /// What the frames cost: an FPS readout, and every sample while a benchmark
  /// records.
  final FrameStats stats = FrameStats();

  /// One fixed step of [dt]: the player, the creatures, the items, the
  /// liquids, spawning, then the spec's systems and hook.
  void step(double dt) {
    // One arbiter for the two buttons every surface shares: the step that
    // drains the one-shots is the only thing that reads them, so one press
    // cannot close a screen here and open another there.
    if (openScreen.value != null) {
      if (input.justPressed(VoxelAction.inventory) || input.justPressed(VoxelAction.pause)) openScreen.value = null;
    } else if (gameplay && input.justPressed(VoxelAction.inventory)) {
      openScreen.value = '';
    } else if (input.justPressed(VoxelAction.pause) && input.wantCapture) {
      input.release();
    }
    if (!player.placed) {
      player.tryPlace(_spawnColumn.x, _spawnColumn.z);
      input.endTick();
      return;
    }
    searchesLeft = Mob.searchesPerStep;
    time += dt;
    if (spec.sky.cycle) timeOfDay = (timeOfDay + dt / spec.sky.dayLength) % 1.0;
    player.tick(this, dt, gameplay: gameplay);
    for (final m in List.of(mobs)) {
      m.tick(this, dt);
    }
    for (final e in List.of(entities)) {
      e.tick(this, dt);
    }
    session?.tick(this, dt);
    world.tickFlow(dt);
    final net = signals;
    if (net != null) {
      if (_plates.isNotEmpty) {
        final pressed = <IVec3>{};
        for (final b in [if (!player.isDead) player, ...mobs.where((m) => !m.isDead)]) {
          final feet = IVec3.floor(b.position + Vector3(0, 0.05, 0));
          if (_plates.contains(world.getBlock(feet))) pressed.add(feet);
        }
        net.setPressed(pressed);
      }
      net.tick(dt);
    }
    spawner.tick(this, dt);
    for (final s in spec.systems) {
      s.tick(this, dt);
    }
    spec.onTick?.call(this, dt);
    _prune();
    input.endTick();
  }

  void _prune() {
    for (final m in mobs.where((m) => m.removed).toList()) {
      mobs.remove(m);
      scene?.remove(m.node);
    }
    for (final e in entities.where((e) => e.removed).toList()) {
      entities.remove(e);
      scene?.remove(e.node);
    }
  }

  /// The camera for this frame.
  Camera camera() => view.camera(this);

  /// The other players of a networked game.
  Iterable<RemotePlayer> get remotePlayers => session?.players.values ?? const <RemotePlayer>[];

  /// Every living thing a projectile can hit: the players and the creatures.
  Iterable<Target> get allTargets sync* {
    yield player;
    yield* remotePlayers;
    yield* mobs;
  }

  /// What a hunter looks for: the players, and the creatures named in [prey].
  Iterable<Target> targetsOf(List<String> prey) sync* {
    if (!player.isDead) yield player;
    for (final r in remotePlayers) {
      if (!r.isDead) yield r;
    }
    if (prey.isEmpty) return;
    for (final m in mobs) {
      if (prey.contains(m.spec.id)) yield m;
    }
  }

  /// Adds [entity] to the world.
  T add<T extends GameEntity>(T entity) {
    if (entity is Mob) {
      if (entity.netId == 0) entity.netId = _nextNetId++;
      mobs.add(entity);
    } else {
      entities.add(entity);
    }
    entity.attached(this);
    scene?.add(entity.node);
    entity.syncNode();
    return entity;
  }

  /// A creature of the spec's mob [id] at [at].
  Mob spawnMob(String id, Vector3 at) {
    final spec = this.spec.mobs.firstWhere(
      (m) => m.id == id,
      orElse: () => throw ArgumentError.value(id, 'id', 'no such mob'),
    );
    return add(Mob(spec, at));
  }

  /// [count] of [item] dropped at [at].
  ItemPickup dropItem(String item, int count, Vector3 at, {Vector3? throwVelocity}) {
    if (!items.has(item)) throw ArgumentError.value(item, 'item', 'no such item');
    return add(
      ItemPickup(
        item,
        count,
        at,
        throwVelocity: throwVelocity ?? Vector3(random.nextDouble() * 2 - 1, 3.0, random.nextDouble() * 2 - 1),
      ),
    );
  }

  /// Shoots [projectile] from [from] toward [at], by [owner].
  Projectile shoot(ProjectileSpec projectile, {required Vector3 from, required Vector3 at, Target? owner}) {
    playSound('shoot', at: from, volumeDb: -4.0);
    final to = at - from;
    final d = to.length;
    final dir = d > 0 ? to / d : Vector3(0, 0, -1);
    // Aim over the target by the drop over the flight.
    if (projectile.gravity > 0.0) {
      final t = d / projectile.speed;
      dir.y += 0.5 * projectile.gravity * t * t / math.max(d, 0.001);
      dir.normalize();
    }
    return add(Projectile(projectile, from, dir * projectile.speed, owner));
  }

  /// Breaks the block at [cell]: air in its place, and its drop on the ground
  /// when [dropFor] (the tool held, or null for the hand) earns one.
  void breakBlock(IVec3 cell, {ItemType? dropFor, bool drop = true, bool byPlayer = false}) {
    final id = world.getBlock(cell);
    if (id == BlockRegistry.air || blocks[id].isLiquid) return;
    final type = blocks[id];
    if (!world.setBlock(cell, BlockRegistry.air)) return;
    playSound('break_${soundFamily(id)}', at: Vector3(cell.x + 0.5, cell.y + 0.5, cell.z + 0.5), volumeDb: -4.0);
    final item = blocks.dropOf(id);
    if (drop && item.isNotEmpty && items.has(item) && spec.mining.drops(type, dropFor)) {
      dropItem(item, 1, Vector3(cell.x + 0.5, cell.y + 0.3, cell.z + 0.5));
    }
    if (byPlayer) spec.onBlockBroken?.call(this, type.id, cell);
  }

  /// A blast at [centre]: up to [damage] to every target within [radius]
  /// (falling to 0 at the edge) and, with [breaksBlocks], the breakable
  /// blocks inside it gone.
  void explode(Vector3 centre, {double radius = 3.0, double damage = 12.0, bool breaksBlocks = true, Target? source}) {
    playSound('explode', at: centre);
    for (final t in allTargets.toList()) {
      if (t.isDead) continue;
      final d = t.centre().distanceTo(centre);
      if (d > radius * 1.5) continue;
      final k = (1.0 - d / (radius * 1.5)).clamp(0.0, 1.0);
      t.takeDamage(Damage(damage * k, source: 'explosion', from: centre, knockback: 10.0 * k, attacker: source));
    }
    if (!breaksBlocks) return;
    final r = radius.ceil();
    final c = IVec3.floor(centre);
    for (var y = -r; y <= r; y++) {
      for (var z = -r; z <= r; z++) {
        for (var x = -r; x <= r; x++) {
          if (x * x + y * y + z * z > radius * radius) continue;
          final cell = c + IVec3(x, y, z);
          final id = world.getBlock(cell);
          if (id == BlockRegistry.air || blocks[id].hardness < 0 || blocks[id].isLiquid) continue;
          breakBlock(cell, drop: random.nextDouble() < 0.3);
        }
      }
    }
  }

  /// Called by a mob as it dies.
  void mobDied(Mob mob) => spec.onMobKilled?.call(this, mob);

  /// Called by the player as it dies.
  void playerDied() {}

  /// Stops the worker isolates, the input devices and the network.
  void dispose() {
    session?.close();
    world.dispose();
    input.dispose();
  }

  /// The spec of mob [id].
  MobSpec mobSpec(String id) => spec.mobs.firstWhere((m) => m.id == id);
}
