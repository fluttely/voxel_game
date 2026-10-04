import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';
import 'package:voxel_game/voxel_game.dart';

import '../classes/class_system.dart';
import '../classes/class_table.dart';
import '../spec/game_title.dart';
import '../villages/villages.dart';
import 'exhibit_builder.dart';
import 'playground_zone.dart';

/// The playground: a world made to show every feature at once, the world
/// option `playground` ([playgroundOption]). Its generation presses a flat
/// [plaza] about the spawn ([worldFor]); this system lays nine exhibits on it
/// in a 3 x 3 grid ([zones]), each built the first time its chunks are
/// loaded ([ExhibitBuilder]) and remembered in the save, so a reload keeps
/// the player's changes. Its wild creatures (the pens, the arena) are not
/// kept by the save: they come back on every boot as the player comes within
/// [wildWithin], and when the player walks back into an exhibit the kit's
/// spawner emptied while they were away.
///
/// A fresh playground starts the player at [spawn] facing the tower with the
/// showcase kit ([kitFor]), at level 10 with ten talent points, in the
/// morning. Walking into an exhibit shows its card for [cardSeconds]
/// (`ZoneCard`). The weather ([cycleWeather], F7), the time of day
/// ([cycleTime], F8) and a rebuild of the exhibit the player stands in
/// ([rebuildHere], F9) are the game's actions and the Playground screen's
/// buttons, in the game menu of a playground only. The hub's waypoint lists
/// the world tour: the nearest structure of each kind and the nearest spot of
/// each biome. In a playground nothing runs out (`ClassSystem.endless`) and
/// there is no tutorial.
///
/// The exhibits are built and their creatures placed on the authority only;
/// a client reads its cards. Saved with the world (under `playground`): the
/// exhibits built.
class Playground extends SavedSystem {
  /// The key of the exhibits built in the save.
  static const String key = 'playground';

  /// The screen of its buttons, in the game menu of a playground.
  static const String screen = 'playground';

  /// The actions that cycle the weather and the time of day and rebuild the
  /// exhibit the player stands in.
  static const String weatherAction = 'playground_weather',
      timeAction = 'playground_time',
      rebuildAction = 'playground_rebuild';

  /// The feet level on the plaza: its grass is a block under.
  static const int floor = 64;

  /// The ground pressed flat: 144 x 144 about the hub, in the plains.
  static const Plaza plaza = Plaza(minX: -64, minZ: -64, maxX: 80, maxZ: 80, height: floor, biome: 'plains');

  /// Seconds an exhibit's card stays up after the player walks in.
  static const double cardSeconds = 12.0;

  /// Seconds between two looks at the exhibits loaded.
  static const double lookEvery = 0.25;

  /// The key of an exhibit's creature's tag in its `Mob.data`: the exhibit's
  /// id, or [broodTag] for what the arena's spawner brought.
  static const String exhibitKey = 'exhibit';

  /// The tag of the arena spawner's creatures.
  static const String broodTag = 'arena_spawner';

  /// The exhibits whose creatures the save does not keep.
  static const Set<String> wild = {'farm', 'arena'};

  /// Metres from a wild exhibit's middle within which the player brings its
  /// creatures: well inside the kit spawner's despawn distance, which sends
  /// away at once a zoo placed farther off.
  static const double wildWithin = 64.0;

  /// Where a fresh playground's player starts: south of the tower.
  static Vector3 get spawn => Vector3(PlaygroundZone.originX + 0.5, floor + 0.1, PlaygroundZone.originZ + 12.5);

  /// The nine exhibits, the hub in the middle.
  static const List<PlaygroundZone> zones = [
    PlaygroundZone(
      'hub',
      0,
      0,
      'Playground Hub',
      'Climb the tower and glide off with G. The chests hold every item. Use the waypoint for the world tour.\n'
          'F5 fly · F7 weather · F8 time of day · F9 rebuild the exhibit you stand in (or Playground in the menu)',
    ),
    PlaygroundZone(
      'blocks',
      0,
      -1,
      'Block Gallery',
      'Every block in the game, one on each pedestal. Aim at a block to read its name.',
    ),
    PlaygroundZone(
      'building',
      1,
      -1,
      'Shapes & Building',
      'Slabs, stairs, fences, doors, ladders and glass. Walk into a one-block step to hop up. '
          'The tall wall is for climbing.',
    ),
    PlaygroundZone(
      'redstone',
      1,
      0,
      'Redstone',
      'Flip the levers, press the buttons, stand on the plate. Wires carry power 15 blocks to lamps, '
          'iron doors, pistons and TNT.',
    ),
    PlaygroundZone(
      'rails',
      1,
      1,
      'Rails & Minecarts',
      'A loop with a hill and a powered stretch. Use a cart to ride it, and walk to push it.',
    ),
    PlaygroundZone(
      'water',
      0,
      1,
      'Water, Lava & Portal',
      'Dive into the pool, row the boat, fish from the dock. Break the cobblestone to pour water on lava. '
          'Stand in the portal to reach the Underworld.',
    ),
    PlaygroundZone(
      'farm',
      -1,
      1,
      'Farm & Animals',
      'Wheat at every stage, pens of animals, a tame horse (use it to ride), a wolf and a parrot, '
          'and villagers who trade (use them).',
    ),
    PlaygroundZone(
      'arena',
      -1,
      0,
      'Monster Arena',
      'Every monster waits behind the iron door (press a button). Step on a plate to call a boss inside. '
          'The gold button fills the arena again.',
    ),
    PlaygroundZone(
      'caves',
      -1,
      -1,
      'Light & Mining',
      'Every light in the dark hall, a wall of ores, falling sand and gravel, and a ladder down to the diamonds.',
    ),
  ];

  /// The exhibit [id].
  static PlaygroundZone zone(String id) => zones.firstWhere((z) => z.id == id);

  /// The exhibit the column under [p] is in, or null for none.
  static PlaygroundZone? zoneAt(Vector3 p) {
    for (final z in zones) {
      if (z.contains(p.x, p.z)) return z;
    }
    return null;
  }

  /// The main dimension a world with [options] generates: [world] with the
  /// [plaza] in a playground (`VoxelGameSpec.worldFor`).
  static WorldGenSpec worldFor(WorldGenSpec world, Map<String, String> options) =>
      options[playgroundOption.id] == 'playground' ? world.withPlaza(plaza) : world;

  /// Whether [game] is a playground: its world has the [plaza], the only one
  /// this game presses ([worldFor]), on a client as on its host.
  static bool isOn(VoxelGame game) => game.spec.world.plaza != null;

  /// The playground of [game].
  static Playground of(VoxelGame game) => game.system<Playground>();

  /// The showcase kit of a player of [options]: the hotbar, the class's
  /// weapon first, then the bag.
  static List<String> kitFor(Map<String, String> options) => [
    classOf(options).weapon,
    'diamond_pickaxe',
    'torch',
    'glider',
    'fishing_rod',
    'flint_and_steel',
    'water_bucket',
    'rail',
    'minecart',
    'diamond_axe',
    'diamond_shovel',
    'shears',
    'wooden_hoe',
    'bucket',
    'lava_bucket',
    'milk_bucket',
    'boat',
    'powered_rail',
    'bow',
    'arrow',
    'crystal_staff',
    'iron_dagger',
    'ancient_blade',
    'diamond_armor',
    'wheat_seeds',
    'wheat',
    'bone',
    'cooked_beef',
    'health_potion',
    'speed_potion',
    'strength_potion',
    'tnt',
    'lever',
    'wire',
    'waypoint',
  ];

  /// The times of day [cycleTime] steps through, and what it calls them.
  static const List<(double, String)> times = [(0.5, 'Noon'), (0.74, 'Sunset'), (0.0, 'Midnight'), (0.27, 'Sunrise')];

  /// The sky [cycleWeather] steps through (snow is a cold biome's rain).
  static const List<WeatherKind> skies = [WeatherKind.clear, WeatherKind.rain, WeatherKind.storm];

  /// The exhibits whose blocks are in the world.
  final Set<String> built = {};

  /// The world tour's stops, in the order they were found.
  final List<String> tour = [];

  /// Blocks the exhibits wrote.
  int get edits => _builder?.edits ?? 0;

  /// The exhibit the player stands in, or null for none.
  PlaygroundZone? get current => _current;

  /// Whether the [current] exhibit's card is up.
  bool get cardVisible => _current != null && _zoneTime <= cardSeconds;

  ExhibitBuilder? _builder;
  final Set<String> _populated = {};
  bool _restored = false, _begun = false;
  PlaygroundZone? _current;
  double _zoneTime = 0.0, _lookIn = 0.0, _spawnerIn = 0.0;
  IVec3? _onPlate;
  bool _refillWasOn = false;
  int _timeIndex = 0;
  final Map<String, Mob> _summoned = {};

  ExhibitBuilder _build(VoxelGame game) => _builder ??= ExhibitBuilder(game);

  @override
  void tick(VoxelGame game, double dt) {
    if (!isOn(game)) return;
    final main = game.dimension == VoxelGameSpec.mainDimension;
    if (game.authority) {
      if (!_begun) _begin(game);
      if (main) _look(game, dt);
      if (main && built.contains('arena')) _arena(game, dt);
    }
    _track(game, dt, main);
    if (!game.gameplay || game.screen.value != null) return;
    if (game.actions.justPressed(weatherAction)) cycleWeather(game);
    if (game.actions.justPressed(timeAction)) cycleTime(game);
    if (game.actions.justPressed(rebuildAction)) rebuildHere(game);
  }

  // A fresh playground's start, once the spawn is loaded; a saved one's is
  // its own.
  void _begin(VoxelGame game) {
    final at = spawn;
    if (!game.ready || !game.world.isLoaded(IVec3.floor(at))) return;
    _begun = true;
    if (_restored) return;
    final p = game.player
      ..placeAt(at)
      ..spawnPoint = at.clone()
      ..yaw = 0.0
      ..pitch = -0.1;
    final bag = p.inventory;
    for (var i = 0; i < bag.capacity; i++) {
      bag.setSlot(i, null);
    }
    for (final id in kitFor(game.options)) {
      bag.add(id, game.items[id].stack);
    }
    ClassSystem.of(game).startAt(game, level: 10, points: 10);
    game.timeOfDay = 0.3;
  }

  // The wild creatures of every exhibit built and loaded that wants them, and
  // one exhibit built a look: a first boot with every chunk loaded spreads its
  // nine builds over two seconds instead of one long frame.
  void _look(VoxelGame game, double dt) {
    _lookIn -= dt;
    if (_lookIn > 0.0) return;
    _lookIn = lookEvery;
    final loaded = [
      for (final z in zones)
        if (_loaded(game, z)) z,
    ];
    for (final z in loaded) {
      if (built.contains(z.id) && wild.contains(z.id) && !_populated.contains(z.id) && _near(game, z)) {
        _populate(game, z, fresh: false);
      }
    }
    for (final z in loaded) {
      if (built.contains(z.id)) continue;
      _build(game).build(z);
      built.add(z.id);
      if (z.id == 'hub') tour.addAll(_build(game).tour());
      _populate(game, z, fresh: true);
      return;
    }
  }

  static bool _loaded(VoxelGame game, PlaygroundZone z) {
    const step = 16;
    for (var x = z.cx - PlaygroundZone.half; x <= z.cx + PlaygroundZone.half; x += step) {
      for (var zz = z.cz - PlaygroundZone.half; zz <= z.cz + PlaygroundZone.half; zz += step) {
        if (!game.world.isLoaded(IVec3(x, floor, zz))) return false;
      }
    }
    return true;
  }

  void _track(VoxelGame game, double dt, bool main) {
    final z = main ? zoneAt(game.player.position) : null;
    if (identical(z, _current)) {
      _zoneTime += dt;
      return;
    }
    _current = z;
    _zoneTime = 0.0;
    // An exhibit whose creatures were all sent away fills again as the player walks back in.
    if (z != null && wild.contains(z.id) && !_anyOf(game, z.id)) _populated.remove(z.id);
  }

  static bool _anyOf(VoxelGame game, String tag) =>
      game.mobs.any((m) => !m.isDead && !m.removed && m.data[exhibitKey] == tag);

  // --- the showcase keys ---------------------------------------------------------------

  /// The next sky of [skies], at once; on a client the host's sky stands.
  void cycleWeather(VoxelGame game) {
    if (!game.authority) return game.notify('Only the host changes the weather');
    if (!game.weather.enabled) return game.notify('The weather is off in the settings');
    final next = skies[(skies.indexOf(game.weather.spell) + 1) % skies.length];
    game.weather.set(next, now: true);
    game.notify('Weather: ${_named(next.name)}');
  }

  /// The next time of day of [times]; on a client the host's clock stands.
  void cycleTime(VoxelGame game) {
    if (!game.authority) return game.notify('Only the host changes the time');
    final (at, name) = times[_timeIndex];
    _timeIndex = (_timeIndex + 1) % times.length;
    game.timeOfDay = at;
    game.notify('Time: $name');
  }

  /// The exhibit the player stands in, built again from scratch: its
  /// creatures, vehicles and drops replaced, the player stepped to its south
  /// edge first.
  void rebuildHere(VoxelGame game) {
    if (!game.authority) return game.notify('Only the host rebuilds an exhibit');
    final p = game.player;
    final z = game.dimension == VoxelGameSpec.mainDimension ? zoneAt(p.position) : null;
    if (z == null) return game.notify('Stand inside an exhibit to rebuild it');
    if (p.riding != null) p.dismount();
    bool inside(Vector3 at) => z.contains(at.x, at.z);
    for (final m in game.mobs) {
      final tag = m.data[exhibitKey];
      if (tag == z.id || ((tag != null || m.kept) && inside(m.position))) m.removed = true;
    }
    for (final e in game.entities) {
      if ((e is ItemPickup || e is Vehicle) && inside(e.position)) e.removed = true;
    }
    if (z.id == 'arena') _summoned.clear();
    p.placeAt(Vector3(z.cx + 0.5, floor + 0.1, z.cz + PlaygroundZone.half - 1.5));
    final builder = _build(game)
      ..clear(z)
      ..build(z);
    if (z.id == 'hub') tour.addAll(builder.tour().where((t) => !tour.contains(t)));
    _populate(game, z, fresh: true);
    game.playSound('quest', volumeDb: -6.0, pitch: 1.2);
    game.notify('${z.title} rebuilt');
  }

  // --- creatures -----------------------------------------------------------------------

  static bool _near(VoxelGame game, PlaygroundZone z) {
    final here = game.player.position;
    return Vector3(z.cx + 0.5, here.y, z.cz + 0.5).distanceTo(here) < wildWithin;
  }

  /// The creatures of [z]; [fresh] (a build) also places what the save keeps
  /// afterwards: villagers, companions and vehicles. The wild ones wait for
  /// the player within [wildWithin].
  void _populate(VoxelGame game, PlaygroundZone z, {required bool fresh}) {
    final near = _near(game, z);
    if (near) _populated.add(z.id);
    final cx = z.cx, cz = z.cz;
    switch (z.id) {
      case 'farm':
        for (var p = 0; near && p < ExhibitBuilder.pens.length; p++) {
          final px = cx - 18 + p * 10 + 4, pz = cz - 2;
          final pen = ExhibitBuilder.pens[p];
          for (var i = 0; i < pen.length; i++) {
            _creature(game, pen[i], _at(px - 2 + i * 2 % 5, pz - 1 + i % 3), 'farm', home: _at(px, pz));
          }
        }
        if (!fresh) return;
        for (final sx in [cx + 8, cx + 14]) {
          Villages.settle(game, _at(sx, cz - 13), _at(sx, cz - 13));
        }
        for (final (species, x, y) in [
          ('horse', cx + 4, floor),
          ('wolf', cx + 8, floor),
          ('parrot', cx + 12, floor + 1),
        ]) {
          game.spawnMob(species, Vector3(x + 0.5, y + 0.1, cz + 10.5)).tame(game.player);
        }
      case 'arena':
        if (near) _refillArena(game);
      case 'rails':
        if (fresh) {
          final start = ExhibitBuilder.railStart(z);
          game.placeVehicle(
            'minecart',
            Vector3(start.x + 3.5, start.y.toDouble(), start.z + 0.5),
            facing: -math.pi / 2,
          );
        }
      case 'water':
        if (fresh) game.placeVehicle('boat', Vector3(cx - 8.0, floor - 0.1, cz + 0.5));
    }
  }

  static Vector3 _at(int x, int z) => Vector3(x + 0.5, floor + 0.1, z + 0.5);

  /// A creature of [species] at [at] tagged [tag], grown to the player's
  /// level when its species grows.
  static Mob _creature(VoxelGame game, String species, Vector3 at, String tag, {required Vector3 home}) {
    final m = game.spawnMob(species, at)..home = home;
    if (m.spec.levels != null) m.growTo(game.player.level + 1);
    m.data[exhibitKey] = tag;
    return m;
  }

  // Every arena creature that is not alive gets a new body.
  void _refillArena(VoxelGame game) {
    final z = zone('arena');
    final alive = [
      for (final m in game.mobs)
        if (m.data[exhibitKey] == 'arena' && !m.removed && !m.isDead) m.spec.id,
    ];
    for (var i = 0; i < ExhibitBuilder.arenaMobs.length; i++) {
      final id = ExhibitBuilder.arenaMobs[i];
      if (alive.remove(id)) continue;
      final at = _at(z.cx - 10 + (i % 5) * 5, z.cz - 10 + (i ~/ 5) * 6);
      _creature(game, id, at, 'arena', home: _at(z.cx, z.cz));
    }
  }

  void _arena(VoxelGame game, double dt) {
    final z = zone('arena');
    final world = game.world;
    // The gold button, on the rise of its press.
    final refill = ExhibitBuilder.arenaRefillCell(z);
    final refillOn = world.isLoaded(refill) && world.blockNameAt(refill) == 'button_on';
    if (refillOn && !_refillWasOn) {
      _refillArena(game);
      game.notify('The arena is full again');
    }
    _refillWasOn = refillOn;
    // A boss plate calls its boss on the step onto it.
    final feet = IVec3.floor(game.player.position);
    IVec3? on;
    for (var i = 0; i < ExhibitBuilder.bossPlates.length; i++) {
      final plate = ExhibitBuilder.bossPlateCell(z, i);
      if (feet != plate) continue;
      on = plate;
      if (_onPlate != plate) _summon(game, ExhibitBuilder.bossPlates[i].$1);
    }
    _onPlate = on;
    // The spawner block brings the dungeon's four near a player watching.
    _spawnerIn -= dt;
    if (_spawnerIn > 0.0) return;
    _spawnerIn = 2.0;
    final sp = ExhibitBuilder.arenaSpawnerCell(z);
    if (sp.distanceTo(game.player.position) > 20.0 || !world.isLoaded(sp) || world.blockNameAt(sp) != 'spawner') {
      return;
    }
    if (game.mobs.where((m) => !m.isDead && !m.removed && m.data[exhibitKey] == broodTag).length >= 4) return;
    const brood = ['zombie', 'skeleton', 'spider', 'cave_slime'];
    final m = _creature(
      game,
      brood[game.random.nextInt(brood.length)],
      _at(sp.x + 2, sp.z + 2),
      broodTag,
      home: _at(z.cx, z.cz),
    );
    game.debris.burst(m.position + Vector3(0.0, 0.8, 0.0), Vector3(0.6, 0.2, 0.9), count: 18);
  }

  void _summon(VoxelGame game, String species) {
    final z = zone('arena');
    final there = _summoned[species];
    if (there != null && !there.removed && !there.isDead) {
      return game.notify('The ${there.name} is already in the arena');
    }
    final m = _creature(game, species, _at(z.cx, z.cz), 'arena', home: _at(z.cx, z.cz));
    _summoned[species] = m;
    game.debris.burst(m.position + Vector3(0.0, 1.0, 0.0), Vector3(0.9, 0.3, 0.2), count: 30);
    game.playSound('quest', volumeDb: -4.0, pitch: 0.6);
    game.notify('${m.name} called into the arena!');
  }

  // An id as a name: `storm` is Storm.
  static String _named(String id) => id[0].toUpperCase() + id.substring(1);

  @override
  String get saveKey => key;

  @override
  Object? save(VoxelGame game) => {'built': built.toList()};

  /// Puts back the exhibits built; throws for one it does not know.
  @override
  void restore(VoxelGame game, Object? saved) {
    _restored = true;
    built.clear();
    for (final id in ((saved! as Map<String, Object?>)['built']! as List<Object?>).cast<String>()) {
      if (!zones.any((z) => z.id == id)) throw FormatException('no exhibit $id');
      built.add(id);
    }
  }
}
