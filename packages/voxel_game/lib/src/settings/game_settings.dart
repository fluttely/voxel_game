import '../spec/voxel_game_spec.dart';

/// What the player sets for themselves, as opposed to what the game declares:
/// how far they see, how fast the view turns, how wide it is, how loud the
/// game is, whether the eye bobs, whether the frame rate shows and whether
/// the weather turns.
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
  }) {
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
  }) => GameSettings(
    renderDistance: renderDistance ?? this.renderDistance,
    lookSpeed: lookSpeed ?? this.lookSpeed,
    fov: fov ?? this.fov,
    volume: volume ?? this.volume,
    musicVolume: musicVolume ?? this.musicVolume,
    viewBob: viewBob ?? this.viewBob,
    showFps: showFps ?? this.showFps,
    weather: weather ?? this.weather,
  );

  /// The version of the JSON [toJson] writes: 2 added [weather].
  static const version = 2;

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
  };

  /// Settings read from [toJson]'s JSON, of this [version] or version 1 (the
  /// weather on); throws for another version, a value missing or one out of
  /// its range.
  factory GameSettings.fromJson(Map<String, Object?> json) {
    final v = (json['version']! as num).toInt();
    if (v != 1 && v != version) throw StateError('settings version $v: this kit reads 1 and $version');
    return GameSettings(
      renderDistance: (json['renderDistance']! as num).toInt(),
      lookSpeed: (json['lookSpeed']! as num).toDouble(),
      fov: (json['fov']! as num).toDouble(),
      volume: (json['volume']! as num).toDouble(),
      musicVolume: (json['musicVolume']! as num).toDouble(),
      viewBob: json['viewBob']! as bool,
      showFps: json['showFps']! as bool,
      weather: v == 1 || json['weather']! as bool,
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
      other.weather == weather;

  @override
  int get hashCode => Object.hash(renderDistance, lookSpeed, fov, volume, musicVolume, viewBob, showFps, weather);

  @override
  String toString() => 'GameSettings${toJson()}';
}
