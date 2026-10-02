import 'dart:math' as math;

import 'package:flutter/foundation.dart' show TargetPlatform, ValueListenable, ValueNotifier, defaultTargetPlatform;
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
import '../settings/game_settings.dart';
import '../spec/graphics_spec.dart';
import '../spec/signal_spec.dart';
import '../spec/voxel_game_spec.dart';
import '../ui/damage_numbers.dart';
import '../ui/game_screen.dart';
import '../ui/notices.dart';
import '../spec/portal_spec.dart';
import '../world/block_rules.dart';
import '../world/game_world.dart';
import '../world/portals.dart';
import '../world/travel.dart';
import '../weather/weather.dart';
import '../world/world_save.dart';

/// A running game made from a [VoxelGameSpec]: the world, the player, the
/// creatures and items in it, the clock and the sky. [frame] advances it by
/// real time in fixed steps; everything a game hooks into is reachable from
/// here.
///
/// Headless ([VoxelGame.startHeadless]) it has no scene, no worker isolates and no
/// visuals, and steps as fast as it is asked: tests, bots and servers.
class VoxelGame {
  VoxelGame._(
    this.spec,
    this.blocks,
    this.items,
    this.world,
    GameSettings settings, {
    required this.headless,
    this.authority = true,
  }) : random = math.Random(spec.seed),
       input = InputMap<VoxelAction>(VoxelAction.defaultBindings),
       recipes = RecipeBook(spec.recipes),
       timeOfDay = spec.sky.startTime,
       weather = Weather(spec.sky.weather, spec.dimensionWorlds, seed: spec.seed),
       _settings = ValueNotifier(settings) {
    assert(settings.renderDistance == world.loadRadius, 'the world streams the settings\' render distance');
    spec.checkDimensions(blocks, items);
    spec.checkMobs(items);
    portals = Portals(world, spec.portals);
    _applyLive(settings);
    pathCosts = blocks.pathCosts(avoidLiquids: const {'lava'});
    player = PlayerEntity(
      spec.player,
      Inventory(stackSize: (id) => items[id].stack, maxDurability: (id) => items[id].durability),
      StatusEffects(spec.buildEffects()),
    );
    spawner = MobSpawner(this);
    blockRules = BlockRules(this);
    if (!authority) {
      // A client: the host runs the liquids, the circuits and the spawning.
      world.flow.enabled = false;
      spawner.enabled = false;
      return;
    }
    blockRules.attach();
    final s = spec.signals;
    if (s != null) {
      _signals = _signalRules(s);
      world.addListener((cell, old, id) => signals!.touch(cell, old, id));
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
    if (s.pistons.isNotEmpty) {
      final pairs = {for (final e in s.pistons.entries) id(e.key): id(e.value)};
      final pushes = _pistonFacings(s);
      final piston = SignalReactions.piston(
        pairs,
        facing: (piston) => pushes[piston]!,
        pushable: (b) => blocks[b].hardness >= 0 && !blocks[b].isLiquid && blocks[b].storage == null && !blocks[b].tall,
        givesWay: blocks.isReplaceable,
        onExtend: (c) => playSound(
          'place_${soundFamily(world.getBlock(c))}',
          at: Vector3(c.x + 0.5, c.y + 0.5, c.z + 0.5),
          volumeDb: -8,
          pitch: 0.7,
        ),
      );
      for (final e in pairs.entries) {
        reactions[e.key] = piston;
        reactions[e.value] = piston;
      }
    }
    if (s.poweredRails.isNotEmpty) {
      final pairs = {for (final e in s.poweredRails.entries) id(e.key): id(e.value)};
      final run = SignalReactions.poweredRun(pairs, reach: s.railReach);
      for (final e in pairs.entries) {
        reactions[e.key] = run;
        reactions[e.value] = run;
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

  /// The way each of [s]'s pistons pushes, retracted and extended, by id: the
  /// compass side its retracted block is a variant of.
  Map<int, IVec3> _pistonFacings(SignalSpec s) {
    final sides = <String, IVec3>{};
    for (final b in blocks.types) {
      final f = b.facing;
      if (f == null || f.north == null) continue;
      sides[f.north!] = const IVec3(0, 0, -1);
      sides[f.east!] = const IVec3(1, 0, 0);
      sides[f.south!] = const IVec3(0, 0, 1);
      sides[f.west!] = const IVec3(-1, 0, 0);
    }
    final out = <int, IVec3>{};
    for (final e in s.pistons.entries) {
      final side = sides[e.key];
      if (side == null) throw ArgumentError('piston ${e.key} is no variant of a Facing.compass: it faces nowhere');
      out[blocks.indexOf(e.key)] = side;
      out[blocks.indexOf(e.value)] = side;
    }
    return out;
  }

  /// The circuits of the dimension streaming; null when the spec declares
  /// none, or on a client (the host runs them). Each dimension keeps its own.
  SignalNetwork? get signals {
    final rules = _signals;
    return rules == null ? null : _networks.putIfAbsent(world.dimension, () => SignalNetwork(world, rules));
  }

  SignalRules? _signals;
  final Map<int, SignalNetwork> _networks = {};

  Set<int> _plates = const {};

  /// A game with a scene and worker isolates; await it before the first
  /// [frame]. The static resources of flutter_scene and the terrain shader
  /// must be loaded first (`VoxelGameWidget` does both).
  ///
  /// With [save] the world is the saved one: its seed, its edits, its clock
  /// and its player. With [settings] the player's own ([GameSettings.of] the
  /// spec when null).
  static Future<VoxelGame> start(
    VoxelGameSpec spec, {
    SavedWorld? save,
    GameSettings? settings,
    bool authority = true,
  }) async {
    final blocks = spec.buildBlocks();
    final chosen = settings ?? GameSettings.of(spec);
    final world = GameWorld(
      blocks,
      spec.dimensionWorlds,
      save?.seed ?? spec.seed,
      loadRadius: chosen.renderDistance,
      liquids: spec.liquids,
    );
    final game = VoxelGame._(
      spec,
      blocks,
      spec.buildItems(blocks),
      world,
      chosen,
      headless: false,
      authority: authority,
    );
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
    if (spec.sky.weather != null) game.scene!.add((game.weatherParticles = WeatherParticles()).node);
    game._begin(save);
    game.firstPerson = FirstPersonView(game);
    await world.start();
    return game;
  }

  /// A game with no renderer and no isolates: chunks are generated as they
  /// are needed, on this isolate. [loadRadius] chunks around the player: its
  /// [settings] are the spec's at that render distance.
  static Future<VoxelGame> startHeadless(
    VoxelGameSpec spec, {
    int loadRadius = 2,
    SavedWorld? save,
    bool authority = true,
  }) async {
    final blocks = spec.buildBlocks();
    final world = GameWorld.headless(
      blocks,
      spec.dimensionWorlds,
      save?.seed ?? spec.seed,
      loadRadius: loadRadius,
      liquids: spec.liquids,
    );
    final game = VoxelGame._(
      spec,
      blocks,
      spec.buildItems(blocks),
      world,
      GameSettings.of(spec).copyWith(renderDistance: loadRadius),
      headless: true,
      authority: authority,
    );
    game._begin(save);
    await world.start();
    return game;
  }

  void _begin(SavedWorld? save) {
    if (save != null) world.replaceEdits(save.editsFor(spec.dimensionIds));
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

  /// The id of the dimension the player is in (`VoxelGameSpec.dimensionIds`).
  String get dimension => spec.dimensionIds[world.dimension];

  /// The portals of the spec, in this world.
  late final Portals portals;

  /// Where the player stands between dimensions: in one, in a portal, or
  /// arriving in another.
  Travel get travelState => _travel;
  Travel _travel = const Staying();

  /// Takes the player to [dimension]: to [at] exactly, or to the arrival of
  /// its present column there (`GameWorld.arrivalAt`), with a return portal
  /// when it went [through] a portal and none is near. The creatures and the
  /// items of the dimension left are left behind for good; a store's screen
  /// shuts. The player waits off the ground ([ready] false) until the world
  /// is loaded around it. Throws for the dimension the player is in, one the
  /// spec does not declare, and during another arrival.
  void travel(String dimension, {Vector3? at, PortalSpec? through}) {
    final d = spec.dimensionIds.indexOf(dimension);
    if (d < 0) throw ArgumentError.value(dimension, 'dimension', 'the spec declares no such dimension');
    if (d == world.dimension) throw ArgumentError.value(dimension, 'dimension', 'the player is there');
    if (_travel is Arriving) throw StateError('the player is arriving already');
    for (final m in mobs) {
      m.removed = true;
    }
    for (final e in entities) {
      if (e is! RemotePlayer) e.removed = true;
    }
    _prune();
    if (_screen.value is StorageScreen) closeScreen();
    final from = player.position;
    final x = (at?.x ?? from.x).floor(), z = (at?.z ?? from.z).floor();
    world.switchDimension(d);
    player.hold(at ?? Vector3(x + 0.5, world.generator.surfaceHeight(x, z).toDouble(), z + 0.5));
    _travel = Arriving(dimension, x, z, exactly: at?.clone(), portal: through);
  }

  /// Stands the arriving player on the ground once the chunks around its
  /// column are loaded, building the return portal it may need.
  void _arrive(Arriving a) {
    final here = ChunkStreamer.chunkOfXZ(a.x, a.z);
    for (final o in ChunkStreamer.ring) {
      if (!world.isLoaded(IVec3((here.x + o.x) * ChunkSize.sizeX, 0, (here.z + o.z) * ChunkSize.sizeZ))) return;
    }
    final at = a.exactly;
    if (at != null) {
      player.placeAt(at);
    } else {
      final feet = world.arrivalAt(a.x, a.z);
      player.placeAt(Vector3(feet.x + 0.5, feet.y.toDouble(), feet.z + 0.5));
      final portal = a.portal;
      if (portal != null && portals.nearest(portal, feet, portal.search) == null) {
        portals.build(portal, feet - const IVec3(0, 0, 2), world.generator.spec.stone);
      }
    }
    _travel = const Lingering();
  }

  /// One step of the portal underfoot: standing in one long enough takes
  /// the player to its other end.
  void _portalStep(double dt) {
    final feet = IVec3.floor(player.position + Vector3(0, 0.3, 0));
    final under = player.isDead ? null : portals.at(feet);
    final to = under?.otherEnd(dimension);
    switch (_travel) {
      case Arriving():
        return;
      case Lingering():
        if (under == null) _travel = const Staying();
      case Staying():
        if (under != null && to != null) _travel = Charging(under, 0.0);
      case Charging(:final portal, :final seconds):
        if (under != portal || to == null) {
          _travel = const Staying();
        } else if (seconds + dt < portal.seconds) {
          _travel = Charging(portal, seconds + dt);
        } else {
          travel(to, through: portal);
        }
    }
  }

  /// Hosts this game on [port] (0 picks a free one): other games join it with
  /// [joinGame]. Returns the session; its host's `port` is the one bound.
  Future<HostSession> host({int port = 7777}) async {
    final s = HostSession(this, await NetHost.bind(port: port));
    session = s;
    return s;
  }

  /// Joins the game hosted at [address]:[port]: its world, its players, its
  /// mobs, seen with this player's [settings]. [headless] for a test or a bot.
  static Future<VoxelGame> joinGame(
    VoxelGameSpec spec,
    String address, {
    int port = 7777,
    GameSettings? settings,
    bool headless = false,
  }) async {
    final hello = await joinHost(address, port: port);
    final game = headless
        ? await startHeadless(spec, save: hello.world, authority: false)
        : await start(spec, save: hello.world, settings: settings, authority: false);
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

  /// What item [id] looks like: the one model every item of its look shares,
  /// drawn in the hand, held by a body, lying on the ground and in a slot.
  ItemModel itemModel(String id) => _itemModels[id] ??= ItemModel.of(items[id], blocks, items);
  final Map<String, ItemModel> _itemModels = {};

  /// The world.
  final GameWorld world;

  /// Whether there is no scene and no visuals.
  final bool headless;

  /// The scene; null headless.
  Scene? scene;

  /// The sky, sun and fog; null headless.
  DayNightSky? sky;

  /// The rain, storms and snow (`SkySpec.weather`): always clear when the
  /// spec declares none.
  final Weather weather;

  /// The rain and snow falling around the player; null headless or with no
  /// weather declared.
  WeatherParticles? weatherParticles;

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

  /// What blocks do on their own: fall, drop off what held them, grow. It
  /// listens to the world, and grows the crops, only where this game is the
  /// [authority].
  late final BlockRules blockRules;

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
  /// nothing past 32 m; at the player when [at] is null. All of it under the
  /// player's [GameSettings.volume], and nothing at 0.
  void playSound(String name, {Vector3? at, double volumeDb = 0.0, double pitch = 1.0}) {
    final volume = settings.value.volume;
    if (!spec.sounds.enabled || volume == 0.0) return;
    var db = volumeDb + 20.0 * math.log(volume) / math.ln10;
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

  /// The screen open over the world, or null while the player plays: one
  /// [GameScreen] at a time, changed only by [openScreen], [closeScreen],
  /// [respawn] and the player's death. The widget shows it; the world keeps
  /// stepping behind it.
  ValueListenable<GameScreen?> get screen => _screen;
  final ValueNotifier<GameScreen?> _screen = ValueNotifier(null);

  /// Opens [next] over the world, in place of the screen open. Throws for a
  /// [DeathScreen] (the player's death opens it), over one (only [respawn]
  /// leaves it), for a [BagScreen] at a block no recipe names, a
  /// [StorageScreen] on a client or at a block that stores nothing, and a
  /// [DeclaredScreen] the spec does not declare.
  void openScreen(GameScreen next) {
    if (_screen.value is DeathScreen) throw StateError('the dead leave the death screen only by a respawn');
    switch (next) {
      case DeathScreen():
        throw ArgumentError.value(next, 'next', 'only the player\'s death opens the death screen');
      case BagScreen(:final station) when station.isNotEmpty && !stations.contains(station):
        throw ArgumentError.value(station, 'station', 'no recipe is crafted there');
      case StorageScreen() when !authority:
        throw StateError('a client opens no store: the host keeps them');
      case StorageScreen(:final cell) when blocks[world.getBlock(cell)].storage == null:
        throw ArgumentError.value(cell, 'cell', 'no store there: ${world.blockNameAt(cell)}');
      case DeclaredScreen(:final id) when !spec.screens.containsKey(id):
        throw ArgumentError.value(id, 'id', 'the spec declares no such screen');
      case BagScreen() || StorageScreen() || PauseScreen() || SettingsScreen() || DeclaredScreen():
        _screen.value = next;
    }
  }

  /// Closes the screen open. Throws when none is, and over the [DeathScreen],
  /// which only [respawn] leaves.
  void closeScreen() {
    final open = _screen.value;
    if (open == null) throw StateError('no screen is open');
    if (open is DeathScreen) throw StateError('the dead leave the death screen only by a respawn');
    _screen.value = null;
  }

  /// Whether the dead player may stand up again: dead for at least
  /// `PlayerSpec.respawnDelay`.
  bool get canRespawn => player.isDead && player.deadSeconds >= spec.player.respawnDelay;

  /// Stands the dead player up at its spawn, and closes the [DeathScreen].
  /// Throws before [canRespawn].
  void respawn() {
    if (!canRespawn) throw StateError('the player cannot stand up yet');
    player.respawn();
    _screen.value = null;
    // The spawn is in the main world.
    if (world.dimension != 0) travel(VoxelGameSpec.mainDimension, at: player.spawnPoint);
  }

  /// The store open beside the bag ([StorageScreen]), or null.
  Inventory? get openStorage => switch (_screen.value) {
    StorageScreen(:final cell) => blockRules.storeAt(cell),
    _ => null,
  };

  /// What the HUD tells the player for a few seconds: [notify]'s feed and
  /// the pickups. [frame] ages it.
  final Notices notices = Notices();

  /// Tells the player [text] for a few seconds, in the HUD's feed. Throws
  /// for empty text.
  void notify(String text) => notices.add(text);

  /// The damage dealt to creatures, a number over each for a second: a
  /// creature's hit adds one where it is the [authority], and a replica's
  /// lost health where it is not. [frame] ages it.
  final DamageNumbers damageNumbers = DamageNumbers();

  /// What the player has set: the render distance, the turn, the field of
  /// view, the volumes, the bob, the frame rate, the weather. [applySettings]
  /// changes it.
  ValueListenable<GameSettings> get settings => _settings;
  final ValueNotifier<GameSettings> _settings;

  /// Puts [next] in force at once: the world streams to its render distance
  /// (cut back now when it is nearer), the view turns at its speed and bobs
  /// or not, the next frame's camera takes its field of view, the next sound
  /// its volume, the HUD shows the frame rate or not, the sky clears or is
  /// let turn. The music follows it
  /// where it plays (`VoxelGameWidget`), listening to [settings].
  void applySettings(GameSettings next) {
    if (next.renderDistance != world.loadRadius) world.loadRadius = next.renderDistance;
    _applyLive(next);
    _settings.value = next;
  }

  void _applyLive(GameSettings s) {
    input.lookScale = s.lookSpeed;
    view.bob = s.viewBob;
    weather.enabled = s.weather;
  }

  /// The frames drawn so far: moves once at the end of every [frame]. A HUD
  /// listens to it to check what it shows (`HudSelector`).
  ValueListenable<int> get frames => _frames;
  final ValueNotifier<int> _frames = ValueNotifier(0);

  /// Every station some recipe names.
  late final Set<String> stations = {
    for (final r in spec.recipes)
      if (r.station.isNotEmpty) r.station,
  };

  /// Whether the player stands in a loaded world yet.
  bool get ready => player.placed;

  /// Whether the player stands in the world and every chunk of the window
  /// around it is generated, meshed and built ([GameWorld.isIdle]): what
  /// `VoxelGameWidget` waits for before it shows the game. An edit or a step
  /// of the window makes it false again until the world catches up.
  bool get filled => ready && world.isIdle;

  /// 0 at night, 1 at noon: how much the sky's light counts.
  double get daylight {
    final elevation = math.sin((timeOfDay - 0.25) * math.pi * 2);
    return (elevation * 3.0 + 0.15).clamp(0.0, 1.0);
  }

  /// Advances by [dt] seconds of real time: the look, whole fixed steps, the
  /// chunk streaming, the sky and its weather; then draws every body between its last two
  /// steps, [alpha] of the way.
  ///
  /// The look is drained here, once a frame and before the steps, not by a
  /// step: the view turns at the display's rate and the steps aim with the
  /// newest yaw. It is a motion the pointer and pad only add to, with this one
  /// reader; the buttons are the step's alone (see [step]).
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
    if (gameplay) player.look(input.takeLook(dt));
    final steps = _loop.advance(dt, step);
    world.update(player.position);
    _draw(_loop.alpha);
    _camera = view.camera(this);
    firstPerson?.update(dt);
    final s = sky;
    if (s != null) {
      final w = weather;
      world.setSkyIntensity(s.update(timeOfDay, fogDistance: viewDistance, overcast: w.overcast, flash: w.flash));
      weatherParticles?.update(player.eyePosition, rainShare: w.rainShare, snowShare: w.snowShare);
    }
    notices.advance(dt);
    damageNumbers.advance(dt);
    _frameWatch.stop();
    stats.addFrame(seconds: dt, simMs: _frameWatch.elapsedMicroseconds / 1000.0, steps: steps);
    _frames.value++;
  }

  final Stopwatch _frameWatch = Stopwatch();

  /// How far this frame is from the last step toward the next, 0..1: the
  /// bodies are drawn this far between their last two steps' poses.
  double get alpha => _loop.alpha;

  /// The game [time] a frame shows: a step behind the last one, [alpha] of the
  /// way to it. Between two frames it moves by the frame's `dt`, so what
  /// animates by it (the view bob, the camera's pull-out) moves every frame.
  double get drawnTime => time - _loop.step * (1.0 - _loop.alpha);

  void _draw(double alpha) {
    player.drawNode(alpha);
    for (final m in mobs) {
      m.drawNode(alpha);
    }
    for (final e in entities) {
      e.drawNode(alpha);
    }
    player.drawOutline();
  }

  void _beginStep() {
    player.beginStep();
    for (final m in mobs) {
      m.beginStep();
    }
    for (final e in entities) {
      e.beginStep();
    }
  }

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

  /// One fixed step of [dt]: the clock and the weather, the player, the
  /// creatures, the items, the liquids, spawning, then the spec's systems and
  /// hook. Every body's pose
  /// before it is kept first, for the frames to draw from.
  void step(double dt) {
    _beginStep();
    // One arbiter for the buttons every screen shares: the step that drains
    // the one-shots is the only thing that reads them, so one press cannot
    // close a screen here and open another there.
    switch (_screen.value) {
      case null:
        if (gameplay && input.justPressed(VoxelAction.inventory)) {
          openScreen(const BagScreen());
        } else if (gameplay && input.justPressed(VoxelAction.pause)) {
          openScreen(const PauseScreen());
        }
      case BagScreen() || StorageScreen():
        if (input.justPressed(VoxelAction.inventory) || input.justPressed(VoxelAction.pause)) closeScreen();
      case PauseScreen() || DeclaredScreen():
        if (input.justPressed(VoxelAction.pause)) closeScreen();
      case SettingsScreen():
        if (input.justPressed(VoxelAction.pause)) openScreen(const PauseScreen());
      case DeathScreen():
        // Jump stands up: the respawn of a keyboard and a pad.
        if (canRespawn && input.justPressed(VoxelAction.jump)) respawn();
    }
    final trip = _travel;
    if (trip is Arriving) {
      // An arrival keeps the world going; only the player waits.
      _arrive(trip);
    } else if (!player.placed) {
      // The first stand: the world waits for the player.
      player.tryPlace(_spawnColumn.x, _spawnColumn.z);
      input.endTick();
      return;
    }
    searchesLeft = Mob.searchesPerStep;
    time += dt;
    if (spec.sky.cycle) timeOfDay = (timeOfDay + dt / spec.sky.dayLength) % 1.0;
    weather.tick(this, dt);
    if (player.placed) {
      player.tick(this, dt, gameplay: gameplay);
      _portalStep(dt);
    }
    for (final m in List.of(mobs)) {
      m.tick(this, dt);
    }
    for (final e in List.of(entities)) {
      e.tick(this, dt);
    }
    world.tickFlow(dt);
    if (authority) blockRules.tick(dt);
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
    // Last, so every edit of this step, whoever made it, leaves in this step.
    session?.tick(this, dt);
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

  /// The camera this frame draws with: built once a [frame], after the
  /// bodies are placed, so the scene and whatever a HUD projects from the
  /// world (`Camera.worldToScreen`) see the same view. Before the first frame,
  /// the view as it stands.
  Camera camera() => _camera ??= view.camera(this);
  Camera? _camera;

  /// The liquid block the [camera] is in, or null: what the default HUD
  /// washes the screen with (`LiquidSpec.tint`).
  BlockType? get eyeLiquid {
    final t = blocks[world.getBlock(IVec3.floor(camera().position))];
    return t.isLiquid ? t : null;
  }

  /// How liquid [kind] flows and looks: the spec's, or its default.
  LiquidSpec liquid(String kind) => spec.liquids[kind] ?? LiquidSpec.defaultFor(kind);

  /// The nearest living boss (`MobSpec.boss`) to the player, or null.
  Mob? get boss {
    Mob? best;
    var bestD = double.infinity;
    for (final m in mobs) {
      if (!m.spec.boss || m.isDead) continue;
      final d = m.position.distanceToSquared(player.position);
      if (d < bestD) {
        best = m;
        bestD = d;
      }
    }
    return best;
  }

  /// The other players of a networked game.
  Iterable<RemotePlayer> get remotePlayers => session?.players.values ?? const <RemotePlayer>[];

  /// The other players in the player's dimension.
  Iterable<RemotePlayer> get playersHere => remotePlayers.where((r) => r.dimension == world.dimension);

  /// Every living thing a projectile can hit: the players and the creatures
  /// of the dimension.
  Iterable<Target> get allTargets sync* {
    yield player;
    yield* playersHere;
    yield* mobs;
  }

  /// What a hunter looks for: the players, and the creatures named in [prey].
  Iterable<Target> targetsOf(List<String> prey) sync* {
    if (!player.isDead) yield player;
    for (final r in playersHere) {
      if (!r.isDead) yield r;
    }
    if (prey.isEmpty) return;
    for (final m in mobs) {
      if (prey.contains(m.spec.id)) yield m;
    }
  }

  /// Whether a body (the player's, a living creature's) stands in [cell]:
  /// where no solid block may go.
  bool bodyIn(IVec3 cell) {
    bool overlaps(VoxelBody b) =>
        b.position.x + b.halfWidth > cell.x &&
        b.position.x - b.halfWidth < cell.x + 1 &&
        b.position.z + b.halfWidth > cell.z &&
        b.position.z - b.halfWidth < cell.z + 1 &&
        b.position.y + b.height > cell.y &&
        b.position.y < cell.y + 1;
    return overlaps(player) || mobs.any((m) => !m.isDead && overlaps(m));
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

  /// [count] of a new [item] dropped at [at].
  ItemPickup dropItem(String item, int count, Vector3 at, {Vector3? throwVelocity}) =>
      dropStack(ItemStack(item, count), at, throwVelocity: throwVelocity);

  /// [stack], as it left a slot (wear and bonus kept), dropped at [at]:
  /// thrown with [throwVelocity], or tossed up at random.
  ItemPickup dropStack(ItemStack stack, Vector3 at, {Vector3? throwVelocity}) {
    if (!items.has(stack.id)) throw ArgumentError.value(stack.id, 'stack', 'no such item');
    if (stack.count <= 0) throw ArgumentError.value(stack.count, 'stack', 'an empty stack');
    return add(
      ItemPickup(
        stack.copy(),
        at,
        throwVelocity: throwVelocity ?? Vector3(random.nextDouble() * 2 - 1, 3.0, random.nextDouble() * 2 - 1),
      ),
    );
  }

  /// Shoots [projectile] from [from] toward [at], by [owner], its damage
  /// multiplied by [power].
  Projectile shoot(
    ProjectileSpec projectile, {
    required Vector3 from,
    required Vector3 at,
    Target? owner,
    double power = 1.0,
  }) {
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
    return add(Projectile(projectile, from, dir * projectile.speed, owner, power: power));
  }

  /// Breaks the block at [cell]: air in its place, and its drop on the ground
  /// when [dropFor] (the tool held, or null for the hand) earns one: its
  /// `loot` rolled, or else its `drop`.
  void breakBlock(IVec3 cell, {ItemType? dropFor, bool drop = true, bool byPlayer = false}) {
    final id = world.getBlock(cell);
    if (id == BlockRegistry.air || blocks[id].isLiquid) return;
    final type = blocks[id];
    if (!world.setBlock(cell, BlockRegistry.air)) return;
    final centre = Vector3(cell.x + 0.5, cell.y + 0.3, cell.z + 0.5);
    playSound('break_${soundFamily(id)}', at: centre, volumeDb: -4.0);
    if (drop && spec.mining.drops(type, dropFor)) {
      final loot = type.loot;
      if (loot != null) {
        for (final s in loot.roll(random)) {
          dropItem(s.id, s.count, centre);
        }
      } else {
        final item = blocks.dropOf(id);
        if (item.isNotEmpty && items.has(item)) dropItem(item, 1, centre);
      }
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

  /// Called by the player as it dies: the [DeathScreen] replaces whatever
  /// was open.
  void playerDied() => _screen.value = const DeathScreen();

  /// Stops the worker isolates, the input devices and the network.
  void dispose() {
    session?.close();
    world.dispose();
    input.dispose();
    _frames.dispose();
    _screen.dispose();
    _settings.dispose();
  }

  /// The spec of mob [id].
  MobSpec mobSpec(String id) => spec.mobs.firstWhere((m) => m.id == id);
}
