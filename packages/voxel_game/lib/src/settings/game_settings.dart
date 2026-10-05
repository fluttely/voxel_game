import '../spec/voxel_game_spec.dart';

/// What the player sets for themselves, as opposed to what the game declares:
/// how far they see, how fast the view turns, how wide it is, how loud the
/// game is, whether the eye bobs, whether the frame rate shows, whether the
/// weather turns, and what the game itself keeps of the player's ([game]).
///
/// The spec's values are the defaults ([GameSettings.of]); `VoxelGame`
/// applies a change at once ([VoxelGame.applySettings]), and a
/// `SettingsStore` keeps them between runs, beside the worlds. Every value is
/// checked against its range: a setting out of it, read from a file or built
/// in code, throws.
class GameSettings {
  /// Settings of these values; throws [ArgumentError] for one out of its range.
  GameSettings({
    required this.renderDistance,
    this.lookSpeed = 1.0,
    required this.fov,
    this.volume = 1.0,
    required this.musicVolume,
    this.viewBob = true,
    this.showFps = false,
    this.weather = true,
    Map<String, Object?> game = const {},
  }) : game = _frozen(game) {
    if (renderDistance < minRenderDistance || renderDistance > maxRenderDistance) {
      throw ArgumentError.value(renderDistance, 'renderDistance', 'not in $minRenderDistance..$maxRenderDistance');
    }
    _check(lookSpeed, 'lookSpeed', minLookSpeed, maxLookSpeed);
    _check(fov, 'fov', minFov, maxFov);
    _check(volume, 'volume', 0.0, 1.0);
    _check(musicVolume, 'musicVolume', 0.0, 1.0);
  }

  /// The spec's defaults: its render distance, its player's field of view, its
  /// music's loudness; the turn at its stock speed, full volume, the eye
  /// bobbing, no frame rate, the weather on.
  factory GameSettings.of(VoxelGameSpec spec) =>
      GameSettings(renderDistance: spec.renderDistance, fov: spec.player.fov, musicVolume: spec.sounds.musicVolume);

  // A deep copy no one can change, of JSON values only.
  static Map<String, Object?> _frozen(Map<String, Object?> map) =>
      Map.unmodifiable({for (final e in map.entries) e.key: _frozenValue(e.value, e.key)});

  static Object? _frozenValue(Object? value, String key) => switch (value) {
    null || bool() || String() || int() => value,
    double() when value.isFinite => value,
    List<Object?>() => List<Object?>.unmodifiable([for (final v in value) _frozenValue(v, key)]),
    Map<String, Object?>() => _frozen(value),
    _ => throw ArgumentError.value(value, 'game[$key]', 'not a JSON value'),
  };

  static bool _same(Object? a, Object? b) => switch ((a, b)) {
    (List<Object?> a, List<Object?> b) =>
      a.length == b.length && [for (var i = 0; i < a.length; i++) i].every((i) => _same(a[i], b[i])),
    (Map<String, Object?> a, Map<String, Object?> b) =>
      a.length == b.length && a.keys.every((k) => b.containsKey(k) && _same(a[k], b[k])),
    _ => a == b,
  };

  static void _check(double value, String name, double min, double max) {
    if (!(value >= min && value <= max)) throw ArgumentError.value(value, name, 'not in $min..$max');
  }

  /// The nearest the world may be cut, in chunks.
  static const minRenderDistance = 2;

  /// The furthest it may stream, in chunks.
  static const maxRenderDistance = 16;

  /// The slowest turn, a fraction of the stock speed.
  static const minLookSpeed = 0.25;

  /// The fastest turn.
  static const maxLookSpeed = 4.0;

  /// The narrowest view, degrees from bottom to top.
  static const minFov = 50.0;

  /// The widest view.
  static const maxFov = 110.0;

  /// How many chunks are streamed around the player (`GameWorld.loadRadius`):
  /// the fog's end and the camera's far plane follow it.
  final int renderDistance;

  /// How fast the view turns, times the stock speed: the mouse, a finger's
  /// drag and the right stick alike (`InputMap.lookScale`).
  final double lookSpeed;

  /// The camera's vertical field of view, degrees.
  final double fov;

  /// Every sound's loudness, linear: the effects and, under it, the music.
  final double volume;

  /// The music's loudness, linear, under [volume].
  final double musicVolume;

  /// The loudness the music plays at, linear: [musicVolume] under [volume].
  double get musicGain => volume * musicVolume;

  /// Whether the eye bobs as the player walks (`ViewCamera.bob`).
  final bool viewBob;

  /// Whether the HUD shows the frame rate.
  final bool showFps;

  /// Whether the weather turns (`SkySpec.weather`); off, the sky stays clear.
  final bool weather;

  /// The game's own settings of the player's, which the kit never reads:
  /// JSON values (maps, lists, strings, numbers, bools, null) under the
  /// game's keys, kept with the rest across worlds and runs. What a world
  /// keeps belongs in its save (`SavedSystem`) and a world's choice in its
  /// `WorldInfo.options`; this is what holds across them, a tutorial seen,
  /// say. Copied and unmodifiable: a change is a [copyWith] put in force by
  /// `VoxelGame.applySettings`. A value that is not JSON throws.
  final Map<String, Object?> game;

  /// These settings with the given values replaced.
  GameSettings copyWith({
    int? renderDistance,
    double? lookSpeed,
    double? fov,
    double? volume,
    double? musicVolume,
    bool? viewBob,
    bool? showFps,
    bool? weather,
    Map<String, Object?>? game,
  }) => GameSettings(
    renderDistance: renderDistance ?? this.renderDistance,
    lookSpeed: lookSpeed ?? this.lookSpeed,
    fov: fov ?? this.fov,
    volume: volume ?? this.volume,
    musicVolume: musicVolume ?? this.musicVolume,
    viewBob: viewBob ?? this.viewBob,
    showFps: showFps ?? this.showFps,
    weather: weather ?? this.weather,
    game: game ?? this.game,
  );

  /// The version of the JSON [toJson] writes: 2 added [weather], 3 [game].
  static const version = 3;

  /// These settings as JSON, with their [version].
  Map<String, Object?> toJson() => {
    'version': version,
    'renderDistance': renderDistance,
    'lookSpeed': lookSpeed,
    'fov': fov,
    'volume': volume,
    'musicVolume': musicVolume,
    'viewBob': viewBob,
    'showFps': showFps,
    'weather': weather,
    'game': game,
  };

  /// Settings read from [toJson]'s JSON, of this [version], of version 2
  /// (no [game] yet) or of version 1 (nor the weather: on); throws for
  /// another version, a value missing or one out of its range.
  factory GameSettings.fromJson(Map<String, Object?> json) {
    final v = (json['version']! as num).toInt();
    if (v < 1 || v > version) throw StateError('settings version $v: this kit reads 1 to $version');
    return GameSettings(
      renderDistance: (json['renderDistance']! as num).toInt(),
      lookSpeed: (json['lookSpeed']! as num).toDouble(),
      fov: (json['fov']! as num).toDouble(),
      volume: (json['volume']! as num).toDouble(),
      musicVolume: (json['musicVolume']! as num).toDouble(),
      viewBob: json['viewBob']! as bool,
      showFps: json['showFps']! as bool,
      weather: v == 1 || json['weather']! as bool,
      game: v < 3 ? const {} : json['game']! as Map<String, Object?>,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GameSettings &&
      other.renderDistance == renderDistance &&
      other.lookSpeed == lookSpeed &&
      other.fov == fov &&
      other.volume == volume &&
      other.musicVolume == musicVolume &&
      other.viewBob == viewBob &&
      other.showFps == showFps &&
      other.weather == weather &&
      _same(other.game, game);

  @override
  int get hashCode => Object.hash(
    renderDistance,
    lookSpeed,
    fov,
    volume,
    musicVolume,
    viewBob,
    showFps,
    weather,
    Object.hashAllUnordered(game.keys),
  );

  @override
  String toString() => 'GameSettings${toJson()}';
}
