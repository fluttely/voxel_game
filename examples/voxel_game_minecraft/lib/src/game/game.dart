import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart'
    show Offset, PointerCancelEvent, PointerDeviceKind, PointerDownEvent, PointerMoveEvent, PointerUpEvent;
import 'package:flutter/widgets.dart' show Size, WidgetsBinding;
import 'package:voxel_game/voxel_game.dart' show FixedStepLoop;
import 'package:flutter_scene/scene.dart' hide Spawner;
import 'package:vector_math/vector_math.dart';

import '../core/blocks.dart';
import '../core/items.dart';
import '../ui/paced_scene.dart';
import 'package:voxel_engine/core.dart';
import '../core/species.dart';
import '../entities/boat.dart';
import '../entities/item_drop.dart';
import '../entities/minecart.dart';
import '../entities/mob.dart';
import '../entities/player_model.dart';
import '../entities/projectile.dart';
import '../entities/remote_player.dart';
import '../entities/spawner.dart';
import '../entities/target.dart';
import '../entities/voxel_mesh_builder.dart';
import '../player/player.dart';
import '../world/terrain_generator.dart';
import 'package:voxel_scene/voxel_scene.dart';
import '../world/voxel_world.dart';
import 'achievements.dart';
import 'game_state.dart';
import 'input.dart';
import 'inventory.dart';
import 'loot.dart';
import 'music.dart';
import 'net.dart';
import 'playground.dart';
import 'portals.dart';
import 'quests.dart';
import 'rails.dart';
import 'sfx.dart';
import 'settings.dart';
import 'tutorial.dart';
import 'weather.dart';
import 'worlds.dart';
import '../core/recipes.dart';
import '../ui/settings_panel.dart';
import '../ui/hud_state.dart';
import '../ui/item_icon.dart';

enum ScreenKind { none, inventory, pause, death, journal, trade }

class Note {
  Note(this.text, this.t);
  final String text;
  double t;
}

class DamageNumber {
  DamageNumber(this.pos, this.text, this.color, [this.crit = false]);
  final Vector3 pos;
  final String text;
  final Vector3 color;
  final bool crit; // stage 32
  double age = 0.0;

  /// Stage 32: a number rises 1 m over 0.8 s and fades from 0.2 s to 1.0 s.
  static const double riseSeconds = 0.8;
  static const double rise = 1.0;
  static const double fadeDelay = 0.2;
  static const double lifetime = 1.0;
}

class _Effect {
  _Effect(this.node, this.mat, this.radius, this.color);
  final Node node;
  final UnlitMaterial mat;
  final double radius;
  final Vector3 color;
  double age = 0.0;
}

class _Debris {
  _Debris(this.node, this.vel, this.size);
  final Node node;
  final Vector3 vel;
  final double size;
  double age = 0.0;
  double rx = 0, ry = 0, rz = 0;
}

class _Tnt {
  _Tnt(this.node, this.mat, this.at);
  final Node node;
  final UnlitMaterial mat;
  final IVec3 at;
  double age = 0.0;
}

class _Stage21a {
  _Stage21a(this.at, this.kind, this.origin);
  final Vector3 at;
  final int kind;
  final IVec3 origin;
}

class _Stage20 {
  _Stage20(this.horse, this.wool);
  final Mob horse;
  final int wool;
}

class Loot {
  Loot(this.id, this.bonus);
  final String id;
  final int bonus;
}

/// Orchestrates a play session: world, player, sky and day/night, drops,
/// projectiles, effects, damage numbers, mobs (spawner), HUD state,
/// save/load. Args: `--screenshot=<png>` --frames=N --seed=N --radius=N
/// --class=warrior|ranger|mage|rogue --time=0..1 --fly --fire=primary|secondary
class Game extends ChangeNotifier {
  Game({required this.args, required String saveDir})
      : saveRoot = Directory(saveDir).parent.parent.path,
        saveDir = args.containsKey('--slot=') ? '${Directory(saveDir).parent.path}/${args['--slot=']}' : saveDir;

  static const double dayLength = 600.0;
  static const double fixedStep = 1.0 / 60.0;

  final Map<String, String> args;

  /// `worlds/<name>`, or `worlds/<slot>` with `--slot=` (stage 24).
  final String saveDir;

  /// Godot's `user://`: the folder holding `worlds/`, `settings.cfg` and the
  /// stage 24 probe flag.
  final String saveRoot;

  /// Stage 24: every chunk the player ever stood in (the world map's explored
  /// area, saved), the structures the player came close to (kind per origin,
  /// the map's icons), and the verify half of the `--stage24` probe, signalled
  /// across the reload by `probe24.flag`.
  final Set<ChunkPos> visitedChunks = {};
  final Map<IVec3, int> discoveredStructures = {};
  bool _stage24Verify = false;
  String get _probe24Flag => '$saveRoot/probe24.flag';

  /// Stage 27: the same two-boot trick for the circuit save round trip; the
  /// flag carries the site's cells, read (and removed) at init.
  Map<String, int>? _stage27Site;
  String get _probe27Flag => '$saveRoot/probe27.flag';

  /// Stage 28: the same for the rails and carts.
  Map<String, int>? _stage28Site;
  String get _probe28Flag => '$saveRoot/probe28.flag';

  /// Stage 29: the same for the underworld; the flag carries the return
  /// portal's cells as JSON.
  Map<String, dynamic>? _stage29Site;
  String get _probe29Flag => '$saveRoot/probe29.flag';

  /// Stage 30: the stats round trip, two boots again; the flag carries the
  /// counters saved.
  Map<String, dynamic>? _stage30Saved;
  String get _probe30Flag => '$saveRoot/probe30.flag';
  double _prevTimeOfDay = 0.3;

  /// Set by the view: throws this session away and builds a fresh one with the
  /// same arguments (Godot's `reload_current_scene`).
  void Function()? reloader;

  /// Stage 30: set by the launcher; the pause menu's "Save & back to title"
  /// (Godot's `change_scene_to_file("res://menu.tscn")`).
  void Function()? exitToTitle;
  final Scene scene = PacedScene(); // the glyph atlas survives a busy GPU (paced_scene.dart)
  late VoxelWorld world;
  late Player player;
  final Node entities = Node(name: 'Entities');
  final GameInput input = GameInput();
  final QuestLog quests = QuestLog();
  final math.Random random = math.Random();
  double timeOfDay = 0.3;
  // The sun turns in steps of this many radians (`--sunstep=` degrees, 0 = smooth). flutter_scene
  // keeps its static shadow tiles only while the light direction holds still
  // (shadow_cache.dart:106); a sun moving every frame rebuilt all four cascades every frame.
  double _sunStep = 0.0;
  bool flyMode = false;
  Mob? boss;
  final Map<IVec3, Inventory> chests = {};
  final Map<IVec3, double> crops = {};
  final Map<IVec3, String> waypoints = {};
  late final Weather weather;
  int journalTab = 0;
  final List<Mob> mobs = [];
  final List<Mob> pets = [];
  final List<ItemDrop> drops = [];
  final List<Projectile> projectiles = [];
  final List<Boat> boats = [];
  final List<Minecart> carts = []; // stage 28
  final List<RemotePlayer> puppets = [];
  final List<DamageNumber> damageNumbers = [];
  final List<Note> notes = [];
  final List<_Effect> _effects = [];
  final List<_Debris> _debris = [];
  final List<_Tnt> _tnts = [];
  final Set<IVec3> _bossesSpawned = {};

  /// Stage 32: the HUD's animated state, and the probe's counters.
  final HudState hud = HudState();
  int crits = 0;
  int damageNumbersSpawned = 0;
  int debrisSpawned = 0;
  String lastBreakFamily = '';
  static const double critChance = 0.1;
  static const double critMult = 1.5;

  /// Off only for a probe that measures one exact hit (`--strike`): the 10%
  /// roll would make its damage x1.5 one run in ten.
  bool critsEnabled = true;

  /// Godot's `spawner.set_process(false)`: no natural spawns while true, but
  /// `forceSpawn` (the fortress blazes, a probe's own mobs) still works, which
  /// nulling [spawner] would not allow.
  bool spawnerPaused = false;
  static CuboidGeometry? _debrisCube;

  /// Stage 26: the villager whose trade screen is open, the rows flashing green
  /// (true) or red after a click with the seconds left, and the slimes that
  /// died this tick and split at its end.
  Mob? tradeVillager;
  final Map<int, bool> tradeFlash = {};
  final Map<int, double> _tradeFlashT = {};
  final List<Mob> pendingSplits = [];

  /// Stage 23: plates pressed and not yet left, so one press lights one fuse.
  final Set<IVec3> _platesFired = {};
  Spawner? spawner;

  /// Stage 33: the showcase world's exhibits and keys (null outside a
  /// playground), and its save block read by [_loadGame].
  Playground? playground;
  Map<String, dynamic>? _playgroundSave;

  /// Stage 31: how much of the baked skylight shows right now (1.0 noon, 0.35
  /// night, 0.0 in the underworld); the terrain shader and the spawner's light
  /// gate both read it. Night is 0.35 rather than lower because the shader
  /// raises the level to the fourth power: 0.35 leaves a moonlit field at about
  /// a fifth of noon, 0.15 would leave it black.
  double skyIntensity = 1.0;

  /// Stage 31: the spawner's view of the sky: `sky * dayFactor + block` is the
  /// light a cell has for a hostile to care about.
  double get dayFactor => skyIntensity;
  ScreenKind screen = ScreenKind.none;
  String station = '';
  Inventory? chest;
  IVec3 chestPos = IVec3.zero;
  bool debugVisible = true;

  /// Whether the on-screen controls are on the screen: always on a phone or a
  /// tablet, where there is no keyboard to play with, and on `--touch` so the
  /// layout can be seen (and captured) from a desktop. The HUD reads it too —
  /// the bottom-left corner belongs to the movement stick when it is on.
  bool touchControls = false;
  MapView mapView = MapView.off;
  final ValueNotifier<int> frame = ValueNotifier<int>(0);
  double fps = 0.0;
  double _fpsAcc = 0.0;
  int _fpsCount = 0;
  double _structTimer = 0.0;
  double _autosave = 0.0;
  /// The frame bank, `voxel_game`'s (`CL-002`): `alpha` is how far into the
  /// next step it stands, for smoothing a pose between two.
  final FixedStepLoop _loop = FixedStepLoop(step: fixedStep);
  double _sleepFrom = 0, _sleepTo = 0, _sleepT = -1.0;
  bool started = false;
  bool ready = false;
  Future<void> Function(String path)? screenshotter;

  /// The map bitmap's size and its last build time, handed over by the view
  /// for the map probe.
  String Function()? mapStats;

  /// Where the probe wants the camera on the captured frame, when it must not
  /// drift (a body is swept out of terrain every tick).
  Vector3 Function()? _pinCameraTo;

  /// A probe's per-tick hook, called right after the simulation step (Godot's
  /// `await physics_frame`, which a per-frame await here would undercount).
  void Function()? _probeTick;
  final List<Completer<void>> _frameWaiters = [];

  /// Look tuning (also settable with --sun= --amb= --tm=).
  static double sunScale = 0.6;
  static double ambientScale = 0.6;

  late final GradientSkySource sky;
  late final SunLight sun;
  Vector3 _ambient = Vector3.zero();
  double _ambientTimer = 99.0;

  String _arg(String prefix, String fallback) => args[prefix] ?? fallback;
  bool _hasArg(String flag) => args.containsKey(flag);

  bool get gameplay => screen == ScreenKind.none && !player.isDead && started;

  Future<void> init() async {
    touchControls = _hasArg('--touch') || Platform.isAndroid || Platform.isIOS;
    sunScale = double.tryParse(_arg('--sun=', '')) ?? sunScale;
    ambientScale = double.tryParse(_arg('--amb=', '')) ?? ambientScale;
    _buildEnvironment();
    switch (_arg('--tm=', '')) {
      case 'agx':
        scene.toneMapping = ToneMappingMode.agx;
      case 'neutral':
        scene.toneMapping = ToneMappingMode.pbrNeutral;
      case 'aces':
        scene.toneMapping = ToneMappingMode.aces;
      case 'linear':
        scene.toneMapping = ToneMappingMode.linear;
    }
    scene.add(entities);
    final flag = File(_probe24Flag);
    _stage24Verify = flag.existsSync();
    if (_stage24Verify) flag.deleteSync(); // one verify boot, whatever happens next
    final flag27 = File(_probe27Flag);
    if (flag27.existsSync()) {
      final cells = flag27.readAsStringSync().trim().split(',').map(int.parse).toList();
      _stage27Site = {'x0': cells[0], 'y': cells[1], 'z0': cells[2]};
      flag27.deleteSync(); // one verify boot, whatever happens next
    }
    final flag28 = File(_probe28Flag);
    if (flag28.existsSync()) {
      final cells = flag28.readAsStringSync().trim().split(',').map(int.parse).toList();
      _stage28Site = {'x0': cells[0], 'y': cells[1], 'z0': cells[2]};
      flag28.deleteSync();
    }
    final flag29 = File(_probe29Flag);
    if (flag29.existsSync()) {
      _stage29Site = jsonDecode(flag29.readAsStringSync()) as Map<String, dynamic>;
      flag29.deleteSync();
    }
    final flag30 = File(_probe30Flag);
    if (flag30.existsSync()) {
      _stage30Saved = jsonDecode(flag30.readAsStringSync()) as Map<String, dynamic>;
      flag30.deleteSync();
    }
    if (_hasArg('--stage30')) Settings.instance.tutorialDone = false; // the probe drives the chain from step 1
    Tutorial.instance.notify = notify;

    if (_hasArg('--playground')) {
      GameState.instance.playground = true; // stage 33: the probe's way in
      GameState.instance.creative = true;
    }
    await TerrainMaterial.loadLibrary(); // stage 31: before the world builds its materials
    world = VoxelWorld(
      playground: GameState.instance.playground,
      seedValue: int.tryParse(_arg('--seed=', '')) ?? GameState.instance.seedValue,
      // A probe run keeps radius 8 so its chunk counts never depend on this
      // machine's settings.cfg.
      loadRadius: int.tryParse(_arg('--radius=', '')) ?? (_arg('--screenshot=', '') != '' ? 8 : Settings.instance.renderRadius),
    );
    world.lightingEnabled = !_hasArg('--no-light'); // stage 31: the probe's cost comparison
    scene.add(world.root);
    await world.start();
    timeOfDay = double.tryParse(_arg('--time=', '')) ?? 0.3;
    _sunStep = (double.tryParse(_arg('--sunstep=', '')) ?? 0.5) * math.pi / 180.0;

    player = Player();
    player.setupPlayer(world, this, _arg('--class=', GameState.instance.playerClass));
    entities.add(player.node);
    // The first-person hand is placed in world space against the camera basis,
    // not carried by the body node, so it hangs off the scene root like the
    // highlight does rather than off the player.
    entities.add(player.handView.root);
    entities.add(player.highlight);
    entities.add(player.crack);
    for (final l in player.crackLines) {
      entities.add(l); // stage 32
    }
    quests.player = player;
    Achievements.instance.notify = notify;

    if (GameState.instance.playground) playground = Playground(this);
    final loaded = await _loadGame();
    if (!loaded) {
      final spawn = playground != null ? Playground.spawn : _findSpawn();
      player.position = spawn;
      player.spawnPoint = spawn.clone();
    }
    final pg = playground;
    if (pg != null) {
      final saved = _playgroundSave;
      if (saved != null) pg.fromJson(saved);
      if (!loaded) pg.startFresh();
    }
    // Stage 30: the tutorial on a world the title screen just created (a probe's
    // bare `--new` stays quiet; `--stage30` drives it); once the world exists, a
    // reload is a load. The launcher also marks a bare `--new` fresh (Godot's
    // title does not), so `--new` is excluded here explicitly.
    final titleFresh = GameState.instance.freshWorld && !_hasArg('--new');
    if ((titleFresh || _hasArg('--stage30')) && !_hasArg('--no-tutorial') && _stage30Saved == null && !Net.instance.isClient && playground == null) {
      Tutorial.instance.begin();
    }
    GameState.instance.freshWorld = false;
    _prevTimeOfDay = timeOfDay;
    flyMode = _hasArg('--fly');
    if (_hasArg('--climb')) Settings.instance.climbWalls = true;
    if (_hasArg('--fp')) player.setFirstPerson(true);
    // `--hold=<item>` puts one of something in the selected slot, so a capture
    // can show the first-person hand carrying a named tool or block.
    if (_arg('--hold=', '') != '') {
      player.inventory.setSlot(player.selectedSlot, ItemStack(_arg('--hold=', ''), 1));
    }
    final fogd = double.tryParse(_arg('--fogd=', ''));
    if (fogd != null) {
      // A probe asking for a density asks for the old exponential haze, so the
      // distance fog stops driving the fog for the rest of the run.
      fogFixed = true;
      scene.fog.enabled = fogd > 0;
      scene.fog.mode = FogMode.exponential;
      scene.fog.density = fogd;
    }
    if (_arg('--tp=', '') != '') {
      final parts = _arg('--tp=', '').split(',');
      player.position = Vector3(double.parse(parts[0]), double.parse(parts[1]), double.parse(parts[2]));
    }
    if (_arg('--look=', '') != '') {
      final parts = _arg('--look=', '').split(',');
      player.setLook(double.parse(parts[0]) * math.pi / 180.0, double.parse(parts[1]) * math.pi / 180.0);
    }
    if (_hasArg('--underwater')) _placeUnderwater();
    player.syncNode();
    world.updateAround(player.position);

    weather = Weather(() => player.position, world);
    scene.add(weather.node);
    weather.setEnabled(Settings.instance.weather);
    weather.suppressed = world.dimension == VoxelWorld.dimUnderworld; // stage 29: no sky down there
    if (_arg('--weather=', '') != '') weather.force(_arg('--weather=', ''));

    final net = Net.instance;
    net.main = this;
    net.rejectOne = _hasArg('--reject-one') && net.isHost;
    if (net.isClient) net.applyPendingEdits();
    world.onBlockChanged = net.onBlockChanged;
    world.flowEnabled = !net.isClient;
    world.circuits.onTntPowered = igniteTnt; // stage 27: TNT beside a live wire or a pressed plate
    if (!net.isClient) spawner = Spawner(world, player, this);
    if (net.mode != NetMode.solo) notify(net.isHost ? 'Hosting on port ${Net.port}' : 'Joined the host');
    // Stage 26: the ambient music follows the biome, the night and the depth; a
    // change is a HUD hint.
    Music.instance.onTrackChanged = (track) => notify('\u266A $track');
    _updateMusic();

    started = true;
    ready = true;
    if (_arg('--screenshot=', '') != '') {
      unawaited(_runScreenshot(_arg('--screenshot=', ''), int.tryParse(_arg('--frames=', '')) ?? 300));
    } else {
      await input.capture();
    }
    notifyListeners();
  }

  Vector3 _findSpawn() {
    for (var ring = 0; ring < 40; ring++) {
      for (var i = 0; i < 8; i++) {
        final a = i * math.pi * 2 / 8.0;
        final x = (math.cos(a) * ring * 12).toInt() + 8;
        final z = (math.sin(a) * ring * 12).toInt() + 8;
        final h = world.surfaceHeight(x, z);
        final biome = world.biomeAt(x, z);
        if (h > 48 && biome != 0 && biome != 6) return Vector3(x + 0.5, h + 1.5, z + 0.5);
      }
    }
    return Vector3(8.5, 80, 8.5);
  }

  void _buildEnvironment() {
    sky = GradientSkySource(sunSharpness: 600.0);
    scene.skybox = Skybox(sky);
    sun = SunLight(
      sky,
      castsShadow: !_hasArg('--noshadow'),
      cacheStaticShadows: _arg('--shadowcache=', '1') != '0',
      shadowMaxDistance: 110.0,
      shadowMapResolution: 2048,
      shadowCascadeCount: 4,
      shadowSoftness: 0.04,
      shadowDepthBias: 0.02,
      shadowNormalBias: 0.06,
      // The terrain and the voxel models wind like Godot, which the unmirrored
      // shadow pass reads as the engine's back faces: `front` here draws the
      // real back faces into the map (what `back` did before `MirroredCamera`).
      shadowCasterFaces: _arg('--casterfaces=', 'back') == 'front' ? ShadowCasterFaces.back : ShadowCasterFaces.front,
      shadowAmbientStrength: 0.0,
    );
    scene.sunLight = sun;
    scene.toneMapping = ToneMappingMode.aces;
    scene.exposure = 1.0;
    scene.fog
      ..enabled = true
      ..mode = FogMode.exponentialSquared
      // The flat colour, not the sky sample: `skyColorInfluence` reads the
      // prefiltered radiance cube, and this scene's environment is a
      // constant-diffuse one that has no such cube, so the sample comes back
      // black. It never showed while the fog was a faint haze; at full cover it
      // painted the far chunks in silhouette. `_updateSky` puts the live
      // horizon colour in `fog.color` every frame, which is the colour the
      // sample was meant to find anyway.
      ..skyColorInfluence = 0.0
      ..maxOpacity = 1.0;
    _updateSky();
  }

  static Vector3 _mix(Vector3 a, Vector3 b, double t) => a + (b - a) * t;

  void _updateSky() {
    if (ready && world.dimension == VoxelWorld.dimUnderworld) {
      // Stage 29: no sun, no moon, a dark red haze. The chunks carry their own
      // baked light (glowstone, lava); the ambient is a warm dim wash so the
      // rock is not pitch black.
      sun.intensity = 0.0;
      sky.sunColor = Vector3.zero();
      sky.zenithColor = Vector3(0.06, 0.01, 0.01);
      sky.horizonColor = Vector3(0.28, 0.05, 0.03);
      sky.groundColor = Vector3(0.12, 0.02, 0.02);
      final radiance = Vector3(1.0, 0.55, 0.42) * (0.55 * 1.25 * ambientScale);
      if ((radiance - _ambient).length > 0.02) {
        _ambient = radiance;
        _ambientTimer = 0.0;
        scene.environment = EnvironmentMap.constantDiffuse(radiance);
      }
      scene.fog
        ..mode = FogMode.exponential // a haze that closes in, not a view distance
        ..density = 0.014
        ..color = Vector3(0.30, 0.06, 0.04);
      skyIntensity = 0.0; // stage 31: no sky down there, only block light
      world.setSkyIntensity(skyIntensity);
      return;
    }
    var angle = (timeOfDay - 0.25) * math.pi * 2; // 0.25 = sunrise, 0.5 = noon
    if (_sunStep > 0.0) angle = (angle / _sunStep).roundToDouble() * _sunStep;
    final sunDir = Vector3(math.cos(angle) * 0.6, math.sin(angle), -0.5).normalized();
    final elevation = sunDir.y;
    final day = (elevation * 3.0 + 0.15).clamp(0.0, 1.0);
    final dusk = (1.0 - elevation.abs() * 5.0).clamp(0.0, 1.0);
    final sunColor = _mix(Vector3(1.0, 0.95, 0.85), Vector3(1.0, 0.55, 0.3), dusk);
    final dark = ready ? weather.darken() : 0.0;
    final bolt = ready ? weather.flash : 0.0;
    final overcast = Vector3(0.45, 0.48, 0.55);
    final topDay = Vector3(0.20, 0.42, 0.85);
    final horDay = Vector3(0.62, 0.78, 0.92);
    final topNight = Vector3(0.02, 0.03, 0.08);
    final horNight = Vector3(0.06, 0.08, 0.15);
    final horDusk = Vector3(0.95, 0.55, 0.30);
    var top = _mix(topNight, topDay, day);
    var hor = _mix(_mix(horNight, horDay, day), horDusk, dusk * 0.8);
    if (dark > 0.0 || bolt > 0.0) {
      final grey = overcast * (0.15 + 0.85 * day);
      top = _mix(_mix(top, grey, dark), Vector3(1, 1, 1), bolt * 0.8);
      hor = _mix(_mix(hor, overcast * (0.2 + 0.8 * day), dark), Vector3(1, 1, 1), bolt * 0.8);
    }
    sky.zenithColor = top;
    sky.horizonColor = hor;
    sky.groundColor = hor * 0.9;
    // Stage 31: the sun is a shading hint over the baked light, not the light
    // itself, so it drops from Godot's 0.85 to 0.6 and leaves the AO visible; the
    // baked skylight follows the day through the terrain shader.
    skyIntensity = (0.35 + 0.65 * day) * (1.0 - dark * 0.4);
    if (ready) world.setSkyIntensity(skyIntensity);
    if (elevation > 0.0) {
      sky.sunDirection = sunDir;
      sun.color = sunColor;
      sun.intensity = (3.0 * 0.6 * day * (1.0 - dark) + 0.02 + bolt * 1.5) * sunScale;
      sky.sunColor = sunColor * (2.5 * day + 0.4);
    } else {
      sky.sunDirection = -sunDir;
      // The moon and the night ambient are raised so the engine's own lighting
      // does not darken the night a second time: the terrain shader's
      // Minecraft light map already sets how dark a moonlit field is.
      sun.color = Vector3(0.55, 0.65, 0.95);
      sun.intensity = (3.0 * 0.45 * (1.0 - day) + 0.02) * sunScale;
      sky.sunColor = Vector3(0.5, 0.6, 0.9) * 0.9;
    }
    final ambientEnergy = (0.9 - 0.5 * day) * (1.0 - dark * 0.5) + bolt * 0.6;
    final ambientColor = _mix(Vector3(0.35, 0.40, 0.60), Vector3(0.80, 0.84, 0.92), day);
    final radiance = ambientColor * (ambientEnergy * 1.25 * ambientScale);
    if ((radiance - _ambient).length > 0.02 && _ambientTimer > 0.5) {
      _ambient = radiance;
      _ambientTimer = 0.0;
      scene.environment = EnvironmentMap.constantDiffuse(radiance);
    }
    scene.fog.color = hor;
    if (ready) _setDistanceFog(dark);
  }

  /// A `--fogd=` probe has taken the fog over; [_setDistanceFog] keeps off it.
  bool fogFixed = false;

  /// Minecraft's distance fog: the horizon is hidden a little short of the last
  /// loaded chunk, so the world dissolves into the sky instead of stopping on a
  /// row of chunk edges over empty air. The band is tied to the render distance
  /// because that is what it exists to hide — raising the slider pushes the fog
  /// out with it — and rain or a storm pulls it in, as Minecraft's does.
  ///
  /// Not weather: a clear day must look clear. The fog is an
  /// exponential-squared curve that only begins at 72% of the edge, so
  /// everything nearer stays untouched, then climbs steeply — about a third at
  /// 80%, 87% at 90%, 98% at 97% — and the band sits on the last chunks, where
  /// the world ends. The linear ramp this replaced started at 45% and hazed half
  /// the view; the exponential haze before it hazed all of it.
  void _setDistanceFog(double dark) {
    if (fogFixed) return;
    // The nearest chunk edge is loadRadius chunks away, 16 blocks each.
    final edge = world.loadRadius * 16.0 * (1.0 - dark * 0.35);
    final start = edge * _fogStartAt;
    scene.fog
      ..mode = FogMode.exponentialSquared
      ..start = start
      // 1 - exp(-x²) reaches 98% where x² = ln 50.
      ..density = math.sqrt(math.log(50.0)) / (edge * _fogFullAt - start);
  }

  /// Where the horizon fog begins and where it is full, as fractions of the
  /// distance to the nearest unloaded chunk.
  static const double _fogStartAt = 0.72;
  static const double _fogFullAt = 0.97;

  /// The liquid the camera's eye is in: 'water', 'lava' or ''. The HUD washes
  /// the screen with it.
  String eyeLiquid = '';

  /// Under a liquid the fog closes in and takes its colour: water fades to a
  /// deep blue over about 20 m (60% at 18 m), lava to orange in about 2 m. Runs after
  /// [_updateSky], which sets the open-air fog every frame.
  void _updateSubmerged() {
    final eye = player.cameraPosition;
    final cell = IVec3(eye.x.floor(), eye.y.floor(), eye.z.floor());
    final id = world.getBlockXYZ(cell.x, cell.y, cell.z);
    var kind = Blocks.liquidKind(id);
    // The top cell of a pool is drawn 0.875 high: an eye above that surface is in air.
    if (kind != '' && Blocks.liquidKind(world.getBlockXYZ(cell.x, cell.y + 1, cell.z)) == '' && eye.y - cell.y > 0.875) kind = '';
    eyeLiquid = kind;
    final fog = scene.fog;
    switch (kind) {
      case 'water':
        fog
          ..mode = FogMode.exponential
          ..color = Vector3(0.03, 0.12, 0.28) * (0.25 + 0.75 * skyIntensity)
          ..density = 0.05
          ..skyColorInfluence = 0.0
          ..maxOpacity = 1.0;
      case 'lava':
        fog
          ..mode = FogMode.exponential
          ..color = Vector3(0.75, 0.22, 0.02)
          ..density = 1.2
          ..skyColorInfluence = 0.0
          ..maxOpacity = 1.0;
      default:
        // Full opacity, so the far band lands exactly on the horizon colour
        // and the chunk edge goes rather than showing through.
        fog
          ..skyColorInfluence = 0.0
          ..maxOpacity = 1.0;
    }
  }

  String timeLabel() {
    if (world.dimension == VoxelWorld.dimUnderworld) return 'Underworld'; // stage 29: no clock, no weather
    final h = (timeOfDay * 24.0).toInt();
    final m = ((timeOfDay * 24.0) % 1.0 * 60.0).toInt();
    const biomeNames = ['Ocean', 'Beach', 'Plains', 'Forest', 'Desert', 'Snow', 'Mountains', 'Swamp', 'Jungle', 'Underworld'];
    final b = world.biomeAt(player.position.x.toInt(), player.position.z.toInt());
    final clock = '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}   ${biomeNames[b]}${isNight ? '   (night)' : ''}';
    return weather.kind == WeatherKind.clear ? clock : '$clock   ${weather.label}';
  }

  bool get isNight => timeOfDay < 0.22 || timeOfDay > 0.78;

  /// Stage 26: the music's mood for where the player stands (underground =
  /// below y 40).
  static const double musicUndergroundY = 40.0;

  void _updateMusic() {
    final biome = world.biomeAt(player.position.x.toInt(), player.position.z.toInt());
    Music.instance.setContext(biome, isNight, player.position.y < musicUndergroundY, world.dimension == VoxelWorld.dimUnderworld);
  }

  String debugText() =>
      'FPS ${fps.round()}  chunks ${world.loadedChunkCount}  queue ${world.pendingCount}  faces ${world.facesEmitted}  mobs ${mobs.length}\n'
      'pos ${player.position.x.toStringAsFixed(1)} ${player.position.y.toStringAsFixed(1)} ${player.position.z.toStringAsFixed(1)}  seed ${world.seedValue}  dim ${world.dimension}   [F1] hide';

  void notify(String text) {
    notes.add(Note(text, 3.0));
    if (notes.length > 5) notes.removeRange(0, notes.length - 5);
  }

  // --- the frame -----------------------------------------------------------------

  /// Called once per rendered frame by the view; runs the fixed-step simulation.
  void onFrame(double dt) {
    if (!ready) return;
    _fpsAcc += dt;
    _fpsCount++;
    if (_fpsAcc >= 0.5) {
      fps = _fpsCount / _fpsAcc;
      _fpsAcc = 0.0;
      _fpsCount = 0;
    }
    // The bank is `voxel_game`'s `FixedStepLoop`: the same six lines this file
    // used to carry, to the same numbers (0.1 s of frame at most, whole steps
    // of 1/60, at most 4 a frame), plus the clamp that stops a hitch becoming
    // a spiral of catch-up and `alpha`, the fraction into the next step.
    //
    // A frame that runs no step does NOT drain the one-shots: a press set
    // between two frames is read by the next step, whenever that lands. The
    // drain used to live here, and above 60 fps it threw away every press it
    // beat to the simulation — `--touch-probe` measured 0 of 20 taps arriving
    // at 120 fps, because a frame that just spent the bank runs no step.
    _loop.advance(dt, _tick);
    world.update();
    _ambientTimer += dt;
    _updateSky();
    _updateSubmerged();
    hud.update(dt, this); // stage 32: Godot's hud `_process`
    frame.value++;
    if (_frameWaiters.isNotEmpty) {
      final waiters = List.of(_frameWaiters);
      _frameWaiters.clear();
      for (final w in waiters) {
        w.complete();
      }
    }
  }

  Future<void> nextFrame() {
    final c = Completer<void>();
    _frameWaiters.add(c);
    return c.future;
  }

  void _handleGlobalKeys() {
    if (input.justPressed(GameAction.debugHud)) debugVisible = !debugVisible;
    if (input.justPressed(GameAction.map)) cycleMap(); // stage 24: the corner map, then the full map, then off
    if (input.justPressed(GameAction.screenshot)) {
      final dir = Directory('$saveDir/../../screenshots');
      dir.createSync(recursive: true);
      final path = '${dir.path}/${DateTime.now().millisecondsSinceEpoch ~/ 1000}.png';
      screenshotter?.call(path).then((_) => notify('Screenshot saved: $path'));
    }
    if (input.justPressed(GameAction.fly)) {
      if (flyAllowed()) {
        flyMode = !flyMode;
        notify('Fly mode ${flyMode ? 'ON (Space up, Ctrl down)' : 'OFF'}');
      } else {
        notify('Flying is for Creative worlds');
      }
    }
    if (input.justPressed(GameAction.skipTutorial)) Tutorial.instance.skipAll(); // stage 30: F6
    final pg = playground;
    if (pg != null && !Net.instance.isClient) {
      // Stage 33: the showcase keys.
      if (input.justPressed(GameAction.cycleWeather)) pg.cycleWeather();
      if (input.justPressed(GameAction.cycleTime)) pg.cycleTime();
      if (input.justPressed(GameAction.rebuildExhibit)) pg.rebuildHere();
    }
    if (input.justPressed(GameAction.pause)) {
      if (screen != ScreenKind.none) {
        if (screen != ScreenKind.death) closeScreen();
      } else {
        openScreen(ScreenKind.pause);
      }
    } else if (input.justPressed(GameAction.interact) && screen == ScreenKind.trade) {
      closeScreen(); // stage 26: F closes the trade screen it opened
    } else if (input.justPressed(GameAction.journal) && !player.isDead) {
      if (screen != ScreenKind.none) {
        closeScreen();
      } else {
        openJournal(0);
      }
    } else if (input.justPressed(GameAction.inventory) && !player.isDead) {
      if (screen != ScreenKind.none) {
        closeScreen();
      } else {
        openStation('', IVec3.zero);
      }
    }
    if (input.captureLost && screen == ScreenKind.none && !player.isDead) {
      input.captureLost = false;
      openScreen(ScreenKind.pause);
    }
  }

  void _tick(double dt) {
    _handleGlobalKeys();
    timeOfDay = (timeOfDay + dt / dayLength) % 1.0;
    if (_sleepT >= 0.0) {
      _sleepT += dt;
      final t = (_sleepT / 2.2).clamp(0.0, 1.0);
      final e = t < 0.5 ? 2 * t * t : 1 - math.pow(-2 * t + 2, 2) / 2;
      timeOfDay = (_sleepFrom + (_sleepTo - _sleepFrom) * e) % 1.0;
      if (t >= 1.0) {
        timeOfDay = 0.26;
        _sleepT = -1.0;
      }
    }
    if (_prevTimeOfDay < 0.25 && timeOfDay >= 0.25) Tutorial.instance.event('sleep'); // stage 30: sunrise counts as the night survived
    _prevTimeOfDay = timeOfDay;
    GameState.instance.playTime += dt;
    final play = gameplay;
    // Stage 29: the arrival holds the player until the other dimension's chunks
    // are in; a body in a portal for two seconds travels.
    _arriveTick();
    _portalTick(dt);
    player.physicsProcess(dt, input, play);
    for (final m in mobs) {
      if (isHere(m)) m.update(dt);
    }
    for (final m in pets) {
      if (isHere(m)) m.update(dt);
    }
    // Stage 23: the pressure plates (Godot's `Main._physics_process`). Since
    // stage 27 a plate is a power SOURCE while pressed: the TNT under it ignites
    // through the circuit tick, and so does anything else the plate touches.
    // Host / solo only: a client sees the block edits arrive.
    if (!Net.instance.isClient) {
      final pressed = <IVec3>{};
      _checkPlateUnder(player, pressed);
      for (final m in mobs) {
        _checkPlateUnder(m, pressed);
      }
      for (final m in pets) {
        _checkPlateUnder(m, pressed);
      }
      for (final cell in pressed) {
        if (_platesFired.contains(cell)) continue;
        Sfx.play('click', 0.0, 0.6);
        final below = world.getBlock(cell + IVec3.down);
        if (below != Blocks.air && Blocks.idOf(below) == 'tnt') notify('Click... the floor rumbles!');
      }
      _platesFired
        ..clear()
        ..addAll(pressed);
      world.circuits.setPressedPlates(pressed);
    }
    for (final d in drops) {
      if (isHere(d)) d.update(dt);
    }
    for (final p in projectiles) {
      p.update(dt);
    }
    for (final b in boats) {
      if (isHere(b)) b.update(dt);
    }
    for (final c in carts) {
      if (isHere(c)) c.update(dt);
    }
    for (final p in puppets) {
      p.update(dt);
    }
    weather.process(dt);
    _tickVisuals(dt);
    if (!spawnerPaused) spawner?.update(dt);
    if (!Net.instance.isClient) playground?.tick(dt); // stage 33
    // Stage 25: the tick's flow edits leave as one `blocks` message.
    Net.instance.beginBlockBatch();
    world.tickFlow(dt);
    if (world.flowEnabled) world.circuits.tick(dt); // stage 27: host-only, in the same batch
    Net.instance.endBlockBatch();
    _probeTick?.call();
    Net.instance.process(dt);
    if (pendingSplits.isNotEmpty) {
      final dead = List.of(pendingSplits);
      pendingSplits.clear();
      for (final m in dead) {
        m.spawnSplit();
      }
    }
    for (final k in List.of(_tradeFlashT.keys)) {
      _tradeFlashT[k] = _tradeFlashT[k]! - dt;
      if (_tradeFlashT[k]! <= 0.0) {
        _tradeFlashT.remove(k);
        tradeFlash.remove(k);
      }
    }
    _prune();

    for (final n in notes) {
      n.t -= dt;
    }
    notes.removeWhere((n) => n.t <= 0.0);

    _structTimer += dt;
    if (_structTimer > 1.0) {
      _structTimer = 0.0;
      visitedChunks.add(VoxelWorld.chunkOf(IVec3.floor(player.position)));
      _checkStructures();
      _updateMusic();
      // Stage 25: growth is a host block edit; it reaches clients as one.
      if (!Net.instance.isClient) _growCrops();
      _tickSpawners();
      _tickRuinGhosts();
      _trackBoss();
      if (weather.isWet) {
        if (!Net.instance.isClient) _growCrops();
        final surface = world.surfaceHeight(player.position.x.toInt(), player.position.z.toInt());
        if (player.effects.has('burning') && player.position.y >= surface - 1) {
          player.effects.clear('burning');
        }
      }
      if (player.position.y < 20.0) Achievements.instance.unlock('deep');
      final b = boss;
      if (b != null && (b.removed || b.state == MobState.dead)) boss = null;
    }
    _autosave += dt;
    if (_autosave > 60.0) {
      _autosave = 0.0;
      saveGame();
    }
    input.endTick();
  }

  void _tickVisuals(double dt) {
    for (final e in _effects) {
      e.age += dt;
      final t = (e.age / 0.35).clamp(0.0, 1.0);
      final eased = 1 - math.pow(1 - t, 3).toDouble();
      final s = 1.0 + (e.radius * 2.0 - 1.0) * eased;
      e.node.scale = Vector3(s, s, s);
      e.mat.baseColorFactor = Vector4(e.color.x, e.color.y, e.color.z, 0.55 * (1 - t));
    }
    for (final d in _debris) {
      d.age += dt;
      d.node.position = d.node.position + d.vel * dt;
      d.vel.y -= 9.8 * dt;
      d.rx += 0.1 * dt * 60;
      d.ry += 0.13 * dt * 60;
      d.rz += 0.07 * dt * 60;
      d.node.rotation = Quaternion.euler(d.ry, d.rx, d.rz);
      d.node.scale = Vector3(d.size, d.size, d.size);
    }
    for (final t in _tnts) {
      t.age += dt;
      final phase = (t.age / 0.4) % 2.0;
      final white = phase < 1.0 ? phase : 2.0 - phase;
      final c = Blocks.def(Blocks.indexOf('tnt'));
      t.mat.baseColorFactor = Vector4(c.r + (1 - c.r) * white, c.g + (1 - c.g) * white, c.b + (1 - c.b) * white, 1);
      if (t.age >= 3.2) {
        entities.remove(t.node);
        explode(t.at.centre, 3.5, 18.0, null);
      }
    }
    _tnts.removeWhere((t) => t.age >= 3.2);
    for (final n in damageNumbers) {
      n.age += dt;
    }
    damageNumbers.removeWhere((n) => n.age >= DamageNumber.lifetime);
  }

  void _prune() {
    void pruneList<T>(List<T> list, bool Function(T) gone, Node Function(T) nodeOf) {
      for (final e in list) {
        if (gone(e)) entities.remove(nodeOf(e));
      }
      list.removeWhere(gone);
    }

    pruneList<Mob>(mobs, (m) => m.removed, (m) => m.node);
    pruneList<Mob>(pets, (m) => m.removed, (m) => m.node);
    for (final d in drops) {
      if (d.removed) Net.instance.onDropGone(d);
    }
    pruneList<ItemDrop>(drops, (d) => d.removed, (d) => d.node);
    pruneList<Projectile>(projectiles, (p) => p.removed, (p) => p.node);
    for (final b in boats) {
      if (b.removed) Net.instance.onBoatGone(b);
    }
    pruneList<Boat>(boats, (b) => b.removed, (b) => b.node);
    for (final c in carts) {
      if (c.removed) Net.instance.onCartGone(c);
    }
    pruneList<Minecart>(carts, (c) => c.removed, (c) => c.node);
    pruneList<RemotePlayer>(puppets, (p) => p.removed, (p) => p.node);
    pruneList<_Effect>(_effects, (e) => e.age >= 0.35, (e) => e.node);
    pruneList<_Debris>(_debris, (d) => d.age >= 0.6, (d) => d.node);
  }

  // --- screens ------------------------------------------------------------------------

  /// Stage 30: F5 flies in a creative world (or under the `--fly` probe arg).
  bool flyAllowed() => GameState.instance.creative || _hasArg('--fly');

  void openStation(String st, IVec3 at) {
    Tutorial.instance.event('inventory');
    station = st;
    chestPos = at;
    chest = st != 'chest' ? null : (Net.instance.isClient ? Net.instance.openChest(at) : chestInventory(at));
    openScreen(ScreenKind.inventory);
  }

  void openScreen(ScreenKind kind) {
    screen = kind;
    input.releaseKeys();
    unawaited(input.release());
    notifyListeners();
  }

  void closeScreen() {
    screen = ScreenKind.none;
    chest = null;
    tradeVillager = null;
    tradeFlash.clear();
    _tradeFlashT.clear();
    if (!player.isDead) unawaited(input.capture());
    notifyListeners();
  }

  void onPlayerDied() => openScreen(ScreenKind.death);

  void openJournal(int tab) {
    Tutorial.instance.event('journal');
    journalTab = tab;
    openScreen(ScreenKind.journal);
  }

  /// Waypoints sorted by label, as the journal lists them.
  List<MapEntry<IVec3, String>> waypointList() {
    final out = waypoints.entries.toList();
    out.sort((a, b) => a.value.compareTo(b.value));
    return out;
  }

  /// Travel to a waypoint block: free when standing beside any waypoint, 10
  /// mana from anywhere.
  bool travelToWaypoint(IVec3 to) {
    final label = waypoints[to];
    if (label == null) return false;
    var near = false;
    for (final k in waypoints.keys) {
      if ((k.toVector3() - player.position).length < 6.0) near = true;
    }
    if (!near) {
      if (player.mana < 10.0) {
        notify('Need 10 mana to travel from afar');
        return false;
      }
      player.mana -= 10.0;
    }
    spawnEffect(player.centre(), Vector3(0.35, 0.75, 0.95), 1.5);
    player.position = to.toVector3() + Vector3(0.5, 1.05, 0.5);
    player.velocity = Vector3.zero();
    player.syncNode();
    world.updateAround(player.position);
    spawnEffect(player.centre(), Vector3(0.35, 0.75, 0.95), 1.5);
    Sfx.play('quest', -6.0, 1.4);
    notify('Travelled to $label');
    Achievements.instance.unlock('traveler');
    return true;
  }

  /// A chest's contents, created on first open. A chest that came with a
  /// structure is filled with loot decided by its position, so it is the same
  /// loot for everyone.
  Inventory chestInventory(IVec3 at) {
    final existing = chests[at];
    if (existing != null) return existing;
    final inv = Inventory();
    chests[at] = inv;
    if (!GameState.instance.placedChests.contains(at.key)) {
      // Stage 23: the table of the structure the chest belongs to (`LootTables`).
      final rng = math.Random(LootTables.seedFor(at, world.seedValue));
      final table = LootTables.tableNear(world, at);
      for (final stack in LootTables.roll(table, rng)) {
        inv.add(stack.id, stack.count);
      }
      if ((table == 'dungeon' || table == 'temple') && rng.nextDouble() < 0.45) {
        final w = randomLootWeapon(rng);
        inv.addStack(ItemStack(w.id, 1, bonus: w.bonus));
      }
    }
    return inv;
  }

  /// Kinds 5..8 of `structuresNear` (ruin, well, mine, temple), announced once each.
  static const Map<int, String> minorStructureFound = {
    5: 'You found an old ruin!',
    6: 'You found a well!',
    7: 'You found an abandoned mine!',
    8: 'You found a desert temple!',
  };

  void _checkStructures() {
    final here = VoxelWorld.chunkOf(IVec3.floor(player.position));
    for (final s in world.structuresNear(here)) {
      final key = IVec3(s.x, s.y, s.z);
      // Stage 24: any structure within 48 m is discovered (the map draws it
      // from now on).
      if (s.type >= 1 && s.type <= 9 && !discoveredStructures.containsKey(key) && key.distanceTo(player.position) < 48.0) {
        discoveredStructures[key] = s.type;
      }
      if (s.type == VoxelWorld.structFortress) {
        _checkFortress(key);
        continue;
      }
      if (s.type == 4) {
        if (!_bossesSpawned.contains(key) && key.distanceTo(player.position) < 40.0) {
          _bossesSpawned.add(key);
          // Stage 26: 3-5 villagers, born beside the well and kept to the
          // village by `home`.
          final count = 3 + random.nextInt(3);
          for (var i = 0; i < count; i++) {
            final ang = i * math.pi * 2 / 5.0;
            final vx = s.x + math.cos(ang) * 4.0, vz = s.z + math.sin(ang) * 4.0;
            final v = Mob();
            v.setupMob(world, this, player, Species.def('villager'));
            v.position = Vector3(vx, world.groundHeight(vx.toInt(), vz.toInt()) + 0.5, vz);
            v.makeTrader(v.position);
            v.home = Vector3(s.x.toDouble(), s.y.toDouble(), s.z.toDouble());
            addMob(v);
          }
          notify('A village! F on a villager to trade');
        }
        continue;
      }
      final found = minorStructureFound[s.type];
      if (found != null) {
        if (!_bossesSpawned.contains(key) && key.distanceTo(player.position) < 24.0) {
          _bossesSpawned.add(key);
          notify(found);
        }
        // Stage 23: the Mummy King wakes the first time someone steps into the
        // temple chamber. Its own key is the chamber's, lifted by
        // templeBossKeyY so it never collides with the announcement key above
        // (both live in `_bossesSpawned` and the save).
        if (s.type == TerrainGenerator.structTemple) {
          final bkey = IVec3(s.x, s.y + templeBossKeyY, s.z);
          final chamber = Vector3(s.x + 0.5, s.y + 1.0, s.z + 0.5);
          if (!_bossesSpawned.contains(bkey) && (player.position - chamber).length < 6.0) {
            _bossesSpawned.add(bkey);
            spawnTempleBoss(chamber);
          }
        }
        // Stage 28: the first visit to a mine leaves a chest cart with mine loot
        // at the end of its rail. Its key is lifted like the temple boss's, and
        // only set once the corridor's chunks are in (an unloaded cell reads as
        // air, not as a rail).
        if (s.type == TerrainGenerator.structMine && !Net.instance.isClient) {
          final ckey = IVec3(s.x, s.y + mineCartKeyY, s.z);
          if (!_bossesSpawned.contains(ckey) && key.distanceTo(player.position) < 48.0) {
            final last = _mineRailEnd(key);
            if (last != IVec3.zero) {
              _bossesSpawned.add(ckey);
              final cart = spawnMinecart(last, 'chest_minecart');
              final rng = math.Random(LootTables.seedFor(ckey, world.seedValue));
              for (final stack in LootTables.roll('mine', rng)) {
                cart?.cargo?.add(stack.id, stack.count);
              }
            }
          }
        }
        continue;
      }
      if (s.type != 1) continue;
      if (_bossesSpawned.contains(key)) continue;
      final bossRoom = Vector3(s.x + 24.0, s.y + 1.0, s.z.toDouble());
      if ((player.position - bossRoom).length < 14.0) {
        _bossesSpawned.add(key);
        final mob = Mob();
        mob.setupMob(world, this, player, Species.def('troll'));
        mob.position = bossRoom + Vector3(-2, 0, 2);
        mob.scaleToLevel(player.level + 2);
        addMob(mob);
        boss = mob;
        notify('A Cave Troll guards the treasure!');
      }
    }
  }

  static const int templeBossKeyY = 1000;
  static const int mineCartKeyY = 2000;

  // --- stage 29: the fortress --------------------------------------------------------

  static const int fortressBossKeyY = 3000;
  static const int fortressDeadKeyY = 4000;
  static const int fortressBlazeKeyY = 5000;

  /// Announced once within 48 m (achievement `underworld`); two blazes wake at
  /// the hall's middle the first time someone is within 20 m of it; the
  /// Underworld Lord wakes in the throne room the first time someone is within
  /// 14 m of the core. All three keys live in `_bossesSpawned` (lifted by their
  /// own offsets) and so in the save.
  void _checkFortress(IVec3 origin) {
    final layout = world.generator.fortressLayout(origin.x, origin.y, origin.z);
    if (!_bossesSpawned.contains(origin) && origin.distanceTo(player.position) < 48.0) {
      _bossesSpawned.add(origin);
      notify('A fortress looms in the dark!');
      Achievements.instance.unlock('underworld');
    }
    final sp = spawner;
    if (Net.instance.isClient || sp == null) return;
    final blazeKey = origin + const IVec3(0, fortressBlazeKeyY, 0);
    final blazeAt = layout.blaze.toVector3() + Vector3(0.5, 0.5, 0.5);
    if (!_bossesSpawned.contains(blazeKey) && (player.position - blazeAt).length < 20.0 && world.isLoaded(layout.blaze)) {
      _bossesSpawned.add(blazeKey);
      for (var i = 0; i < 2; i++) {
        final b = sp.forceSpawn('blaze', blazeAt + Vector3(i * 2.0 - 1.0, 1.0, 0.0));
        spawnEffect(b.centre(), Vector3(1.0, 0.6, 0.2), 1.2);
      }
      notify('Blazes!');
    }
    final bossKey = origin + const IVec3(0, fortressBossKeyY, 0);
    final core = layout.core;
    if (!_bossesSpawned.contains(bossKey) && core.distanceTo(player.position) < 14.0 && world.isLoaded(core)) {
      _bossesSpawned.add(bossKey);
      spawnFortressBoss(core.toVector3() + Vector3(0.5, 1.0, 0.5));
    }
  }

  Mob spawnFortressBoss(Vector3 throne) {
    final mob = Mob();
    mob.setupMob(world, this, player, Species.def('underworld_lord'));
    mob.position = throne + Vector3(1.5, 0.6, 0.0);
    mob.scaleToLevel(player.level + 3);
    addMob(mob);
    boss = mob;
    notify('The Underworld Lord rises!');
    Sfx.play('thunder', -6.0, 1.2);
    return mob;
  }

  /// The fortress whose core block is [core] (kind 9 within the 3x3 regions
  /// around it), or zero.
  IVec3 _fortressOfCore(IVec3 core) {
    for (final s in world.structuresNear(VoxelWorld.chunkOf(core))) {
      if (s.type != VoxelWorld.structFortress) continue;
      if (world.generator.fortressLayout(s.x, s.y, s.z).core == core) return IVec3(s.x, s.y, s.z);
    }
    return IVec3.zero;
  }

  /// A fortress core stays sealed until its lord is dead; a core with no fortress is free.
  bool coreLocked(IVec3 core) {
    final origin = _fortressOfCore(core);
    if (origin == IVec3.zero) return false;
    return !_bossesSpawned.contains(origin + const IVec3(0, fortressDeadKeyY, 0));
  }

  void onUnderworldLordDied(Vector3 at) {
    for (final s in world.structuresNear(VoxelWorld.chunkOf(IVec3.floor(at)))) {
      if (s.type != VoxelWorld.structFortress) continue;
      final core = world.generator.fortressLayout(s.x, s.y, s.z).core;
      if ((at - core.toVector3()).length < 40.0) {
        _bossesSpawned.add(IVec3(s.x, s.y + fortressDeadKeyY, s.z));
        notify('The fortress core is unsealed!');
      }
    }
  }

  /// Stage 28: the last rail cell of the corridor of the mine at [origin] (it
  /// runs +x from the shaft at mineFloorY + 1), or zero while its chunks are
  /// not all loaded or it has no rail.
  IVec3 _mineRailEnd(IVec3 origin) {
    final fy = TerrainGenerator.mineFloorY + 1;
    if (!world.isLoaded(IVec3(origin.x + 1, fy, origin.z)) || !world.isLoaded(IVec3(origin.x + 31, fy, origin.z))) {
      return IVec3.zero;
    }
    var last = IVec3.zero;
    for (var x = 1; x < 32; x++) {
      final c = IVec3(origin.x + x, fy, origin.z);
      if (Rails.isRailAt(world, c)) {
        last = c;
      } else if (last != IVec3.zero) {
        break;
      }
    }
    return last;
  }

  /// Rails of the mine at [origin], for the probe.
  int mineRailCount(IVec3 origin) {
    final fy = TerrainGenerator.mineFloorY + 1;
    var n = 0;
    for (var x = 1; x < 32; x++) {
      if (Rails.isRailAt(world, IVec3(origin.x + x, fy, origin.z))) n += 1;
    }
    return n;
  }

  /// Stage 23: the Mummy King, between the two chests at the back of the
  /// chamber whose floor centre is [chamber] (the cell above the pressure plate).
  Mob spawnTempleBoss(Vector3 chamber) {
    final mob = Mob();
    mob.setupMob(world, this, player, Species.def('mummy_king'));
    mob.position = chamber + Vector3(0, 0.05, -1.0);
    mob.scaleToLevel(player.level + 2);
    addMob(mob);
    boss = mob;
    notify('The Mummy King stirs!');
    Sfx.play('thunder', -8.0, 1.6);
    return mob;
  }

  /// Stage 23: a pressure plate is pressed while any body's feet are in its
  /// cell (stage 27: the pressed set feeds `Circuits.setPressedPlates`).
  void _checkPlateUnder(VoxelBody body, Set<IVec3> pressed) {
    final cell = IVec3(body.position.x.floor(), (body.position.y + 0.05).floor(), body.position.z.floor());
    final id = world.getBlock(cell);
    if (id == Blocks.air || Blocks.idOf(id) != 'pressure_plate') return;
    if (body.overlapsBlock(cell)) pressed.add(cell);
  }

  int platesFired() => _platesFired.length;

  /// Stage 23: ghosts haunt ruins at night — up to two per ruin within 40 m, one
  /// every few seconds.
  void _tickRuinGhosts() {
    final sp = spawner;
    if (!isNight || Net.instance.isClient || sp == null) return;
    final here = VoxelWorld.chunkOf(IVec3.floor(player.position));
    for (final s in world.structuresNear(here)) {
      if (s.type != TerrainGenerator.structRuin) continue;
      final at = Vector3(s.x.toDouble(), s.y.toDouble(), s.z.toDouble());
      if ((player.position - at).length > 40.0 || random.nextDouble() > 0.35) continue;
      var near = 0;
      for (final m in mobs) {
        if (m.species.id == 'ghost' && (m.position - at).length < 24.0) near += 1;
      }
      if (near >= 2) continue;
      final x = s.x + random.nextInt(9) - 4;
      final z = s.z + random.nextInt(9) - 4;
      final ghost = sp.forceSpawn('ghost', Vector3(x + 0.5, world.groundHeight(x, z) + 0.5, z + 0.5));
      spawnEffect(ghost.centre(), Vector3(0.7, 0.8, 1.0), 1.5);
    }
  }

  // --- spawning helpers used by the player, mobs and projectiles ----------------------

  void addMob(Mob mob) {
    mobs.add(mob);
    mob.syncNode();
    entities.add(mob.node);
  }

  void addPuppet(RemotePlayer p) {
    puppets.add(p);
    entities.add(p.node);
  }

  ItemDrop? spawnDrop(Vector3 at, String id, int count, [Vector3? vel, double delay = 0.6]) {
    // The host owns drops (stage 21b); a client asks for one instead.
    if (Net.instance.isClient) {
      Net.instance.requestDrop(at, id, count, vel ?? Vector3.zero());
      return null;
    }
    final drop = ItemDrop();
    drop.setupDrop(world, id, count, player, delay);
    drop.position = at.clone();
    drop.velocity = vel ?? Vector3(random.nextDouble() * 3 - 1.5, 3.0, random.nextDouble() * 3 - 1.5);
    drop.syncNode();
    drops.add(drop);
    entities.add(drop.node);
    Net.instance.onDropSpawned(drop);
    return drop;
  }

  void spawnLootDrop(Vector3 at, ItemStack stack) {
    final drop = ItemDrop();
    drop.setupDrop(world, stack.id, 1, player);
    drop.bonus = stack.bonus;
    drop.position = at.clone();
    drop.velocity = Vector3(random.nextDouble() * 3 - 1.5, 3.0, random.nextDouble() * 3 - 1.5);
    drop.syncNode();
    drops.add(drop);
    entities.add(drop.node);
    Net.instance.onDropSpawned(drop);
  }

  bool _hasOpaqueSide(IVec3 b) {
    for (final side in IVec3.sides) {
      if (Blocks.isOpaque(world.getBlock(b + side))) return true;
    }
    return false;
  }

  void spawnBoat(Vector3 at, double heading) {
    // The host owns boats (stage 25); a client asks for one instead.
    if (Net.instance.isClient) {
      Net.instance.requestBoat(at, heading);
      return;
    }
    final b = Boat();
    b.setupBoat(world, this, at, heading);
    boats.add(b);
    entities.add(b.node);
    Net.instance.onBoatSpawned(b);
  }

  /// Stage 28: a cart on the rail at [cell]. The host owns carts like boats; a
  /// client asks and gets null.
  Minecart? spawnMinecart(IVec3 cell, String kind) {
    if (Net.instance.isClient) {
      Net.instance.requestCart(cell, kind);
      return null;
    }
    final c = Minecart();
    c.setupCart(world, cell, kind);
    carts.add(c);
    entities.add(c.node);
    Net.instance.onCartSpawned(c);
    return c;
  }

  /// The cart goes back to being its item; a chest cart spills its slots.
  void breakMinecart(Minecart c) {
    final at = c.position + Vector3(0, 0.5, 0);
    final cargo = c.cargo;
    if (cargo != null) {
      for (final s in cargo.slots) {
        if (s != null) spawnDrop(at, s.id, s.count);
      }
    }
    spawnDrop(at, c.kind, 1);
    c.removed = true;
  }

  /// A chest cart's slots on the chest screen. The screen edits the inventory
  /// in place, so solo and host see the cart's own slots; a client is told the
  /// cart is the host's.
  void openCartCargo(Minecart c) {
    if (c.replica) {
      notify("This cart's chest opens on the host only");
      return;
    }
    station = 'chest';
    chestPos = c.cell;
    chest = c.cargo;
    openScreen(ScreenKind.inventory);
  }

  /// Enchanting: one level and two magic dust buy a random +1..+3 on the held weapon or tool.
  void enchantHeld() {
    final item = player.heldItem();
    if (item == '' || (Items.kind(item) != ItemKind.weapon && Items.kind(item) != ItemKind.tool)) {
      notify('Hold a weapon or tool to enchant it');
      return;
    }
    if (player.level < 2) {
      notify('Need level 2 to enchant');
      return;
    }
    if (player.inventory.countOf('magic_dust') < 2) {
      notify('Need 2 Magic Dust');
      return;
    }
    player.inventory.remove('magic_dust', 2);
    player.level -= 1;
    final bonus = player.inventory.bonusAt(player.selectedSlot) + 1 + random.nextInt(3);
    player.inventory.slots[player.selectedSlot]!.bonus = bonus;
    player.inventory.emitChanged();
    spawnEffect(player.centre() + Vector3(0, 0.8, 0), Vector3(0.7, 0.4, 1.0), 2.0);
    Sfx.play('bolt', -6.0);
    notify('${Items.displayName(item)} is now +$bonus');
  }

  void spawnProjectile(Vector3 from, Vector3 vel, double dmg, Object? owner, String kind,
      [double radius = 0.1, double knockback = 5.0]) {
    final net = Net.instance;
    if (net.isClient && identical(owner, player)) {
      // The host owns the hit; what flies here is only a picture of the shot.
      spawnReplica(from, vel, kind, radius);
      net.requestFire(from, vel, dmg, kind, radius, knockback);
      return;
    }
    final p = Projectile();
    p.setupProjectile(world, this, from, vel, dmg, owner, kind, radius, knockback);
    projectiles.add(p);
    entities.add(p.node);
    net.broadcastReplica(from, vel, kind, radius);
  }

  void meleeStrike(Vector3 dir, double dmg, double followUp, Target attacker) {
    // A swing is a segment of meleeReach from the attacker's own centre along
    // its facing; the nearest body on it takes the hit, block or creature.
    // Runs on whoever owns the simulation, never on a camera cache.
    final net = Net.instance;
    if (net.isClient && identical(attacker, player)) {
      net.requestMelee(dir, dmg, followUp);
      return;
    }
    final origin = attacker.centre();
    if (net.isHost && !identical(attacker, player) && attacker is RemotePlayer) {
      debugPrint('[net] melee strike resolved for peer ${attacker.peerId}');
    }
    // Reach: the swing stops at the first thing that stops a body, so a
    // creature behind a wall is not hit through it. Grass and the gap between
    // two fence posts are not in the way — a body walks through them.
    final best = Reach.nearestBody(mobs, origin, dir,
        maxDist: Player.meleeReach,
        blockedAt: Reach.toBarrier(world, origin, dir, Player.meleeReach),
        inflate: 0.15);
    if (best == null) return;
    Sfx.play('hit', -4.0);
    // Stage 32: one melee hit in ten is a critical for x1.5, shown as "-N!" in yellow.
    final crit = rollCrit();
    if (crit) dmg = (dmg * critMult).roundToDouble();
    best.takeDamage(dmg, attacker.position, Mob.knockbackSpeed, attacker);
    spawnDamageNumber(best.centre(), dmg, Vector3(1, 0.95, 0.6), crit);
    if (followUp > 0.0) {
      best.takeDamage(followUp, attacker.position, Mob.knockbackSpeed * 0.5, attacker);
      spawnDamageNumber(best.centre() + Vector3(0, 0.3, 0), followUp, Vector3(1, 0.6, 0.3));
    }
  }

  /// Stage 32: the 10% critical roll every melee hit and arrow makes (counted
  /// for the probe).
  bool rollCrit() {
    if (!critsEnabled || !rollCritWith(random)) return false;
    crits += 1;
    return true;
  }

  static bool rollCritWith(math.Random rng) => rng.nextDouble() < critChance;

  /// Stage 32: the damage a hit deals after the roll.
  static double critDamage(double dmg, bool crit) => crit ? (dmg * critMult).roundToDouble() : dmg;

  List<Target> targets() {
    final out = <Target>[player];
    if (Net.instance.isHost) out.addAll(Net.instance.puppetBodies());
    return out;
  }

  void spawnReplica(Vector3 from, Vector3 vel, String kind, double radius) {
    final p = Projectile()..replica = true;
    p.setupProjectile(world, this, from, vel, 0.0, player, kind, radius, 0.0);
    projectiles.add(p);
    entities.add(p.node);
  }

  /// Stage 32: numbers read `-N`; a critical reads `-N!` in yellow.
  void spawnDamageNumber(Vector3 at, double amount, Vector3 color, [bool crit = false]) {
    Net.instance.broadcastDamageNumber(at, amount, color, crit);
    damageNumbersSpawned += 1;
    damageNumbers.add(DamageNumber(at + Vector3(random.nextDouble() * 0.6 - 0.3, 0.3, random.nextDouble() * 0.6 - 0.3),
        '-${amount.round()}${crit ? '!' : ''}', crit ? Vector3(1.0, 0.9, 0.2) : color, crit));
  }

  void spawnEffect(Vector3 at, Vector3 color, double radius) {
    final mat = UnlitMaterial()
      ..baseColorFactor = Vector4(color.x, color.y, color.z, 0.55)
      ..alphaMode = AlphaMode.blend;
    final node = MirroredCamera.primitiveNode(Mesh(SphereGeometry(radius: 0.5), mat), castsShadows: false)..position = at.clone();
    entities.add(node);
    _effects.add(_Effect(node, mat, radius, color));
  }

  /// Stage 32: [count] small cubes of [color] burst out of [at] (12 for a broken
  /// block, 2 per mining tick, 8 white ones for a spawn poof, 1 ember for a
  /// burning mob); [speed] scales the burst. One shared unit cube geometry,
  /// scaled per node (a geometry uploads at construction).
  void spawnDebris(Vector3 at, Vector3 color, [int count = 12, double speed = 1.0]) {
    debrisSpawned += count;
    final cube = _debrisCube ??= CuboidGeometry(Vector3(1, 1, 1));
    for (var i = 0; i < count; i++) {
      final size = 0.08 + random.nextDouble() * 0.08;
      final f = 0.8 + random.nextDouble() * 0.3;
      final mat = PhysicallyBasedMaterial()
        ..baseColorFactor = Vector4(color.x * f, color.y * f, color.z * f, 1)
        ..roughnessFactor = 1.0
        ..metallicFactor = 0.0;
      final node = MirroredCamera.primitiveNode(Mesh(cube, mat), castsShadows: false)
        ..position = at + Vector3(random.nextDouble() * 0.6 - 0.3, random.nextDouble() * 0.6 - 0.2, random.nextDouble() * 0.6 - 0.3)
        ..scale = Vector3(size, size, size);
      entities.add(node);
      _debris.add(_Debris(node, Vector3(random.nextDouble() * 4 - 2, 2 + random.nextDouble() * 2, random.nextDouble() * 4 - 2) * speed, size));
    }
  }

  /// Stage 32: the puff a mob appears in.
  void spawnPoof(Vector3 at) => spawnDebris(at, Vector3(0.92, 0.92, 0.9), 8, 0.5);

  /// Stage 32: debris cubes still in the air (the probe's count).
  int get debrisAlive => _debris.length;

  /// Stage 26: F on a villager opens its three offers (`TradeScreen`); F or
  /// Escape closes them.
  void trade(Mob villager) {
    if (screen != ScreenKind.none) {
      closeScreen();
      return;
    }
    tradeVillager = villager;
    openScreen(ScreenKind.trade);
  }

  /// The trade at row [i] of the open villager: a green flash and a notice on
  /// success, a red flash when the bag lacks it.
  bool tradeRow(int i) {
    final v = tradeVillager;
    if (v == null || v.removed || i < 0 || i >= v.trades.length) return false;
    final o = v.trades[i];
    final ok = v.tradeWith(player.inventory, i);
    tradeFlash[i] = ok;
    _tradeFlashT[i] = 0.5;
    if (ok) {
      notify('Traded ${o.takeCount} ${Items.displayName(o.take)} for ${o.giveCount} ${Items.displayName(o.give)}');
    } else {
      notify('Villager wants ${o.takeCount} ${Items.displayName(o.take)}');
    }
    return ok;
  }

  void _tickSpawners() {
    final here = VoxelWorld.chunkOf(IVec3.floor(player.position));
    for (final s in world.structuresNear(here)) {
      final candidates = <IVec3>[];
      if (s.type == 1) {
        for (var room = 0; room < 2; room++) {
          candidates.add(IVec3(s.x + room * 12, s.y + 1, s.z + 2));
        }
      } else if (s.type == TerrainGenerator.structMine) {
        // The mine corridor runs +x from the shaft, 20-30 long; the spawner
        // sits on its centre line.
        for (var x = s.x + 17; x < s.x + 31; x++) {
          candidates.add(IVec3(x, TerrainGenerator.mineFloorY + 1, s.z));
        }
      }
      for (final pos in candidates) {
        final id = world.getBlock(pos);
        if (id == Blocks.air || Blocks.idOf(id) != 'spawner') continue;
        if (pos.distanceTo(player.position) > 13.0) continue;
        var near = 0;
        for (final m in mobs) {
          if (pos.distanceTo(m.position) < 12.0) near++;
        }
        if (near >= 5 || random.nextDouble() < 0.4) continue;
        final pick = const ['zombie', 'skeleton', 'spider', 'cave_slime'][random.nextInt(4)];
        final mob = Mob();
        mob.setupMob(world, this, player, Species.def(pick));
        mob.position = pos.toVector3() + Vector3(random.nextDouble() * 4 - 2, 0.1, -1 - random.nextDouble() * 2);
        mob.scaleToLevel(player.level + 1);
        addMob(mob);
        spawnEffect(mob.centre(), Vector3(0.6, 0.2, 0.9), 1.2);
      }
    }
  }

  void _trackBoss() {
    final b = boss;
    if (b != null && !b.removed && b.state != MobState.dead && (b.position - player.position).length < 40.0) return;
    boss = null;
    for (final mob in mobs) {
      if (mob.isBoss && (mob.position - player.position).length < 30.0) {
        boss = mob;
        notify('A ${mob.species.name} approaches!');
        return;
      }
    }
  }

  /// Blows a hole: blocks inside the radius go (bedrock and chests stay), a
  /// third drop items, and every body nearby takes damage falling off with
  /// distance.
  void explode(Vector3 at, double radius, double damage, Object? source) {
    Sfx.play('bolt', 2.0, 0.5);
    spawnEffect(at, Vector3(1, 0.6, 0.2), radius * 1.6);
    final r = radius.ceil();
    final centre = IVec3.floor(at);
    final chained = <IVec3>[];
    for (var dx = -r; dx <= r; dx++) {
      for (var dy = -r; dy <= r; dy++) {
        for (var dz = -r; dz <= r; dz++) {
          final p = centre + IVec3(dx, dy, dz);
          if (math.sqrt(dx * dx + dy * dy + dz * dz) > radius + random.nextDouble() * 0.5) continue;
          final id = world.getBlock(p);
          if (id == Blocks.air || Blocks.hardness(id) < 0.0 || Blocks.idOf(id) == 'chest') continue;
          if (Blocks.idOf(id) == 'tnt') {
            world.setBlock(p, Blocks.air);
            chained.add(p);
            continue;
          }
          world.setBlock(p, Blocks.air);
          if (random.nextDouble() < 0.3 && Blocks.dropOf(id) != '') spawnDrop(p.centre, Blocks.dropOf(id), 1);
        }
      }
    }
    for (final m in List.of(mobs)) {
      if (identical(m, source)) continue;
      final d = (m.centre() - at).length;
      if (d < radius * 2.0) {
        final dmg = damage * (1.0 - d / (radius * 2.0));
        m.takeDamage(dmg, at, 8.0, source);
        spawnDamageNumber(m.centre(), dmg, Vector3(1, 0.5, 0.2));
      }
    }
    final pd = (player.centre() - at).length;
    if (pd < radius * 2.0) player.takeDamage(damage * (1.0 - pd / (radius * 2.0)), 'explosion', at);
    for (final p in chained) {
      Future<void>.delayed(Duration.zero, () => explode(p.centre, radius, damage, source));
    }
  }

  void igniteTnt(IVec3 at) {
    world.setBlock(at, Blocks.air);
    final c = Blocks.def(Blocks.indexOf('tnt'));
    final mat = UnlitMaterial()..baseColorFactor = Vector4(c.r, c.g, c.b, 1);
    final node = MirroredCamera.primitiveNode(Mesh(CuboidGeometry(Vector3(1, 1, 1)), mat))..position = at.centre;
    entities.add(node);
    _tnts.add(_Tnt(node, mat, at));
    Sfx.play('dig', -6.0, 1.5);
  }

  /// Stage 23: TNT blocks lit and not yet exploded.
  int litTntCount() => _tnts.length;

  /// Probes only: put every lit TNT back unexploded, so a trap can be shown
  /// after it fired.
  void probeDefuseTnt() {
    for (final t in _tnts) {
      entities.remove(t.node);
      world.setBlock(t.at, Blocks.indexOf('tnt'));
    }
    _tnts.clear();
    _platesFired.clear();
  }

  /// A weapon with a random bonus: rarity from the bonus size.
  Loot randomLootWeapon(math.Random rng, [int minBonus = 1]) {
    const pool = ['stone_sword', 'iron_sword', 'iron_dagger', 'bow', 'longbow', 'staff', 'diamond_sword', 'crystal_staff'];
    final id = pool[rng.nextInt(pool.length)];
    final bonus = minBonus + rng.nextInt(6 - minBonus + 1);
    return Loot(id, bonus);
  }

  void _growCrops() {
    final now = GameState.instance.playTime;
    for (final pos in crops.keys.toList()) {
      final id = world.getBlock(pos);
      final name = id != Blocks.air ? Blocks.idOf(id) : '';
      if (!name.startsWith('wheat_')) {
        crops.remove(pos);
        continue;
      }
      final stage = int.parse(name.substring(6));
      if (stage >= 2) {
        crops.remove(pos);
        continue;
      }
      final lit = world.groundHeight(pos.x, pos.z) <= pos.y + 1;
      final need = lit ? 45.0 : 90.0;
      if (now - crops[pos]! > need) {
        world.setBlock(pos, Blocks.indexOf('wheat_${stage + 1}'));
        crops[pos] = now;
      }
    }
  }

  void plantCrop(IVec3 pos) => crops[pos] = GameState.instance.playTime;

  /// Sand and gravel above a removed block fall until they land.
  void _settleFalling(IVec3 above) {
    final id = world.getBlock(above);
    if (id == Blocks.air) return;
    final name = Blocks.idOf(id);
    if (name != 'sand' && name != 'gravel') return;
    var target = above;
    while (target.y > 1 && Blocks.isReplaceable(world.getBlock(target + IVec3.down))) {
      target = target + IVec3.down;
    }
    if (target != above) {
      world.setBlock(above, Blocks.air);
      world.setBlock(target, id);
      _settleFalling(above + IVec3.up);
    }
  }

  void sleepInBed(IVec3 at) {
    if (world.dimension == VoxelWorld.dimUnderworld) {
      notify('You cannot sleep in the underworld'); // stage 29
      return;
    }
    player.spawnPoint = at.toVector3() + Vector3(0.5, 1.2, 0.5);
    if (isNight) {
      player.position = at.toVector3() + Vector3(0.5, 1.0, 0.5);
      player.startSleep();
      _sleepFrom = timeOfDay;
      _sleepTo = timeOfDay > 0.5 ? 1.26 : 0.26;
      _sleepT = 0.0;
      notify('You sleep until morning. Spawn point set.');
      Achievements.instance.unlock('sleeper');
      Tutorial.instance.event('sleep');
      for (final m in mobs) {
        if (m.species.hostile && (m.position - player.position).length < 30.0) m.removed = true;
      }
    } else {
      notify('Spawn point set. You can only sleep at night.');
    }
    saveGame();
  }

  void onBlockBroken(IVec3 b, int id) {
    Tutorial.instance.event('break');
    Achievements.instance.unlock('first_block');
    if (Blocks.idOf(id) == 'waypoint') waypoints.remove(b);
    GameState.instance.blocksMined += 1;
    _settleFalling(b + IVec3.up);
    for (final side in IVec3.sides) {
      final n = b + side;
      final nid = Blocks.idOf(world.getBlock(n));
      if (nid == 'wall_torch' && !_hasOpaqueSide(n)) {
        world.setBlock(n, Blocks.air);
        spawnDrop(n.toVector3() + Vector3(0.5, 0.4, 0.5), 'torch', 1);
      }
    }
    if (Blocks.idOf(id).startsWith('door_')) {
      for (final other in [b + IVec3.up, b + IVec3.down]) {
        if (Blocks.idOf(world.getBlock(other)).startsWith('door_')) world.setBlock(other, Blocks.air);
      }
    }
    final c = Blocks.def(id);
    spawnDebris(b.centre, Vector3(c.r, c.g, c.b), 12);
    lastBreakFamily = Blocks.materialFamily(id); // stage 32: the family's voice
    Sfx.play('break_$lastBreakFamily', -6.0);
    if (Blocks.isRail(id)) Rails.removed(world, b); // stage 28: the neighbours no longer turn toward this cell
    if (Blocks.idOf(id) == 'chest' && chests.containsKey(b)) {
      final inv = chests.remove(b)!;
      for (final s in inv.slots) {
        if (s != null) spawnDrop(b.centre, s.id, s.count);
      }
    }
  }

  void onBlockPlaced(IVec3 b, int id) {
    Tutorial.instance.event('place');
    if (GameState.instance.blocksPlaced >= 99) Achievements.instance.unlock('builder');
    if (Blocks.idOf(id) == 'waypoint') {
      waypoints[b] = 'Waypoint ${waypoints.length + 1}';
      notify('${waypoints[b]} set. Right click it to travel (J lists them)');
    }
    GameState.instance.blocksPlaced += 1;
    Sfx.play('place_${Blocks.materialFamily(id)}', -8.0);
    if (Blocks.idOf(id) == 'chest') GameState.instance.placedChests.add(b.key);
  }

  // --- persistence -------------------------------------------------------------------

  Future<void> saveGame() async {
    try {
      await Directory(saveDir).create(recursive: true);
      await world.saveEdits('$saveDir/blocks.bin');
      final data = {
        'player': player.toJson(),
        'time': timeOfDay,
        'seed': world.seedValue,
        'dimension': world.dimension, // stage 29
        'crops': {for (final e in crops.entries) e.key.key: e.value},
        'stats': GameState.instance.toJson(),
        'chests': {for (final e in chests.entries) e.key.key: e.value.toJson()},
        'bosses': [for (final k in _bossesSpawned) k.key],
        'quests': quests.toJson(),
        'waypoints': {for (final e in waypoints.entries) e.key.key: e.value},
        // Stage 24: boats, tamed mobs (the mount by its index), dropped items,
        // the explored map.
        ...entityData(),
        if (playground != null) 'playground': playground!.toJson(), // stage 33
      };
      await File('$saveDir/player.json').writeAsString(jsonEncode(data), flush: true);
    } catch (e) {
      debugPrint('[save] failed: $e');
    }
  }

  /// Stage 24: the save keys Godot added — `boats`, `pets`, `mount`, `drops`,
  /// `visited`, `structures`.
  Map<String, Object> entityData() {
    final petData = <Map<String, Object>>[];
    var mountIndex = -1;
    for (final m in pets) {
      if (m.puppet || !m.tamed || m.isDead || m.removed) continue;
      if (identical(m, player.mount)) mountIndex = petData.length;
      petData.add(_withDim(m, m.toJson()));
    }
    // Stage 26: a villager is not tamed but never despawns, so it rides the save
    // like a pet.
    for (final m in mobs) {
      if (!m.puppet && m.species.persistent && !m.isDead && !m.removed) petData.add(_withDim(m, m.toJson()));
    }
    return {
      'boats': [for (final b in boats) if (!b.removed && !b.replica) _withDim(b, b.toJson())],
      'carts': [for (final c in carts) if (!c.removed && !c.replica) _withDim(c, c.toJson())], // stage 28
      'pets': petData,
      'mount': mountIndex,
      'drops': [for (final d in drops) if (!d.replica && !d.removed) _withDim(d, d.toJson())],
      'visited': encodeVisited(visitedChunks),
      'structures': encodeStructures(discoveredStructures),
    };
  }

  static List<String> encodeVisited(Set<ChunkPos> chunks) => [for (final c in chunks) '${c.x},${c.z}'];

  static Set<ChunkPos> decodeVisited(List<dynamic> keys) {
    final out = <ChunkPos>{};
    for (final k in keys) {
      final parts = k.toString().split(',');
      out.add((x: int.parse(parts[0]), z: int.parse(parts[1])));
    }
    return out;
  }

  static Map<String, int> encodeStructures(Map<IVec3, int> found) => {for (final e in found.entries) e.key.key: e.value};

  static Map<IVec3, int> decodeStructures(Map<String, dynamic> data) {
    final out = <IVec3, int>{};
    for (final e in data.entries) {
      out[IVec3.parse(e.key)] = (e.value as num).toInt();
    }
    return out;
  }

  Future<bool> _loadGame() async {
    final f = File('$saveDir/player.json');
    if ((_hasArg('--new') || GameState.instance.freshWorld) && !_stage24Verify && _stage27Site == null && _stage28Site == null && _stage29Site == null && _stage30Saved == null) {
      return false;
    }
    if (!await f.exists()) return false;
    final data = jsonDecode(await f.readAsString());
    if (data is! Map<String, dynamic>) return false;
    // The seed is the world: a save made under another seed wins over the
    // menu's default (an explicit --seed= still overrides, for the probes).
    final savedSeed = (data['seed'] as num?)?.toInt();
    if (_arg('--seed=', '') == '' && savedSeed != null && savedSeed != world.seedValue) {
      await world.setWorldSeed(savedSeed);
    }
    // Stage 29: the dimension comes first, so the live edit delta is the right one.
    final savedDim = (data['dimension'] as num?)?.toInt() ?? 0;
    if (savedDim != world.dimension) world.switchDimension(savedDim);
    await world.loadEdits('$saveDir/blocks.bin');
    timeOfDay = (data['time'] as num?)?.toDouble() ?? 0.3;
    _playgroundSave = data['playground'] as Map<String, dynamic>?; // stage 33
    GameState.instance.fromJson((data['stats'] as Map<String, dynamic>?) ?? {});
    player.fromJson(data['player'] as Map<String, dynamic>);
    quests.fromJson((data['quests'] as Map<String, dynamic>?) ?? {});
    for (final e in ((data['crops'] as Map<String, dynamic>?) ?? {}).entries) {
      crops[IVec3.parse(e.key)] = (e.value as num).toDouble();
    }
    for (final e in ((data['chests'] as Map<String, dynamic>?) ?? {}).entries) {
      chests[IVec3.parse(e.key)] = Inventory()..fromJson(e.value as List<dynamic>);
    }
    for (final e in ((data['waypoints'] as Map<String, dynamic>?) ?? {}).entries) {
      waypoints[IVec3.parse(e.key)] = e.value.toString();
    }
    for (final k in (data['bosses'] as List<dynamic>? ?? const [])) {
      _bossesSpawned.add(IVec3.parse(k.toString()));
    }
    // Stage 24: the entities and the explored map.
    visitedChunks.addAll(decodeVisited(data['visited'] as List<dynamic>? ?? const []));
    discoveredStructures.addAll(decodeStructures(data['structures'] as Map<String, dynamic>? ?? const {}));
    for (final b in (data['boats'] as List<dynamic>? ?? const [])) {
      final bd = b as Map<String, dynamic>;
      final p = (bd['pos'] as List<dynamic>).map((e) => (e as num).toDouble()).toList();
      spawnBoat(Vector3(p[0], p[1], p[2]), (bd['yaw'] as num?)?.toDouble() ?? 0.0);
      if (boats.isNotEmpty) _tagEntity(boats.last, (bd['dim'] as num?)?.toInt() ?? 0);
    }
    for (final cd in (data['carts'] as List<dynamic>? ?? const [])) {
      // Stage 28: the cart, its ends, `t`, speed and cargo.
      final d = cd as Map<String, dynamic>;
      final c = (d['cell'] as List<dynamic>).map((e) => (e as num).toInt()).toList();
      final cart = spawnMinecart(IVec3(c[0], c[1], c[2]), d['kind']?.toString() ?? 'minecart');
      cart?.fromJson(d);
      if (cart != null) _tagEntity(cart, (d['dim'] as num?)?.toInt() ?? 0);
    }
    final restored = <Mob>[];
    for (final pd in (data['pets'] as List<dynamic>? ?? const [])) {
      final d = pd as Map<String, dynamic>;
      if (!Species.defs.containsKey(d['species'].toString())) continue;
      final m = Mob();
      m.setupMob(world, this, player, Species.def(d['species'].toString()));
      m.fromJson(d);
      _tagEntity(m, (d['dim'] as num?)?.toInt() ?? 0);
      if (m.tamed) {
        pets.add(m);
        entities.add(m.node);
      } else {
        addMob(m);
      }
      restored.add(m);
    }
    final mountIndex = (data['mount'] as num?)?.toInt() ?? -1;
    if (mountIndex >= 0 && mountIndex < restored.length && restored[mountIndex].isMount && restored[mountIndex].tamed) {
      player.mountHorse(restored[mountIndex]);
    }
    for (final dd in (data['drops'] as List<dynamic>? ?? const [])) {
      final d = dd as Map<String, dynamic>;
      final p = (d['pos'] as List<dynamic>).map((e) => (e as num).toDouble()).toList();
      final drop = ItemDrop();
      drop.setupDrop(world, d['item'].toString(), (d['count'] as num?)?.toInt() ?? 1, player);
      drop.position = Vector3(p[0], p[1], p[2]);
      drop.bonus = (d['bonus'] as num?)?.toInt() ?? 0;
      drop.syncNode();
      _tagEntity(drop, (d['dim'] as num?)?.toInt() ?? 0);
      drops.add(drop);
      entities.add(drop.node);
      Net.instance.onDropSpawned(drop);
    }
    return true;
  }

  // --- the screenshot probe --------------------------------------------------------------

  Future<void> _runScreenshot(String path, int frames) async {
    final stage21a = _hasArg('--stage21a')
        ? _probeStage21aTeleport()
        // The temple: seed 42's nearest is past 24 chunks.
        : (_hasArg('--stage23') ? _probeStage21aTeleport(48) : null);
    final shot26 = _hasArg('--stage26') ? _arg('--shot=', '') : '';
    if (shot26 != '') _stage26ShotPrepare(shot26);
    final t0 = DateTime.now();
    for (var i = 0; i < frames; i++) {
      await nextFrame();
      if (i % 40 == 0 && _hasArg('--trace')) {
        debugPrint('[trace] f$i pos ${player.position} vel ${player.velocity} floor ${player.onFloor}');
      }
      if (i > 10 && world.isIdle) break;
    }
    debugPrint('[probe] window filled: ${world.loadedChunkCount} chunks, ${world.facesEmitted} faces in ${DateTime.now().difference(t0).inMilliseconds} ms');
    final net = Net.instance;
    if (net.mode != NetMode.solo) debugPrint('[probe] net mode ${net.mode} puppets ${net.puppetPositions()}');
    debugPrint('[probe] camera at ${player.cameraPosition} distance ${player.camDistance.toStringAsFixed(2)} yaw ${player.yaw.toStringAsFixed(2)} pitch ${player.pitch.toStringAsFixed(2)}');
    debugPrint('[probe] player at ${player.position} structures near: ${world.structuresNear(VoxelWorld.chunkOf(IVec3.floor(player.position)))}');
    if (stage21a != null) {
      // The chunks are in now: stand exactly where the probe chose, with a
      // pocket of air behind the player for the orbit camera (the mine's
      // corridor is its own pocket).
      final at = stage21a.at;
      if (stage21a.kind != TerrainGenerator.structMine) {
        for (var dx = -2; dx < 3; dx++) {
          for (var dz = -3; dz < 8; dz++) {
            for (var dy = 0; dy < 6; dy++) {
              world.setBlock(IVec3(at.x.floor() + dx, at.y.floor() + dy, at.z.floor() + dz), Blocks.air);
            }
          }
        }
      }
      player.position = at.clone();
      player.velocity = Vector3.zero();
      player.syncNode();
    }
    if (_hasArg('--stage21a')) {
      final counts = <int, int>{};
      final seen = <IVec3>{};
      for (final pos in world.chunks.keys) {
        for (final st in world.structuresNear(pos)) {
          final key = IVec3(st.x, st.y, st.z);
          if (!seen.add(key)) continue;
          counts[st.type] = (counts[st.type] ?? 0) + 1;
        }
      }
      debugPrint('[probe] stage21a: structures by kind $counts');
    }
    if (shot26 != '') await _stage26ShotFinish(shot26);
    if (_hasArg('--map')) mapView = MapView.corner;
    if (_hasArg('--open-map')) mapView = MapView.full;
    if (_hasArg('--open-settings')) openScreen(ScreenKind.pause);
    if (_arg('--journal=', '') != '') openJournal(int.tryParse(_arg('--journal=', '')) ?? 0);
    if (_hasArg('--open-inventory')) openStation('crafting_table', IVec3.zero);
    final fire = _arg('--fire=', '');
    if (_hasArg('--stage16')) {
      final b = IVec3.floor(player.position) + const IVec3(0, 0, -3);
      world.setBlock(b + const IVec3(-1, 0, 0), Blocks.indexOf('oak_planks'));
      world.setBlock(b + const IVec3(-1, 1, 0), Blocks.indexOf('oak_planks'));
      world.setBlock(b + const IVec3(1, 0, 0), Blocks.indexOf('oak_planks'));
      world.setBlock(b + const IVec3(1, 1, 0), Blocks.indexOf('oak_planks'));
      world.setBlock(b, Blocks.indexOf('door_z'));
      world.setBlock(b + IVec3.up, Blocks.indexOf('door_z'));
      world.setBlock(b + const IVec3(2, 1, 0), Blocks.indexOf('wall_torch'));
      world.setBlock(b + const IVec3(3, 0, 0), Blocks.indexOf('enchanting_table'));
      spawnBoat(b.toVector3() + Vector3(-3.5, 0.6, 2.5), 0.4);
    }
    // --stage19: a row of slabs, three fences in a line, and two stairs three
    // blocks ahead.
    final stage19FacesBefore = world.facesEmitted;
    var stage19Placed = 0;
    if (_hasArg('--stage19')) {
      // The player looks north (-Z); the row sits one block below eye level,
      // shifted right so the block on the left of the spawn does not hide it.
      final b = IVec3.floor(player.position) + const IVec3(3, -1, -3);
      final stairs = Blocks.stairsFacing(Blocks.indexOf('oak_stairs_n'), 0, -1);
      final stoneStairs = Blocks.stairsFacing(Blocks.indexOf('stone_stairs_n'), 0, -1);
      final row = [
        b + const IVec3(-3, 0, 0), b + const IVec3(-2, 0, 0), b + const IVec3(-1, 0, 0), b,
        b + const IVec3(1, 0, 0), b + const IVec3(2, 0, 0), b + const IVec3(3, 0, 0),
      ];
      final ids = [
        Blocks.indexOf('oak_slab'), Blocks.indexOf('stone_slab'), Blocks.indexOf('oak_fence'),
        Blocks.indexOf('oak_fence'), Blocks.indexOf('oak_fence'), stairs, stoneStairs,
      ];
      for (var i = 0; i < row.length; i++) {
        for (var dz = -1; dz < 3; dz++) {
          for (var dy = 0; dy < 4; dy++) {
            world.setBlock(row[i] + IVec3(0, dy, dz), Blocks.air); // clear the view
          }
        }
        // Contrasts with every block in the row.
        world.setBlock(row[i] + IVec3.down, Blocks.indexOf('dark_stone'));
        if (world.setBlock(row[i], ids[i])) stage19Placed += 1;
      }
    }
    Mob? dummy;
    if (_hasArg('--strike') && !net.isClient) {
      // The row reads 18 -> 8: one plain swing of 10. Since stage 32 a zombie
      // burns in daylight (0.5 per half second before the swing) and one hit in
      // ten is a critical, so the probe runs at night unless --time= is given
      // and rolls no critical. Godot's probe has both latent flakes.
      if (_arg('--time=', '') == '') {
        timeOfDay = 0.0;
        _updateSky();
      }
      critsEnabled = false;
      dummy = Mob();
      dummy.setupMob(world, this, player, Species.def('zombie'));
      final ahead = player.aimDirection().clone()..y = 0;
      dummy.position = player.position + ahead.normalized() * 2.2;
      addMob(dummy);
    }
    final elite = _hasArg('--stage18') ? _probeStage18() : null;
    final stage20 = _hasArg('--stage20') ? _probeStage20() : null;
    var rideFrom = Vector3.zero();
    final settle = int.tryParse(_arg('--settle=', '')) ?? 30;
    // The mean over the whole settle window: `fps` is the last half second only, too noisy
    // for a perf gate (VP3.0 in docs/VOXEL_PACKAGES_PLAN_2026-09-14.md).
    final settleWatch = Stopwatch()..start();
    for (var i = 0; i < settle; i++) {
      await nextFrame();
      // --ride (with --stage20): hold W and sprint for ten frames and measure
      // how far the horse went.
      if (stage20 != null && _hasArg('--ride') && i == 3) {
        rideFrom = stage20.horse.position.clone();
        input.probeHold(GameAction.moveForward, true);
        input.probeHold(GameAction.sprint, true);
      }
      if (stage20 != null && _hasArg('--ride') && i == 13) {
        input.probeHold(GameAction.moveForward, false);
        input.probeHold(GameAction.sprint, false);
        debugPrint('[probe] stage20: rode ${(stage20.horse.position - rideFrom).length.toStringAsFixed(2)} m in ten '
            'frames, horse velocity ${stage20.horse.velocity}, rider at ${player.position}');
      }
      if (elite != null && i == 5) player.probeDodge();
      if (elite != null && i == 6) {
        debugPrint('[probe] stage18: dodging ${player.isDodging()}, invulnerable ${player.invulnerable}, from ${player.position}');
      }
      if (fire != '' && i % 6 == 0 && i >= 6) player.probeFire(fire == 'secondary');
      if (dummy != null && i == 12) {
        debugPrint('[probe] strike: zombie hp ${dummy.hp.toStringAsFixed(1)} before, ray ${dummy.rayDistance(player.centre(), player.aimDirection(), 0.15).toStringAsFixed(2)} m from the player\'s centre');
        player.probeStrike();
      }
    }
    settleWatch.stop();
    debugPrint('[probe] settle fps ${(settle * 1e6 / settleWatch.elapsedMicroseconds).toStringAsFixed(1)} over $settle frames');
    if (dummy != null) debugPrint('[probe] strike: zombie hp ${dummy.hp.toStringAsFixed(1)} after');
    if (_hasArg('--stage19')) {
      debugPrint('[probe] stage19: placed $stage19Placed blocks, faces before/after '
          '$stage19FacesBefore/${world.facesEmitted}');
    }
    if (stage20 != null) {
      debugPrint('[probe] stage20: wool in inventory ${player.inventory.countOf('wool')} (dropped ${stage20.wool})');
      debugPrint('[probe] stage20: capture mounted ${player.isMounted()} at ${player.position} '
          '(horse at ${stage20.horse.position}), bobber out ${player.bobber != null} '
          'landed ${player.bobber?.landed ?? false}');
    }
    if (elite != null) {
      final ach = Achievements.instance;
      debugPrint('[probe] stage18: effects ${player.effects.rows.keys.toList()}');
      debugPrint('[probe] stage18: elite \'${elite.displayName()}\' hp ${elite.maxHp.toStringAsFixed(0)} '
          'speed x${elite.speedMult.toStringAsFixed(1)}, talents ${player.talents}, points left ${player.talentPoints}');
      debugPrint('[probe] stage18: weather ${weather.label} intensity ${weather.intensity.toStringAsFixed(2)} '
          'darken ${weather.darken().toStringAsFixed(2)}');
      debugPrint('[probe] stage18: waypoints ${waypoints.length}, player at ${player.position}, '
          'achievements ${ach.count}: ${ach.unlocked.toList()}');
    }
    if (_hasArg('--wait-peer')) {
      final t1 = DateTime.now();
      while (net.puppetPositions().isEmpty && DateTime.now().difference(t1).inMilliseconds < 40000) {
        await nextFrame();
      }
      if (net.puppetPositions().isNotEmpty) {
        final z = Mob();
        z.setupMob(world, this, player, Species.def('zombie'));
        z.position = net.puppetPositions()[0].$2 + Vector3(2.5, 0, 0);
        addMob(z);
        for (var i = 0; i < 90; i++) {
          await nextFrame();
        }
        debugPrint('[probe] zombie beside the puppet: hp ${z.hp.toStringAsFixed(1)} after the peer\'s swing');
      }
      if (_hasArg('--strike') && net.isClient) {
        for (var i = 0; i < 30; i++) {
          await nextFrame();
        }
        debugPrint('[probe] strike sent to the host, aim ${player.aimDirection()}');
        player.probeStrike();
        for (var i = 0; i < 60; i++) {
          await nextFrame();
        }
      }
      var hunting = 0;
      for (final m in mobs) {
        if (m.huntsPuppet()) hunting++;
      }
      debugPrint('[probe] net mode ${net.mode} puppets ${net.puppetPositions()}, mobs hunting a puppet: $hunting, edits ${world.editCount}');
    }
    // --stage21b (with --wait-peer): drops, chests, weather and mounts across the
    // wire. The host pre-fills a chest, forces a storm, mounts a horse and drops
    // an item beside the client's puppet; the client reports what reached it and
    // reads the host's chest.
    const chestAt = IVec3(7, 77, 7);
    if (_hasArg('--stage21b') && net.isHost && net.puppetPositions().isNotEmpty) {
      final chestInv = chestInventory(chestAt);
      chestInv.fromJson(const []);
      chestInv.add('apple', 3);
      weather.force('storm');
      // A flat 7x7 stone pad 4 m east so the horse stands where the client's
      // camera can see it.
      final pad = IVec3.floor(player.position + Vector3(4.0, 0.0, 0.0));
      for (var dx = -3; dx < 4; dx++) {
        for (var dz = -3; dz < 4; dz++) {
          world.setBlock(pad + IVec3(dx, -1, dz), Blocks.indexOf('stone'));
          for (var dy = 0; dy < 6; dy++) {
            world.setBlock(pad + IVec3(dx, dy, dz), Blocks.air);
          }
        }
      }
      final horse = Mob();
      horse.setupMob(world, this, player, Species.def('horse'));
      horse.position = pad.toVector3() + Vector3(0.5, 0.5, 0.5);
      addMob(horse);
      horse.tame(player);
      player.mountHorse(horse);
      debugPrint('[probe] stage21b: host forced weather ${weather.label}, chest $chestAt holds '
          '${chestInv.toJson().first}, riding ${player.isMounted()} (riddenBy ${horse.riddenBy})');
      // One metre east of the puppet, on a block laid there so the drop cannot
      // fall into a hole.
      final ppos = net.puppetPositions().first.$2;
      final under = IVec3(ppos.x.floor() + 1, ppos.y.floor() - 1, ppos.z.floor());
      world.setBlock(under, Blocks.indexOf('stone'));
      world.setBlock(under + IVec3.up, Blocks.air);
      spawnDrop(ppos + Vector3(1.0, 0.4, 0.0), 'iron_ingot', 2, Vector3(0, 0.5, 0));
      // A spider bites the puppet once through the simulation: the poison must
      // reach the peer.
      final spider = Mob();
      spider.setupMob(world, this, player, Species.def('spider'));
      spider.position = ppos + Vector3(-2.0, 0.5, 0.0);
      addMob(spider);
      spider.hurtTarget(net.puppetBodies().first, 1.0);
      debugPrint('[probe] stage21b: spider bit the puppet (effect ${spider.species.effect})');
      final t2 = DateTime.now();
      while (net.lastGive == null && DateTime.now().difference(t2).inMilliseconds < 15000) {
        await nextFrame();
      }
      final give = net.lastGive;
      debugPrint('[probe] stage21b: client picked up ${give == null ? 'nothing' : '${give.$2} x${give.$3}'}');
      final t3 = DateTime.now();
      while (net.puppetPositions().isNotEmpty && DateTime.now().difference(t3).inMilliseconds < 12000) {
        await nextFrame();
      }
      debugPrint('[probe] stage21b: host rider at ${player.position}, horse at ${horse.position} '
          '(ridden ${horse.ridden} by ${horse.riddenBy})');
    }
    if (_hasArg('--stage21b') && net.isClient) {
      final t2 = DateTime.now();
      while (DateTime.now().difference(t2).inMilliseconds < 3000) {
        await nextFrame();
      }
      debugPrint('[probe] stage21b: client weather ${weather.label} (forced ${weather.forced}), '
          'iron_ingot in bag ${player.inventory.countOf('iron_ingot')}, drop replicas '
          '${net.dropReplicas.length}, effects ${player.effects.rows.keys.toList()}');
      final view = net.openChest(chestAt);
      final t3 = DateTime.now();
      while (view.countOf('apple') == 0 && DateTime.now().difference(t3).inMilliseconds < 5000) {
        await nextFrame();
      }
      debugPrint('[probe] stage21b: chest $chestAt from the host holds ${view.toJson().take(2).toList()}');
      net.closeChest(chestAt);
      var mounted = 0;
      for (final b in net.puppetBodies()) {
        if (b.mountedOn != null) mounted++;
      }
      debugPrint('[probe] stage21b: host puppets riding a horse puppet: $mounted');
      // Frame the host puppet for the capture: hover 3.5 m south of it in first
      // person, looking north.
      if (net.puppetBodies().isNotEmpty) {
        flyMode = true;
        player.setFirstPerson(true);
        player.setLook(0.0, -0.3);
        for (var i = 0; i < 20; i++) {
          player.position = net.puppetBodies().first.position + Vector3(0, 0.8, 3.5);
          player.velocity = Vector3.zero();
          player.syncNode();
          await nextFrame();
        }
        debugPrint('[probe] stage21b: capture from ${player.position}, '
            'host puppet at ${net.puppetBodies().first.position}');
        // The body keeps being swept out of whatever it stands in, so pin the
        // camera again on the frame that is actually captured.
        _pinCameraTo = () => net.puppetBodies().first.position + Vector3(0, 0.8, 3.5);
      }
    }
    if (_hasArg('--stage25') && net.isHost && net.puppetPositions().isNotEmpty) await _probeStage25Host();
    if (_hasArg('--stage25') && net.isClient) await _probeStage25Client();
    if (_hasArg('--stage22')) await _probeStage22();
    if (_hasArg('--move-probe')) await _probeMovement();
    if (_hasArg('--reach-probe')) await _probeReach();
    if (_hasArg('--touch-probe')) await _probeTouch();
    if (_hasArg('--map-probe')) await _probeMap();
    if (_hasArg('--model-probe')) await _probeModel();
    if (_hasArg('--anim-probe')) await _probeAnimation();
    if (_hasArg('--outline-probe')) await _probeOutline();
    if (_hasArg('--item-probe')) await _probeItems();
    if (_hasArg('--stage23')) await _probeStage23(stage21a);
    if (_hasArg('--stage26') && shot26 == '') await _probeStage26();
    if (_hasArg('--stage24')) {
      // The setup half saved and asked for a fresh session; the verify half
      // prints the rest and captures.
      if (await _probeStage24()) return;
    }
    if (_hasArg('--stage27')) {
      // Same two-boot shape: the circuit is built and saved, the reload reads it back.
      if (await _probeStage27()) return;
    }
    if (_hasArg('--stage28')) {
      // Two boots again: the track and the carts are saved, the reload reads them back.
      if (await _probeStage28()) return;
    }
    if (_hasArg('--stage29')) {
      // Two boots: the second reads the underworld save back.
      if (await _probeStage29()) return;
    }
    if (_hasArg('--stage30')) {
      // Two boots: the second reads the stats back.
      if (await _probeStage30()) return;
    }
    if (_hasArg('--stage31')) await _probeStage31();
    if (_hasArg('--stage32')) await _probeStage32();
    if (playground != null && _hasArg('--playground')) await _probePlayground();
    await nextFrame();
    await nextFrame();
    debugPrint('[probe] fps ${fps.toStringAsFixed(0)} mobs ${mobs.length} drops ${drops.length} projectiles ${projectiles.length}');
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    debugPrint('[probe] view ${view.physicalSize.width / view.devicePixelRatio}x${view.physicalSize.height / view.devicePixelRatio} logical @${view.devicePixelRatio}x');
    final pin = _pinCameraTo;
    if (pin != null) {
      player.position = pin();
      player.velocity = Vector3.zero();
      player.syncNode();
      await nextFrame();
    }
    // `--swing=<frames>` starts a swing and lets it run that many frames before
    // the capture, so a shot can catch the first-person hand mid-chop.
    final swingAt = int.tryParse(_arg('--swing=', ''));
    if (swingAt != null) {
      player.swingArm();
      for (var i = 0; i < swingAt; i++) {
        await nextFrame();
      }
    }
    final shot = screenshotter;
    if (shot != null) {
      await shot(path);
      debugPrint('[probe] screenshot saved to $path');
    } else {
      debugPrint('[probe] no screenshotter, nothing captured');
    }
    exit(0);
  }

  // --- stage 33: the playground ---------------------------------------------------------

  /// `--new --playground --screenshot=<png> [--shot=aerial|<zone id>|underwater|arena_inside|hall]`:
  /// waits for all nine exhibits, prints what they hold, and frames the shot.
  Future<void> _probePlayground() async {
    final pg = playground!;
    final t0 = DateTime.now();
    for (var i = 0; i < 3000 && pg.built.length < Playground.zones.length; i++) {
      await nextFrame();
    }
    for (var i = 0; i < 30 || (!world.isIdle && i < 1200); i++) {
      await nextFrame();
    }
    var exhibits = 0;
    for (final m in mobs) {
      if (m.exhibit != '') exhibits += 1;
    }
    final villagers = mobs.where((m) => m.species.persistent).length;
    debugPrint('[probe] playground: zones built=${pg.built.length}/${Playground.zones.length} in ${DateTime.now().difference(t0).inMilliseconds} ms, '
        'edits=${pg.edits} exhibit mobs=$exhibits villagers=$villagers pets=${pets.length} carts=${carts.length} boats=${boats.length} '
        'chests=${chests.length} waypoints=${waypoints.length} gallery=${Playground.galleryBlocks().length} library=${Playground.libraryItems().length}');
    debugPrint('[probe] playground tour: ${pg.tour.join(', ')}');
    debugPrint('[probe] playground kit: ${[for (var i = 0; i < 9; i++) player.inventory.idAt(i)].join(' ')} level=${player.level} creative=${GameState.instance.creative}');
    final hub = Playground.zone('hub');
    debugPrint('[probe] playground floor: surface=${world.surfaceHeight(hub.cx, hub.cz)} ground=${world.groundHeight(hub.cx + 20, hub.cz + 20)} '
        'biome=${world.biomeAt(hub.cx, hub.cz)} structures inside the plaza=${world.structuresNear(VoxelWorld.chunkOf(IVec3(hub.cx, 64, hub.cz))).where((st) => TerrainGenerator.inPlaza(st.x, st.z)).length}');
    if (_hasArg('--pg-checks')) await _playgroundChecks(pg);
    // `--shots=a,b,c`: one capture per shot beside the `--screenshot=` file
    // (`<name>_<shot>.png`) in the same run, then the main shot as usual.
    final shots = _arg('--shots=', '');
    final shoot = screenshotter;
    if (shots != '' && shoot != null) {
      final base = _arg('--screenshot=', '').replaceAll(RegExp(r'\.png$'), '');
      for (final name in shots.split(',')) {
        final v = _playgroundView(name);
        if (v == null) continue;
        await _playgroundFrame(v);
        await shoot('${base}_$name.png');
        debugPrint('[probe] playground capture $name from ${v.eye} -> ${base}_$name.png');
      }
    }
    final view = _playgroundView(_arg('--shot=', 'aerial'));
    if (view == null) return;
    await _playgroundFrame(view);
    _pinCameraTo = () => view.eye.clone();
    debugPrint('[probe] playground capture ${_arg('--shot=', 'aerial')} from ${view.eye}');
  }

  /// `--pg-checks`: the playground's interactive pieces, driven through the
  /// same calls the keys and the blocks use.
  Future<void> _playgroundChecks(Playground pg) async {
    const f = Playground.floor;
    String idAt(int x, int y, int z) => Blocks.idOf(world.getBlock(IVec3(x, y, z)));
    final b = Playground.zone('building');
    debugPrint('[probe] playground check shapes: step top ${idAt(b.cx + 14, f + 4, b.cz - 14)} half-step ${idAt(b.cx + 10, f + 2, b.cz - 14)} '
        'climb wall ${idAt(b.cx + 5, f + 2, b.cz + 4)} ladder ${idAt(b.cx + 13, f + 4, b.cz + 7)} roof ${idAt(b.cx - 14, f + 5, b.cz - 12)} '
        'iron door ${idAt(b.cx + 3, f, b.cz + 14)} stairs ${idAt(b.cx + 5, f + 4, b.cz - 14)}');
    flyMode = false;
    // A boss plate: one step summons, a second step while it lives does not.
    final arena = Playground.zone('arena');
    final plate = Playground.bossPlateCell(arena, 1);
    int trolls() => mobs.where((m) => m.species.id == 'troll' && m.exhibit == 'arena' && !m.removed).length;
    _probePlace(plate.toVector3() + Vector3(0.5, 0.6, 0.5));
    await _ticks(6);
    final first = trolls();
    _probePlace(plate.toVector3() + Vector3(0.5, 0.1, 3.5));
    await _ticks(3);
    _probePlace(plate.toVector3() + Vector3(0.5, 0.6, 0.5));
    await _ticks(6);
    debugPrint('[probe] playground check boss plate: troll summoned=$first, second step keeps ${trolls()}, boss bar ${boss?.species.id}');
    // The gold button refills what died.
    int arenaCount() => mobs.where((m) => m.exhibit == 'arena' && !m.removed && !m.isDead).length;
    final before = arenaCount();
    for (final m in mobs) {
      if (m.exhibit == 'arena' && m.species.id == 'zombie' && m.affix == '') m.removed = true;
    }
    await _ticks(2);
    final killed = arenaCount();
    final refill = Playground.arenaRefillCell(arena);
    world.circuits.useBlock(refill);
    await _ticks(4);
    debugPrint('[probe] playground check refill: arena $before -> one zombie gone $killed -> gold button ${arenaCount()} (button ${idAt(refill.x, refill.y, refill.z)})');
    // F7 / F8.
    pg.cycleWeather();
    final w1 = weather.label;
    pg.cycleTime();
    final t1 = timeOfDay;
    pg.cycleTime();
    debugPrint('[probe] playground check keys: F7 -> $w1, F8 -> ${t1.toStringAsFixed(2)} then ${timeOfDay.toStringAsFixed(2)}');
    weather.force('clear');
    timeOfDay = 0.3;
    // F9: a cottage wall plank broken, then the exhibit rebuilt.
    final wall = IVec3(b.cx - 17, f + 1, b.cz - 18);
    world.setBlock(wall, Blocks.air);
    _probePlace(Vector3(b.cx + 0.5, f + 0.1, b.cz + 0.5));
    await _ticks(3);
    final broken = idAt(wall.x, wall.y, wall.z);
    pg.rebuildHere();
    await _ticks(3);
    debugPrint('[probe] playground check F9: wall $broken -> ${idAt(wall.x, wall.y, wall.z)}, player moved to ${player.position}, zone ${pg.current?.id}');
    // The save carries the built zones and the flag.
    await saveGame();
    final saved = jsonDecode(File('$saveDir/player.json').readAsStringSync()) as Map<String, dynamic>;
    debugPrint('[probe] playground check save: built=${(saved['playground'] as Map<String, dynamic>)['built']} '
        'flag=${(saved['stats'] as Map<String, dynamic>)['playground']} waypoints=${(saved['waypoints'] as Map<String, dynamic>).length} '
        'pets=${(saved['pets'] as List<dynamic>).length} carts=${(saved['carts'] as List<dynamic>).length} boats=${(saved['boats'] as List<dynamic>).length}');
    _probePlace(Playground.spawn);
    await _ticks(2);
  }

  /// Hovers the first-person camera at [view]'s eye, looking at its target,
  /// until the chunks around it are meshed.
  Future<void> _playgroundFrame(({Vector3 eye, Vector3 target}) view) async {
    flyMode = true;
    player.setFirstPerson(true);
    final dir = view.target - view.eye;
    player.setLook(math.atan2(-dir.x, -dir.z), math.atan2(dir.y, math.sqrt(dir.x * dir.x + dir.z * dir.z)));
    world.updateAround(view.eye);
    for (var i = 0; i < 40 || (!world.isIdle && i < 1200); i++) {
      _probePlace(view.eye);
      await nextFrame();
    }
  }

  ({Vector3 eye, Vector3 target})? _playgroundView(String shot) {
    const f = Playground.floor;
    Vector3 c(String id) => Vector3(Playground.zone(id).cx.toDouble(), f.toDouble(), Playground.zone(id).cz.toDouble());
    switch (shot) {
      case 'aerial':
        return (eye: Vector3(8.0, f + 62.0, 118.0), target: Vector3(8.0, f.toDouble(), 4.0));
      case 'underwater':
        final w = c('water');
        return (eye: w + Vector3(-9.5, -3.0, 4.5), target: w + Vector3(-3.0, -5.5, -5.0));
      case 'arena_inside':
        final a = c('arena');
        return (eye: a + Vector3(0.5, 2.6, 11.0), target: a + Vector3(0.5, 0.8, -4.0));
      case 'hall':
        final h = c('caves');
        return (eye: h + Vector3(-6.5, 2.2, -5.0), target: h + Vector3(-6.5, 1.0, -15.0));
      case 'steps':
        final b = c('building');
        return (eye: b + Vector3(19.5, 7.0, -3.0), target: b + Vector3(11.0, 1.0, -13.0));
      case 'spawn':
        return null;
    }
    if (!Playground.zones.any((z) => z.id == shot)) return null;
    final z = c(shot);
    return (eye: z + Vector3(0.5, 17.0, 31.0), target: z + Vector3(0.5, 1.0, 0.0));
  }

  // --- stage 32: polish -----------------------------------------------------------------

  /// --stage32: the polish pass. A stone pad over the chunk east of spawn and the
  /// eight columns west of it (so a border runs through the pad): a torch 4 cells
  /// inside the east chunk must light the west chunk's cell 5 steps away (the
  /// seam stage 31 left open), a stunned zombie takes a swing (knockback, flash,
  /// the crit roll over 200 swings), a stone cell shows its cracks and breaks, a
  /// 5 m walk counts its footsteps, three zombies stand in the noon sun / under a
  /// roof / in a pool for the daylight rule, one dies for the fall-and-fade clock,
  /// and the HUD merges two apple toasts. `--shot=combat|mining` stages the two
  /// windowed captures. Waits count simulation ticks (gotcha 7).
  Future<void> _probeStage32() async {
    final sp = spawner!;
    spawner = null; // Godot: spawner.set_process(false)
    final here = VoxelWorld.chunkOf(IVec3.floor(player.position));
    final cpos = (x: here.x + 1, z: here.z);
    final sx = cpos.x * VoxelWorld.sizeX;
    final sz = cpos.z * VoxelWorld.sizeZ;
    var y0 = 0;
    for (var x = sx - 8; x < sx + 16; x++) {
      for (var z = sz; z < sz + 16; z++) {
        y0 = math.max(y0, world.groundHeight(x, z));
      }
    }
    final stone = Blocks.indexOf('stone');
    _stage31Fill(IVec3(sx - 8, y0, sz), IVec3(sx + 15, y0, sz + 15), stone);
    _stage31Fill(IVec3(sx - 8, y0 + 1, sz), IVec3(sx + 15, y0 + 14, sz + 15), Blocks.air);
    final y = y0 + 1;
    timeOfDay = 0.5; // noon, for the daylight rule and a lit capture
    _updateSky();
    GameState.instance.creative = false;
    _probePlace(Vector3(sx + 8.5, y + 0.1, sz + 8.5));
    player.setLook(0.0, 0.0);
    debugPrint('[probe] stage32 site x=$sx y=$y0 z=$sz (chunk (${cpos.x}, ${cpos.z}), border at x=$sx)');
    await _stage31Idle();
    // 1. the seam: a torch (light 13) at local x 4 -> the west chunk's cell at x-1 is 5 steps away.
    final built = world.chunksBuilt;
    final msBefore = world.meshMsTotal;
    final torch = IVec3(sx + 4, y, sz + 3);
    world.setBlock(torch, Blocks.indexOf('torch'));
    await _stage31Idle();
    final seam = IVec3(sx - 1, y, sz + 3);
    final deeper = IVec3(sx - 3, y, sz + 3);
    final mirror = IVec3(sx + 9, y, sz + 3); // 5 steps the other way, inside the torch's chunk
    debugPrint('[probe] stage32 seam light: torch at 5 cells from border -> neighbour chunk face block light=${world.lightAt(seam).block} (>=8); '
        '2 cells further=${world.lightAt(deeper).block} (>=6); same 5 steps inside the chunk=${world.lightAt(mirror).block}; '
        'chunk (${cpos.x - 1}, ${cpos.z}) remeshed with the ring');
    final ring = world.chunksBuilt - built;
    debugPrint('[probe] stage32 mesh time avg=${(world.meshMsTotal / math.max(world.chunksBuilt, 1)).toStringAsFixed(2)} ms over '
        '${world.chunksBuilt} chunks (stage 31 was ~7-14); the torch\'s ring of $ring took '
        '${((world.meshMsTotal - msBefore) / math.max(ring, 1)).toStringAsFixed(2)} ms each');
    world.setBlock(torch, Blocks.air);
    // 2. knockback and the player's hit
    final ahead = (player.aimDirection().clone()..y = 0.0).normalized();
    final zombie = sp.forceSpawn('zombie', player.position + ahead * 2.0);
    zombie.stun(999.0, false);
    zombie.hp = 1.0e9;
    zombie.maxHp = 1.0e9;
    await _ticks(1);
    final z0 = zombie.position.clone();
    player.probeStrike();
    final rose = zombie.velocity.y > 0.0;
    final flashed = zombie.isFlashing() && zombie.isFrozen();
    await _ticks(45);
    final moved = math.sqrt(math.pow(zombie.position.x - z0.x, 2) + math.pow(zombie.position.z - z0.z, 2));
    player.takeDamage(4.0, 'zombie', zombie.position);
    debugPrint('[probe] stage32 knockback: zombie moved ${moved.toStringAsFixed(2)} m away (>1.5) and rose (vy>0)=$rose '
        'flash+hitstop=$flashed; player hit -> shake=${player.shakeActive()} vignette alpha=${hud.vignetteAlpha().toStringAsFixed(2)} (>0) '
        'model flash=${player.model.isFlashing()}');
    // 3. the crit roll over 200 swings (the zombie is put back in front before each)
    final crits0 = crits;
    final numbers0 = damageNumbersSpawned;
    for (var i = 0; i < 200; i++) {
      zombie.position = player.position + ahead * 2.0;
      zombie.velocity = Vector3.zero();
      player.probeStrike();
    }
    debugPrint('[probe] stage32 crit: over 200 swings crits=${crits - crits0} (10-40) damage numbers spawned=${damageNumbersSpawned - numbers0}');
    zombie.removed = true;
    // 4. cracks, then the break
    final cell = IVec3(sx + 8, y0, sz + 5);
    final alpha = player.probeCrack(cell, 0.5);
    final linesShown = player.crackLines.where((l) => l.visible).length;
    final debris0 = debrisSpawned;
    player.probeBreakAt(cell);
    debugPrint('[probe] stage32 cracks: progress 0.5 -> overlay alpha=${alpha.toStringAsFixed(2)} (>0), stage ${Player.crackStage(0.5)} '
        'lines shown $linesShown before the break; break -> particles emitted=${debrisSpawned > debris0} '
        '(${debrisSpawned - debris0} cubes), sfx family=$lastBreakFamily');
    world.setBlock(cell, stone);
    // 5. footsteps over 5 m
    final steps0 = player.stepsTaken;
    final walk = await _stage22Walk(Vector3(sx - 6.5, y + 0.1, sz + 12.5), sx - 1.5, 120, false);
    debugPrint('[probe] stage32 footsteps: walked ${(walk.x - (sx - 6.5)).toStringAsFixed(1)} m -> steps=${player.stepsTaken - steps0} '
        '(one per ${Player.footstepInterval} s at ${Player.walkSpeed} m/s: ~${(5.0 / Player.walkSpeed / Player.footstepInterval).round()})');
    // 6. the daylight rule: sun, roof, water
    _stage31Fill(IVec3(sx + 11, y + 4, sz + 12), IVec3(sx + 13, y + 4, sz + 14), stone);
    _stage31Fill(IVec3(sx + 6, y0 - 1, sz + 12), IVec3(sx + 8, y0 - 1, sz + 14), stone);
    _stage31Fill(IVec3(sx + 6, y0, sz + 12), IVec3(sx + 8, y0, sz + 14), Blocks.indexOf('water'));
    await _stage31Idle();
    final sun = sp.forceSpawn('zombie', Vector3(sx + 2.5, y + 0.1, sz + 13.5));
    final roof = sp.forceSpawn('zombie', Vector3(sx + 12.5, y + 0.1, sz + 13.5));
    final pool = sp.forceSpawn('zombie', Vector3(sx + 7.5, y0 + 0.1, sz + 13.5));
    for (final m in [sun, roof, pool]) {
      m.stun(999.0, false);
    }
    await _stage28Settle(1.2);
    int headSky(Mob m) => world.lightAt(IVec3.floor(m.position + Vector3(0, 1.5, 0))).sky;
    debugPrint('[probe] stage32 daylight: zombie in sun burning=${sun.burning}, zombie under roof burning=${roof.burning}, '
        'zombie in water burning=${pool.burning} (head sky ${headSky(sun)} / ${headSky(roof)} / ${headSky(pool)}, in_water=${pool.inLiquid}, '
        'day factor ${dayFactor.toStringAsFixed(2)})');
    roof.removed = true;
    pool.removed = true;
    // 7. the death clock: drops at t=0, freed after the fall (0.4 s) and the fade (0.3 s)
    sun.probeDrops = const {'apple': [1, 1]};
    final drops0 = drops.length;
    sun.takeDamage(1.0e9, player.position, 0.0, player);
    final dropsAtZero = drops.length > drops0;
    var deathTicks = 0;
    await _stage28Until(() {
      deathTicks += 1;
      return !mobs.contains(sun);
    }, 3.0);
    debugPrint('[probe] stage32 death anim: zombie killed -> freed after ${(deathTicks / 60.0).toStringAsFixed(2)} s (0.6-0.9), '
        'drops spawned at t=0=$dropsAtZero');
    // 8. the HUD: two apple toasts merge; a low HP pulses the vignette
    hud.toasts.clear(); // a stray pickup from the walk must not merge into the probe's toast
    hud.addPickup('apple', 3);
    final first = hud.toastTexts();
    hud.addPickup('apple', 3);
    final merged = hud.toastTexts();
    final hpWas = player.hp;
    player.hp = player.maxHp * 0.1;
    await nextFrame();
    final pulsing = hud.lowHpPulsing();
    player.hp = hpWas;
    debugPrint("[probe] stage32 hud: pickup toast merged '${first.isEmpty ? '' : first[0]}' -> '${merged.isEmpty ? '' : merged[0]}'="
        '${merged.length == 1 && merged[0] == '+6 Apple'}; low hp vignette pulsing=$pulsing');
    // The captures.
    final shot = _arg('--shot=', '');
    if (shot == 'combat') {
      player.setFirstPerson(false);
      _probePlace(Vector3(sx + 8.5, y + 0.1, sz + 8.5));
      player.setLook(0.0, -12.0 * math.pi / 180.0);
      for (var i = 0; i < 20; i++) {
        await nextFrame();
      }
      final target = sp.forceSpawn('zombie', player.position + ahead * 2.4);
      target.stun(999.0, false);
      target.hp = 1.0e9;
      target.maxHp = 1.0e9;
      await _ticks(1);
      player.probeStrike();
      player.takeDamage(3.0, 'zombie', target.position);
      // After the hit: a side step so the two bodies do not line up.
      player.position = player.position + Vector3(-ahead.z, 0, ahead.x) * -1.3;
      // One tick, not Godot's six frames: the capture itself lands a few frames later and the flash is 100 ms.
      await _ticks(1);
      final cam = player.camera();
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      final vs = Size(view.physicalSize.width / view.devicePixelRatio, view.physicalSize.height / view.devicePixelRatio);
      debugPrint("[probe] stage32 capture 'combat': zombie at ${target.position} vel ${target.velocity} (screen ${cam.worldToScreen(target.centre(), vs)}), "
          'player screen ${cam.worldToScreen(player.centre(), vs)}, vignette ${hud.vignetteAlpha().toStringAsFixed(2)}, '
          'player flash ${player.model.isFlashing()}, numbers ${[for (final n in damageNumbers) '${n.text} age ${n.age.toStringAsFixed(2)} at ${cam.worldToScreen(n.pos, vs)}']}');
    } else if (shot == 'mining') {
      player.setFirstPerson(true);
      _probePlace(Vector3(sx + 8.5, y + 0.1, sz + 8.5));
      player.setLook(0.0, -16.0 * math.pi / 180.0);
      world.setBlock(IVec3(sx + 8, y, sz + 5), stone); // a raised block shows three faces of cracks
      player.inventory.add('iron_pickaxe', 1);
      for (var i = 0; i < 9; i++) {
        if (player.inventory.idAt(i) == 'iron_pickaxe') player.selectedSlot = i;
      }
      for (var i = 0; i < 20; i++) {
        await nextFrame();
      }
      await _stage31Idle();
      input.probeHold(GameAction.attack, true);
      // Godot holds 40 frames; here the hold ends once the crack reaches its third stage, so the few frames
      // the capture still takes cannot finish the block (iron on stone is ${Items.mineTime('iron_pickaxe', stone)} s).
      await _stage28Until(() => player.mineProgress >= 0.6, 3.0);
      debugPrint("[probe] stage32 capture 'mining': aiming ${player.isAiming} at ${player.aimedBlock} progress "
          '${player.mineProgress.toStringAsFixed(2)} crack alpha ${player.crackAlpha().toStringAsFixed(2)} chips in the air $debrisAlive');
    } else if (shot == 'seam') {
      // Flutter-only capture: the torch back at night, seen from above, its pool
      // of light running across the border at x = sx (a seam would cut it at
      // that column).
      timeOfDay = 0.0;
      _updateSky();
      world.setBlock(torch, Blocks.indexOf('torch'));
      flyMode = true;
      player.setFirstPerson(true);
      final eye = Vector3(sx + 0.5, y + 7.0, sz + 11.5);
      final look = Vector3(sx + 0.5, y.toDouble(), sz + 3.5) - eye;
      player.setLook(math.atan2(-look.x, -look.z), math.atan2(look.y, math.sqrt(look.x * look.x + look.z * look.z)));
      await _stage31Idle();
      for (var i = 0; i < 10; i++) {
        _probePlace(eye);
        await nextFrame();
      }
      _pinCameraTo = () => eye.clone();
      final row = [for (var x = sx - 6; x <= sx + 12; x++) world.lightAt(IVec3(x, y, sz + 3)).block];
      debugPrint("[probe] stage32 capture 'seam': block light along z=${sz + 3} from x=${sx - 6} to ${sx + 12} (border at $sx): $row");
    }
    spawner = sp;
  }

  // --- stage 31: voxel light + AO, light-gated spawns, A* for walkers -----------------

  /// Frames until every queued chunk (a build or a remesh) has landed.
  Future<void> _stage31Idle() async {
    for (var i = 0; i < 3; i++) {
      await nextFrame();
    }
    for (var i = 0; !world.isIdle && i < 3000; i++) {
      await nextFrame();
    }
    for (var i = 0; i < 2; i++) {
      await nextFrame();
    }
  }

  /// [id] from [lo] to [hi] inclusive.
  void _stage31Fill(IVec3 lo, IVec3 hi, int id) {
    for (var x = lo.x; x <= hi.x; x++) {
      for (var y = lo.y; y <= hi.y; y++) {
        for (var z = lo.z; z <= hi.z; z++) {
          world.setBlock(IVec3(x, y, z), id);
        }
      }
    }
  }

  /// --stage31: a stone pad over the chunk east of spawn and the one south of it.
  /// Chunk A holds a roofed 7x7x4 room (door gap in a corner of its south wall, a
  /// roofed 6-cell porch running along that wall so the sky has 13 steps to the
  /// centre) with a wall torch on the north wall, and a 3x10 pit three deep with
  /// an 8-cell overhang; chunk B holds a 12x12 walled maze whose two 10-long
  /// walls form an S between the player (north end) and a zombie (south end).
  /// The room sits inside one chunk on purpose: the light BFS runs on the padded
  /// volume, so a torch across a border would not reach (the accepted seam).
  /// `--shot=room|cave` places the camera for the two captures.
  Future<void> _probeStage31() async {
    final sp = spawner!;
    spawner = null; // no strays wandering onto the maze (Godot: set_process(false))
    final here = VoxelWorld.chunkOf(IVec3.floor(player.position));
    final cpos = (x: here.x + 1, z: here.z);
    final sx = cpos.x * VoxelWorld.sizeX;
    final sz = cpos.z * VoxelWorld.sizeZ;
    var y0 = 0;
    for (var x = sx; x < sx + 16; x++) {
      for (var z = sz; z < sz + 32; z++) {
        y0 = math.max(y0, world.groundHeight(x, z));
      }
    }
    final stone = Blocks.indexOf('stone');
    const air = Blocks.air;
    _stage31Fill(IVec3(sx, y0, sz), IVec3(sx + 15, y0, sz + 31), stone);
    _stage31Fill(IVec3(sx, y0 + 1, sz), IVec3(sx + 15, y0 + 8, sz + 31), air);
    final y = y0 + 1; // the walk floor
    // (a) the room: walls x 1..9 / z 1..9, roof at y+4, interior x 2..8 / z 2..8, y..y+3.
    for (var lx = 1; lx < 10; lx++) {
      for (var lz = 1; lz < 10; lz++) {
        if (lx == 1 || lx == 9 || lz == 1 || lz == 9) {
          _stage31Fill(IVec3(sx + lx, y, sz + lz), IVec3(sx + lx, y + 3, sz + lz), stone);
        }
        world.setBlock(IVec3(sx + lx, y + 4, sz + lz), stone);
      }
    }
    world.setBlock(IVec3(sx + 2, y, sz + 9), air); // the door gap, 2 tall
    world.setBlock(IVec3(sx + 2, y + 1, sz + 9), air);
    _stage31Fill(IVec3(sx + 1, y, sz + 11), IVec3(sx + 8, y + 1, sz + 11), stone); // porch south wall
    _stage31Fill(IVec3(sx + 1, y, sz + 10), IVec3(sx + 1, y + 1, sz + 10), stone); // porch west end
    _stage31Fill(IVec3(sx + 1, y + 2, sz + 10), IVec3(sx + 7, y + 2, sz + 11), stone); // porch roof; x 8 is the mouth
    final torch = IVec3(sx + 5, y + 1, sz + 2);
    final wallTorch = Blocks.indexOf('wall_torch');
    world.setBlock(torch, wallTorch);
    final centre = IVec3(sx + 5, y + 1, sz + 5);
    final outside = IVec3(sx + 12, y, sz + 14);
    // (b) the pit: a stone shell, the hole x 11..13 / z 1..10 three deep, an overhang over z 1..8.
    _stage31Fill(IVec3(sx + 10, y - 5, sz), IVec3(sx + 14, y - 1, sz + 11), stone);
    _stage31Fill(IVec3(sx + 11, y - 3, sz + 1), IVec3(sx + 13, y - 1, sz + 10), air);
    _stage31Fill(IVec3(sx + 11, y, sz + 1), IVec3(sx + 13, y, sz + 8), stone);
    final under = IVec3(sx + 12, y - 3, sz + 1);
    // (c) the maze in chunk B: a walled 12x12, wall 1 at z 5 (x 2..11), wall 2 at z 9 (x 4..13).
    final mz = sz + 16;
    for (var lx = 1; lx < 15; lx++) {
      for (var lz = 1; lz < 15; lz++) {
        var wall = lx == 1 || lx == 14 || lz == 1 || lz == 14;
        wall = wall || (lz == 5 && lx >= 2 && lx <= 11) || (lz == 9 && lx >= 4 && lx <= 13);
        if (wall) _stage31Fill(IVec3(sx + lx, y, mz + lz), IVec3(sx + lx, y + 1, mz + lz), stone);
      }
    }
    final stand = Vector3(sx + 8.5, y + 0.1, mz + 2.5);
    final start = Vector3(sx + 8.5, y + 0.1, mz + 12.5);
    _probePlace(Vector3(sx + 12.5, y + 0.1, sz + 14.5)); // out of the way for the light half
    debugPrint('[probe] stage31 site x=$sx y=$y0 z=$sz (chunk (${cpos.x}, ${cpos.z}), walk floor y=$y) lighting ${world.lightingEnabled ? 'on' : 'off'}');
    final builtBefore = world.chunksBuilt, queuedBefore = world.remeshesQueued;
    await _stage31Idle();
    if (_hasArg('--trace')) {
      debugPrint('[trace] stage31 after edits: built ${world.chunksBuilt - builtBefore} queued ${world.remeshesQueued - queuedBefore} '
          'idle ${world.isIdle} roof ${Blocks.idOf(world.getBlock(centre + const IVec3(0, 3, 0)))} '
          'wall light ${world.lightAt(IVec3(sx + 1, y + 1, sz + 5))} centre block ${Blocks.idOf(world.getBlock(centre))}');
    }
    // 1. light
    final lOut = world.lightAt(outside), lC = world.lightAt(centre), lU = world.lightAt(under);
    debugPrint('[probe] stage31 light: outside sky=${lOut.sky} block=${lOut.block}; room centre sky=${lC.sky} (<=2) '
        'block=${lC.block} (>=8); under overhang sky=${lU.sky} (between 3 and 12)');
    // 2. the torch goes: the room falls dark once the ring remeshes
    final built = world.chunksBuilt;
    world.setBlock(torch, air);
    await _stage31Idle();
    debugPrint('[probe] stage31 torch removed -> room block light=${world.lightAt(centre).block} (0) after remesh; '
        'chunks remeshed=${world.chunksBuilt - built} (>=1)');
    // 3. AO
    debugPrint('[probe] stage31 AO: face verts with ao<1 in room mesh=${world.aoVertsOf(cpos)} (>0)');
    // 4. the spawn gate, dark then lit
    final darkOk = sp.hostileAllowedAt(centre);
    world.setBlock(torch, wallTorch);
    await _stage31Idle();
    final litOk = sp.hostileAllowedAt(centre);
    debugPrint('[probe] stage31 spawn gate: dark room spawn allowed=$darkOk, lit room allowed=$litOk (day factor ${dayFactor.toStringAsFixed(2)})');
    // 5. the maze: a zombie at the south end, the player at the north end, 1.5 m counts as reached
    final gs = GameState.instance;
    final wasCreative = gs.creative;
    gs.creative = true; // the zombie that arrives may swing; the clock is what matters
    _probePlace(stand);
    player.probeWalk(Vector3.zero());
    final zombie = sp.forceSpawn('zombie', start);
    final from = IVec3(start.x.floor(), (start.y + 0.05).floor(), start.z.floor());
    final to = IVec3(stand.x.floor(), (stand.y + 0.05).floor(), stand.z.floor());
    final sw = Stopwatch()..start();
    final path = Pathfinder.find(world, from, to, costs: Blocks.pathCosts);
    final findMs = sw.elapsedMicroseconds / 1000.0;
    final straight = (from.x - to.x).abs() + (from.z - to.z).abs();
    Mob.pathfindingEnabled = true;
    final result = await _stage31Chase(zombie, 15.0);
    debugPrint('[probe] stage31 path: zombie to player length=${path.length} (> straight-line $straight, found in '
        '${findMs.toStringAsFixed(2)} ms), reached=${result.reached} in ${result.seconds.toStringAsFixed(1)} s (replans ${zombie.pathReplans})');
    Mob.pathfindingEnabled = false;
    zombie.position = start.clone();
    zombie.velocity = Vector3.zero();
    final control = await _stage31Chase(zombie, 6.0);
    debugPrint('[probe] stage31 no-path control: direct chase stuck=${!control.reached} '
        '(closest ${control.closest.toStringAsFixed(1)} m in ${control.seconds.toStringAsFixed(1)} s)');
    Mob.pathfindingEnabled = true;
    zombie.removed = true;
    gs.creative = wasCreative;
    spawner = sp;
    // 6. the mesher's own clock
    debugPrint('[probe] stage31 mesh time: avg ${(world.meshMsTotal / math.max(world.chunksBuilt, 1)).toStringAsFixed(2)} ms per chunk '
        'over ${world.chunksBuilt} chunks (lighting ${world.lightingEnabled ? 'on' : 'off'})');
    // The captures: inside the room facing the torch wall, or at the back of the pit facing its mouth.
    final shot = _arg('--shot=', '');
    if (shot != '') {
      flyMode = true;
      player.setFirstPerson(true);
      final Vector3 eye;
      if (shot == 'cave') {
        eye = Vector3(sx + 12.5, y - 2.9, sz + 1.5);
        player.setLook(math.pi, 4.0 * math.pi / 180.0);
      } else {
        eye = Vector3(sx + 5.5, y + 0.1, sz + 7.5);
        player.setLook(0.0, -6.0 * math.pi / 180.0);
      }
      for (var i = 0; i < 30; i++) {
        _probePlace(eye);
        await nextFrame();
      }
      await _stage31Idle();
      for (var i = 0; i < 10; i++) {
        _probePlace(eye);
        await nextFrame();
      }
      _pinCameraTo = () => eye.clone();
      debugPrint('[probe] stage31 capture \'$shot\' from $eye');
    }
  }

  /// Simulation ticks until the mob is within 1.5 m of the player (body edge to
  /// body edge, on the ground plane; a zombie stops at its attack reach, so the
  /// swing counts too) or [seconds] of ticks pass; the closest it got and the
  /// time spent.
  Future<({bool reached, double seconds, double closest})> _stage31Chase(Mob mob, double seconds) {
    final done = Completer<({bool reached, double seconds, double closest})>();
    final frames = (seconds * 60).round();
    var closest = double.infinity;
    var i = 0;
    _probeTick = () {
      i += 1;
      final dx = mob.position.x - player.position.x, dz = mob.position.z - player.position.z;
      final d = math.sqrt(dx * dx + dz * dz) - mob.halfWidth - player.halfWidth;
      closest = math.min(closest, d);
      if (_hasArg('--trace') && i % 30 == 0) {
        debugPrint('[trace] chase f$i mob ${mob.position} state ${mob.state} wp ${mob.pathProgress} wall ${mob.hitWall} floor ${mob.onFloor}');
      }
      if (d <= 1.5 || mob.state == MobState.attack) {
        _probeTick = null;
        done.complete((reached: true, seconds: i / 60.0, closest: closest));
      } else if (i >= frames) {
        _probeTick = null;
        done.complete((reached: false, seconds: seconds, closest: closest));
      }
    };
    return done.future;
  }

  /// --stage22: sub-block collision and liquid flow on a stone pad beside
  /// spawn. Three walks along +x (onto a slab, up a stairs onto a block, into a
  /// fence with a jump), then a water source that spreads and drains, then lava
  /// meeting water. The camera ends above the pad.
  /// `--underwater`: fly the first-person eye 2.5 m under the sea surface over
  /// the nearest column whose sea floor is at least 6 m down, looking slightly
  /// down, for a capture of the underwater fog and wash.
  void _placeUnderwater() {
    const sea = TerrainGenerator.seaLevel;
    final ox = player.position.x.floor();
    final oz = player.position.z.floor();
    for (var ring = 0; ring < 200; ring++) {
      for (var i = 0; i < 16; i++) {
        final a = i * math.pi * 2 / 16.0;
        final x = ox + (math.cos(a) * ring * 4).toInt();
        final z = oz + (math.sin(a) * ring * 4).toInt();
        if (world.surfaceHeight(x, z) > sea - 6) continue;
        flyMode = true;
        player.setFirstPerson(true);
        player.position = Vector3(x + 0.5, sea - 2.5 - Player.eyeHeight, z + 0.5);
        player.setLook(0.0, -0.6);
        debugPrint('[probe] underwater at $x,$z floor ${world.surfaceHeight(x, z)} sea $sea eye ${player.cameraPosition}');
        return;
      }
    }
    throw StateError('no sea within 800 m');
  }

  /// `--move-probe`: the two movement settings on a flat stone pad. A one-block
  /// step is walked into with the step teleport off (the body must rise over
  /// several ticks, a jump) and on (one tick lifts it the whole block); a wall
  /// three blocks high is pushed into with jump held, climbing off (a jump, no
  /// higher) and on (the climber must stand on top of the wall, past its face).
  Future<void> _probeMovement() async {
    final x0 = player.position.x.floor() + 3;
    final z0 = player.position.z.floor();
    var y0 = 0;
    for (var x = x0 - 2; x < x0 + 12; x++) {
      for (var z = z0 - 2; z < z0 + 3; z++) {
        y0 = math.max(y0, world.groundHeight(x, z));
      }
    }
    final stone = Blocks.indexOf('stone');
    for (var x = x0 - 2; x < x0 + 12; x++) {
      for (var z = z0 - 2; z < z0 + 3; z++) {
        world.setBlock(IVec3(x, y0, z), stone);
        for (var y = y0 + 1; y < y0 + 8; y++) {
          world.setBlock(IVec3(x, y, z), Blocks.air);
        }
      }
    }
    final floorY = y0 + 1.0;
    // Returns the highest feet, the largest one-tick rise, the final feet and x.
    Future<({double maxY, double maxRise, double y, double x, bool floor})> walk(double stopX, int ticks, bool holdJump) async {
      player.position = Vector3(x0 + 0.5, floorY + 0.01, z0 + 0.5);
      player.velocity = Vector3.zero();
      player.syncNode();
      await _ticks(5);
      player.probeWalk(Vector3(1, 0, 0));
      input.probeHold(GameAction.jump, holdJump);
      var maxY = player.position.y;
      var maxRise = 0.0;
      var last = player.position.y;
      for (var i = 0; i < ticks && player.position.x < stopX; i++) {
        await _ticks(1);
        maxY = math.max(maxY, player.position.y);
        maxRise = math.max(maxRise, player.position.y - last);
        last = player.position.y;
      }
      player.probeWalk(Vector3.zero());
      input.probeHold(GameAction.jump, false);
      await _ticks(60);
      return (maxY: maxY, maxRise: maxRise, y: player.position.y, x: player.position.x, floor: player.onFloor);
    }

    final settings = Settings.instance;
    // A half step (a row of slabs) is hopped, never lifted onto.
    for (var x = x0 + 3; x < x0 + 6; x++) {
      for (var z = z0 - 2; z < z0 + 3; z++) {
        world.setBlock(IVec3(x, y0 + 1, z), Blocks.indexOf('stone_slab'));
      }
    }
    await _ticks(10);
    final hopped = await walk(x0 + 4.6, 120, false);
    debugPrint('[probe] move half step: top y=${hopped.y.toStringAsFixed(3)} (expect ${(floorY + 0.5).toStringAsFixed(1)}) '
        'highest feet=${hopped.maxY.toStringAsFixed(3)} (a hop: < ${(floorY + 0.8).toStringAsFixed(1)}) '
        'largest one-tick rise=${hopped.maxRise.toStringAsFixed(3)} (< 0.3) x=${hopped.x.toStringAsFixed(2)}');
    // Step and wall are three blocks deep, so the walker stops on top of them
    // instead of crossing and dropping off the far side.
    for (var x = x0 + 3; x < x0 + 6; x++) {
      for (var z = z0 - 2; z < z0 + 3; z++) {
        world.setBlock(IVec3(x, y0 + 1, z), stone);
      }
    }
    await _ticks(10);
    final jumped = await walk(x0 + 4.6, 120, false);
    debugPrint('[probe] move full step: top y=${jumped.y.toStringAsFixed(3)} (expect ${(floorY + 1).toStringAsFixed(1)}) '
        'largest one-tick rise=${jumped.maxRise.toStringAsFixed(3)} (a jump: < 0.3, a lift would be >= 1.0) '
        'x=${jumped.x.toStringAsFixed(2)}');
    for (var x = x0 + 3; x < x0 + 6; x++) {
      for (var z = z0 - 2; z < z0 + 3; z++) {
        for (var y = y0 + 1; y <= y0 + 3; y++) {
          world.setBlock(IVec3(x, y, z), stone);
        }
      }
    }
    await _ticks(10);
    final wallTop = floorY + 3;
    settings.climbWalls = false;
    final blocked = await walk(x0 + 4.6, 180, true);
    debugPrint('[probe] move climb=off: highest feet=${blocked.maxY.toStringAsFixed(3)} (a jump only: < ${(floorY + 1.5).toStringAsFixed(1)}) '
        'x=${blocked.x.toStringAsFixed(2)} (wall face ${x0 + 3})');
    settings.climbWalls = true;
    player.stamina = player.maxStamina;
    final climbed = await walk(x0 + 4.6, 300, true);
    debugPrint('[probe] move climb=on: final feet y=${climbed.y.toStringAsFixed(3)} (expect ${wallTop.toStringAsFixed(1)}) '
        'on floor=${climbed.floor} x=${climbed.x.toStringAsFixed(2)} (past the face ${x0 + 3}: ${climbed.x > x0 + 3.3})');
    settings.climbWalls = false;

    // A pool whose bank stands one block over the water: swimming into it
    // with jump held reaches the bank on the first try, never falling back.
    for (var x = x0 + 3; x < x0 + 6; x++) {
      for (var z = z0 - 2; z < z0 + 3; z++) {
        world.setBlock(IVec3(x, y0 + 2, z), Blocks.air);
        world.setBlock(IVec3(x, y0 + 3, z), Blocks.air);
      }
    }
    final water = Blocks.indexOf('water');
    for (var x = x0 - 1; x < x0 + 3; x++) {
      for (var z = z0 - 1; z < z0 + 2; z++) {
        world.setBlock(IVec3(x, y0 - 2, z), stone);
        world.setBlock(IVec3(x, y0 - 1, z), water);
        world.setBlock(IVec3(x, y0, z), water);
      }
    }
    await _ticks(20);
    player.position = Vector3(x0 + 0.5, y0 - 0.99, z0 + 0.5);
    player.velocity = Vector3.zero();
    player.syncNode();
    await _ticks(5);
    player.probeWalk(Vector3(1, 0, 0));
    input.probeHold(GameAction.jump, true);
    var touched = false, wasIn = player.inLiquid, fellBack = 0, outAt = -1;
    for (var i = 0; i < 600; i++) {
      await _ticks(1);
      touched = touched || player.position.x > x0 + 2.6;
      if (touched && player.inLiquid && !wasIn) fellBack++;
      wasIn = player.inLiquid;
      if (player.onFloor && player.position.y >= floorY + 0.99) {
        outAt = i;
        break;
      }
    }
    player.probeWalk(Vector3.zero());
    input.probeHold(GameAction.jump, false);
    debugPrint('[probe] move water exit: on the bank=${outAt >= 0} after $outAt ticks, feet y=${player.position.y.toStringAsFixed(3)} '
        '(expect ${(floorY + 1).toStringAsFixed(1)}), fell back into the water $fellBack times after reaching the bank (expect 0) '
        'x=${player.position.x.toStringAsFixed(2)} hp=${player.hp}');

    // Walking backward keeps the body facing the camera (Minecraft), it
    // never turns around.
    player.setFirstPerson(false);
    player.setLook(0.0, 0.0);
    _probePlace(Vector3(x0 + 4.5, floorY + 1.01, z0 + 0.5));
    player.probeWalk(Vector3(0, 0, 1));
    await _ticks(40);
    final back = player.model.yaw;
    player.probeWalk(Vector3(0, 0, -1));
    await _ticks(40);
    player.probeWalk(Vector3.zero());
    debugPrint('[probe] move backward: walking +Z at camera yaw 0 body yaw=${back.toStringAsFixed(2)} (expect 0.00, not 3.14); '
        'walking -Z body yaw=${player.model.yaw.toStringAsFixed(2)} (expect 0.00)');

    // A walled one-block puddle, so it cannot drain: the liquid state used to
    // flip every tick in shallow water (the feet probe rides on the cell edge)
    // and took the pose, the gravity, the speed and the splash with it, which
    // is what made the body tremble. Standing in it is wading, not swimming.
    final padY = floorY.toInt();
    final px0 = x0 - 2, px1 = x0 + 8, pz0 = z0 + 6, pz1 = z0 + 8;
    for (var x = px0 - 1; x <= px1 + 1; x++) {
      for (var z = pz0 - 1; z <= pz1 + 1; z++) {
        world.setBlock(IVec3(x, padY, z), stone);
        for (var y = padY + 1; y <= padY + 4; y++) {
          world.setBlock(IVec3(x, y, z), Blocks.air);
        }
        if (x < px0 || x > px1 || z < pz0 || z > pz1) world.setBlock(IVec3(x, padY + 1, z), stone);
      }
    }
    for (var x = px0; x <= px1; x++) {
      for (var z = pz0; z <= pz1; z++) {
        world.setBlock(IVec3(x, padY + 1, z), water);
      }
    }
    await _ticks(20);
    _probePlace(Vector3(px0 + 0.5, floorY + 1.01, pz0 + 1.5));
    await _ticks(10);
    player.probeWalk(Vector3(1, 0, 0));
    var wetFlips = 0, floorFlips = 0, airTicks = 0;
    var wasWet = player.inLiquid, wasFloor = player.onFloor;
    var loY = 1e9, hiY = -1e9, legJump = 0.0, lastLeg = player.model.legL.rx;
    for (var i = 0; i < 150; i++) {
      await _ticks(1);
      if (player.inLiquid != wasWet) wetFlips++;
      if (player.onFloor != wasFloor) floorFlips++;
      wasWet = player.inLiquid;
      wasFloor = player.onFloor;
      if (!player.onFloor) airTicks++;
      loY = math.min(loY, player.position.y);
      hiY = math.max(hiY, player.position.y);
      legJump = math.max(legJump, (player.model.legL.rx - lastLeg).abs());
      lastLeg = player.model.legL.rx;
    }
    player.probeWalk(Vector3.zero());
    debugPrint('[probe] move puddle: wading=${player.wading} swimming=${player.swimming} liquid flips=$wetFlips (expect 0) '
        'floor flips=$floorFlips (expect 0) airborne ticks=$airTicks (expect 0) feet y span '
        '${(hiY - loY).toStringAsFixed(4)} (expect < 0.01) biggest leg jump per tick ${legJump.toStringAsFixed(3)} (expect < 0.1)');

    // View bobbing: the camera sways while walking and is perfectly still
    // standing. The aim never moves with it, which is why the sway is added to
    // the camera and not to the body.
    player.setFirstPerson(true);
    player.setLook(0.0, 0.0);
    _probePlace(Vector3(x0 + 4.5, floorY + 1.01, z0 + 0.5));
    await _ticks(40);
    final bobStill = player.viewBobOffset().length;
    // The drop and the sway are measured apart: Minecraft's bob is a drop with
    // a hint of sway, so the sway must come out about half the drop. With the
    // look level the drop is the offset's -y and the sway is what is left in
    // the horizontal plane.
    var dropMax = 0.0, sideMax = 0.0, sways = 0;
    var lastSide = 0.0;
    for (final dir in [Vector3(0, 0, -1), Vector3(0, 0, 1)]) {
      player.probeWalk(dir);
      for (var i = 0; i < 45; i++) {
        await _ticks(1);
        final b = player.viewBobOffset();
        dropMax = math.max(dropMax, -b.y);
        final side = math.sqrt(b.x * b.x + b.z * b.z);
        sideMax = math.max(sideMax, side);
        if (b.x != 0.0 && lastSide != 0.0 && b.x.sign != lastSide.sign) sways++;
        lastSide = b.x;
      }
    }
    player.probeWalk(Vector3.zero());
    await _ticks(90);
    final settled = player.viewBobOffset().length;
    // Third person bobs too, as Minecraft's whole view does: the same walk,
    // over the same ground, with the camera behind the shoulder.
    player.setFirstPerson(false);
    _probePlace(Vector3(x0 + 4.5, floorY + 1.01, z0 + 0.5)); // the same ground, so the two peaks compare
    await _ticks(30);
    var thirdMax = 0.0, thirdSpeed = 0.0;
    for (final dir in [Vector3(0, 0, -1), Vector3(0, 0, 1)]) {
      player.probeWalk(dir);
      for (var i = 0; i < 45; i++) {
        await _ticks(1);
        thirdMax = math.max(thirdMax, player.viewBobOffset().length);
        final v = player.velocity;
        thirdSpeed = math.max(thirdSpeed, math.sqrt(v.x * v.x + v.z * v.z));
      }
    }
    player.probeWalk(Vector3.zero());
    player.setFirstPerson(true);
    debugPrint('[probe] move bob: standing=${bobStill.toStringAsFixed(4)} (expect 0.0000) walking drop=${dropMax.toStringAsFixed(4)} '
        'sway=${sideMax.toStringAsFixed(4)} (expect a sixth of the drop, ratio '
        '${(dropMax > 0 ? sideMax / dropMax : 0).toStringAsFixed(2)}) side-to-side crossings=$sways (expect one per leg walked) '
        'after stopping=${settled.toStringAsFixed(4)} (expect 0.0000) third person peak=${thirdMax.toStringAsFixed(4)} at speed ${thirdSpeed.toStringAsFixed(2)} (expect > 0)');

    // Stage 40: every creature climbs a step by jumping it. A staircase of
    // three whole blocks is walked by a cow on its own legs and by a horse
    // with the player in the saddle; the largest rise in one tick tells a jump
    // (a few centimetres) from the lift it used to be (a whole block).
    player.setFirstPerson(false);
    final sz = z0 - 10;
    for (var x = x0 - 2; x < x0 + 12; x++) {
      for (var z = sz - 2; z < sz + 3; z++) {
        world.setBlock(IVec3(x, y0, z), stone);
        for (var y = y0 + 1; y < y0 + 8; y++) {
          world.setBlock(IVec3(x, y, z), Blocks.air);
        }
      }
    }
    for (var x = x0 + 3; x < x0 + 12; x++) {
      final steps = math.min(x - x0 - 2, 3); // three steps, then the landing
      for (var z = sz - 2; z < sz + 3; z++) {
        for (var y = y0 + 1; y <= y0 + steps; y++) {
          world.setBlock(IVec3(x, y, z), stone);
        }
      }
    }
    await _ticks(10);
    // Walks a body east for [ticks]: the feet it ends on, the top it reached
    // and the largest rise it made in one tick.
    Future<({double y, double rise})> climb(VoxelBody body, void Function(Vector3) steer, int ticks) async {
      var last = body.position.y;
      var rise = 0.0;
      steer(Vector3(1, 0, 0));
      for (var i = 0; i < ticks && body.position.x < x0 + 7.4; i++) {
        await _ticks(1);
        rise = math.max(rise, body.position.y - last);
        last = body.position.y;
      }
      steer(Vector3.zero());
      await _ticks(20);
      return (y: body.position.y, rise: rise);
    }

    final cow = Mob()..setupMob(world, this, player, Species.def('cow'));
    cow.position = Vector3(x0 + 0.5, floorY + 0.1, sz + 0.5);
    addMob(cow);
    await _ticks(5);
    final cowClimb = await climb(cow, cow.probeWalk, 300);
    cow.removed = true;
    debugPrint('[probe] move mob steps: a cow walked the staircase to feet y=${cowClimb.y.toStringAsFixed(3)} '
        '(expect ${(floorY + 3).toStringAsFixed(1)}) largest one-tick rise=${cowClimb.rise.toStringAsFixed(3)} '
        '(a jump: < 0.3, a lift would be >= 1.0)');

    final horse = Mob()..setupMob(world, this, player, Species.def('horse'));
    horse.position = Vector3(x0 + 0.5, floorY + 0.1, sz + 0.5);
    addMob(horse);
    horse.tame(player);
    player.position = horse.position + Vector3(0, 1.0, 0);
    player.velocity = Vector3.zero();
    player.mountHorse(horse);
    await _ticks(10);
    final rideClimb = await climb(horse, player.probeWalk, 300);
    debugPrint('[probe] move mount steps: the horse carried the rider to feet y=${rideClimb.y.toStringAsFixed(3)} '
        '(expect ${(floorY + 3).toStringAsFixed(1)}) largest one-tick rise=${rideClimb.rise.toStringAsFixed(3)} '
        '(a jump: < 0.3, a lift would be >= 1.0) rider on the saddle=${player.isMounted()}');

    // Stage 40: nothing walks on water. The same horse crosses a pool four
    // blocks deep: its feet must ride well under the surface (it swims) and it
    // must climb out on the far bank.
    final wz = sz - 8;
    for (var x = x0 - 2; x < x0 + 12; x++) {
      for (var z = wz - 2; z < wz + 3; z++) {
        world.setBlock(IVec3(x, y0, z), stone);
        for (var y = y0 + 1; y < y0 + 8; y++) {
          world.setBlock(IVec3(x, y, z), Blocks.air);
        }
      }
    }
    for (var x = x0 + 3; x <= x0 + 8; x++) {
      for (var z = wz - 2; z < wz + 3; z++) {
        for (var y = y0 - 3; y <= y0; y++) {
          world.setBlock(IVec3(x, y, z), water);
        }
      }
    }
    await _ticks(20);
    horse.position = Vector3(x0 + 0.5, floorY + 0.1, wz + 0.5);
    horse.velocity = Vector3.zero();
    player.position = horse.position + Vector3(0, 1.0, 0);
    await _ticks(10);
    player.probeWalk(Vector3(1, 0, 0));
    var overWater = 0, onTop = 0, stood = 0, swam = 0, deepest = 1e9;
    for (var i = 0; i < 400; i++) {
      await _ticks(1);
      final x = horse.position.x;
      if (x > x0 + 3.5 && x < x0 + 8.5) {
        overWater++;
        if (horse.swimming) swam++;
        if (horse.onFloor) stood++;
        deepest = math.min(deepest, horse.position.y);
        // The first half second is the body sinking in from the bank, and the
        // last metre is it climbing out on the far side; in between, a body
        // that walked on water would still be at the surface.
        if (overWater > 30 && x < x0 + 7.0 && horse.position.y > floorY - 0.5) onTop++;
      }
      if (x > x0 + 9.5) break;
    }
    player.probeWalk(Vector3.zero());
    await _ticks(30);
    debugPrint('[probe] move mount water: over the pool for $overWater ticks, swimming $swam of them, '
        'standing on something $stood (expect 0), at the surface $onTop once sunk in (expect 0), '
        'deepest feet ${deepest.toStringAsFixed(2)} (the surface is ${floorY.toStringAsFixed(1)}), '
        'reached x=${horse.position.x.toStringAsFixed(2)} (the far bank is ${x0 + 9}) '
        'back on the floor=${horse.onFloor} feet y=${horse.position.y.toStringAsFixed(2)}');
    player.dismount();
    horse.removed = true;

    // Stage 40: a playground is a showroom — stamina and mana never run out
    // there, so every ability can be tried one after the other. The flag is the
    // world's own (`GameState.playground`); what is spent below is spent
    // through the real dodge and the real class abilities, on dry ground at the
    // top of the staircase (a dodge is refused in water).
    final gs = GameState.instance;
    final wasPlayground = gs.playground;
    player.probeSetClass('mage');
    _probePlace(Vector3(x0 + 9.5, floorY + 3.01, sz + 0.5));
    await _ticks(10);
    Future<({double stamina, double mana})> spendEverything() async {
      player.stamina = player.maxStamina;
      player.mana = player.maxMana;
      player.probeDodge();
      player.probeAbility();
      player.probeAbility2();
      await _ticks(2);
      return (stamina: player.stamina, mana: player.mana);
    }

    gs.playground = false;
    final paid = await spendEverything();
    await _ticks(60); // the dodge's own cooldown, so the second round can dodge too
    gs.playground = true;
    final free = await spendEverything();
    gs.playground = wasPlayground;
    debugPrint('[probe] move endless: a dodge and both class abilities cost '
        '${(player.maxStamina - paid.stamina).toStringAsFixed(1)} stamina and '
        '${(player.maxMana - paid.mana).toStringAsFixed(1)} mana in an ordinary world (expect > 0), '
        '${(player.maxStamina - free.stamina).toStringAsFixed(1)} and '
        '${(player.maxMana - free.mana).toStringAsFixed(1)} in a playground (expect 0.0 and 0.0)');
  }

  /// `--reach-probe`: the reach rule — what is nearest is what is acted on,
  /// and nothing acts through it. A creature stands two metres off with a
  /// stone block between it and the crosshair: the block must be what is
  /// aimed at, mining it must run, and a swing must leave the creature
  /// untouched. The block comes down and the same swing lands. The creature's
  /// own bite obeys the rule too — a wall between the two stops it. Last the
  /// player mounts a horse and mines a block from the saddle, which the
  /// saddle used to forbid.
  Future<void> _probeReach() async {
    final stone = Blocks.indexOf('stone');
    final base = IVec3.floor(player.position);
    final floor = base.y - 1;
    for (var dx = -6; dx < 12; dx++) {
      for (var dz = -6; dz < 7; dz++) {
        world.setBlock(IVec3(base.x + dx, floor, base.z + dz), stone);
        for (var dy = 1; dy < 7; dy++) {
          world.setBlock(IVec3(base.x + dx, floor + dy, base.z + dz), Blocks.air);
        }
      }
    }
    final floorY = floor + 1.0;
    player.setFirstPerson(true);
    player.setLook(0.0, 0.0);
    _probePlace(Vector3(base.x + 0.5, floorY + 0.01, base.z + 0.5));
    await _ticks(10);
    final aim = player.aimDirection().clone()..y = 0.0;
    aim.normalize();
    Vector3 ahead(double m) => player.aimOrigin() + aim * m;

    final zombie = Mob()..setupMob(world, this, player, Species.def('zombie'));
    zombie.position = ahead(2.4)..y = floorY + 0.05;
    addMob(zombie);
    zombie.stun(30.0, false); // it holds its two metres, so the two aims compare
    // A wall between them, from the floor to over the heads: what the eye
    // sees and what the swing meets are the same thing.
    final wall = IVec3(IVec3.floor(ahead(1.4)).x, floor + 1, IVec3.floor(ahead(1.4)).z);
    for (var dy = 0; dy < 3; dy++) {
      world.setBlock(wall + IVec3(0, dy, 0), stone);
    }
    await _ticks(6);
    final hpBefore = zombie.hp;
    player.probeStrike();
    await _ticks(4);
    final hpThrough = zombie.hp;
    debugPrint('[probe] reach block first: crosshair on ${player.isAiming ? 'the block $wall' : 'nothing'} '
        '(the wall is $wall), creature aimed=${player.aimedMob?.species.id ?? '-'} (expect -), '
        'mining runs=${player.isAiming}, the zombie took ${(hpBefore - hpThrough).toStringAsFixed(1)} damage through it (expect 0.0)');
    for (var dy = 0; dy < 3; dy++) {
      world.setBlock(wall + IVec3(0, dy, 0), Blocks.air);
    }
    await _ticks(6);
    final aimedOpen = player.aimedMob?.species.id ?? '-';
    player.probeStrike();
    await _ticks(4);
    debugPrint('[probe] reach block gone: creature aimed=$aimedOpen (expect zombie), '
        'the same swing took ${(hpThrough - zombie.hp).toStringAsFixed(1)} damage (expect > 0)');

    // The bite: a wall between the two stops the creature, which keeps
    // chasing instead of hitting through it.
    final wasCreative = GameState.instance.creative;
    GameState.instance.creative = false;
    zombie.removed = true;
    final biter = Mob()..setupMob(world, this, player, Species.def('zombie'));
    biter.position = ahead(1.9)..y = floorY + 0.05;
    addMob(biter);
    // A wall, not a post: eleven cells across, so walking around it takes
    // longer than the watch below.
    final side = Vector3(-aim.z, 0.0, aim.x);
    final pen = <IVec3>[];
    for (var dw = -5; dw <= 5; dw++) {
      final at = IVec3.floor(ahead(1.0) + side * dw.toDouble());
      for (var dy = 0; dy < 2; dy++) {
        pen.add(IVec3(at.x, floor + 1 + dy, at.z));
      }
    }
    for (final cell in pen) {
      world.setBlock(cell, stone);
    }
    await _ticks(6);
    final hpWalled = player.hp;
    await _ticks(180);
    final tookWalled = hpWalled - player.hp;
    final stateWalled = biter.state.name;
    for (final cell in pen) {
      world.setBlock(cell, Blocks.air);
    }
    await _ticks(6);
    final hpOpen = player.hp;
    await _ticks(180);
    debugPrint('[probe] reach bite: through the wall the player took ${tookWalled.toStringAsFixed(1)} '
        '(expect 0.0, the zombie $stateWalled), with it gone ${(hpOpen - player.hp).toStringAsFixed(1)} '
        '(expect > 0, the zombie ${biter.state.name})');
    biter.removed = true;
    player.hp = player.maxHp;
    GameState.instance.creative = wasCreative;

    // From the saddle: the rider mines the block in front of the horse.
    final horse = Mob()..setupMob(world, this, player, Species.def('horse'));
    horse.position = Vector3(base.x + 0.5, floorY + 0.05, base.z + 0.5);
    addMob(horse);
    horse.tame(player);
    player.mountHorse(horse);
    await _ticks(10);
    player.setLook(0.0, -0.9); // down at the floor in front of the hooves
    await _ticks(6);
    final target = player.aimedBlock;
    world.setBlock(target, Blocks.indexOf('dirt'));
    await _ticks(6);
    final aimedFromSaddle = player.aimedBlock;
    input.probeHold(GameAction.attack, true);
    var mined = 0;
    for (var i = 0; i < 240; i++) {
      await _ticks(1);
      mined = i;
      if (world.getBlock(target) == Blocks.air) break;
    }
    input.probeHold(GameAction.attack, false);
    debugPrint('[probe] reach mounted: riding=${player.isMounted()}, the crosshair holds $aimedFromSaddle '
        '(the dirt at $target), it broke=${world.getBlock(target) == Blocks.air} after $mined ticks');
    player.dismount();
    horse.removed = true;
    player.setLook(0.0, 0.0);
  }

  /// `--touch-probe`: a finger plays the game. Every read below goes through
  /// the kit's `InputMap` (`CL-003`), which is what `GameInput` became, so
  /// this probe is the product's own touch scheme running inside the app:
  /// a finger that stays put mines a real block, one that lifts in place uses
  /// what the crosshair points at (and swings when that is a creature), one
  /// that travels only turns the head, and one the system takes away does
  /// nothing at all. The on-screen half — stick, button, hotbar slot — is
  /// driven through the same three calls `TouchControls` makes.
  Future<void> _probeTouch() async {
    const finger = 1;
    const at = Offset(400, 300);
    void down([Offset where = at]) =>
        input.onPointerDown(PointerDownEvent(pointer: finger, kind: PointerDeviceKind.touch, position: where));
    void move(Offset to, Offset delta) =>
        input.onPointerMove(PointerMoveEvent(pointer: finger, kind: PointerDeviceKind.touch, position: to, delta: delta));
    void up([Offset where = at]) =>
        input.onPointerUp(PointerUpEvent(pointer: finger, kind: PointerDeviceKind.touch, position: where));

    final stone = Blocks.indexOf('stone');
    final base = IVec3.floor(player.position);
    final floor = base.y - 1;
    for (var dx = -6; dx < 7; dx++) {
      for (var dz = -6; dz < 7; dz++) {
        // Three courses deep: a hole the finger digs must not drop the body
        // into the sea underneath the beach.
        for (var dy = 0; dy < 3; dy++) {
          world.setBlock(IVec3(base.x + dx, floor - dy, base.z + dz), stone);
        }
        for (var dy = 1; dy < 7; dy++) {
          world.setBlock(IVec3(base.x + dx, floor + dy, base.z + dz), Blocks.air);
        }
      }
    }
    player.setFirstPerson(true);
    _probePlace(Vector3(base.x + 0.5, floor + 1.01, base.z + 0.5));
    player.setLook(0.0, -1.2); // down at the floor just ahead of the boots
    player.inventory.setSlot(player.selectedSlot, ItemStack('stone', 8));
    // A phone never locks the pointer, so this is what its first tap sets; a
    // probe sets it by hand rather than grabbing the developer's real mouse.
    input.wantCapture = true;
    await _ticks(12);

    // A finger that stays where it landed digs, and goes on digging until it
    // lifts: no button was pressed, the gesture held the primary one.
    final target = player.aimedBlock;
    world.setBlock(target, Blocks.indexOf('dirt')); // the bare hand's own block
    await _ticks(6);
    down();
    await _ticks(20); // well past the 180 ms the gesture waits before it digs
    final holds = input.down(GameAction.attack);
    var ticks = 0;
    for (var i = 0; i < 240; i++) {
      await _ticks(1);
      ticks = i + 1;
      if (world.getBlock(target) == Blocks.air) break;
    }
    final mined = world.getBlock(target) == Blocks.air;
    up();
    await _ticks(2);
    debugPrint('[probe] touch hold: the finger holds attack=$holds and broke $target=$mined after $ticks ticks, '
        'and let go=${!input.down(GameAction.attack)} (a dig is never also a tap: use pressed=${input.justPressed(GameAction.use)})');

    // A finger that lifts where it landed uses what the crosshair points at:
    // the hole it just dug is filled back in from the hotbar.
    await _ticks(6);
    final tapAttacks = input.touchTapAttacks;
    final placed = await _probeTouchTap(() => world.getBlock(target) != Blocks.air, down, up);
    debugPrint('[probe] touch tap: aim=${player.aimedBlock} tapAttacks=$tapAttacks (expect false, no creature), '
        'the block came back=${placed > 0} (${Blocks.idOf(world.getBlock(target))}) on tap $placed');

    // The same tap, with a creature as the nearest thing under the crosshair:
    // Player writes that one bit every time it re-aims, and the tap swings.
    player.setLook(0.0, 0.0);
    final aim = player.aimDirection().clone()..y = 0.0;
    aim.normalize();
    final zombie = Mob()..setupMob(world, this, player, Species.def('zombie'));
    zombie.position = player.aimOrigin() + aim * 2.0
      ..y = floor + 1.05;
    addMob(zombie);
    zombie.stun(30.0, false); // it holds its two metres while the finger decides
    await _ticks(8);
    final hpBefore = zombie.hp;
    final swingsAt = input.touchTapAttacks;
    final hits = await _probeTouchTap(() => zombie.hp < hpBefore, down, up);
    debugPrint('[probe] touch tap on a creature: tapAttacks=$swingsAt (expect true), aimed=${player.aimedMob?.species.id ?? '-'}, '
        'the zombie took ${(hpBefore - zombie.hp).toStringAsFixed(1)} damage on tap $hits');

    // A finger that travels is the camera and nothing else.
    final yawBefore = player.yaw;
    final standing = player.aimedBlock;
    down();
    move(at + const Offset(60, 0), const Offset(60, 0));
    await _ticks(20);
    final minedWhileDragging = input.down(GameAction.attack);
    up(at + const Offset(60, 0));
    await _ticks(3);
    debugPrint('[probe] touch drag: yaw ${yawBefore.toStringAsFixed(3)} -> ${player.yaw.toStringAsFixed(3)} '
        '(turned ${(player.yaw - yawBefore).abs().toStringAsFixed(3)} rad), mining=$minedWhileDragging (expect false), '
        'nothing placed=${world.getBlock(standing) == Blocks.air || standing == target}');

    // A finger the system takes away decides nothing.
    down();
    input.onPointerCancel(const PointerCancelEvent(pointer: finger, kind: PointerDeviceKind.touch, position: at));
    await _ticks(20);
    debugPrint('[probe] touch cancel: mining=${input.down(GameAction.attack)} (expect false), '
        'use pressed=${input.justPressed(GameAction.use)} (expect false)');
    zombie.removed = true;

    // The on-screen half: the stick walks and runs, a button jumps, a slot is
    // chosen. TouchControls makes exactly these three calls.
    world.setBlock(target, stone); // the hole filled in, whatever the tap did
    _probePlace(Vector3(base.x + 0.5, floor + 1.01, base.z + 0.5));
    player.setLook(0.0, 0.0);
    await _ticks(8);
    final from = player.position.clone();
    input.touchMove(0.0, -1.0);
    await _ticks(30);
    input.touchMove(0.0, 0.0);
    final walked = (player.position - from).length;
    await _ticks(10);
    final floorY = player.position.y;
    input.setTouchHeld(GameAction.jump, true);
    var peak = floorY;
    for (var i = 0; i < 40; i++) {
      await _ticks(1);
      peak = math.max(peak, player.position.y);
    }
    input.setTouchHeld(GameAction.jump, false);
    await _ticks(30);
    final wasSlot = player.selectedSlot;
    var slotTaps = 0;
    for (var i = 0; i < 8 && player.selectedSlot == wasSlot; i++) {
      input.touchHotbar(3);
      slotTaps = i + 1;
      await _ticks(1);
    }
    debugPrint('[probe] touch controls: the stick walked ${walked.toStringAsFixed(2)} m in 30 ticks, '
        'the jump button lifted ${(peak - floorY).toStringAsFixed(2)} m, '
        'the hotbar went slot $wasSlot -> ${player.selectedSlot} on tap $slotTaps');

    // How many one-shot presses reach the simulation at all. A press set
    // between two frames is only read by a frame that runs a simulation step,
    // and `onFrame` used to drain the one-shots on a frame that ran none — so
    // above 60 fps a share of every tap, on every device, was thrown away
    // before anything read it: this line read 0 of 20 at 120 fps before the
    // drain moved into the step, and 20 of 20 after.
    var landed = 0;
    for (var i = 0; i < 20; i++) {
      final slot = i % 8 + 1;
      input.touchHotbar(slot);
      await _ticks(1);
      if (player.selectedSlot == slot) landed++;
    }
    debugPrint('[probe] touch one-shot: $landed of 20 taps reached the simulation at ${fps.toStringAsFixed(0)} fps');
    input.releaseKeys();
  }

  /// A tap on the world, repeated until the simulation acts on it, with the
  /// number of taps it took. One tap is one press and one press is enough, so
  /// anything above 1 here is a press that went missing between the finger and
  /// the step — which is what this helper is for: it counts them instead of
  /// hiding them.
  Future<int> _probeTouchTap(bool Function() landed, void Function() down, void Function() up) async {
    for (var i = 0; i < 8; i++) {
      down();
      up();
      await _ticks(3);
      if (landed()) return i + 1;
    }
    return 0;
  }

  /// `--outline-probe`: no two parts of any creature share a face plane, and
  /// the aim outline hugs what it outlines. Every species is built and its
  /// rest-pose part boxes are checked pairwise for a shared plane (the
  /// flicker a leg flush with a barrel's side made). Then, on a cleared pad,
  /// the crosshair is put on a block sunk flush in the floor, a torch, a slab,
  /// a fence, a door, a flower, a wall torch, a sheep and a giant zombie, and
  /// the box the outline was fitted to is printed for each. Every species is
  /// also built at every affix size and its model checked against its
  /// collider's top. With `--screenshot=<png>`, `_block.png`, `_torch.png`,
  /// `_mob.png` and `_giant.png` capture four of them.
  Future<void> _probeOutline() async {
    final bad = <String>[];
    for (final sp in Species.defs.values) {
      final m = Mob()..setupMob(world, this, player, sp);
      final hits = Mob.coplanarFaces(m.restBoxes());
      if (hits.isNotEmpty) bad.add('${sp.id} (${sp.body}): ${hits.join(', ')}');
    }
    debugPrint('[probe] outline parts: ${Species.defs.length} species built, '
        '${bad.length} with parts sharing a face plane${bad.isEmpty ? '' : ':\n  ${bad.join('\n  ')}'}');
    // The outline is the collider, so every body, at every size an affix
    // gives it, must be drawn under the collider's top.
    final poking = <String>[];
    var tallest = 0.0;
    for (final sp in Species.defs.values) {
      for (final affix in ['', ...Mob.affixes.keys]) {
        final m = Mob()..setupMob(world, this, player, sp);
        if (affix != '') m.setAffix(affix);
        final over = m.modelTop() - m.height;
        tallest = math.max(tallest, over);
        if (over > Mob.modelHeadroom) {
          poking.add('${affix == '' ? '' : '$affix '}${sp.id}: model ${m.modelTop().toStringAsFixed(2)} m, collider ${m.height.toStringAsFixed(2)} m');
        }
      }
    }
    debugPrint('[probe] outline sizes: ${Species.defs.length * (Mob.affixes.length + 1)} bodies, worst model-over-collider '
        '${tallest.toStringAsFixed(3)} m, ${poking.length} poking out${poking.isEmpty ? '' : ':\n  ${poking.join('\n  ')}'}');

    final x0 = player.position.x.floor();
    final z0 = player.position.z.floor();
    var y0 = 0;
    for (var x = x0 - 12; x <= x0 + 12; x++) {
      for (var z = z0 - 12; z <= z0 + 4; z++) {
        y0 = math.max(y0, world.groundHeight(x, z));
      }
    }
    final stone = Blocks.indexOf('stone');
    for (var x = x0 - 12; x <= x0 + 12; x++) {
      for (var z = z0 - 12; z <= z0 + 4; z++) {
        world.setBlock(IVec3(x, y0, z), stone);
        for (var y = y0 + 1; y < y0 + 8; y++) {
          world.setBlock(IVec3(x, y, z), Blocks.air);
        }
      }
    }
    timeOfDay = 0.3;
    weather.force('clear');
    final floor = y0 + 1.0;
    // Each target sits 3 m north of where the eye stands, its own column.
    final targets = <(String, IVec3)>[];
    void put(String name, String block, int dx, {int dy = 1, String? wall}) {
      final cell = IVec3(x0 + dx, y0 + dy, z0 - 3);
      if (wall != null) world.setBlock(cell + const IVec3(0, 0, -1), Blocks.indexOf(wall));
      world.setBlock(cell, Blocks.indexOf(block));
      targets.add((name, cell));
    }

    put('sunk dirt', 'dirt', -9, dy: 0); // flush with the floor: the case that lost its edges
    put('torch', 'torch', -6);
    put('slab', 'stone_slab', -3);
    put('fence', 'oak_fence', 0);
    put('door', 'door_z', 3);
    put('flower', 'flower_red', 6);
    put('wall torch', 'wall_torch', 9, dy: 2, wall: 'stone');
    put('ladder', 'ladder', 12, wall: 'stone');
    for (var dy = 2; dy <= 3; dy++) {
      world.setBlock(IVec3(x0 + 12, y0 + dy, z0 - 4), stone);
      world.setBlock(IVec3(x0 + 12, y0 + dy, z0 - 3), Blocks.indexOf('ladder'));
    }
    final sheep = Mob()..setupMob(world, this, player, Species.def('sheep'));
    sheep.position = Vector3(x0 + 0.5, floor, z0 - 7.5);
    sheep.probeWalk(Vector3.zero());
    sheep.syncNode();
    addMob(sheep);

    final shots = <String, Vector3>{};
    Future<void> aimAt(String name, Vector3 eye, Vector3 point) async {
      player.setFirstPerson(true);
      final lift = player.pivotPosition.y - player.position.y;
      await _playgroundFrame((eye: eye, target: point - Vector3(0, lift, 0)));
      flyMode = false; // the fly tick returns before `_updateAim`
      for (var i = 0; i < 6; i++) {
        _probePlace(eye);
        await nextFrame();
      }
      final b = player.outline.box;
      String f(double v) => v.toStringAsFixed(3);
      debugPrint('[probe] outline $name: ${b == null ? 'hidden' : '${f(b.x0 - point.x.floorToDouble())},${f(b.y0 - point.y.floorToDouble())},${f(b.z0 - point.z.floorToDouble())}'
          ' .. ${f(b.x1 - point.x.floorToDouble())},${f(b.y1 - point.y.floorToDouble())},${f(b.z1 - point.z.floorToDouble())} (cell-relative), '
          'size ${f(b.x1 - b.x0)} x ${f(b.y1 - b.y0)} x ${f(b.z1 - b.z0)}'} · aimed mob ${player.aimedMob?.species.id ?? '-'}');
      shots[name] = eye;
    }

    for (final (name, cell) in targets) {
      final c = cell.toVector3();
      final top = name == 'wall torch' ? 0.55 : (name == 'sunk dirt' ? 0.98 : 0.3);
      final point = c + Vector3(0.5, top, name == 'wall torch' ? 0.9 : 0.5);
      await aimAt(name, Vector3(c.x + 0.5, floor + (name == 'sunk dirt' ? 0.9 : 0.4), c.z + 2.8), point);
      final shoot = screenshotter;
      if (shoot != null && (name == 'sunk dirt' || name == 'torch' || name == 'ladder')) {
        final base = _arg('--screenshot=', '').replaceAll(RegExp(r'\.png$'), '');
        if (name == 'ladder') {
          // Close and from the side, where the rungs meet the rails.
          await _playgroundFrame((eye: c + Vector3(1.3, 0.9, 1.1), target: c + Vector3(0.5, 0.4, 0.05)));
          await nextFrame();
        }
        final file = switch (name) { 'torch' => '${base}_torch.png', 'ladder' => '${base}_ladder.png', _ => '${base}_block.png' };
        await shoot(file);
        debugPrint('[probe] outline capture: $name -> $file');
      }
    }
    // The ladder, walked into and climbed: its rungs stop the player 0.12
    // short of the wall, inside the ladder's cell, so jump still climbs.
    flyMode = false; // the close-up frame flies the eye
    player.setFirstPerson(false);
    _probePlace(Vector3(x0 + 12.5, floor, z0 - 0.5));
    await _ticks(10);
    player.probeWalk(Vector3(0, 0, -1));
    input.probeHold(GameAction.jump, true);
    var climbed = 0.0;
    var stopZ = double.infinity;
    for (var i = 0; i < 90; i++) {
      await _ticks(1);
      climbed = math.max(climbed, player.position.y - floor);
      // Below the wall's top: still on the ladder, not walking over the wall.
      if (player.position.y < floor + 2.5) stopZ = math.min(stopZ, player.position.z);
    }
    input.probeHold(GameAction.jump, false);
    player.probeWalk(Vector3.zero());
    debugPrint('[probe] outline ladder climb: nearest the wall at z ${(stopZ - (z0 - 3)).toStringAsFixed(3)} in the cell '
        '(expect ${(ladderDepth + 0.3).toStringAsFixed(3)}, against the rungs), rose ${climbed.toStringAsFixed(2)} m '
        '(expect > 3: up the ladder and onto the wall)');

    final sheepEye = Vector3(x0 + 2.3, floor + 0.9, z0 - 5.2);
    await aimAt('sheep', sheepEye, sheep.position + Vector3(0, 0.6, 0));
    final collider = Player.mobBox(sheep);
    debugPrint('[probe] outline sheep collider: ${collider.x1 - collider.x0} x ${collider.y1 - collider.y0} x ${collider.z1 - collider.z0}');
    final shoot = screenshotter;
    final base = _arg('--screenshot=', '').replaceAll(RegExp(r'\.png$'), '');
    if (shoot != null) {
      await shoot('${base}_mob.png');
      debugPrint('[probe] outline capture: sheep -> ${base}_mob.png');
    }
    // A giant: the outline reaches the top of its head.
    sheep.removed = true;
    final giant = Mob()..setupMob(world, this, player, Species.def('zombie'));
    giant.setAffix('Giant');
    giant.position = Vector3(x0 + 0.5, floor, z0 - 7.5);
    giant.stun(999.0, false);
    giant.syncNode();
    addMob(giant);
    await aimAt('giant zombie', Vector3(x0 + 1.2, floor + 0.2, z0 - 5.2), giant.position + Vector3(0, 1.6, 0));
    final gb = player.outline.box;
    debugPrint('[probe] outline giant zombie: box top ${gb == null ? '-' : (gb.y1 - floor).toStringAsFixed(2)} m, '
        'collider ${giant.height.toStringAsFixed(2)} m, model ${giant.modelTop().toStringAsFixed(2)} m');
    if (shoot != null) {
      await shoot('${base}_giant.png');
      debugPrint('[probe] outline capture: giant zombie -> ${base}_giant.png');
    }
  }

  /// `--item-probe`: one model per item, drawn in the hand, on the ground and
  /// in the bag. The hotbar is filled with a spread of kinds and one of each
  /// is dropped on a cleared pad; for each the model's size, the drop's size
  /// and the icon's face count are printed, and the first-person pickaxe's
  /// head direction is measured in view space (it must run into the screen,
  /// not across it). With `--screenshot=<png>`, `_drops.png` (the drops under
  /// the hotbar), `_fp.png` (the pickaxe in the fist) and `_bag.png` (the
  /// inventory) are captured.
  Future<void> _probeItems() async {
    const ids = ['iron_pickaxe', 'wooden_axe', 'iron_sword', 'bow', 'torch', 'flower_red', 'stone_slab', 'apple', 'iron_armor'];
    const more = ['stone', 'oak_planks', 'tall_grass', 'diamond_pickaxe', 'stone_shovel', 'crystal_staff', 'arrow', 'cooked_beef', 'glider'];
    for (var i = 0; i < ids.length; i++) {
      player.inventory.setSlot(i, ItemStack(ids[i], 1));
    }
    for (var i = 0; i < more.length; i++) {
      player.inventory.setSlot(ids.length + i, ItemStack(more[i], 1));
    }
    final x0 = player.position.x.floor();
    final z0 = player.position.z.floor();
    var y0 = 0;
    for (var x = x0 - 8; x <= x0 + 8; x++) {
      for (var z = z0 - 8; z <= z0 + 4; z++) {
        y0 = math.max(y0, world.groundHeight(x, z));
      }
    }
    final stone = Blocks.indexOf('stone');
    for (var x = x0 - 8; x <= x0 + 8; x++) {
      for (var z = z0 - 8; z <= z0 + 4; z++) {
        world.setBlock(IVec3(x, y0, z), stone);
        for (var y = y0 + 1; y < y0 + 8; y++) {
          world.setBlock(IVec3(x, y, z), Blocks.air);
        }
      }
    }
    timeOfDay = 0.3;
    weather.force('clear');
    final floor = y0 + 1.0;
    String f(double v) => v.toStringAsFixed(2);
    for (var i = 0; i < ids.length; i++) {
      final id = ids[i];
      final shape = VoxelMeshBuilder.itemShape(id);
      final b = shape.bounds();
      final model = ItemDrop.dropModel(id);
      final k = model.scale.x;
      // Never picked up: the probe only looks at them.
      spawnDrop(Vector3(x0 - 3.2 + i * 0.8, floor, z0 - 3.5), id, 1, Vector3.zero(), 1e9);
      debugPrint('[probe] item $id: ${shape.flat ? 'flat' : 'solid'}${shape.block ? ' block' : ''}, '
          'model ${f(b.max.x - b.min.x)} x ${f(b.max.y - b.min.y)} x ${f(b.max.z - b.min.z)} m, '
          'drop x${f(k)}, icon ${ItemIcon.faces(shape).length} faces');
    }
    await _playgroundFrame((eye: Vector3(x0 + 0.1, floor + 1.3, z0 - 0.6), target: Vector3(x0 + 0.1, floor + 0.2, z0 - 3.5)));
    for (var i = 0; i < 30; i++) {
      _probePlace(Vector3(x0 + 0.1, floor + 1.3, z0 - 0.6));
      await nextFrame();
    }
    final base = _arg('--screenshot=', '').replaceAll(RegExp(r'\.png$'), '');
    final shoot = screenshotter;
    if (shoot != null) {
      await shoot('${base}_drops.png');
      debugPrint('[probe] item capture: drops -> ${base}_drops.png');
    }

    // The fist: where the pickaxe's head runs, in the camera's own axes.
    player.selectedSlot = 0;
    final eye = Vector3(x0 + 0.5, floor + 1.6, z0 + 2.5);
    await _playgroundFrame((eye: eye, target: eye + Vector3(0, -0.15, -4)));
    for (var i = 0; i < 20; i++) {
      _probePlace(eye);
      await nextFrame();
    }
    final head = player.handView.heldNode;
    if (head != null) {
      final m = head.globalTransform;
      // The head is built across the model's own X.
      final across = m.transform3(Vector3(1, 0, 0)) - m.transform3(Vector3.zero());
      final view = player.handView.root.globalTransform;
      final right = view.getColumn(0).xyz, up = view.getColumn(1).xyz, back = view.getColumn(2).xyz;
      across.normalize();
      debugPrint('[probe] item fp pickaxe head in view space: right ${f(across.dot(right))}, '
          'up ${f(across.dot(up))}, depth ${f(across.dot(back))}');
    }
    if (shoot != null) {
      await shoot('${base}_fp.png');
      debugPrint('[probe] item capture: first person -> ${base}_fp.png');
      openStation('crafting_table', IVec3.zero);
      for (var i = 0; i < 10; i++) {
        await nextFrame();
      }
      await shoot('${base}_bag.png');
      debugPrint('[probe] item capture: bag -> ${base}_bag.png');
    }
  }

  /// `--anim-probe`: the creatures move like creatures, and the saddle moves
  /// the camera. On a cleared pad one creature of each body is spawned and
  /// steered by hand, and what its limbs actually do is measured: a flier's
  /// wings must sweep the whole beat while a chicken with its feet on the
  /// floor keeps them folded, and must beat the moment that chicken is off the
  /// ground; every walker's legs must swing while it walks and settle back to
  /// rest when it stops; a blob must splat the tick it lands. Then the camera
  /// is measured on foot and in the saddle, first person and third, because a
  /// trot is the walk's own sway turned up and nothing else.
  Future<void> _probeAnimation() async {
    final x0 = player.position.x.floor() + 4;
    final z0 = player.position.z.floor();
    var y0 = 0;
    for (var x = x0 - 4; x <= x0 + 90; x++) {
      for (var z = z0 - 4; z <= z0 + 4; z++) {
        y0 = math.max(y0, world.groundHeight(x, z));
      }
    }
    final stone = Blocks.indexOf('stone');
    for (var x = x0 - 4; x <= x0 + 90; x++) {
      for (var z = z0 - 4; z <= z0 + 4; z++) {
        world.setBlock(IVec3(x, y0, z), stone);
        for (var y = y0 + 1; y < y0 + 10; y++) {
          world.setBlock(IVec3(x, y, z), Blocks.air);
        }
      }
    }
    final floor = y0 + 1.0;
    // Parked at the far end of the pad while the creatures are measured: a
    // zombie 12 m away chases instead of standing, and a chased zombie never
    // lets its legs settle.
    final park = Vector3(x0 + 80.5, floor, z0 + 0.5);
    _probePlace(park);
    await _ticks(20);

    Mob spawn(String id, Vector3 at) {
      final m = Mob();
      m.setupMob(world, this, player, Species.def(id));
      m.position = at;
      m.syncNode();
      addMob(m);
      return m;
    }

    // The widest either way a named angle of [m] gets while it walks toward
    // [dir] (or stands, for a zero direction), ignoring the first [settle]
    // ticks — the walk eases in and out, so a window that starts at the
    // handover measures the easing rather than the pose it eases into.
    Future<({double lo, double hi})> swing(Mob m, String part, int axis, Vector3 dir, int ticks, {int settle = 0}) async {
      m.probeWalk(dir);
      var lo = 1e9, hi = -1e9;
      for (var i = 0; i < ticks; i++) {
        await _ticks(1);
        final a = m.partAngles(part);
        if (a == null || i < settle) continue;
        final v = axis == 0 ? a.x : (axis == 1 ? a.y : a.z);
        lo = math.min(lo, v);
        hi = math.max(hi, v);
      }
      return (lo: lo, hi: hi);
    }

    // The wings. A parrot flies, so it beats the whole time; a chicken on the
    // floor keeps its folded; the same chicken dropped from four blocks up has
    // to beat before it lands.
    final parrot = spawn('parrot', Vector3(x0 + 0.5, floor + 3.0, z0 + 0.5));
    final chicken = spawn('chicken', Vector3(x0 + 3.5, floor, z0 + 0.5));
    await _ticks(30);
    final flier = await swing(parrot, 'wing1', 2, Vector3.zero(), 60);
    final perched = await swing(chicken, 'wing1', 2, Vector3.zero(), 60, settle: 40);
    debugPrint('[probe] anim wings: a flying parrot sweeps ${flier.lo.toStringAsFixed(2)}..${flier.hi.toStringAsFixed(2)} rad '
        '(expect about ${(-Mob.wingSweep).toStringAsFixed(2)}..${Mob.wingSweep.toStringAsFixed(2)}); a chicken standing on the floor '
        'holds ${perched.lo.toStringAsFixed(2)}..${perched.hi.toStringAsFixed(2)} (expect the fold, ${Mob.wingFold.toStringAsFixed(2)})');
    chicken.position = Vector3(x0 + 3.5, floor + 4.0, z0 + 0.5);
    chicken.velocity = Vector3.zero();
    chicken.syncNode();
    final falling = await swing(chicken, 'wing1', 2, Vector3.zero(), 22);
    debugPrint('[probe] anim wings: the same chicken dropped four blocks beats '
        '${falling.lo.toStringAsFixed(2)}..${falling.hi.toStringAsFixed(2)} on the way down (expect a spread, not the fold)');

    // The legs. Every walker swings them while it walks and lets them settle
    // when it stops — the walk is eased in and out, so nothing snaps.
    for (final (id, part, axis) in const [
      ('sheep', 'leg0', 0),
      ('zombie', 'leg0', 0),
      ('spider', 'leg0', 2),
      ('chicken', 'leg0', 0),
    ]) {
      final m = spawn(id, Vector3(x0 + 8.5, floor, z0 + 0.5));
      await _ticks(20);
      final walked = await swing(m, part, axis, Vector3(1, 0, 0), 90, settle: 30);
      final stopped = await swing(m, part, axis, Vector3.zero(), 90, settle: 60);
      debugPrint('[probe] anim legs $id: walking ${walked.lo.toStringAsFixed(2)}..${walked.hi.toStringAsFixed(2)} rad '
          '(expect a spread), settled ${stopped.lo.toStringAsFixed(2)}..${stopped.hi.toStringAsFixed(2)} '
          '(expect it back near rest)');
      m.removed = true;
    }

    // The blob. It stretches off the top of a hop and splats the tick it lands.
    final slime = spawn('slime', Vector3(x0 + 12.5, floor + 2.0, z0 + 0.5));
    await _ticks(5);
    var stretch = -1e9, splat = 1e9;
    var wasFloor = slime.onFloor;
    var landed = false;
    slime.probeWalk(Vector3(1, 0, 0));
    for (var i = 0; i < 150; i++) {
      await _ticks(1);
      if (!slime.onFloor) stretch = math.max(stretch, slime.squash());
      if (slime.onFloor && !wasFloor) landed = true;
      if (landed) splat = math.min(splat, slime.squash());
      wasFloor = slime.onFloor;
    }
    slime.probeRelease();
    debugPrint('[probe] anim blob: tallest in the air ${stretch.toStringAsFixed(3)} (expect > 1.0), '
        'flattest after landing ${splat.toStringAsFixed(3)} (expect < 1.0), landed=$landed');
    slime.removed = true;

    // The camera. The same walk on foot and in the saddle, in both views: the
    // saddle is the walk's own sway multiplied, so the ride figure has to come
    // out near the walk's times `Player.gaitAmplitude` — and a horse at 8.5 m/s
    // is already past the speed clamp, so the walk figure it multiplies is the
    // clamped one, not the one a body on foot reaches.
    final start = Vector3(x0 + 4.5, floor, z0 + 0.5);
    Future<double> peakBob(bool firstPerson, int ticks) async {
      player.setFirstPerson(firstPerson);
      var peak = 0.0;
      for (var i = 0; i < ticks; i++) {
        await _ticks(1);
        peak = math.max(peak, player.viewBobOffset().length);
      }
      return peak;
    }

    player.setLook(0.0, 0.0);
    _probePlace(start);
    await _ticks(30);
    player.probeWalk(Vector3(1, 0, 0));
    final footFp = await peakBob(true, 90);
    _probePlace(start);
    final footTp = await peakBob(false, 90);
    player.probeWalk(Vector3.zero());
    _probePlace(start);
    await _ticks(60);

    // A tamed horse, ridden. Each run starts back at the near end of the pad:
    // a horse covers 17 m in two seconds and would otherwise spend the second
    // run standing in the terrain past the end of it.
    final horse = spawn('horse', Vector3(x0 + 5.5, floor, z0 + 0.5));
    horse.tamed = true;
    mobs.remove(horse);
    pets.add(horse);
    await _ticks(20);
    _probePlace(horse.position + Vector3(0, 1.0, 0));
    player.mountHorse(horse);
    void rewind() {
      horse.position = Vector3(x0 + 5.5, floor, z0 + 0.5);
      horse.velocity = Vector3.zero();
      horse.syncNode();
      player.position = Player.saddlePosition(horse);
      player.syncNode();
    }

    player.probeWalk(Vector3(1, 0, 0));
    final rideFp = await peakBob(true, 90);
    rewind();
    final rideTp = await peakBob(false, 90);
    rewind();
    input.probeHold(GameAction.sprint, true);
    final gallop = await peakBob(false, 90);
    input.probeHold(GameAction.sprint, false);
    player.probeWalk(Vector3.zero());
    final rode = player.position.x - (x0 + 5.5);
    player.dismount();
    final trot = Player.gaitAmplitude(mounted: true, sprinting: false);
    final run = Player.gaitAmplitude(mounted: true, sprinting: true);
    debugPrint('[probe] anim camera: on foot peak first person ${footFp.toStringAsFixed(4)} third ${footTp.toStringAsFixed(4)}; '
        'in the saddle first ${rideFp.toStringAsFixed(4)} third ${rideTp.toStringAsFixed(4)} '
        '(expect the two views equal, and ${trot.toStringAsFixed(1)}x a clamped walk = '
        '${(1.7 * Player.bobAmplitude * trot).toStringAsFixed(4)}), galloping ${gallop.toStringAsFixed(4)} '
        '(expect ${(1.7 * Player.bobAmplitude * run).toStringAsFixed(4)}, more than the trot); the gallop covered '
        '${rode.toStringAsFixed(1)} m, so it was moving');

    // Fly mode (F5) walks on the air: the arms swing along the body instead
    // of the glide's spread (rz 1.4), and a still flyer stands at rest.
    flyMode = true;
    _probePlace(start + Vector3(0, 3.0, 0));
    player.probeWalk(Vector3(1, 0, 0));
    var spread = 0.0, legLo = 0.0, legHi = 0.0;
    for (var i = 0; i < 90; i++) {
      await _ticks(1);
      final pm = player.model;
      spread = math.max(spread, math.max(pm.armL.rz.abs(), pm.armR.rz.abs()));
      if (i > 20) {
        legLo = math.min(legLo, pm.legL.rx);
        legHi = math.max(legHi, pm.legL.rx);
      }
    }
    player.probeWalk(Vector3.zero());
    await _ticks(60);
    final still = math.max(player.model.armL.rz.abs(), player.model.legL.rx.abs());
    flyMode = false;
    _probePlace(start);
    await _ticks(30);
    debugPrint('[probe] anim fly: arm spread ${spread.toStringAsFixed(2)} rad (expect < 0.1, never the glide\'s 1.4), '
        'leg swing ${legLo.toStringAsFixed(2)}..${legHi.toStringAsFixed(2)} (expect a stride, about -0.65..0.65), '
        'hovering still ${still.toStringAsFixed(2)} (expect ~0)');

    // The dodge dash (Left Alt): walking backward it goes backward and the
    // body turns to face it; it leans in with the arms thrown back, the legs
    // open, and it leaves the floor a little. Then a sideways one, captured
    // from the side mid-dash.
    player.setFirstPerson(false);
    player.setLook(math.pi / 2, 0.0); // the camera looks down -X, so backward is +X
    player.probeWalk(Vector3(1, 0, 0));
    await _ticks(10);
    player.stamina = player.maxStamina;
    final dashFrom = player.position.clone();
    player.probeDodge();
    var dashIn = 0.0, arms = 0.0, legOpen = 0.0, rise = 0.0, faceErr = 0.0;
    for (var i = 0; i < 40; i++) {
      await _ticks(1);
      final pm = player.model;
      dashIn = math.max(dashIn, pm.dashWeight);
      arms = math.min(arms, pm.armL.rx);
      legOpen = math.max(legOpen, pm.legL.rx - pm.legR.rx);
      rise = math.max(rise, player.position.y - dashFrom.y);
      // Facing +X is a yaw of -pi/2.
      if (i == 12) faceErr = (((pm.yaw + math.pi / 2) + math.pi) % (math.pi * 2) - math.pi).abs();
    }
    player.probeWalk(Vector3.zero());
    final dashed = player.position - dashFrom;
    await _ticks(30);
    debugPrint('[probe] anim dash: backward moved ${dashed.x.toStringAsFixed(2)} m along +X (expect > 3), '
        'facing off by ${faceErr.toStringAsFixed(2)} rad (expect ~0), pose in ${dashIn.toStringAsFixed(2)}, '
        'arms ${arms.toStringAsFixed(2)} rad (expect ~${PlayerModel.dashArms}), legs open ${legOpen.toStringAsFixed(2)} rad, '
        'rose ${rise.toStringAsFixed(2)} m (expect ~0.3), pose after ${player.model.dashWeight.toStringAsFixed(2)} (expect 0)');
    final dashShot = screenshotter;
    if (dashShot != null) {
      _probePlace(start);
      player.setLook(0.0, -0.15); // the camera looks down -Z, so right is +X
      player.probeWalk(Vector3(1, 0, 0));
      await _ticks(10);
      player.stamina = player.maxStamina;
      player.probeDodge();
      await _ticks(7);
      await dashShot('${_arg('--screenshot=', '').replaceAll(RegExp(r'\.png$'), '')}_dash.png');
      player.probeWalk(Vector3.zero());
      await _ticks(40);
      debugPrint('[probe] anim dash capture: a dash to the right, seen from behind the camera line -> _dash.png');
    }
    _probePlace(start);
    await _ticks(10);

    // And the picture of it: a hovering parrot with its wings out beside a
    // chicken standing with its own folded, both seen from the side, where a
    // wing that never opened or never shut shows at a glance.
    final shoot = screenshotter;
    if (shoot == null) return;
    final base = _arg('--screenshot=', '').replaceAll(RegExp(r'\.png$'), '');
    parrot.position = Vector3(x0 + 0.4, floor + 1.5, z0 + 0.5);
    parrot.syncNode();
    chicken.position = Vector3(x0 + 2.4, floor, z0 + 0.5);
    chicken.velocity = Vector3.zero();
    chicken.syncNode();
    // A few ticks past the placement, so the two wings are caught mid-stroke
    // rather than flat out at the peak, where a hinge and a stroke look alike.
    await _ticks(3);
    final at = Vector3(x0 + 1.4, floor + 1.1, z0 + 0.5);
    await _playgroundFrame((eye: at + Vector3(-1.2, 0.9, -2.6), target: at));
    await shoot('${base}_wings.png');
    debugPrint('[probe] anim wings capture: a flying parrot at ${parrot.position} (gone=${parrot.removed}) beside a chicken '
        'standing at ${chicken.position} (gone=${chicken.removed}) -> ${base}_wings.png '
        '(the parrot\'s wings out, the chicken\'s folded)');

    // And the four-legged half, side on and mid-stride: the diagonal pairs
    // have to be apart, the barrel up on its beat, and the tail behind the
    // rump rather than inside it.
    final walkers = [
      for (final (i, id) in const ['horse', 'sheep', 'wolf'].indexed)
        spawn(id, Vector3(x0 + 20.0 + i * 4.0, floor, z0 + 0.5))..probeWalk(Vector3(0, 0, 1)),
    ];
    await _ticks(30);
    // Framed on the horse alone, from behind and to one side: it walks toward
    // +Z, so the rump — and the tail that has to hang clear of it — is on the
    // -Z end, and the quarter angle keeps the two diagonals readable too.
    final trotting = walkers.first.position;
    await _playgroundFrame((eye: trotting + Vector3(-2.4, 1.7, -3.2), target: trotting + Vector3(0, 0.85, 0)));
    await shoot('${base}_walk.png');
    String pose(Mob m) {
      // The head is built ahead of the body and the tail behind it, and the
      // model is yawed to face where it walks, so the two have to come out on
      // opposite sides of the animal along its heading — a tail that reads as
      // inside the barrel would show up here as a distance near zero.
      final here = m.position;
      final head = m.partWorld('head')! - here;
      final tail = m.partWorld('tail')! - here;
      return '${m.species.id}: head ${head.z.toStringAsFixed(2)} m and tail ${tail.z.toStringAsFixed(2)} m '
          'along +Z (it walks +Z, so the head is the positive one and the tail must be clear behind it), '
          'fore leg ${m.partAngles('leg2')!.x.toStringAsFixed(2)} hind leg ${m.partAngles('leg1')!.x.toStringAsFixed(2)}';
    }

    debugPrint('[probe] anim walk capture: ${walkers.map(pose).join(' · ')} -> ${base}_walk.png '
        '(a trot: each fore leg matches the hind leg across the body from it)');
  }

  /// `--map-probe --screenshot=<png>`: the corner map, captured five times
  /// through one walk (`<name>_1.png` … `_5.png`), then the full map in its
  /// place (`<name>_full.png`). Both are frames of the one world-fixed
  /// bitmap, so the ground slides under the arrow with every step, rebuild or
  /// not, and the corner is gone from the full map's capture.
  Future<void> _probeMap() async {
    final shoot = screenshotter;
    if (shoot == null) {
      debugPrint('[probe] map: no screenshotter, nothing captured');
      return;
    }
    final base = _arg('--screenshot=', '').replaceAll(RegExp(r'\.png$'), '');
    mapView = MapView.corner;
    player.setFirstPerson(false);
    player.setLook(0.0, 0.0);
    await _ticks(150); // the first bitmap, and time for the mobs to be about
    player.probeWalk(Vector3(1, 0, 0));
    var last = player.position.clone();
    for (var i = 1; i <= 5; i++) {
      final at = player.position.clone();
      final step = math.sqrt(math.pow(at.x - last.x, 2) + math.pow(at.z - last.z, 2));
      debugPrint('[probe] map corner $i: player ${at.x.toStringAsFixed(2)},${at.z.toStringAsFixed(2)} '
          'moved ${step.toStringAsFixed(2)} m, so the ground slid ${(step * 2.5).toStringAsFixed(1)} px under the arrow · '
          '${mapStats?.call() ?? 'no map'}');
      await shoot('${base}_$i.png');
      last = at;
      if (i < 5) await _ticks(36);
    }
    player.probeWalk(Vector3.zero());
    mapView = mapView.next;
    await _ticks(150);
    await shoot('${base}_full.png');
    debugPrint('[probe] map full ($mapView): mobs ${mobs.length} pets ${pets.length} over ${visitedChunks.length} visited chunks · '
        '${mapStats?.call() ?? 'no map'}; M again: ${mapView.next}');
  }

  /// `--model-probe --screenshot=<png>`: on a cleared stone pad, facing the
  /// camera, a player model mid-chop with a pickaxe, one seen from the side
  /// mid-chop with a sword, one at rest with an axe, and a zombie. Two more
  /// captures land beside it: `_hold.png`, a model holding a block at arm's
  /// length (the block must hang off the fist, not run through the forearm),
  /// and `_ride.png`, a model on a horse (its legs must be inside the barrel).
  Future<void> _probeModel() async {
    final x0 = player.position.x.floor();
    final z0 = player.position.z.floor();
    var y0 = 0;
    for (var x = x0 - 6; x <= x0 + 6; x++) {
      for (var z = z0 - 10; z <= z0 + 2; z++) {
        y0 = math.max(y0, world.groundHeight(x, z));
      }
    }
    final stone = Blocks.indexOf('stone');
    for (var x = x0 - 6; x <= x0 + 6; x++) {
      for (var z = z0 - 10; z <= z0 + 2; z++) {
        world.setBlock(IVec3(x, y0, z), stone);
        for (var y = y0 + 1; y < y0 + 6; y++) {
          world.setBlock(IVec3(x, y, z), Blocks.air);
        }
      }
    }
    final floor = y0 + 1.0;
    timeOfDay = 0.3;
    weather.force('clear');
    void pose(double x, double yaw, String item, double swingDt, [Vector3? at]) {
      final m = PlayerModel()..build(Player.skinTone, player.classDef.shirt, Player.pantsTone, Player.hairTone);
      m.setHeld(item);
      m.yaw = yaw;
      if (swingDt > 0.0) m.swing();
      m.animate(swingDt > 0.0 ? swingDt : 0.016, 0.0, true, false, false);
      final holder = Node()..add(m.root);
      holder.position = at ?? Vector3(x, floor, z0 - 5.5);
      entities.add(holder);
    }

    pose(x0 - 1.0, 0.0, 'iron_pickaxe', 0.09);
    pose(x0 + 0.5, math.pi / 2, 'stone_sword', 0.09);
    pose(x0 + 2.0, 0.0, 'stone_axe', 0.0);
    // The held block, side on, where the arm is between the eye and the block:
    // anything of the block inside the forearm shows here.
    final holdAt = Vector3(x0 - 4.0, floor, z0 - 3.0);
    pose(0, math.pi / 2, 'dirt', 0.0, holdAt);
    // The rider: a standing horse with a model seated the way the game seats
    // one, so the capture measures `saddlePosition` and nothing else.
    final horse = Mob();
    horse.setupMob(world, this, player, Species.def('horse'));
    horse.position = Vector3(x0 + 4.0, floor, z0 - 2.0);
    horse.tamed = true;
    horse.ridden = true; // stands still, as a mount with no rider input does
    addMob(horse);
    await nextFrame(); // the mob builds its model, so `backHeight` is filled
    pose(0, 0.0, '', 0.0, Player.saddlePosition(horse));
    final eye = Vector3(x0 + 0.5, floor + 1.4, z0 - 9.5);
    // The crosshair rests on a dirt block STANDING on the pad, not sunk into
    // it: a block flush with the floor buries eleven of the outline's twelve
    // edges in the stone and lays the rest in the floor's own plane, which
    // shows nothing.
    final aimed = IVec3(x0 - 3, y0 + 1, z0 - 8);
    world.setBlock(aimed, Blocks.indexOf('dirt'));
    // `_playgroundFrame` places the feet at the eye; the first-person camera
    // sits higher, so the target drops by that lift to keep the ray on the dirt.
    player.setFirstPerson(true);
    final lift = player.pivotPosition.y - player.position.y;
    await _playgroundFrame((eye: eye, target: aimed.toVector3() + Vector3(0.5, 0.5 - lift, 0.5)));
    final zombie = Mob();
    zombie.setupMob(world, this, player, Species.def('zombie'));
    zombie.position = Vector3(x0 - 2.5, floor, z0 - 6.5);
    addMob(zombie);
    flyMode = false; // the fly tick returns before `_updateAim`; the pin holds the camera still
    for (var i = 0; i < 6; i++) {
      _probePlace(eye);
      await nextFrame();
    }
    debugPrint('[probe] model: three poses and a zombie at z=${z0 - 5.5}, camera $eye; '
        'aimed ${player.aimedBlock} (dirt at $aimed) outline visible=${player.highlight.visible} at ${player.highlight.position}');
    final shoot = screenshotter;
    if (shoot != null) {
      final base = _arg('--screenshot=', '').replaceAll(RegExp(r'\.png$'), '');
      // Far enough back that the probe's own third-person body is not in the
      // way, and off to the side so the arm crosses in front of the block.
      await _playgroundFrame((eye: holdAt + Vector3(-2.8, 1.3, -2.8), target: holdAt + Vector3(0.0, 1.0, 0.0)));
      await shoot('${base}_hold.png');
      debugPrint('[probe] model hold: a block in the hand at $holdAt -> ${base}_hold.png');
      final seat = Player.saddlePosition(horse);
      await _playgroundFrame((eye: horse.position + Vector3(-3.4, 1.9, -1.6), target: horse.position + Vector3(0.0, 1.0, 0.0)));
      await shoot('${base}_ride.png');
      debugPrint('[probe] model ride: horse feet ${horse.position.y.toStringAsFixed(2)} back ${horse.backHeight.toStringAsFixed(2)} '
          'rider feet ${seat.y.toStringAsFixed(2)} hips ${(seat.y + 0.66).toStringAsFixed(2)} '
          '(the hips must land on the back line, so the legs are inside the barrel) -> ${base}_ride.png');
    }
    flyMode = false;
    _pinCameraTo = () => eye.clone();
  }

  Future<void> _probeStage22() async {
    final x0 = player.position.x.floor() + 3;
    final z0 = player.position.z.floor();
    // The pad's stone row sits at the HIGHEST ground of its footprint, so no
    // lake or river can share its level (Godot's first draft exposed a shore
    // and flooded the walks); the walk floor is y0 + 1. The footprint is
    // 16 x 20: every puddle the probe pours stays on the pad.
    var y0 = 0;
    for (var x = x0 - 3; x < x0 + 13; x++) {
      for (var z = z0 - 4; z < z0 + 16; z++) {
        y0 = math.max(y0, world.groundHeight(x, z));
      }
    }
    final lo = IVec3(x0 - 3, y0 + 1, z0 - 4);
    final hi = IVec3(x0 + 12, y0 + 4, z0 + 15); // the counted volume: the pad footprint, 4 high
    final stone = Blocks.indexOf('stone');
    for (var x = lo.x; x <= hi.x; x++) {
      for (var z = lo.z; z <= hi.z; z++) {
        world.setBlock(IVec3(x, y0, z), stone);
        for (var y = y0 + 1; y < y0 + 7; y++) {
          world.setBlock(IVec3(x, y, z), Blocks.air);
        }
      }
    }
    final stairs = Blocks.stairsFacing(Blocks.indexOf('oak_stairs_n'), 1, 0);
    world.setBlock(IVec3(x0 + 2, y0 + 1, z0), Blocks.indexOf('oak_slab'));
    world.setBlock(IVec3(x0 + 5, y0 + 1, z0), stairs);
    world.setBlock(IVec3(x0 + 6, y0 + 1, z0), Blocks.indexOf('oak_planks'));
    world.setBlock(IVec3(x0 + 9, y0 + 1, z0), Blocks.indexOf('oak_fence'));
    final start = Vector3(x0 + 0.5, y0 + 1.1, z0 + 0.5);
    debugPrint('[probe] stage22 site x0=$x0 y0=$y0 z0=$z0 (walk floor y=${y0 + 1})');
    final slab = await _stage22Walk(start, x0 + 2.2, 90, false);
    debugPrint('[probe] stage22 slab top y=${slab.y.toStringAsFixed(3)} (expect ${(y0 + 1.5).toStringAsFixed(1)}) '
        'at x=${slab.x.toStringAsFixed(2)} on_floor=${slab.floor}');
    final stair = await _stage22Walk(start, x0 + 6.3, 150, false);
    debugPrint('[probe] stage22 stairs top y=${stair.y.toStringAsFixed(3)} (expect ${y0 + 2}) '
        'at x=${stair.x.toStringAsFixed(2)} max_vy=${stair.maxVy.toStringAsFixed(2)}');
    final fence = await _stage22Walk(start, x0 + 20.0, 220, true, x0 + 8.5);
    debugPrint('[probe] stage22 fence (one block: the player jumps it) x=${fence.x.toStringAsFixed(3)} (post face ${(x0 + 9.375).toStringAsFixed(3)}) '
        'max y=${fence.maxY.toStringAsFixed(3)} fence cleared=${fence.maxX > x0 + 9.7}');
    player.probeWalk(Vector3.zero());
    player.position = Vector3(x0 - 2.5, y0 + 1.1, z0 - 3.5);
    player.velocity = Vector3.zero();
    player.syncNode();
    // Liquids: a source in mid-air spreads over the pad, drains when scooped,
    // then lava meets water.
    final source = IVec3(x0 + 2, y0 + 3, z0 + 6);
    world.setBlock(source, Blocks.indexOf('water'));
    await _stage22Settle(2.0);
    final water = _stage22Count(lo, hi);
    debugPrint('[probe] stage22 water cells=${water.water} (expect >20 and <=60) max dist=${water.dist} '
        'flow updates=${world.flowUpdates}');
    world.setBlock(source, Blocks.air);
    await _stage22Settle(3.0);
    final drained = _stage22Count(lo, hi);
    debugPrint('[probe] stage22 water after drain=${drained.water} (expect 0) queue=${world.flowPending}');
    world.setBlock(IVec3(x0 + 8, y0 + 2, z0 + 8), Blocks.indexOf('lava'));
    world.setBlock(IVec3(x0 + 8, y0 + 2, z0 + 10), Blocks.indexOf('water'));
    await _stage22Settle(3.0);
    final mixed = _stage22Count(lo, hi);
    debugPrint('[probe] stage22 lava cells=${mixed.lava} water cells=${mixed.water}');
    debugPrint('[probe] stage22 obsidian/cobblestone=${mixed.hard} (expect >=1)');
    // A second water source keeps a puddle for the capture, then the camera
    // hovers over the pad.
    world.setBlock(source, Blocks.indexOf('water'));
    await _stage22Settle(1.5);
    flyMode = true;
    player.setFirstPerson(true);
    final eye = Vector3(x0 + 5.0, y0 + 8.0, z0 - 6.0);
    final target = Vector3(x0 + 4.5, y0 + 1.0, z0 + 5.0);
    final dir = target - eye;
    player.setLook(math.atan2(-dir.x, -dir.z), math.atan2(dir.y, math.sqrt(dir.x * dir.x + dir.z * dir.z)));
    for (var i = 0; i < 30; i++) {
      player.position = eye.clone();
      player.velocity = Vector3.zero();
      player.syncNode();
      await nextFrame();
    }
    _pinCameraTo = () => eye.clone();
    debugPrint('[probe] stage22 capture from $eye toward $target');
  }

  /// Walk +x from [start] until [stopX], for [ticks] simulation ticks; with
  /// [jump] the player jumps once, the moment a wall past [jumpAfterX] stops
  /// it. Reports where it ended and the highest it got.
  Future<({double x, double y, bool floor, double maxX, double maxY, double maxVy})> _stage22Walk(
      Vector3 start, double stopX, int ticks, bool jump, [double jumpAfterX = 0.0]) {
    player.position = start.clone();
    player.velocity = Vector3.zero();
    player.probeWalk(Vector3(1, 0, 0));
    var maxY = start.y, maxX = start.x, maxVy = 0.0;
    var jumped = false;
    var i = 0;
    final done = Completer<({double x, double y, bool floor, double maxX, double maxY, double maxVy})>();
    _probeTick = () {
      final p = player.position;
      maxY = math.max(maxY, p.y);
      maxX = math.max(maxX, p.x);
      maxVy = math.max(maxVy, player.velocity.y);
      if (_hasArg('--trace') && i % 5 == 0) {
        debugPrint('[trace] walk f$i pos $p vel ${player.velocity} floor ${player.onFloor} wall ${player.hitWall} water ${player.inLiquid}');
      }
      if (p.x >= stopX) player.probeWalk(Vector3.zero());
      if (jump && !jumped && player.hitWall && player.onFloor && p.x > jumpAfterX) {
        jumped = true;
        player.velocity.y = Player.jumpVelocity;
      }
      i += 1;
      if (i >= ticks) {
        _probeTick = null;
        player.probeWalk(Vector3.zero());
        done.complete((x: p.x, y: p.y, floor: player.onFloor, maxX: maxX, maxY: maxY, maxVy: maxVy));
      }
    };
    return done.future;
  }

  Future<void> _stage22Settle(double seconds) async {
    final t0 = DateTime.now();
    while (DateTime.now().difference(t0).inMilliseconds < (seconds * 1000).round()) {
      await nextFrame();
    }
  }

  /// Liquid and hardened cells inside the volume, and the farthest flow
  /// distance seen.
  ({int water, int lava, int hard, int dist}) _stage22Count(IVec3 lo, IVec3 hi) {
    var water = 0, lava = 0, hard = 0, dist = 0;
    final cobble = Blocks.indexOf('cobblestone');
    for (var x = lo.x; x <= hi.x; x++) {
      for (var y = lo.y; y <= hi.y; y++) {
        for (var z = lo.z; z <= hi.z; z++) {
          final b = IVec3(x, y, z);
          final id = world.getBlock(b);
          final kind = Blocks.liquidKind(id);
          if (kind != '') {
            if (kind == 'water') {
              water += 1;
            } else {
              lava += 1;
            }
            dist = math.max(dist, world.flowDistOf(b));
          } else if (id == cobble || (Blocks.has('obsidian') && id == Blocks.indexOf('obsidian'))) {
            hard += 1;
          }
        }
      }
    }
    return (water: water, lava: lava, hard: hard, dist: dist);
  }

  // --- stage 25: host-owned drops, boats and bobbers, bag overflow, chest gating,
  // batched flow, predicted block edits. Host + client twins with --wait-peer;
  // the host takes --reject-one.

  /// The probe site, in the same world cells as Godot's: a 7x7 stone pad (the
  /// host fishes from its north-west corner), a walled 5x5 water basin north
  /// of it (the boat) and an empty walled 5x5 pool 10 m east (one source in
  /// its centre floods it: 24 flow cells, and nothing runs downhill).
  ({IVec3 pad, IVec3 basin, IVec3 pool, IVec3 crop, IVec3 editA, IVec3 editB}) _stage25Site() {
    final pad = IVec3.floor(Vector3(8.5, 50.0, 8.5) + Vector3(4.0, 0.0, 0.0));
    return (
      pad: pad,
      basin: pad + const IVec3(0, 0, -8),
      pool: pad + const IVec3(10, 0, 0),
      crop: const IVec3(5, 50, 8),
      editA: const IVec3(8, 45, 8),
      editB: const IVec3(9, 45, 8),
    );
  }

  Future<void> _waitMs(int ms, [bool Function()? until]) async {
    final t = DateTime.now();
    while (DateTime.now().difference(t).inMilliseconds < ms && !(until?.call() ?? false)) {
      await nextFrame();
    }
  }

  Future<void> _probeStage25Host() async {
    final net = Net.instance;
    final site = _stage25Site();
    final stone = Blocks.indexOf('stone');
    for (var dx = -3; dx < 4; dx++) {
      for (var dz = -3; dz < 4; dz++) {
        world.setBlock(site.pad + IVec3(dx, -1, dz), stone);
        for (var dy = 0; dy < 6; dy++) {
          world.setBlock(site.pad + IVec3(dx, dy, dz), Blocks.air);
        }
        final wall = dx.abs() == 3 || dz.abs() == 3;
        for (final at in [site.basin, site.pool]) {
          world.setBlock(at + IVec3(dx, -1, dz), stone);
          world.setBlock(at + IVec3(dx, 0, dz),
              wall ? stone : (at == site.basin ? Blocks.indexOf('water') : Blocks.air));
          for (var dy = 1; dy < 5; dy++) {
            world.setBlock(at + IVec3(dx, dy, dz), Blocks.air);
          }
        }
      }
    }
    // The host fishes from the pad's north-west corner, rod in hand, at the basin's centre cell.
    player.position = site.pad.toVector3() + Vector3(-2.0, 0.0, -2.0);
    player.velocity = Vector3.zero();
    player.syncNode();
    player.inventory.setSlot(player.selectedSlot, ItemStack('fishing_rod', 1));
    player.setLook(0.0, -0.4);
    spawnBoat(site.basin.toVector3() + Vector3(0.5, 0.9, 0.5), 0.0);
    // A crop planted long enough ago to grow on the next pass: growth is a host block edit.
    world.setBlock(site.crop + IVec3.down, Blocks.indexOf('farmland'));
    world.setBlock(site.crop, Blocks.indexOf('wheat_0'));
    crops[site.crop] = GameState.instance.playTime - 200.0;
    _growCrops();
    debugPrint('[probe] stage25 host: crop at ${site.crop} grew to ${Blocks.idOf(world.getBlock(site.crop))} through setBlock');
    // A water source in the empty pool's centre: the flow tick's cells leave batched.
    world.setBlock(site.pool, Blocks.indexOf('water'));
    player.castFishing(site.basin);
    // A drop for the capture: on the basin's south wall, out of the host's pull
    // range and in the client's camera frame.
    spawnDrop(site.basin.toVector3() + Vector3(1.5, 1.5, 3.5), 'apple', 1, Vector3(0, 0.5, 0));
    // The client fills its bag and declares it. Godot waits a flat 1.5 s; the
    // Flutter client can still be filling its window then, so the host also
    // waits (up to 15 s) for the declared bag to show room for exactly one.
    final peer = net.puppetPositions().first.$1;
    await _waitMs(1500);
    await _waitMs(15000, () => net.declaredBag(peer)?.roomFor('iron_ingot', 3) == 1);
    final ppos = net.puppetPositions().first.$2;
    final under = IVec3(ppos.x.floor() + 1, ppos.y.floor() - 1, ppos.z.floor());
    world.setBlock(under, stone);
    world.setBlock(under + IVec3.up, Blocks.air);
    spawnDrop(ppos + Vector3(1.0, 0.4, 0.0), 'iron_ingot', 3, Vector3(0, 0.5, 0));
    final t1 = DateTime.now();
    await _waitMs(22000, () =>
        (net.stats['give_rest_spawned'] as int) > 0 &&
        (net.stats['chest_accepted'] as int) > 0 &&
        (net.stats['rejected_seq'] as int) >= 0 &&
        net.stats['boat_boarded'] == true &&
        net.boatDrivers.isEmpty &&
        DateTime.now().difference(t1).inMilliseconds > 6000);
    final boat = boats.firstWhere((b) => !b.replica);
    final s = net.stats;
    debugPrint('[probe] stage25 host: drop poses sent=${s['drop_pose_rpcs']}');
    debugPrint('[probe] stage25 host: give rest spawned=${s['give_rest_spawned']}');
    debugPrint('[probe] stage25 host: chest edit rejected(not open)=${s['chest_rejected']} accepted=${s['chest_accepted']}');
    debugPrint('[probe] stage25 host: boat spawned net_id=${boat.netId} client aboard=${s['boat_boarded']}');
    debugPrint('[probe] stage25 host: flow batch rpcs=${s['flow_batch_rpcs']} cells=${s['flow_batch_cells']}');
    debugPrint('[probe] stage25 host: rejected client edit seq=${s['rejected_seq']}');
    debugPrint('[probe] stage25 host: bobber out=${player.bobber != null} at ${player.bobber?.position}, boat at ${boat.position}');
    await _waitMs(20000, () => net.puppetPositions().isEmpty);
  }

  Future<void> _probeStage25Client() async {
    final net = Net.instance;
    final site = _stage25Site();
    player.probeFillBag('iron_ingot');
    bool restSeen() => net.liveDropReplicas().any((d) => d.itemId == 'iron_ingot' && d.count == 2);
    // The host's 3-stack is pulled in and split. Godot waits a flat 4.5 s; here
    // at least that, and on until the rest shows (the host may start later).
    final t0 = DateTime.now();
    await _waitMs(12000, () => DateTime.now().difference(t0).inMilliseconds > 4500 && restSeen());
    debugPrint('[probe] stage25 client: bag got=${net.stats['bag_got']} rest dropped seen=${restSeen()}');
    // Chests: an edit without the chest open here is refused; the same edit after opening lands.
    const chestAt = IVec3(7, 77, 7);
    net.chestSlotChanged(chestAt, 1, ItemStack('stone', 1), true);
    final view = net.openChest(chestAt);
    await _waitMs(4000, () => (net.stats['chest_states'] as int) > 0);
    net.chestSlotChanged(chestAt, 1, ItemStack('stone', 1), true);
    await _waitMs(4000, () => view.countOf('stone') > 0);
    var filled = 0;
    for (var i = 0; i < Inventory.size; i++) {
      if (!view.isEmptySlot(i)) filled++;
    }
    debugPrint('[probe] stage25 client: chest state slots=$filled (${view.toJson().take(2).toList()})');
    net.closeChest(chestAt);
    // Boats: board the host's replica, row forward for three seconds, measure how far it went.
    await _waitMs(4000, () => net.boatReplicas().isNotEmpty);
    if (net.boatReplicas().isNotEmpty) {
      final b = net.boatReplicas().first;
      player.boardBoat(b);
      final from = b.position.clone();
      player.probeWalk(Vector3(0, 0, -1));
      await _waitMs(3000);
      player.probeWalk(Vector3.zero());
      final moved = (b.position - from).length;
      debugPrint('[probe] stage25 client: aboard boat net_id=${b.netId} moved=${moved.toStringAsFixed(2)} (from $from to ${b.position})');
      player.leaveBoat();
    } else {
      debugPrint('[probe] stage25 client: aboard boat net_id=0 moved=-1 (no replica arrived)');
    }
    // Predicted edits: the host refuses the first (--reject-one), so it rolls back; the second stands.
    final wasA = world.getBlock(site.editA);
    world.setBlock(site.editA, Blocks.indexOf('oak_planks'));
    world.setBlock(site.editB, Blocks.indexOf('oak_planks'));
    await _waitMs(5000, () => net.prediction.pending.isEmpty);
    debugPrint('[probe] stage25 client: predicted=${net.stats['predicted']} rollbacks=${net.stats['rollbacks']} '
        '(cell a back to ${Blocks.idOf(wasA)}: ${world.getBlock(site.editA) == wasA}, cell b ${Blocks.idOf(world.getBlock(site.editB))})');
    var delta = 0.0;
    final where = <String>[];
    for (final d in net.liveDropReplicas()) {
      delta = math.max(delta, d.netPoseDelta());
      where.add('${d.itemId} x${d.count} at ${d.position}');
    }
    debugPrint('[probe] stage25 client: replica drop delta to host pose=${delta.toStringAsFixed(3)} '
        '(replicas ${net.liveDropReplicas().length}: ${where.join(', ')})');
    debugPrint('[probe] stage25 client: flow cells seen=${net.stats['flow_cells_seen']}');
    debugPrint('[probe] stage25 client: bobber replica of host seen=${net.stats['bobber_seen']} (live ${net.bobberReplicaCount()})');
    debugPrint('[probe] stage25 client: crop at ${site.crop} reads ${Blocks.idOf(world.getBlock(site.crop))}');
    // Frame the host puppet fishing over the basin, the capture's drop in the foreground.
    if (net.puppetBodies().isNotEmpty) {
      flyMode = true;
      player.setFirstPerson(true);
      final hostAt = net.puppetBodies().first.position.clone();
      final eye = hostAt + Vector3(3.5, 2.5, 2.5);
      final to = (hostAt + Vector3(0.5, 0.8, -4.0)) - eye;
      player.setLook(math.atan2(-to.x, -to.z), math.asin(to.y / to.length));
      for (var i = 0; i < 20; i++) {
        player.position = eye.clone();
        player.velocity = Vector3.zero();
        player.syncNode();
        await nextFrame();
      }
      debugPrint('[probe] stage25 client: capture from ${player.position}, host puppet at $hostAt');
      _pinCameraTo = () => eye.clone();
    }
  }

  // --- stage 23: temple boss + trap, loot tables, second abilities, three mobs, durability ---

  /// Waits [n] simulation ticks (Godot's `await physics_frame` n times).
  Future<void> _ticks(int n) {
    final done = Completer<void>();
    var left = n;
    _probeTick = () {
      left -= 1;
      if (left <= 0) {
        _probeTick = null;
        done.complete();
      }
    };
    return done.future;
  }

  /// The chamber floor centre (the pressure plate cell) of the temple found by
  /// `_probeStage21aTeleport`, or of a 5x5x3 sandstone chamber built beside the
  /// player when no temple was in reach.
  ({IVec3 plate, String path}) _stage23Chamber(_Stage21a? found) {
    if (found != null && found.kind == TerrainGenerator.structTemple) {
      final o = found.origin;
      // The generator's chamber floor is at the structure's y; confirm by
      // finding the plate.
      for (var dy = -2; dy < 4; dy++) {
        final cell = IVec3(o.x, o.y + dy, o.z);
        final id = world.getBlock(cell);
        if (id != Blocks.air && Blocks.idOf(id) == 'pressure_plate') return (plate: cell, path: 'temple');
      }
      debugPrint('[probe] stage23 temple at $o has no plate in its floor column');
    }
    final base = IVec3.floor(player.position) + const IVec3(6, 0, 0);
    final y0 = world.groundHeight(base.x, base.z);
    final sand = Blocks.indexOf('sandstone');
    for (var dx = -2; dx < 3; dx++) {
      for (var dz = -2; dz < 3; dz++) {
        for (var dy = -1; dy < 5; dy++) {
          final edge = dx.abs() == 2 || dz.abs() == 2 || dy == -1 || dy == 4;
          world.setBlock(IVec3(base.x + dx, y0 + dy, base.z + dz), edge ? sand : Blocks.air);
        }
      }
    }
    final plate = IVec3(base.x, y0, base.z);
    world.setBlock(plate, Blocks.indexOf('pressure_plate'));
    world.setBlock(plate + IVec3.down, Blocks.indexOf('tnt'));
    world.setBlock(plate + const IVec3(0, 4, 0), Blocks.indexOf('lamp'));
    world.setBlock(plate + const IVec3(-1, 1, -1), Blocks.indexOf('chest'));
    world.setBlock(plate + const IVec3(1, 1, -1), Blocks.indexOf('chest'));
    world.setBlock(plate + const IVec3(0, 1, 2), Blocks.air); // the south doorway
    world.setBlock(plate + const IVec3(0, 2, 2), Blocks.air);
    return (plate: plate, path: 'built');
  }

  void _probePlace(Vector3 at) {
    player.position = at.clone();
    player.velocity = Vector3.zero();
    player.syncNode();
  }

  Future<void> _probeStage23(_Stage21a? found) async {
    final chamber = _stage23Chamber(found);
    final plate = chamber.plate;
    var path = chamber.path;
    final stand = Vector3(plate.x + 0.5, plate.y + 1.05, plate.z + 1.5);
    // 1. The boss wakes when the player enters the chamber: the same check the
    // game runs each second.
    flyMode = false;
    _probePlace(stand);
    player.setLook(0.0, -0.05);
    world.updateAround(stand);
    boss = null;
    if (path == 'temple') _checkStructures();
    var b = boss;
    if (b == null) {
      b = spawnTempleBoss(plate.toVector3() + Vector3(0.5, 1.0, 0.5));
      path += '+direct';
    }
    final theBoss = b;
    theBoss.stun(120.0, false); // held still for the capture: it would step on its own plate otherwise
    debugPrint('[probe] stage23 temple boss=${theBoss.displayName()} hp=${theBoss.maxHp.toInt()} '
        '(path $path, plate $plate, player ${player.position})');
    // 2. The trap: the player on the plate lights the TNT under it (one tick).
    _probePlace(plate.toVector3() + Vector3(0.5, 0.55, 0.5));
    await _ticks(3);
    final below = world.getBlock(plate + IVec3.down);
    debugPrint('[probe] stage23 plate trap: tnt lit=${litTntCount() > 0} (plates fired ${platesFired()}, '
        'block under the plate now ${below != Blocks.air ? Blocks.idOf(below) : 'air'})');
    probeDefuseTnt(); // keep the chamber whole for the capture
    _probePlace(stand);
    // 3. Loot tables, seeded so the line is stable.
    for (final table in const ['temple', 'mine', 'ruin', 'well']) {
      final parts = [for (final st in LootTables.roll(table, math.Random(23))) '${st.id} x${st.count}'];
      debugPrint('[probe] stage23 loot $table=${parts.join(', ')}');
    }
    // 4..6 happen on a flat pad 12 m east of the chamber, out of the boss's reach.
    final pad = IVec3(plate.x + 12, 0, plate.z);
    var py = 0;
    for (var dx = -6; dx < 7; dx++) {
      for (var dz = -6; dz < 7; dz++) {
        py = math.max(py, world.groundHeight(pad.x + dx, pad.z + dz));
      }
    }
    for (var dx = -6; dx < 7; dx++) {
      for (var dz = -6; dz < 7; dz++) {
        world.setBlock(IVec3(pad.x + dx, py, pad.z + dz), Blocks.indexOf('stone'));
        for (var dy = 1; dy < 6; dy++) {
          world.setBlock(IVec3(pad.x + dx, py + dy, pad.z + dz), Blocks.air);
        }
      }
    }
    final padStand = Vector3(pad.x + 0.5, py + 1.05, pad.z + 0.5);
    _probePlace(padStand);
    player.setLook(0.0, 0.0); // north (-z)
    player.inventory.add('arrow', 64);
    for (final cls in const ['warrior', 'ranger', 'mage', 'rogue']) {
      player.probeSetClass(cls);
      _probePlace(padStand);
      final zs = <Mob>[];
      for (var i = 0; i < 3; i++) {
        final z = Mob();
        z.setupMob(world, this, player, Species.def('zombie'));
        z.position = padStand + Vector3(i - 1.0, 0.0, -2.0);
        addMob(z);
        zs.add(z);
      }
      await _ticks(1);
      final before = player.mana;
      player.probeAbility2();
      final after = player.mana;
      await _ticks(20);
      var hits = 0;
      for (final z in zs) {
        if (z.removed || z.isDead) {
          hits += 1;
          continue;
        }
        final hit = switch (cls) {
          'warrior' => z.stunned > 0.0,
          'ranger' => z.hp < z.maxHp,
          'mage' => z.slowed > 0.0,
          _ => z.blinded > 0.0 && z.state != MobState.chase && z.state != MobState.attack,
        };
        if (hit) hits += 1;
      }
      debugPrint('[probe] stage23 ability2 $cls=${player.classDef.ability2} mana ${before.round()}->${after.round()} hits=$hits');
      for (final z in zs) {
        z.removed = true;
      }
      await _ticks(1);
    }
    // 5. The three new mobs, force-spawned; the ghost starts inside a stone block.
    final sp = spawner!;
    final bat = sp.forceSpawn('bat', padStand + Vector3(-3, 1.5, -3));
    final bear = sp.forceSpawn('bear', padStand + Vector3(3, 0, -3));
    final wall = IVec3(pad.x + 4, py + 1, pad.z + 3);
    for (var dx = -1; dx < 2; dx++) {
      for (var dy = 0; dy < 3; dy++) {
        for (var dz = -1; dz < 2; dz++) {
          world.setBlock(wall + IVec3(dx, dy, dz), Blocks.indexOf('stone'));
        }
      }
    }
    final ghost = sp.forceSpawn('ghost', wall.toVector3() + Vector3(0.5, 0.2, 0.5));
    final ghostFrom = ghost.position.clone();
    await _ticks(60);
    int alive(Mob m) => !m.removed && !m.isDead ? 1 : 0;
    final moved = ghost.removed ? 0.0 : (ghost.position - ghostFrom).length;
    debugPrint('[probe] stage23 spawned bat=${alive(bat)} bear=${alive(bear)} ghost=${alive(ghost)}; '
        'ghost passes blocks=${moved > 0.3} (moved ${moved.toStringAsFixed(2)} m from inside stone, noclip ${!ghost.removed && ghost.noclip})');
    for (final m in [bat, bear, ghost]) {
      m.removed = true;
    }
    // 6. Durability: an iron sword swung five times at a zombie, then forced to
    // its last use.
    player.probeSetClass('warrior');
    _probePlace(padStand);
    player.inventory.add('iron_sword', 1);
    player.selectedSlot = player.inventory.find('iron_sword');
    final dummy = Mob();
    dummy.setupMob(world, this, player, Species.def('zombie'));
    dummy.position = padStand + Vector3(0, 0, -2.0);
    dummy.scaleToLevel(30); // outlives six iron-sword swings
    addMob(dummy);
    dummy.stun(30.0, false);
    await _ticks(1);
    final maxDur = Items.durabilityOf('iron_sword');
    for (var i = 0; i < 5; i++) {
      player.probeStrike();
      await _ticks(1);
    }
    final worn = player.inventory.durAt(player.selectedSlot);
    final broke = player.heldItem() != 'iron_sword';
    player.inventory.slots[player.selectedSlot]!.dur = 1;
    player.probeStrike();
    await _ticks(1);
    final forced = player.heldItem() == '';
    debugPrint('[probe] stage23 durability: sword $maxDur->$worn broke=$broke; forced break=$forced '
        '(zombie hp ${dummy.hp.toStringAsFixed(0)}/${dummy.maxHp.toStringAsFixed(0)})');
    dummy.removed = true;
    // The capture: first person in the south corridor, the Mummy King three
    // metres ahead.
    final door = Vector3(plate.x + 0.5, plate.y + 1.05, plate.z + 2.5);
    player.probeSetClass('warrior');
    _probePlace(door);
    player.setFirstPerson(true);
    player.setLook(0.0, 0.05);
    world.updateAround(door);
    for (var i = 0; i < 20; i++) {
      _probePlace(door);
      await nextFrame();
    }
    _pinCameraTo = () => door.clone();
    final gone = theBoss.removed || theBoss.isDead;
    debugPrint('[probe] stage23 capture from ${player.position}, boss at ${theBoss.position} '
        '(${gone ? 'gone' : 'alive'}, hp ${theBoss.hp.toStringAsFixed(0)})');
  }

  // --- stage 26: swamp + jungle, villages with traders, ambient music ----------------

  static const Map<int, String> _stage26BiomeNames = {7: 'swamp', 8: 'jungle'};

  /// The nearest chunk (by chunk distance, in rings) whose centre column is
  /// [biome], scanning [radius] chunks around [around] with [gen]; null when none.
  static ChunkPos? _stage26FindBiome(TerrainGenerator gen, ChunkPos around, int biome, int radius) {
    for (var ring = 0; ring <= radius; ring++) {
      for (var dz = -ring; dz <= ring; dz++) {
        for (var dx = -ring; dx <= ring; dx++) {
          if (math.max(dx.abs(), dz.abs()) != ring) continue;
          final c = (x: around.x + dx, z: around.z + dz);
          if (gen.biomeAt(c.x * VoxelWorld.sizeX + 8, c.z * VoxelWorld.sizeZ + 8) == biome) return c;
        }
      }
    }
    return null;
  }

  /// Stands the player at the centre of chunk [c] (on its ground) and waits for
  /// the window.
  Future<Vector3> _stage26Go(ChunkPos c) async {
    final x = c.x * VoxelWorld.sizeX + 8;
    final z = c.z * VoxelWorld.sizeZ + 8;
    final at = Vector3(x + 0.5, world.surfaceHeight(x, z) + 1.2, z + 0.5);
    _probePlace(at);
    player.spawnPoint = at.clone();
    world.updateAround(at);
    for (var i = 0; i < 600; i++) {
      await nextFrame();
      if (i > 5 && world.isIdle) break;
    }
    at.y = world.groundHeight(x, z) + 1.2;
    _probePlace(at);
    return at;
  }

  /// Block counts of the 3x3 chunks around [c] for the ids asked. "pool" counts
  /// water cells lying on mud (a swamp pool, never the sea).
  Map<String, int> _stage26Count(ChunkPos c, List<String> ids) {
    final out = {for (final id in ids) id: 0};
    final want = <int, String>{for (final id in ids) if (id != 'pool') Blocks.indexOf(id): id};
    final water = Blocks.indexOf('water');
    final mud = Blocks.indexOf('mud');
    for (var wz = (c.z - 1) * VoxelWorld.sizeZ; wz < (c.z + 2) * VoxelWorld.sizeZ; wz++) {
      for (var wx = (c.x - 1) * VoxelWorld.sizeX; wx < (c.x + 2) * VoxelWorld.sizeX; wx++) {
        for (var y = 43; y < 110; y++) {
          final id = world.getBlockXYZ(wx, y, wz);
          if (id == Blocks.air) continue;
          final name = want[id];
          if (name != null) out[name] = out[name]! + 1;
          if (out.containsKey('pool') && id == water && world.getBlockXYZ(wx, y - 1, wz) == mud) out['pool'] = out['pool']! + 1;
        }
      }
    }
    return out;
  }

  /// The nearest village (kind 4) within [radius] chunks, or null.
  StructureAt? _stage26FindVillage(int radius) {
    final here = VoxelWorld.chunkOf(IVec3.floor(player.position));
    StructureAt? best;
    var bestD = double.infinity;
    for (var dz = -radius; dz <= radius; dz += 6) {
      for (var dx = -radius; dx <= radius; dx += 6) {
        for (final s in world.structuresNear((x: here.x + dx, z: here.z + dz))) {
          if (s.type != TerrainGenerator.structVillage) continue;
          final d = math.sqrt(math.pow(s.x - player.position.x, 2) + math.pow(s.z - player.position.z, 2));
          if (d < bestD) {
            bestD = d;
            best = s;
          }
        }
      }
    }
    return best;
  }

  List<Mob> _stage26Villagers() => [for (final m in mobs) if (m.species.trader && !m.isDead && !m.removed) m];

  /// Teleports to the village and wakes its villagers; the counts of the probe line.
  Future<({int x, int z, int huts, int villagers, int chests, int beds})?> _stage26Village(int radius) async {
    final v = _stage26FindVillage(radius);
    if (v == null) return null;
    await _stage26Go(VoxelWorld.chunkOf(IVec3(v.x, 0, v.z)));
    final at = Vector3(v.x + 0.5, world.groundHeight(v.x, v.z + 5) + 1.2, v.z + 5.5);
    _probePlace(at);
    player.spawnPoint = at.clone();
    _checkStructures();
    var chests = 0, beds = 0;
    final chestId = Blocks.indexOf('chest'), bedId = Blocks.indexOf('bed');
    for (var wz = v.z - 20; wz < v.z + 21; wz++) {
      for (var wx = v.x - 20; wx < v.x + 21; wx++) {
        for (var y = v.y - 10; y < v.y + 14; y++) {
          final id = world.getBlockXYZ(wx, y, wz);
          if (id == chestId) {
            chests++;
          } else if (id == bedId) {
            beds++;
          }
        }
      }
    }
    return (x: v.x, z: v.z, huts: world.generator.villageHutCount(v.x, v.z), villagers: _stage26Villagers().length, chests: chests, beds: beds);
  }

  /// --stage26: the two biomes and their blocks, a village with its traders, one
  /// trade through the screen, the slime split, a tamed parrot, the ocelot's
  /// pace, and the music moods with the rendered frame count.
  Future<void> _probeStage26() async {
    final gen = world.generator;
    final here = VoxelWorld.chunkOf(IVec3.floor(player.position));
    final found = {7: 0, 8: 0};
    for (final c in world.chunks.keys) {
      final b = gen.biomeAt(c.x * VoxelWorld.sizeX + 8, c.z * VoxelWorld.sizeZ + 8);
      if (found.containsKey(b)) found[b] = found[b]! + 1;
    }
    debugPrint('[probe] stage26 biomes over window: swamp=${found[7]} jungle=${found[8]}');
    if (found[7] == 0 || found[8] == 0) {
      // Which seeds show both from spawn at radius 6, for the captures.
      final probeGen = TerrainGenerator(ids: Blocks.generatorIds(), seed: 1);
      var reported = 0;
      for (var seedN = 1; seedN < 61 && reported < 3; seedN++) {
        probeGen.setSeed(seedN);
        final sw = _stage26FindBiome(probeGen, (x: 0, z: 0), 7, 6);
        final jg = _stage26FindBiome(probeGen, (x: 0, z: 0), 8, 6);
        if (sw != null && jg != null) {
          debugPrint('[probe] stage26 seed $seedN has swamp at (${sw.x * 16 + 8},${sw.z * 16 + 8}) / jungle at (${jg.x * 16 + 8},${jg.z * 16 + 8})');
          reported++;
        }
      }
    }
    for (final biome in const [7, 8]) {
      final c = _stage26FindBiome(gen, here, biome, 80);
      if (c == null) {
        debugPrint('[probe] stage26 ${_stage26BiomeNames[biome]}: none within 80 chunks of spawn');
        continue;
      }
      final at = await _stage26Go(c);
      final tp = '--tp=${at.x.toInt()},${at.y.toInt()},${at.z.toInt()}';
      if (biome == 7) {
        final n = _stage26Count(c, const ['mud', 'pool', 'reeds']);
        debugPrint('[probe] stage26 swamp blocks: mud=${n['mud']} water pools=${n['pool']} reeds=${n['reeds']} (3x3 chunks at (${c.x}, ${c.z}), $tp)');
      } else {
        final n = _stage26Count(c, const ['jungle_log', 'vines', 'fern', 'melon']);
        debugPrint('[probe] stage26 jungle blocks: jungle_log=${n['jungle_log']} vines=${n['vines']} fern=${n['fern']} melon=${n['melon']} (3x3 chunks at (${c.x}, ${c.z}), $tp)');
      }
    }
    // Village
    final village = await _stage26Village(48);
    if (village == null) {
      debugPrint('[probe] stage26 village: none within 48 chunks (seed ${world.seedValue}); pick another seed');
    } else {
      debugPrint('[probe] stage26 village at (${village.x},${village.z}): huts=${village.huts} villagers=${village.villagers} '
          'chests=${village.chests} beds=${village.beds} (seed ${world.seedValue})');
    }
    // Trade
    final traders = _stage26Villagers();
    if (traders.isEmpty) {
      traders.add(spawner!.forceSpawn('villager', player.position + Vector3(2, 0.2, 0)));
      debugPrint('[probe] stage26 trade: no village villager in reach, one spawned beside the player');
    }
    final trader = traders[0];
    final offer = trader.trades[0];
    player.inventory.add(offer.take, offer.takeCount);
    String bag() => '${offer.take} x${player.inventory.countOf(offer.take)} / ${offer.give} x${player.inventory.countOf(offer.give)}';
    final before = bag();
    trade(trader);
    final traded = tradeRow(0);
    await nextFrame();
    debugPrint('[probe] stage26 trade: villager=${trader.displayName()} offers=${trader.trades.length} screen=${screen.name}; '
        'traded $offer: $traded: bag before/after=$before / ${bag()}');
    closeScreen();
    // Slime split (the children are added at the end of the tick).
    final slime = spawner!.forceSpawn('slime', player.position + Vector3(3, 0.5, 0));
    slime.takeDamage(999.0, player.position, 0.0, player);
    await _ticks(1);
    final small = mobs.where((m) => m.species.id == 'slime_small' && !m.removed).length;
    debugPrint('[probe] stage26 slime split: parent dead=${slime.isDead} -> children=$small');
    // Parrot tamed with seeds through the player's own use path.
    final parrot = spawner!.forceSpawn('parrot', player.position + Vector3(0, 1.5, 2));
    player.inventory.setSlot(8, ItemStack('wheat_seeds', 16));
    player.selectedSlot = 8;
    var tries = 0;
    while (!parrot.tamed && tries < 16) {
      player.aimedMob = parrot;
      player.probeUse();
      tries++;
    }
    debugPrint('[probe] stage26 parrot tamed=${parrot.tamed} (after $tries seeds)');
    debugPrint('[probe] stage26 ocelot speed=${Species.def('ocelot').speed.toStringAsFixed(1)} (player walk ${Player.walkSpeed.toStringAsFixed(1)})');
    // Music
    final music = Music.instance;
    String at(int biome, bool night, bool underground) {
      music.setContext(biome, night, underground);
      return '${music.currentMood} (${music.currentTrack})';
    }

    final mDay = at(2, false, false);
    final mNight = at(2, true, false);
    final mDunes = at(4, false, false);
    final mDeep = at(2, false, true);
    for (var i = 0; i < 60; i++) {
      await nextFrame();
    }
    debugPrint('[probe] stage26 music: plains day=$mDay -> night=$mNight -> desert=$mDunes -> underground=$mDeep');
    debugPrint('[probe] stage26 music tracks started=${music.handlesPlayed}, playing=${music.isPlaying}, audio device=${Sfx.ready}');
  }

  /// --stage26 --shot=biome|village|trade: stand where the capture wants before
  /// the window fills.
  void _stage26ShotPrepare(String shot) {
    if (shot == 'biome') {
      if (_arg('--tp=', '') != '') return; // the caller chose the spot
      final here = VoxelWorld.chunkOf(IVec3.floor(player.position));
      final biome = int.tryParse(_arg('--biome=', '8')) ?? 8;
      final c = _stage26FindBiome(world.generator, here, biome, 80);
      if (c == null) {
        debugPrint('[probe] stage26 shot: no biome $biome within 80 chunks');
        return;
      }
      final x = c.x * VoxelWorld.sizeX + 8, z = c.z * VoxelWorld.sizeZ + 8;
      final at = Vector3(x + 0.5, world.surfaceHeight(x, z) + 1.2, z + 0.5);
      _probePlace(at);
      player.spawnPoint = at.clone();
      world.updateAround(at);
      debugPrint('[probe] stage26 shot: biome $biome at $at');
    } else if (shot == 'village' || shot == 'trade') {
      final v = _stage26FindVillage(48);
      if (v == null) {
        debugPrint('[probe] stage26 shot: no village within 48 chunks');
        return;
      }
      // Hovering (fly mode) 8 m up and 20 m south of the well, looking north
      // and down (`--look=0,-22`): the well, the ring of huts and the villagers
      // all fit the frame.
      final at = Vector3(v.x + 0.5, world.surfaceHeight(v.x, v.z) + 9.0, v.z + 20.5);
      flyMode = true;
      _probePlace(at);
      player.spawnPoint = at.clone();
      world.updateAround(at);
      debugPrint('[probe] stage26 shot: village at (${v.x}, ${v.y}, ${v.z}), standing at $at');
    }
  }

  /// After the window filled: settle on the ground, wake the villagers, open
  /// the trade screen.
  Future<void> _stage26ShotFinish(String shot) async {
    final p = player.position.clone();
    if (_arg('--tp=', '') == '' && !flyMode) {
      p.y = world.groundHeight(p.x.toInt(), p.z.toInt()) + 1.2;
      _probePlace(p);
    }
    if (flyMode) _pinCameraTo = () => p.clone(); // a hover drifts with nobody at the keys
    if (shot == 'village' || shot == 'trade') {
      _checkStructures();
      for (var i = 0; i < 5; i++) {
        await nextFrame();
      }
      final traders = _stage26Villagers();
      debugPrint('[probe] stage26 shot: villagers=${traders.length}');
      if (shot == 'trade' && traders.isNotEmpty) {
        final t = traders[0];
        player.inventory.add(t.trades[0].take, t.trades[0].takeCount);
        trade(t);
      }
    }
  }

  /// --stage21a: stand at the nearest ruin / well / mine / temple (`--kind=5..8`
  /// picks one kind) so the capture shows it. The mine puts the player inside
  /// the corridor, the temple outside its south entrance; `--fp` switches to
  /// first person for the tight corridor.
  _Stage21a? _probeStage21aTeleport([int radius = 24]) {
    final want = int.tryParse(_arg('--kind=', '')) ?? 0;
    final wantBiome = int.tryParse(_arg('--biome=', '')) ?? -1;
    final here = VoxelWorld.chunkOf(IVec3.floor(player.position));
    StructureAt? best;
    var bestD = double.infinity;
    for (var dz = -radius; dz <= radius; dz += 4) {
      for (var dx = -radius; dx <= radius; dx += 4) {
        for (final st in world.structuresNear((x: here.x + dx, z: here.z + dz))) {
          // Kinds 5..8 by default; `--kind=4` (stage 26) reaches a village.
          if ((st.type < 5 && want != st.type) || (want != 0 && st.type != want)) continue;
          if (wantBiome >= 0 && world.biomeAt(st.x, st.z) != wantBiome) continue;
          final d = math.sqrt(math.pow(st.x - player.position.x, 2) + math.pow(st.z - player.position.z, 2));
          if (d < bestD) {
            bestD = d;
            best = st;
          }
        }
      }
    }
    if (best == null) {
      debugPrint('[probe] stage21a: no ruin / well / mine / temple within $radius chunks');
      return null;
    }
    var at = Vector3(best.x + 0.5, best.y + 1.1, best.z + 0.5);
    switch (best.type) {
      case TerrainGenerator.structVillage:
        at += Vector3(0, 0, 6);
      case TerrainGenerator.structRuin:
        at += Vector3(0, 0, 8);
      case TerrainGenerator.structWell:
        at += Vector3(0, 0, 5);
      case TerrainGenerator.structMine:
        // The lit beam is at +10.
        at = Vector3(best.x + 7.5, TerrainGenerator.mineFloorY + 1.1, best.z + 0.5);
      case TerrainGenerator.structTemple:
        at += Vector3(0, 0, 9);
      case TerrainGenerator.structFortress:
        at += Vector3(2, 0, 0); // stage 29: two blocks into the fortress hall
    }
    player.position = at.clone();
    player.velocity = Vector3.zero();
    player.spawnPoint = at.clone();
    player.setFirstPerson(_hasArg('--fp'));
    player.syncNode();
    world.updateAround(at);
    debugPrint('[probe] stage21a: teleported to kind ${best.type} at (${best.x}, ${best.y}, ${best.z}), '
        'standing at $at (${bestD.round()} m from spawn)');
    return _Stage21a(at, best.type, IVec3(best.x, best.y, best.z));
  }

  /// --stage20: a tamed horse is mounted and left, a sheep is sheared, a line
  /// is cast at a fresh water block and the bite forced, a bucket scoops the
  /// water and pours it back. The player is left on the horse with the line out
  /// so the capture shows both.
  _Stage20 _probeStage20() {
    final ahead = player.aimDirection().clone()..y = 0;
    ahead.normalize();
    final right = ahead.cross(Vector3(0, 1, 0));
    // A flat grass stage around the player so the camera, the horse and the
    // water are all in view.
    final base = IVec3.floor(player.position);
    final floorY = base.y - 1;
    for (var dx = -7; dx < 8; dx++) {
      for (var dz = -9; dz < 8; dz++) {
        world.setBlock(IVec3(base.x + dx, floorY, base.z + dz), Blocks.indexOf('grass'));
        for (var dy = 1; dy < 7; dy++) {
          world.setBlock(IVec3(base.x + dx, floorY + dy, base.z + dz), Blocks.air);
        }
      }
    }
    final horse = Mob();
    horse.setupMob(world, this, player, Species.def('horse'));
    horse.position = player.position + ahead * 3.0;
    addMob(horse);
    horse.tame(player);
    player.mountHorse(horse);
    debugPrint('[probe] stage20: riding horse ${player.isMounted()} (tamed ${horse.tamed}, ridden ${horse.ridden})');
    player.dismount();
    debugPrint('[probe] stage20: dismounted, riding ${player.isMounted()}, horse ridden ${horse.ridden}');
    final sheep = Mob();
    sheep.setupMob(world, this, player, Species.def('sheep'));
    sheep.position = player.position + ahead * 2.0 - right * 2.0;
    addMob(sheep);
    final wool = player.shearMob(sheep);
    debugPrint('[probe] stage20: sheared the sheep, $wool wool dropped, sheared ${sheep.sheared}');
    final wc = IVec3.floor(player.position + ahead * 2.0 + right * 2.0) + IVec3.down;
    world.setBlock(wc + IVec3.up, Blocks.air);
    world.setBlock(wc, Blocks.indexOf('water'));
    player.inventory.add('fishing_rod', 1);
    player.selectedSlot = player.inventory.find('fishing_rod');
    player.castFishing(wc);
    player.bobber!.forceBite();
    final got = player.catchFish();
    debugPrint('[probe] stage20: cast at $wc, bite forced, caught $got '
        '(now ${player.inventory.countOf(got)} in the bag), xp ${player.xp}, '
        'achievements ${Achievements.instance.unlocked.toList()}');
    player.inventory.add('bucket', 1);
    player.selectedSlot = player.inventory.find('bucket');
    final scooped = player.scoopLiquid(wc);
    debugPrint('[probe] stage20: scooped $scooped, held ${player.heldItem()}, '
        'block there ${Blocks.idOf(world.getBlock(wc))}');
    final poured = player.pourLiquid(wc);
    debugPrint('[probe] stage20: poured $poured, held ${player.heldItem()}, '
        'block there ${Blocks.idOf(world.getBlock(wc))}');
    player.selectedSlot = player.inventory.find('fishing_rod');
    player.castFishing(wc);
    player.mountHorse(horse);
    return _Stage20(horse, wool);
  }

  /// --stage18: poison plus a potion, an elite spider, a talent, two waypoints
  /// and a hop between them.
  Mob _probeStage18() {
    player.applyEffect('poison', 8.0);
    player.drink('speed', 30.0);
    final ahead = player.aimDirection().clone()..y = 0;
    final elite = Mob();
    elite.setupMob(world, this, player, Species.def('spider'));
    elite.position = player.position + ahead.normalized() * 3.0;
    elite.scaleToLevel(3);
    elite.setAffix('Venomous');
    addMob(elite);
    player.talentPoints = 2;
    player.learnTalent('might');
    final base = IVec3.floor(player.position);
    final a = base + const IVec3(3, 0, 0);
    final b = base + const IVec3(0, 0, 6);
    for (final w in [a, b]) {
      world.setBlock(w, Blocks.indexOf('waypoint'));
      onBlockPlaced(w, Blocks.indexOf('waypoint'));
    }
    travelToWaypoint(b);
    return elite;
  }

  // --- stage 24: persistence of entities, map markers, quests tab, settings, bed respawn ---

  /// M: the corner map, then the full map in its place, then off.
  void cycleMap() => mapView = mapView.next;

  /// The settings screen's live hook: the streaming window follows the slider
  /// at once.
  void applyRenderDistance(int radius) {
    radius = radius.clamp(4, 10);
    Settings.instance.renderRadius = radius;
    world.loadRadius = radius;
    world.unloadRadius = radius + 2;
    world.refresh();
    world.updateAround(player.position);
    world.trimWindow();
  }

  /// The tamed mounts alive right now (brown dots on both maps).
  List<Mob> tamedMounts() => [for (final m in pets) if (m.tamed && m.isMount && !m.isDead && !m.removed) m];

  /// What the maps draw, for the probe: waypoints, discovered structures, tamed
  /// mounts.
  ({int waypoints, int structures, int mounts}) markerCounts() =>
      (waypoints: waypoints.length, structures: discoveredStructures.length, mounts: tamedMounts().length);

  String _stage24Line(String tag) {
    final tamed = pets.where((m) => m.tamed && !m.isDead && !m.removed).length;
    final dropCount = drops.where((d) => !d.removed).length;
    return '[probe] stage24 $tag: boats=${boats.length} tamed=$tamed drops=$dropCount mounted=${player.isMounted()} '
        'waypoints=${waypoints.length} visited=${visitedChunks.length}';
  }

  /// --stage24, first boot: a boat, a ridden horse, a tamed wolf, two drops, a
  /// waypoint and three visited chunks, saved to the slot, then the session is
  /// rebuilt with `probe24.flag` set so the second boot loads that save and
  /// verifies it. Returns true when the reload was requested.
  Future<bool> _probeStage24() async {
    if (_stage24Verify) {
      await _probeStage24Verify();
      return false;
    }
    final ahead = player.aimDirection().clone()..y = 0;
    ahead.normalize();
    final right = ahead.cross(Vector3(0, 1, 0));
    // A flat stone pad so nothing restored falls into a hole before its chunk is in.
    final floorY = player.position.y.floor() - 1;
    final base = IVec3.floor(player.position);
    for (var dx = -8; dx < 9; dx++) {
      for (var dz = -8; dz < 9; dz++) {
        world.setBlock(IVec3(base.x + dx, floorY, base.z + dz), Blocks.indexOf('stone'));
        for (var dy = 1; dy < 7; dy++) {
          world.setBlock(IVec3(base.x + dx, floorY + dy, base.z + dz), Blocks.air);
        }
      }
    }
    player.velocity = Vector3.zero();
    spawnBoat(player.position + ahead * 4.0 + Vector3(0, 0.1, 0), 0.4);
    final horse = Mob();
    horse.setupMob(world, this, player, Species.def('horse'));
    horse.position = player.position + right * 2.0;
    addMob(horse);
    horse.tame(player);
    player.mountHorse(horse);
    final wolf = Mob();
    wolf.setupMob(world, this, player, Species.def('wolf'));
    wolf.position = player.position - right * 3.0;
    addMob(wolf);
    wolf.tame(player);
    // Two drops 5 m out, past the 3 m pull, with a delay so nothing picks them
    // up before the save.
    spawnDrop(player.position + ahead * 5.0 + right * 3.0 + Vector3(0, 0.4, 0), 'apple', 3, Vector3(0, 0.1, 0), 600.0);
    spawnDrop(player.position - ahead * 5.0 - right * 3.0 + Vector3(0, 0.4, 0), 'coal', 2, Vector3(0, 0.1, 0), 600.0);
    // The waypoint 14 blocks off the pad, on the ground there, so its label
    // clears the others on the map.
    final wp = IVec3(base.x - 14, world.groundHeight(base.x - 14, base.z + 14), base.z + 14);
    world.setBlock(wp, Blocks.indexOf('waypoint'));
    onBlockPlaced(wp, Blocks.indexOf('waypoint'));
    final here = VoxelWorld.chunkOf(base);
    visitedChunks.addAll([here, (x: here.x + 1, z: here.z), (x: here.x, z: here.z + 1)]);
    _checkStructures(); // the once-a-second discovery pass, run now so the save carries the ruin nearby
    await _ticks(5); // the drops land, the horse settles under the rider
    debugPrint(_stage24Line('pre-save'));
    await saveGame();
    File(_probe24Flag).writeAsStringSync('verify');
    debugPrint('[probe] stage24 saved to $saveDir, reloading the scene');
    reloader!();
    return true;
  }

  /// --stage24, second boot (`probe24.flag` was set): the save was loaded by
  /// [init]; this half counts what came back, then walks the map markers, the
  /// quests tab, the settings and the bed.
  Future<void> _probeStage24Verify() async {
    // The restored bodies wait for their chunks; give the physics a few ticks
    // once the window is in.
    await _ticks(8);
    debugPrint(_stage24Line('post-load'));
    final saved = jsonDecode(File('$saveDir/player.json').readAsStringSync()) as Map<String, dynamic>;
    Vector3? savedHorse;
    for (final pd in (saved['pets'] as List<dynamic>? ?? const [])) {
      final d = pd as Map<String, dynamic>;
      if (d['species'] == 'horse') {
        final p = (d['pos'] as List<dynamic>).map((e) => (e as num).toDouble()).toList();
        savedHorse = Vector3(p[0], p[1], p[2]);
      }
    }
    final horseNow = player.mount?.position;
    final delta = savedHorse != null && horseNow != null ? (savedHorse - horseNow).length : double.infinity;
    debugPrint('[probe] stage24 horse pos delta=${delta.toStringAsFixed(2)}');
    // Markers: what the maps draw (the discovery pass runs once a second in play).
    _checkStructures();
    mapView = MapView.full;
    final mc = markerCounts();
    debugPrint('[probe] stage24 markers: waypoints=${mc.waypoints} structures=${mc.structures} mounts=${mc.mounts}');
    // The quests tab.
    openJournal(JournalTabs.quests);
    await nextFrame();
    debugPrint('[probe] stage24 quests tab entries=${JournalTabs.questEntries(quests).length} '
        'active=${quests.current?.title ?? 'none'} (tab ${JournalTabs.names[journalTab]})');
    closeScreen();
    // Settings: render distance 8 -> 6 (meshed chunks), weather off, and the file.
    final before = world.meshCount;
    applyRenderDistance(6);
    for (var i = 0; i < 200; i++) {
      await nextFrame();
      if (i > 5 && world.isIdle) break;
    }
    debugPrint('[probe] stage24 settings: radius 8->6 chunks loaded before=$before after=${world.meshCount}');
    weather.force('storm');
    Settings.instance.weather = false;
    weather.setEnabled(false);
    await nextFrame();
    debugPrint('[probe] stage24 settings: weather off -> ${weather.label}');
    Settings.instance.path = '$saveRoot/settings_probe24.cfg'; // never this machine's own settings.cfg
    final written = Settings.instance.save() && File(Settings.instance.path).existsSync();
    debugPrint('[probe] stage24 settings: settings.cfg written=$written (${Settings.instance.path})');
    Settings.instance.weather = true;
    weather.setEnabled(true);
    // Bed respawn: sleep sets the spawn point (daytime: only that), death sends
    // the player back to it.
    if (player.mount != null) player.dismount();
    final bed = IVec3.floor(player.position) + const IVec3(4, 0, 0);
    world.setBlock(bed, Blocks.indexOf('bed'));
    sleepInBed(bed);
    final spawn = player.spawnPoint.clone();
    player.position = player.position + Vector3(0, 0, -6.0);
    player.velocity = Vector3.zero();
    player.takeDamage(9999.0, 'fall');
    await nextFrame();
    final died = player.isDead;
    player.respawn();
    closeScreen();
    String v3(Vector3 v) => '(${v.x.toStringAsFixed(1)},${v.y.toStringAsFixed(1)},${v.z.toStringAsFixed(1)})';
    debugPrint('[probe] stage24 respawn at bed: spawn=${v3(spawn)} died=$died -> pos=${v3(player.position)} '
        'delta=${(spawn - player.position).length.toStringAsFixed(2)}');
  }

  /// --stage27: redstone-lite on a stone pad beside spawn. Eight rows, two
  /// cells apart so no two touch: lever -> 5 wires -> lamp; button -> lamp;
  /// plate -> lamp; lever -> iron door (walked through); a wooden door used by
  /// hand; a 16-wire run for the range; a lever over TNT; a lever behind a
  /// piston with a cobblestone in front. Then the site is saved and the session
  /// rebuilt (`probe27.flag`) so the second boot reads the lamp and a wire back.
  /// Every wait counts simulation ticks (Godot's 0.3 s settle = 18 ticks).
  Future<bool> _probeStage27() async {
    final site = _stage27Site;
    if (site != null) {
      await _probeStage27Verify(site);
      return false;
    }
    final x0 = player.position.x.floor() + 3;
    final z0 = player.position.z.floor();
    var y0 = 0;
    for (var x = x0 - 3; x < x0 + 21; x++) {
      for (var z = z0 - 4; z < z0 + 17; z++) {
        y0 = math.max(y0, world.groundHeight(x, z));
      }
    }
    final stone = Blocks.indexOf('stone');
    for (var x = x0 - 3; x < x0 + 21; x++) {
      for (var z = z0 - 4; z < z0 + 17; z++) {
        world.setBlock(IVec3(x, y0, z), stone);
        for (var y = y0 + 1; y < y0 + 7; y++) {
          world.setBlock(IVec3(x, y, z), Blocks.air);
        }
      }
    }
    final y = y0 + 1;
    final home = Vector3(x0 + 8.5, y + 0.1, z0 + 9.5);
    _probePlace(home);
    final circuits = world.circuits;
    final wire = Blocks.indexOf('wire_off');
    final lever = Blocks.indexOf('lever_off');
    final lampOff = Blocks.indexOf('redstone_lamp_off');
    final lampOn = Blocks.indexOf('redstone_lamp_on');
    String idAt(IVec3 c) => Blocks.idOf(world.getBlock(c));
    Future<void> settle() => _ticks(18);
    debugPrint('[probe] stage27 site x0=$x0 y=$y z0=$z0');
    // 1. lever -> wire x5 -> lamp
    final leverA = IVec3(x0, y, z0);
    final lampA = IVec3(x0 + 6, y, z0);
    world.setBlock(leverA, lever);
    for (var i = 1; i < 6; i++) {
      world.setBlock(IVec3(x0 + i, y, z0), wire);
    }
    world.setBlock(lampA, lampOff);
    await settle();
    circuits.useBlock(leverA);
    await settle();
    final onA = world.getBlock(lampA) == lampOn;
    final wireOnA = idAt(IVec3(x0 + 5, y, z0));
    circuits.useBlock(leverA);
    await settle();
    debugPrint('[probe] stage27 lever -> wire x5 -> lamp: lamp on=$onA, lamp off=${world.getBlock(lampA) == lampOff} '
        '(wire x5 $wireOnA while on, ${idAt(IVec3(x0 + 5, y, z0))} after)');
    // 2. button -> wire x3 -> lamp, on for a second (timed in simulation ticks)
    final buttonB = IVec3(x0, y, z0 + 2);
    final lampB = IVec3(x0 + 4, y, z0 + 2);
    world.setBlock(buttonB, Blocks.indexOf('button'));
    for (var i = 1; i < 4; i++) {
      world.setBlock(IVec3(x0 + i, y, z0 + 2), wire);
    }
    world.setBlock(lampB, lampOff);
    await settle();
    var tOn = -1.0, tOff = -1.0, n = 0;
    final pressed = Completer<void>();
    circuits.useBlock(buttonB);
    _probeTick = () {
      n += 1;
      final t = n * fixedStep;
      final lit = world.getBlock(lampB) == lampOn;
      if (lit && tOn < 0.0) tOn = t;
      final off = !lit && tOn >= 0.0;
      if (off) tOff = t;
      if (off || t >= 3.0) {
        _probeTick = null;
        pressed.complete();
      }
    };
    await pressed.future;
    debugPrint('[probe] stage27 button: lamp on at t=${tOn.toStringAsFixed(2)} off at t=${tOff.toStringAsFixed(2)} '
        '(button now ${idAt(buttonB)})');
    // 3. plate -> wire x3 -> lamp while a body stands on it
    final plateC = IVec3(x0, y, z0 + 4);
    final lampC = IVec3(x0 + 4, y, z0 + 4);
    world.setBlock(plateC, Blocks.indexOf('pressure_plate'));
    for (var i = 1; i < 4; i++) {
      world.setBlock(IVec3(x0 + i, y, z0 + 4), wire);
    }
    world.setBlock(lampC, lampOff);
    await settle();
    _probePlace(plateC.toVector3() + Vector3(0.5, 0.55, 0.5));
    await settle();
    final standing = world.getBlock(lampC) == lampOn;
    _probePlace(home);
    await settle();
    debugPrint('[probe] stage27 plate: lamp on while standing=$standing, off after leaving=${world.getBlock(lampC) == lampOff}');
    // 4. lever -> wire x2 -> iron door (two tall, PANEL_X blocks a walk along +x)
    final leverD = IVec3(x0, y, z0 + 6);
    final doorD = IVec3(x0 + 3, y, z0 + 6);
    world.setBlock(leverD, lever);
    world.setBlock(IVec3(x0 + 1, y, z0 + 6), wire);
    world.setBlock(IVec3(x0 + 2, y, z0 + 6), wire);
    world.setBlock(doorD, Blocks.indexOf('iron_door_x'));
    world.setBlock(doorD + IVec3.up, Blocks.indexOf('iron_door_x'));
    await settle();
    final closedSolid = Blocks.isSolid(world.getBlock(doorD)) && idAt(doorD) == 'iron_door_x';
    circuits.useBlock(leverD);
    await settle();
    final opened = idAt(doorD) == 'iron_door_x_open' && !Blocks.isSolid(world.getBlock(doorD));
    final walk = await _stage22Walk(Vector3(x0 + 1.5, y + 0.1, z0 + 6.5), x0 + 5.0, 120, false);
    _probePlace(home);
    debugPrint('[probe] stage27 iron door: closed solid=$closedSolid -> powered open=$opened, body passes=${walk.x > x0 + 4.0} '
        '(x ${walk.x.toStringAsFixed(2)} past door cell ${doorD.x}, upper half ${idAt(doorD + IVec3.up)})');
    // 5. wooden door: the use action's own toggle
    final doorE = IVec3(x0 + 3, y, z0 + 8);
    world.setBlock(doorE, Blocks.indexOf('door_x'));
    world.setBlock(doorE + IVec3.up, Blocks.indexOf('door_x'));
    player.toggleDoor(doorE);
    debugPrint('[probe] stage27 wooden door: use toggles open=${idAt(doorE) == 'door_x_open'}');
    // 6. range: a lever and sixteen wires
    final leverF = IVec3(x0, y, z0 + 10);
    world.setBlock(leverF, lever);
    for (var i = 1; i < 17; i++) {
      world.setBlock(IVec3(x0 + i, y, z0 + 10), wire);
    }
    await settle();
    circuits.useBlock(leverF);
    await settle();
    final at15 = IVec3(x0 + 15, y, z0 + 10), at16 = IVec3(x0 + 16, y, z0 + 10);
    debugPrint('[probe] stage27 wire range: strength at 15 cells=${circuits.strengthAt(at15)}, at 16=${circuits.strengthAt(at16)} '
        '(${idAt(at15)} / ${idAt(at16)})');
    // 7. TNT under the third wire of a lever's run
    final leverG = IVec3(x0, y, z0 + 12);
    final tntG = IVec3(x0 + 3, y0, z0 + 12);
    world.setBlock(leverG, lever);
    for (var i = 1; i < 4; i++) {
      world.setBlock(IVec3(x0 + i, y, z0 + 12), wire);
    }
    world.setBlock(tntG, Blocks.indexOf('tnt'));
    await settle();
    circuits.useBlock(leverG);
    await settle();
    final litG = litTntCount() > 0 && world.getBlock(tntG) == Blocks.air;
    circuits.useBlock(leverG); // off before the defuse puts the TNT back
    await settle();
    probeDefuseTnt();
    await settle();
    debugPrint('[probe] stage27 tnt under powered wire: lit=$litG (defused, block now ${idAt(tntG)})');
    // 8. piston facing +x with a cobblestone in front, a lever behind it
    final leverH = IVec3(x0 - 1, y, z0 + 14);
    final pistonH = IVec3(x0, y, z0 + 14);
    final cobble = Blocks.indexOf('cobblestone');
    world.setBlock(leverH, lever);
    world.setBlock(pistonH, Blocks.indexOf('piston_e'));
    world.setBlock(pistonH + const IVec3(1, 0, 0), cobble);
    await settle();
    circuits.useBlock(leverH);
    await settle();
    final pushed = world.getBlock(pistonH + const IVec3(2, 0, 0)) == cobble && world.getBlock(pistonH + const IVec3(1, 0, 0)) == Blocks.air;
    debugPrint('[probe] stage27 piston: pushed cobblestone from (${pistonH.x + 1}) to (${pistonH.x + 2})=$pushed '
        '(piston now ${idAt(pistonH)})');
    // 9. redstone ore in the loaded window, below y 30 (a 7x7-chunk core)
    final ore = Blocks.indexOf('redstone_ore');
    final here = VoxelWorld.chunkOf(IVec3.floor(player.position));
    var ores = 0, scanned = 0;
    for (var dz = -3; dz < 4; dz++) {
      for (var dx = -3; dx < 4; dx++) {
        final blocks = world.chunks[(x: here.x + dx, z: here.z + dz)];
        if (blocks == null) continue;
        scanned += 1;
        for (var i = 0; i < 30 * VoxelWorld.sizeX * VoxelWorld.sizeZ; i++) {
          if (blocks[i] == ore) ores += 1;
        }
      }
    }
    debugPrint('[probe] stage27 redstone ore below y30 in window=$ores ($scanned chunks)');
    // 10. Leave the first circuit lit and the door open, save, rebuild the session.
    circuits.useBlock(leverA);
    await settle();
    debugPrint('[probe] stage27 pre-save: lamp ${idAt(lampA)} wire ${idAt(IVec3(x0 + 3, y, z0))} recomputes=${circuits.recomputes}');
    flyMode = false;
    _probePlace(home);
    await saveGame();
    File(_probe27Flag).writeAsStringSync('$x0,$y,$z0');
    debugPrint('[probe] stage27 saved to $saveDir, reloading the scene');
    reloader!();
    return true;
  }

  /// --stage27, second boot: the save was loaded by [init]; the lamp, its wire
  /// and the door come back as block ids. Then the camera hovers south of the
  /// pad looking north down the rows (`--tp=` / `--look=` override).
  Future<void> _probeStage27Verify(Map<String, int> site) async {
    final x0 = site['x0']!, y = site['y']!, z0 = site['z0']!;
    await _ticks(8);
    String idAt(IVec3 c) => Blocks.idOf(world.getBlock(c));
    final lamp = idAt(IVec3(x0 + 6, y, z0));
    final wire = idAt(IVec3(x0 + 3, y, z0));
    debugPrint('[probe] stage27 after reload: lamp on=${lamp == 'redstone_lamp_on'} wire on=${wire == 'wire_on'} '
        '(door ${idAt(IVec3(x0 + 3, y, z0 + 6))}, lever ${idAt(IVec3(x0, y, z0))})');
    flyMode = true;
    player.setFirstPerson(true);
    final eye = _arg('--tp=', '') != '' ? player.position.clone() : Vector3(x0 + 7.0, y + 6.5, z0 + 20.0);
    if (_arg('--look=', '') == '') {
      final target = Vector3(x0 + 6.0, y.toDouble(), z0 + 8.0);
      final dir = target - eye;
      player.setLook(math.atan2(-dir.x, -dir.z), math.atan2(dir.y, math.sqrt(dir.x * dir.x + dir.z * dir.z)));
    }
    for (var i = 0; i < 30 || (!world.isIdle && i < 600); i++) {
      _probePlace(eye);
      await nextFrame();
    }
    for (var i = 0; i < 10; i++) {
      _probePlace(eye);
      await nextFrame();
    }
    _pinCameraTo = () => eye.clone();
    debugPrint('[probe] stage27 capture from $eye');
  }

  // --- stage 28: rails and minecarts --------------------------------------------------

  /// The track the probe lays on a stone pad east of spawn: 12 straight rails
  /// east, a two-cell slope up onto a four-cell plateau, a corner south and six
  /// rails down (three powered, fed by a lever on the east side).
  List<IVec3> _stage28Track(int x0, int y, int z0) => [
        for (var i = 0; i < 13; i++) IVec3(x0 + i, y, z0), // 12 straight + the first slope cell
        IVec3(x0 + 13, y + 1, z0), // second slope cell
        for (var i = 0; i < 4; i++) IVec3(x0 + 14 + i, y + 2, z0), // plateau, the last cell is the corner
        for (var i = 0; i < 6; i++) IVec3(x0 + 17, y + 2, z0 + 1 + i), // south leg
      ];

  IVec3 _stage28Lever(int x0, int y, int z0) => IVec3(x0 + 18, y + 2, z0 + 2);

  Map<String, int> _stage28Orientations(List<IVec3> cells) {
    final out = {'ns': 0, 'ew': 0, 'curves': 0, 'slopes': 0, 'rails': 0};
    for (final c in cells) {
      if (!Rails.isRailAt(world, c)) continue;
      out['rails'] = out['rails']! + 1;
      final sfx = Rails.suffixOf(world.getBlock(c));
      if (sfx == 'ns' || sfx == 'ew') {
        out[sfx] = out[sfx]! + 1;
      } else if (sfx.startsWith('slope')) {
        out['slopes'] = out['slopes']! + 1;
      } else {
        out['curves'] = out['curves']! + 1;
      }
    }
    return out;
  }

  /// Simulation ticks until [done] answers true or [seconds] of 60 Hz ticks
  /// pass (Godot counts physics frames against the wall clock; gotcha 7).
  Future<bool> _stage28Until(bool Function() done, double seconds) {
    final c = Completer<bool>();
    var left = (seconds * 60).round();
    _probeTick = () {
      left -= 1;
      final ok = done();
      if (ok || left <= 0) {
        _probeTick = null;
        c.complete(ok);
      }
    };
    return c.future;
  }

  Future<void> _stage28Settle(double seconds) => _ticks((seconds * 60).round());

  /// --stage28, first boot: the track, five cart runs, a rider, a chest cart,
  /// the mine's rail and cart, then a save and a fresh session
  /// (`probe28.flag`) so the second boot reads the carts and the rails back.
  Future<bool> _probeStage28() async {
    final site = _stage28Site;
    if (site != null) {
      await _probeStage28Verify(site);
      return false;
    }
    final x0 = player.position.x.floor() + 3;
    final z0 = player.position.z.floor();
    var y0 = 0;
    for (var x = x0 - 3; x < x0 + 24; x++) {
      for (var z = z0 - 4; z < z0 + 11; z++) {
        y0 = math.max(y0, world.groundHeight(x, z));
      }
    }
    final stone = Blocks.indexOf('stone');
    for (var x = x0 - 3; x < x0 + 24; x++) {
      for (var z = z0 - 4; z < z0 + 11; z++) {
        world.setBlock(IVec3(x, y0, z), stone);
        for (var y = y0 + 1; y < y0 + 9; y++) {
          world.setBlock(IVec3(x, y, z), Blocks.air);
        }
      }
    }
    final y = y0 + 1;
    final home = Vector3(x0 + 6.5, y + 0.1, z0 + 6.5);
    _probePlace(home);
    String idAt(IVec3 c) => Blocks.idOf(world.getBlock(c));
    debugPrint('[probe] stage28 site x0=$x0 y=$y z0=$z0');
    // Supports: the slope's second step, the plateau and the south leg one and two blocks up.
    world.setBlock(IVec3(x0 + 13, y, z0), stone);
    for (var i = 0; i < 4; i++) {
      world.setBlock(IVec3(x0 + 14 + i, y + 1, z0), stone);
    }
    for (var i = 0; i < 6; i++) {
      world.setBlock(IVec3(x0 + 17, y + 1, z0 + 1 + i), stone);
    }
    world.setBlock(IVec3(x0 + 18, y + 1, z0 + 2), stone);
    final lever = _stage28Lever(x0, y, z0);
    world.setBlock(lever, Blocks.indexOf('lever_off'));
    // 1. The track, laid rail by rail through the same call the player's RMB uses.
    final cells = _stage28Track(x0, y, z0);
    final rail = Blocks.indexOf('rail_ns');
    final powered = Blocks.indexOf('powered_rail_ns');
    for (final c in cells) {
      Rails.place(world, c, c.x == x0 + 17 && c.z >= z0 + 1 && c.z <= z0 + 3 ? powered : rail);
    }
    await _stage28Settle(0.3);
    final o = _stage28Orientations(cells);
    debugPrint('[probe] stage28 placed ${o['rails']} rails: orientations ns=${o['ns']} ew=${o['ew']} '
        'curves=${o['curves']} slopes=${o['slopes']}');
    if (_hasArg('--trace')) {
      for (final c in cells) {
        debugPrint('[trace] rail $c = ${idAt(c)}');
      }
    }
    String f2(double v) => v.toStringAsFixed(2);
    // 2. Coasting: from the 12th rail west at 6 m/s; the line ends at x0 after 11 m.
    final cart = spawnMinecart(IVec3(x0 + 11, y, z0), 'minecart')!;
    cart.head(Rails.w);
    cart.speed = 6.0;
    await _stage28Settle(3.0);
    debugPrint('[probe] stage28 cart coasts: v0=6 -> reached end at x=${f2(cart.position.x)} and stopped=${cart.stopped && cart.speed == 0.0} (cell ${cart.cell})');
    // 3. The slope: east at 6 m/s from x0+8, read at the top; then from rest on the slope down.
    cart.placeOn(IVec3(x0 + 8, y, z0));
    cart.head(Rails.e);
    cart.speed = 6.0;
    final reachedTop = await _stage28Until(() => cart.cell.x >= x0 + 14, 5.0);
    final vTop = cart.speed;
    cart.placeOn(IVec3(x0 + 13, y + 1, z0));
    cart.head(Rails.w);
    await _stage28Settle(1.5);
    debugPrint('[probe] stage28 slope: uphill v 6 -> ${f2(vTop)} at top (<6, reached=$reachedTop), downhill back v=${f2(cart.speed)} (>1) at x=${f2(cart.position.x)}');
    // 4. The corner: east along the plateau, out heading south.
    cart.placeOn(IVec3(x0 + 15, y + 2, z0));
    cart.head(Rails.e);
    cart.speed = 4.0;
    final turned = await _stage28Until(() => cart.cell.z >= z0 + 1, 4.0);
    debugPrint('[probe] stage28 curve: entered heading +x, left heading +z=${cart.heading() == Rails.s} (turned=$turned, heading ${cart.heading()}, cell ${cart.cell})');
    // 5. The powered segment: the cart brakes on the dead rail, then the lever launches it.
    await _stage28Settle(0.5);
    final onDead = cart.stopped && cart.speed == 0.0 && Blocks.isPoweredRail(world.getBlock(cart.cell));
    world.circuits.useBlock(lever);
    var peak = 0.0;
    await _stage28Until(() {
      peak = math.max(peak, cart.speed);
      return false;
    }, 2.0);
    debugPrint('[probe] stage28 powered rail: lever off -> cart stopped on it=$onDead; lever on -> cart peak speed within 2 s=${f2(peak)} (>4), '
        'rails ${idAt(IVec3(x0 + 17, y + 2, z0 + 1))} / ${idAt(IVec3(x0 + 17, y + 2, z0 + 3))}');
    // 6. A rider: F beside the cart boards it, W pushes it along, F leaves it.
    cart.placeOn(IVec3(x0 + 1, y, z0));
    cart.head(Rails.e);
    _probePlace(Vector3(x0 + 2.5, y + 0.1, z0 + 0.5));
    await _ticks(1);
    player.probeInteract();
    final boarded = identical(player.cart, cart) && identical(cart.rider, player);
    final from = player.position.clone();
    player.probeWalk(Vector3(1, 0, 0));
    await _stage28Settle(1.5);
    player.probeWalk(Vector3.zero());
    final carried = (player.position - from).length;
    player.probeInteract();
    final left = player.cart == null && cart.rider == null;
    debugPrint('[probe] stage28 rider: boarded=$boarded, cart carried player ${f2(carried)} m, left=$left');
    _probePlace(home);
    // 7. A chest cart holds three apples across an open / close of the chest screen.
    final chestCart = spawnMinecart(IVec3(x0 + 10, y, z0), 'chest_minecart')!;
    chestCart.cargo!.add('apple', 3);
    openCartCargo(chestCart);
    final opened = screen == ScreenKind.inventory && identical(chest, chestCart.cargo);
    closeScreen();
    debugPrint('[probe] stage28 chest cart: stored 3 apples, reopened count=${chestCart.cargo!.countOf('apple')} (screen showed the cart\'s slots=$opened)');
    // 8. The mine's rail and its chest cart, found through the stage 21a teleport
    // (`--kind=7`). Fly mode holds the player while the far chunks load.
    flyMode = true;
    final found = _probeStage21aTeleport(48);
    if (found == null) {
      debugPrint('[probe] stage28 mine rails at kind 7: no mine within 48 chunks of seed ${world.seedValue}');
    } else {
      final origin = found.origin;
      for (var i = 0; i < 30 || (!world.isIdle && i < 1200); i++) {
        await nextFrame();
      }
      _checkStructures();
      await _ticks(1);
      var mineCart = false;
      for (final c in carts) {
        if (c.cargo != null && c.cell.y == TerrainGenerator.mineFloorY + 1 && c.cell.z == origin.z) mineCart = true;
      }
      debugPrint('[probe] stage28 mine rails at kind 7: rails=${mineRailCount(origin)} (>10) cart=$mineCart (corridor from $origin)');
    }
    // 9. Back home the same way, then save with the lever on and rebuild the session.
    _probePlace(home);
    player.spawnPoint = home.clone();
    world.updateAround(home);
    for (var i = 0; i < 30 || (!world.isIdle && i < 1200); i++) {
      _probePlace(home);
      await nextFrame();
    }
    flyMode = false;
    await _stage28Settle(0.3);
    await saveGame();
    File(_probe28Flag).writeAsStringSync('$x0,$y,$z0');
    debugPrint('[probe] stage28 saved to $saveDir, reloading the scene');
    reloader!();
    return true;
  }

  /// --stage28, second boot: the carts and the track come back from the save;
  /// then the player rides a cart along the straight for the capture (the
  /// slope, the plateau and the lit powered leg ahead).
  Future<void> _probeStage28Verify(Map<String, int> site) async {
    final x0 = site['x0']!, y = site['y']!, z0 = site['z0']!;
    await _ticks(8);
    String idAt(IVec3 c) => Blocks.idOf(world.getBlock(c));
    final o = _stage28Orientations(_stage28Track(x0, y, z0));
    Minecart? ride;
    for (final c in carts) {
      if (c.cargo == null && c.cell.y == y) ride = c;
    }
    debugPrint('[probe] stage28 after reload: carts=${carts.length} rails intact=${o['rails']} (lever ${idAt(_stage28Lever(x0, y, z0))}, '
        'powered leg ${idAt(IVec3(x0 + 17, y + 2, z0 + 2))}, player hp ${player.hp.toStringAsFixed(0)}/${player.maxHp.toStringAsFixed(0)})');
    if (ride != null && _arg('--tp=', '') == '') {
      ride.placeOn(IVec3(x0 + 5, y, z0));
      ride.head(Rails.e);
      player.boardCart(ride);
      ride.speed = 1.5;
    }
    if (_arg('--look=', '') == '') player.setLook(-110.0 * math.pi / 180.0, -18.0 * math.pi / 180.0);
    for (var i = 0; i < 30 || (!world.isIdle && i < 600); i++) {
      await nextFrame();
    }
    for (var i = 0; i < 10; i++) {
      await nextFrame();
    }
    debugPrint('[probe] stage28 capture riding at ${player.position} (cart ${ride?.cell})');
  }

  // --- stage 29: the underworld --------------------------------------------------------
  // One dimension is loaded at a time. Everything that lives in the world (mobs,
  // pets, drops, boats, carts) carries the dimension it is in: an entity in the
  // other dimension is hidden and not stepped until the player comes back. Wild
  // hostiles are simply freed on a travel (the spawner refills them). Puppets
  // carry their peer's dimension in the pose.

  /// Godot's `dim` meta. An entity never tagged belongs to the loaded dimension.
  final Expando<int> _dimOf = Expando<int>('dim');
  double _portalTime = 0.0;
  bool _portalHold = false;
  ({int x, int z, int d, Vector3 hold})? _arrival;
  int travels = 0; // for the probe

  int dimOf(Object e) => _dimOf[e] ?? world.dimension;
  bool isHere(Object e) => dimOf(e) == world.dimension;

  Map<String, Object> _withDim(Object e, Map<String, Object> d) => {...d, 'dim': dimOf(e)};

  void _tagEntity(Object e, int d) {
    _dimOf[e] = d;
    _applyEntityDimension(e);
  }

  void _applyEntityDimension(Object e) {
    final here = isHere(e);
    switch (e) {
      case Mob m:
        m.node.visible = here;
      case ItemDrop d:
        d.node.visible = here;
      case Boat b:
        b.node.visible = here;
      case Minecart c:
        c.node.visible = here;
    }
  }

  /// Every entity that belongs to a dimension: bodies, drops, boats, carts
  /// (never a puppet, a projectile or a one-shot effect).
  List<Object> _dimensionalEntities() => [
        for (final m in mobs) if (!m.puppet) m,
        ...pets,
        for (final d in drops) if (!d.replica) d,
        for (final b in boats) if (!b.replica) b,
        for (final c in carts) if (!c.replica) c,
      ];

  /// Leave for dimension [d] from where the player stands: the current
  /// dimension's entities are tagged and parked, the world switches, and the
  /// arrival ([_arriveTick]) finishes the trip once the chunks around the
  /// player's column are generated.
  void travelToDimension(int d) {
    if (d == world.dimension || _arrival != null) return;
    final from = world.dimension;
    for (final e in _dimensionalEntities()) {
      _dimOf[e] ??= from;
      // A wild mob does not wait for the player to come back.
      if (e is Mob && !e.tamed && !e.species.persistent) e.removed = true;
    }
    if (player.mount != null) player.dismount();
    if (player.riding != null) player.leaveBoat();
    if (player.cart != null) player.leaveCart();
    player.reelIn(false);
    boss = null;
    final pos = player.position.clone();
    world.switchDimension(d);
    for (final e in _dimensionalEntities()) {
      _applyEntityDimension(e);
    }
    weather.suppressed = d == VoxelWorld.dimUnderworld;
    final guessY = d == VoxelWorld.dimUnderworld ? 64.0 : world.surfaceHeight(pos.x.floor(), pos.z.floor()) + 1.0;
    final hold = Vector3(pos.x, guessY, pos.z);
    _probePlace(hold);
    _portalHold = true;
    _portalTime = 0.0;
    _arrival = (x: pos.x.floor(), z: pos.z.floor(), d: d, hold: hold);
    world.updateAround(hold);
    _updateMusic();
    travels += 1;
    GameState.instance.dimensionVisits += 1; // stage 30: the stats block
    notify(d == VoxelWorld.dimUnderworld ? 'You step through the portal...' : 'Daylight again.');
  }

  bool get isArriving => _arrival != null;

  void _arriveTick() {
    final a = _arrival;
    if (a == null) return;
    _probePlace(a.hold);
    final here = VoxelWorld.chunkOfXZ(a.x, a.z);
    for (final o in VoxelWorld.ring) {
      if (!world.chunks.containsKey((x: here.x + o.x, z: here.z + o.z))) return;
    }
    final y = Portals.findSafeY(world, a.x, a.z, a.d);
    final stand = Vector3(a.x + 0.5, y + 0.05, a.z + 0.5);
    _probePlace(stand);
    player.resetFall();
    final existing = Portals.near(world, stand, Portals.search);
    if (existing.y < 0) Portals.buildAt(world, IVec3(a.x, y, a.z - 2));
    _arrival = null;
    world.updateAround(stand);
  }

  /// Flint and steel at [cell] (`Player._usePressed`): lights an obsidian
  /// frame's hollow. Returns how many portal blocks were lit.
  int tryLightPortal(IVec3 cell) {
    final lit = Portals.light(world, cell);
    if (lit > 0) notify('The portal opens!');
    return lit;
  }

  /// A body standing in a portal block for [Portals.seconds] travels. The host
  /// and a solo player go at once; a client asks the host
  /// (`Net.requestTravel`) and waits for its `set_dim`.
  void _portalTick(double dt) {
    if (player.isDead || _arrival != null) return;
    final feet = IVec3(player.position.x.floor(), (player.position.y + 0.3).floor(), player.position.z.floor());
    if (!Portals.isPortal(world.getBlock(feet))) {
      _portalTime = 0.0;
      _portalHold = false;
      return;
    }
    if (_portalHold) return;
    _portalTime += dt;
    if (_portalTime < Portals.seconds) return;
    _portalTime = 0.0;
    _portalHold = true;
    final d = world.dimension == VoxelWorld.dimOverworld ? VoxelWorld.dimUnderworld : VoxelWorld.dimOverworld;
    if (Net.instance.isClient) {
      Net.instance.requestTravel(d);
    } else {
      travelToDimension(d);
    }
  }

  double portalSecondsLeft() => Portals.seconds - _portalTime;

  // --- stage 29: the underworld probe ----------------------------------------------------

  /// Blocks of [id] over the 5x5 chunks around the player (the loaded core).
  int _stage29Count(String id) {
    final b = Blocks.indexOf(id);
    final here = VoxelWorld.chunkOf(IVec3.floor(player.position));
    var n = 0;
    for (var dz = -2; dz < 3; dz++) {
      for (var dx = -2; dx < 3; dx++) {
        final blocks = world.chunks[(x: here.x + dx, z: here.z + dz)];
        if (blocks == null) continue;
        for (final v in blocks) {
          if (v == b) n++;
        }
      }
    }
    return n;
  }

  /// Waits for the trip `travelToDimension` (or the portal) started: chunks in,
  /// the player placed, the return portal built. False when it did not finish
  /// in [seconds].
  Future<bool> _stage29Arrive(double seconds) async {
    final t0 = DateTime.now();
    while (isArriving && DateTime.now().difference(t0).inMilliseconds < (seconds * 1000).round()) {
      await nextFrame();
    }
    return !isArriving;
  }

  /// Stands the player in the portal at [cell] and waits (up to 8 s of ticks)
  /// for the timer to fire the trip.
  Future<bool> _stage29StandInPortal(IVec3 cell) async {
    flyMode = false;
    final before = travels;
    final at = cell.toVector3() + Vector3(0.5, 0.05, 0.5);
    _probePlace(at);
    await _stage28Until(() {
      if (travels != before || isArriving) return true;
      _probePlace(at);
      return false;
    }, 8.0);
    return travels != before;
  }

  Future<void> _stage29TeleportWait(Vector3 at) async {
    flyMode = true;
    _probePlace(at);
    world.updateAround(at);
    for (var i = 0; i < 20; i++) {
      _probePlace(at);
      await nextFrame();
    }
    for (var i = 0; !world.isIdle && i < 1200; i++) {
      _probePlace(at);
      await nextFrame();
    }
  }

  /// Where the first boot and the shots start: a stone pad east of spawn with
  /// the obsidian frame on it.
  ({int x0, int y, int z0, Vector3 home, IVec3 cell}) _stage29Pad() {
    final x0 = player.position.x.floor() + 3;
    final z0 = player.position.z.floor();
    var y0 = 0;
    for (var x = x0 - 3; x < x0 + 18; x++) {
      for (var z = z0 - 4; z < z0 + 14; z++) {
        y0 = math.max(y0, world.groundHeight(x, z));
      }
    }
    final stone = Blocks.indexOf('stone');
    for (var x = x0 - 3; x < x0 + 18; x++) {
      for (var z = z0 - 4; z < z0 + 14; z++) {
        world.setBlock(IVec3(x, y0, z), stone);
        for (var y = y0 + 1; y < y0 + 9; y++) {
          world.setBlock(IVec3(x, y, z), Blocks.air);
        }
      }
    }
    final y = y0 + 1;
    final home = Vector3(x0 + 8.5, y + 0.1, z0 + 9.5);
    _probePlace(home);
    // The frame: 4 wide x 5 tall in the x-y plane at z0 + 3, hollow 2 x 3.
    final cell = IVec3(x0 + 8, y, z0 + 3);
    final obsidian = Blocks.indexOf('obsidian');
    for (var dx = -1; dx < 3; dx++) {
      for (var dy = -1; dy < 4; dy++) {
        final inside = dx >= 0 && dx <= 1 && dy >= 0 && dy <= 2;
        world.setBlock(cell + IVec3(dx, dy, 0), inside ? Blocks.air : obsidian);
      }
    }
    return (x0: x0, y: y, z0: z0, home: home, cell: cell);
  }

  /// --stage29, first boot: obsidian from lava + water, the frame lit, two
  /// seconds in the portal, the underworld census and return portal, the
  /// fortress (`--kind=9`), the sealed core and the heart, soul sand, a
  /// fireball, home and down again, then a save in the underworld and a fresh
  /// session (`probe29.flag`). Windowed: `--shot=portal` / `--shot=fortress`.
  Future<bool> _probeStage29() async {
    final site = _stage29Site;
    if (site != null) {
      await _probeStage29Verify(site);
      return false;
    }
    final shot = _arg('--shot=', '');
    final pad = _stage29Pad();
    final x0 = pad.x0, y = pad.y, z0 = pad.z0;
    final cell = pad.cell;
    final stone = Blocks.indexOf('stone');
    String idAt(IVec3 c) => Blocks.idOf(world.getBlock(c));
    debugPrint('[probe] stage29 site x0=$x0 y=$y z0=$z0');
    if (shot != 'portal') {
      // 1. A lava source touched by water hardens to obsidian; a flowing lava
      // cell to cobblestone. Two walled channels along +x on the pad's west
      // edge (rows z0+1 and z0+5).
      for (var i = 0; i < 6; i++) {
        for (final dz in const [0, 2, 4, 6]) {
          world.setBlock(IVec3(x0 + i, y, z0 + dz), stone);
        }
      }
      world.setBlock(IVec3(x0 - 1, y, z0 + 1), stone);
      world.setBlock(IVec3(x0 - 1, y, z0 + 5), stone);
      final flowSrc = IVec3(x0, y, z0 + 1);
      final src = IVec3(x0, y, z0 + 5);
      world.setBlock(flowSrc, Blocks.indexOf('lava'));
      await _stage28Settle(2.0);
      final flowing = idAt(IVec3(x0 + 2, y, z0 + 1)) == 'lava_flow';
      world.setBlock(IVec3(x0 + 3, y, z0 + 1), Blocks.indexOf('water'));
      world.setBlock(src, Blocks.indexOf('lava'));
      world.setBlock(IVec3(x0 + 1, y, z0 + 5), Blocks.indexOf('water'));
      await _stage28Settle(2.5);
      final obsidianOk = idAt(src) == 'obsidian';
      final cobbleOk = idAt(IVec3(x0 + 2, y, z0 + 1)) == 'cobblestone';
      debugPrint('[probe] stage29 obsidian: lava source + water -> obsidian=$obsidianOk, flowing lava -> cobblestone=$cobbleOk (flow cell was lava_flow=$flowing)');
      world.setBlock(IVec3(x0 + 3, y, z0 + 1), Blocks.air);
      world.setBlock(IVec3(x0 + 1, y, z0 + 5), Blocks.air);
      world.setBlock(flowSrc, Blocks.air);
      await _stage28Settle(1.0);
    }
    // 2. The frame lit by the flint and steel.
    final lit = tryLightPortal(cell + IVec3.up);
    final portalId = Blocks.indexOf('portal');
    var portalBlocks = 0;
    for (var dx = 0; dx < 2; dx++) {
      for (var dy = 0; dy < 3; dy++) {
        if (world.getBlock(cell + IVec3(dx, dy, 0)) == portalId) portalBlocks += 1;
      }
    }
    debugPrint('[probe] stage29 portal built and lit: portal blocks=$portalBlocks (lit $lit)');
    if (shot == 'portal') {
      // The capture: first person five metres south of the frame, looking north at it.
      final eye = Vector3(x0 + 8.5, y + 0.05, z0 + 11.5);
      player.setFirstPerson(true);
      player.setLook(0.0, 0.06);
      // The pad's chunks remesh first, or the capture shows the terrain it replaced.
      for (var i = 0; i < 30 || (!world.isIdle && i < 600); i++) {
        _probePlace(eye);
        await nextFrame();
      }
      _pinCameraTo = () => eye.clone();
      return false;
    }
    // No natural spawns from the trip down until the trip home: the count below
    // must see the fortress's two blazes only, and the underworld spawner can add
    // a third during the teleport waits (Godot's probe has the same latent flake).
    // A capture that returns early keeps them off, which only keeps strays out of
    // its frame.
    spawnerPaused = true;
    // 3. Two seconds inside the portal: the trip, the arrival, the safe spot.
    final went = await _stage29StandInPortal(cell);
    final arrived = await _stage29Arrive(40.0);
    final feet = IVec3(player.position.x.floor(), (player.position.y + 0.05).floor(), player.position.z.floor());
    final under = world.getBlock(feet + IVec3.down);
    final safe = world.getBlock(feet) == Blocks.air && world.getBlock(feet + IVec3.up) == Blocks.air && Blocks.isSolid(under);
    final arrival = player.position.clone();
    debugPrint('[probe] stage29 travelled: dimension=${world.dimension} pos=(${feet.x},${feet.y},${feet.z}) safe=$safe '
        '(air over ${Blocks.idOf(under)}) [timer fired=$went arrived=$arrived]');
    // 4. What the underworld is made of, over the loaded core.
    for (var i = 0; i < 30 || (!world.isIdle && i < 1200); i++) {
      await nextFrame();
    }
    debugPrint('[probe] stage29 underworld window: hellstone=${_stage29Count('hellstone')} lava=${_stage29Count('lava')} '
        'glowstone=${_stage29Count('glowstone')} quartz=${_stage29Count('nether_quartz_ore')} soul_sand=${_stage29Count('soul_sand')}');
    if (shot == 'cavern') {
      // Flutter-only capture: the nearest open column over the lava sea (air at
      // y 40, lava at the sea level below), hovered in fly mode looking down
      // across it toward the glowstone-hung ceilings.
      final c = IVec3.floor(arrival);
      IVec3? best;
      var bestD = 1 << 30;
      for (var dz = -24; dz <= 24; dz++) {
        for (var dx = -24; dx <= 24; dx++) {
          final x = c.x + dx, z = c.z + dz;
          if (world.getBlockXYZ(x, TerrainGenerator.lavaSeaY, z) != Blocks.indexOf('lava')) continue;
          var open = true;
          for (var yy = TerrainGenerator.lavaSeaY + 1; yy < 46 && open; yy++) {
            if (world.getBlockXYZ(x, yy, z) != Blocks.air) open = false;
          }
          if (open && dx * dx + dz * dz < bestD) {
            bestD = dx * dx + dz * dz;
            best = IVec3(x, 40, z);
          }
        }
      }
      final eye = (best ?? c).toVector3() + Vector3(0.5, 0.0, 0.5);
      flyMode = true;
      player.setLook(_arg('--look=', '') == '' ? 0.0 : player.yaw, _arg('--look=', '') == '' ? -20.0 * math.pi / 180.0 : player.pitch);
      for (var i = 0; i < 30 || (!world.isIdle && i < 600); i++) {
        _probePlace(eye);
        await nextFrame();
      }
      _pinCameraTo = () => eye.clone();
      debugPrint('[probe] stage29 cavern capture from $eye (open column over the lava sea: ${best != null})');
      return false;
    }
    // 5. The return portal.
    final back = Portals.near(world, arrival, Portals.search);
    debugPrint('[probe] stage29 return portal exists=${back.y >= 0} within ${Portals.search} blocks (at $back)');
    // 6. The fortress, through the stage 21a helper (`--kind=9`), wide scan.
    final found = _probeStage21aTeleport(48);
    if (found == null) {
      debugPrint('[probe] stage29 fortress: none within 48 chunks of seed ${world.seedValue}');
    } else {
      final origin = found.origin;
      final layout = world.generator.fortressLayout(origin.x, origin.y, origin.z);
      final core = layout.core;
      final len = layout.length;
      await _stage29TeleportWait(found.at);
      _checkStructures();
      var bricks = 0;
      final brickId = Blocks.indexOf('nether_brick');
      for (var x = origin.x; x < origin.x + len + 11; x++) {
        for (var yy = origin.y; yy < origin.y + 9; yy++) {
          for (var z = origin.z - 5; z < origin.z + 6; z++) {
            if (world.getBlockXYZ(x, yy, z) == brickId) bricks += 1;
          }
        }
      }
      var chests = 0;
      for (final c in [layout.chestA, layout.chestB]) {
        if (idAt(c) == 'chest') chests += 1;
      }
      // The blazes wake at the hall's middle, the lord at the throne.
      await _stage29TeleportWait(layout.blaze.toVector3() + Vector3(0.5, 0.1, 0.5));
      _checkStructures();
      await _stage29TeleportWait(core.toVector3() + Vector3(-3.5, 1.1, 0.5));
      _checkStructures();
      await _ticks(1);
      var blazes = 0;
      for (final m in mobs) {
        if (m.species.id == 'blaze') {
          blazes += 1;
          m.stun(120.0, false);
        }
      }
      final lord = boss;
      lord?.stun(120.0, false);
      debugPrint('[probe] stage29 fortress at (${origin.x},${origin.z}): bricks=$bricks chests=$chests blazes=$blazes '
          'boss=${lord?.species.name ?? 'none'} hp=${lord?.maxHp.toInt() ?? 0} (origin $origin, length $len, core $core)');
      if (shot == 'fortress') {
        // The capture: first person in the throne room's door, the lord and the core ahead.
        final door = core.toVector3() + Vector3(-4.5, 1.05, 0.5);
        flyMode = false;
        player.setFirstPerson(true);
        player.setLook(-math.pi / 2.0, 0.04);
        for (var i = 0; i < 30 || (!world.isIdle && i < 600); i++) {
          _probePlace(door);
          await nextFrame();
        }
        _pinCameraTo = () => door.clone();
        debugPrint('[probe] stage29 capture from $door, boss at ${lord?.position}');
        return false;
      }
      // 7. The core: sealed while the lord lives, then the heart.
      player.inventory.add('iron_pickaxe', 1);
      player.selectedSlot = player.inventory.find('iron_pickaxe');
      final coreId = Blocks.indexOf('fortress_core');
      player.probeBreak(core, coreId);
      final refused = world.getBlock(core) == coreId;
      if (lord != null) lord.takeDamage(lord.hp + 1.0, lord.position + Vector3(1, 0, 0), 0.0, player);
      await _ticks(1);
      player.probeBreak(core, coreId);
      var hearts = 0;
      for (final d in drops) {
        if (d.itemId == 'underworld_heart' && !d.removed) {
          hearts += d.count;
          d.removed = true;
        }
      }
      player.pickUp('underworld_heart', hearts);
      final ach = Achievements.instance.unlocked;
      debugPrint('[probe] stage29 core: break before boss dies=${refused ? 'refused' : 'BROKE'}, after kill=heart x$hearts, '
          'achievement heart=${ach.contains('heart')} (underworld=${ach.contains('underworld')})');
      // 8. Soul sand on the hall floor, and a blaze's fireball.
      final soul = Blocks.indexOf('soul_sand');
      for (var x = origin.x + 2; x < origin.x + 16; x++) {
        world.setBlock(IVec3(x, origin.y, origin.z), soul);
        world.setBlock(IVec3(x, origin.y, origin.z + 1), soul);
      }
      flyMode = false;
      _probePlace(Vector3(origin.x + 3.5, origin.y + 1.05, origin.z + 0.5));
      player.probeWalk(Vector3(1, 0, 0));
      final speeds = <double>[];
      var tick = 0;
      await _stage28Until(() {
        if (tick >= 40) speeds.add(math.sqrt(player.velocity.x * player.velocity.x + player.velocity.z * player.velocity.z));
        tick += 1;
        return tick >= 70;
      }, 2.0);
      player.probeWalk(Vector3.zero());
      final v = speeds.isEmpty ? 0.0 : speeds.reduce((a, b) => a + b) / speeds.length;
      final underNow = idAt(IVec3(player.position.x.floor(), (player.position.y - 0.05).floor(), player.position.z.floor()));
      debugPrint('[probe] stage29 soul sand speed=${v.toStringAsFixed(2)} (< walk ${Player.walkSpeed}) on $underNow');
      player.effects.clear('burning');
      final shooter = spawner!.forceSpawn('blaze', player.centre() + Vector3(3.0, 0.6, 0.0)); // down the hall, not into its wall
      shooter.stun(30.0, false);
      spawnProjectile(shooter.centre(), (player.centre() - shooter.centre()).normalized() * 20.0, 2.0, shooter, 'fire', 0.25);
      await _ticks(20);
      debugPrint('[probe] stage29 blaze fireball applies burning=${player.effects.has('burning')} '
          '(hp ${player.hp.toStringAsFixed(0)}/${player.maxHp.toStringAsFixed(0)})');
      player.effects.clear('burning');
      shooter.removed = true;
    }
    spawnerPaused = false;
    // 9. Home through the return portal.
    if (back.y >= 0) {
      player.hp = player.maxHp;
      await _stage29TeleportWait(back.toVector3() + Vector3(0.5, 0.05, 0.5));
      final wentBack = await _stage29StandInPortal(back);
      final arrivedBack = await _stage29Arrive(40.0);
      final f2 = IVec3(player.position.x.floor(), (player.position.y + 0.05).floor(), player.position.z.floor());
      final surface = (world.groundHeight(f2.x, f2.z) - f2.y).abs() <= 1;
      debugPrint('[probe] stage29 back home: dimension=${world.dimension} pos=(${f2.x},${f2.y},${f2.z}) surface=$surface '
          '(ground ${world.groundHeight(f2.x, f2.z)}) [timer fired=$wentBack arrived=$arrivedBack, weather ${weather.label}, label ${timeLabel()}]');
    }
    // 10. Down again, save there, reload.
    await _stage29TeleportWait(cell.toVector3() + Vector3(0.5, 0.05, 0.5));
    await _stage29StandInPortal(cell);
    await _stage29Arrive(40.0);
    final down = Portals.near(world, player.position, Portals.search);
    final cells = <List<int>>[];
    if (down.y >= 0) {
      // The six cells of that portal: walk the portal blocks around the one found.
      for (var dx = -2; dx < 3; dx++) {
        for (var dy = -3; dy < 4; dy++) {
          for (var dz = -2; dz < 3; dz++) {
            final b = down + IVec3(dx, dy, dz);
            if (world.getBlock(b) == portalId) cells.add([b.x, b.y, b.z]);
          }
        }
      }
    }
    flyMode = false;
    await _stage28Settle(0.3);
    await saveGame();
    File(_probe29Flag).writeAsStringSync(jsonEncode({
      'cells': cells,
      'pos': [player.position.x, player.position.y, player.position.z],
    }));
    debugPrint('[probe] stage29 saved in dimension ${world.dimension} (edits_0=${world.editCountIn(0)} edits_1=${world.editCountIn(1)}, '
        'portal cells ${cells.length}) to $saveDir, reloading the scene');
    reloader!();
    return true;
  }

  /// --stage29, second boot: the save puts the player back in the underworld,
  /// both deltas come back, the return portal stands.
  Future<void> _probeStage29Verify(Map<String, dynamic> site) async {
    for (var i = 0; i < 30 || (!world.isIdle && i < 1200); i++) {
      await nextFrame();
    }
    final portalId = Blocks.indexOf('portal');
    final cells = site['cells'] as List<dynamic>;
    var intact = 0;
    for (final c in cells) {
      final l = c as List<dynamic>;
      if (world.getBlockXYZ(l[0] as int, l[1] as int, l[2] as int) == portalId) intact += 1;
    }
    debugPrint('[probe] stage29 after reload: dimension=${world.dimension} edits_0=${world.editCountIn(0)} edits_1=${world.editCountIn(1)} '
        'portal intact=${intact == cells.length && intact > 0} ($intact/${cells.length} cells, player at ${player.position}, '
        'label ${timeLabel()}, mood ${Music.instance.currentMood})');
  }

  // --- stage 30: creative, the tutorial chain, the stats round trip ----------------------

  /// --stage30 (after the title half started a creative mage world, or on a bare
  /// `--new`): a hit ignored, a block placed for free, F5 allowed; then the
  /// tutorial driven through its first seven steps by the events the game
  /// raises, skipped, and the flag read back from disk; then the counters
  /// saved, the session rebuilt and compared. `--shot=tutorial` stops after
  /// step 3 so the capture shows the card on step 4.
  Future<bool> _probeStage30() async {
    if (_stage30Saved != null) {
      await _probeStage30Verify(_stage30Saved!);
      return false;
    }
    await _ticks(5);
    final shot = _arg('--shot=', '');
    final aim = player.aimDirection();
    var ahead = Vector3(aim.x, 0, aim.z);
    ahead = ahead.length < 0.01 ? Vector3(0, 0, -1) : ahead.normalized();
    final base = IVec3.floor(player.position);
    final sx = base.x + (ahead.x * 3.0).round(), sz = base.z + (ahead.z * 3.0).round();
    final spot = IVec3(sx, world.groundHeight(sx, sz), sz);
    final stone = Blocks.indexOf('stone');
    if (shot != 'tutorial') {
      // 1. Creative: no damage, free blocks, flight.
      final hp0 = player.hp;
      player.takeDamage(5.0, 'fall');
      final ignored = (player.hp - hp0).abs() < 1e-9;
      player.inventory.setSlot(0, ItemStack('stone', 1));
      player.selectedSlot = 0;
      _probePlaceAt(spot);
      final placedFree = world.getBlock(spot + IVec3.up) == stone && player.inventory.countAt(0) == 1;
      debugPrint('[probe] stage30 creative: damage ignored=$ignored, block placed without consuming=$placedFree, fly=${flyAllowed()} '
          '(mode creative=${GameState.instance.creative} class=${player.playerClass})');
      world.setBlock(spot + IVec3.up, Blocks.air);
    }
    // 2. The tutorial, step by step: move, look, jump ...
    player.probeWalk(ahead);
    await _ticks(6);
    player.probeWalk(Vector3.zero());
    player.setLook(0.4, -0.35);
    player.probeJump();
    await _ticks(1);
    final tut = Tutorial.instance;
    if (shot == 'tutorial') {
      await _ticks(40); // the jump lands before the capture
      player.velocity = Vector3.zero();
      for (var i = 0; i < 30 || (!world.isIdle && i < 600); i++) {
        await nextFrame();
      }
      debugPrint('[probe] stage30 tutorial capture on step ${tut.index + 1} (${tut.currentId})');
      return false;
    }
    // ... break, inventory, craft, place.
    final below = spot;
    final belowId = world.getBlock(below);
    world.setBlock(below, Blocks.air);
    onBlockBroken(below, belowId);
    openStation('', IVec3.zero);
    await nextFrame();
    closeScreen();
    player.inventory.add('oak_planks', 3);
    player.inventory.add('stick', 2);
    var crafted = false;
    for (final r in Recipes.list) {
      if (r.result == 'wooden_pickaxe' && r.station == '') {
        crafted = player.craft(r);
        break;
      }
    }
    player.inventory.setSlot(0, ItemStack('stone', 1));
    player.selectedSlot = 0;
    _probePlaceAt(below + IVec3.down);
    debugPrint('[probe] stage30 tutorial: steps=${tut.stepCount}, completed ${tut.completed.length} by events: ${tut.completed.join(', ')} '
        '(pickaxe crafted=$crafted, next step ${tut.currentId})');
    tut.skipAll();
    final cfg = Settings.instance.path;
    final persisted = File(cfg).existsSync() && RegExp(r'\[tutorial\]\s*done=true').hasMatch(File(cfg).readAsStringSync());
    debugPrint('[probe] stage30 tutorial skipped -> done=${Settings.instance.tutorialDone && !tut.active} persisted=$persisted ($cfg)');
    // 3. The stats, saved and read back by a second session.
    for (var i = 0; i < 10; i++) {
      await nextFrame();
    }
    final gs = GameState.instance;
    final counters = {
      'play_seconds': gs.playTime,
      'blocks_broken': gs.blocksMined,
      'blocks_placed': gs.blocksPlaced,
      'distance': gs.distanceWalked,
      'mobs_killed': gs.mobsKilled,
      'deaths': gs.deaths,
      'dimension_visits': gs.dimensionVisits,
    };
    await saveGame();
    File(_probe30Flag).writeAsStringSync(jsonEncode(counters));
    debugPrint('[probe] stage30 stats saved (play_seconds=${gs.playTime.toStringAsFixed(1)} blocks_broken=${gs.blocksMined} '
        'blocks_placed=${gs.blocksPlaced} walked=${gs.distanceWalked.toStringAsFixed(1)} m) to $saveDir, reloading the scene');
    reloader!();
    return true;
  }

  /// The placement path the right mouse button takes, aimed at the top of
  /// [ground] by hand.
  void _probePlaceAt(IVec3 ground) {
    player.aimedBlock = ground;
    player.aimedNormal = IVec3.up;
    player.isAiming = true;
    player.probeUse();
  }

  /// --stage30, second session: the counters came back through the save.
  Future<void> _probeStage30Verify(Map<String, dynamic> saved) async {
    for (var i = 0; i < 5; i++) {
      await nextFrame();
    }
    final gs = GameState.instance;
    final playSaved = (saved['play_seconds'] as num).toDouble();
    final equal = gs.blocksMined == (saved['blocks_broken'] as num).toInt() &&
        gs.blocksPlaced == (saved['blocks_placed'] as num).toInt() &&
        gs.playTime >= playSaved &&
        playSaved > 0.0 &&
        gs.mobsKilled == (saved['mobs_killed'] as num).toInt() &&
        gs.deaths == (saved['deaths'] as num).toInt() &&
        gs.dimensionVisits == (saved['dimension_visits'] as num).toInt() &&
        (gs.distanceWalked - (saved['distance'] as num).toDouble()).abs() < 1e-6;
    debugPrint('[probe] stage30 stats: play_seconds=${gs.playTime.toStringAsFixed(1)} (>0) blocks_broken=${gs.blocksMined} '
        'blocks_placed=${gs.blocksPlaced} after reload equal=$equal (creative=${gs.creative} tutorial card=${Tutorial.instance.active})');
    debugPrint('[probe] stage30 stats screen: ${SettingsPanel.statsText().replaceAll('\n', ' | ')}');
    var removed = 0;
    for (final e in Worlds.list()) {
      if (e.slot.startsWith('probe30_') && Worlds.delete(e.slot)) removed += 1;
    }
    debugPrint('[probe] stage30 cleanup: probe30_ slots removed=$removed');
  }

  void shutdown() {
    world.dispose();
    input.dispose();
  }
}
