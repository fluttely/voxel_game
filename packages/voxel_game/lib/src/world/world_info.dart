import '../spec/voxel_game_spec.dart';

/// How a world is played, chosen when it is made.
enum WorldMode {
  /// Blocks take mining, placing uses them up, and the player can be hurt.
  survival,

  /// `PlayerSpec.creative`: blocks break at once, placing is free, no damage.
  creative,
}

/// What a save slot says about its world, kept in its `world.json`: the
/// world list's row, read without reading the world.
class WorldInfo {
  /// A world in [slot] named [name], generated from [seed].
  const WorldInfo({
    required this.slot,
    required this.name,
    required this.seed,
    required this.saved,
    this.mode,
    this.options = const {},
    this.created,
    this.lastPlayed,
    this.playTime = Duration.zero,
  }) : assert(name != '');

  /// The folder it lives in, under `WorldSaves.directory`; never changes.
  final String slot;

  /// The name the player gave it.
  final String name;

  /// The seed its terrain is generated from.
  final int seed;

  /// Whether it has been saved since it was made (`game.json`); a world that
  /// has not starts fresh from [seed].
  final bool saved;

  /// How it is played, or null for a world that plays as the game declares
  /// (`PlayerSpec.creative`): one made where no mode was offered, or saved
  /// before worlds had a `world.json`.
  final WorldMode? mode;

  /// The game's own choices for this world, by option id: what the
  /// new-world form offered (`TitleSpec.worldOptions`) and the player picked,
  /// read by the game's systems through `VoxelGame.worldInfo` (a class, a
  /// playground). Empty for a world made where none was offered.
  final Map<String, String> options;

  /// When it was made; null for a world saved before worlds had a
  /// `world.json`.
  final DateTime? created;

  /// When it was last saved; null for a world never played.
  final DateTime? lastPlayed;

  /// How long it has run, in game time (`VoxelGame.time`).
  final Duration playTime;

  /// When it was last touched: played, else made. Every world has one of the
  /// two: a world from before `world.json` has been saved, and a newer one
  /// was made.
  DateTime get touched => (lastPlayed ?? created)!;

  /// [spec] as this world is played: its [seed], its player and its main
  /// dimension as its [options] make them (`VoxelGameSpec.playerFor`,
  /// `VoxelGameSpec.worldFor`), and its [mode] when it has one. (A saved
  /// world's seed wins anyway: `VoxelGame.start`.)
  VoxelGameSpec applyTo(VoxelGameSpec spec) {
    final m = mode;
    final player = spec.playerWith(options);
    return spec.copyWith(
      seed: seed,
      world: spec.worldWith(options),
      player: m == null ? player : player.copyWith(creative: m == WorldMode.creative),
    );
  }

  /// This world with the given fields replaced.
  WorldInfo copyWith({String? name, bool? saved, DateTime? lastPlayed, Duration? playTime}) => WorldInfo(
    slot: slot,
    name: name ?? this.name,
    seed: seed,
    saved: saved ?? this.saved,
    mode: mode,
    options: options,
    created: created,
    lastPlayed: lastPlayed ?? this.lastPlayed,
    playTime: playTime ?? this.playTime,
  );

  /// The version of `world.json` [toJson] writes. Version 1, from before
  /// [options], still reads (with none).
  static const version = 2;

  /// `world.json`: what is unknown is left out.
  Map<String, Object?> toJson() => {
    'version': version,
    'name': name,
    'seed': seed,
    if (mode case final m?) 'mode': m.name,
    if (options.isNotEmpty) 'options': options,
    if (created case final c?) 'created': c.millisecondsSinceEpoch,
    if (lastPlayed case final p?) 'played': p.millisecondsSinceEpoch,
    'playSeconds': playTime.inMicroseconds / 1e6,
  };

  /// Reads [json], the `world.json` of [slot]; throws for a version this kit
  /// does not read.
  factory WorldInfo.fromJson(String slot, Map<String, Object?> json, {required bool saved}) {
    final v = (json['version']! as num).toInt();
    if (v < 1 || v > version) throw StateError('world.json version $v: this kit reads 1 to $version');
    DateTime? at(Object? ms) => ms == null ? null : DateTime.fromMillisecondsSinceEpoch((ms as num).toInt());
    final mode = json['mode'] as String?;
    return WorldInfo(
      slot: slot,
      name: json['name']! as String,
      seed: (json['seed']! as num).toInt(),
      saved: saved,
      mode: mode == null ? null : WorldMode.values.byName(mode),
      options: {
        for (final e in (json['options'] as Map<String, Object?>? ?? const {}).entries) e.key: e.value! as String,
      },
      created: at(json['created']),
      lastPlayed: at(json['played']),
      playTime: Duration(microseconds: ((json['playSeconds']! as num) * 1e6).round()),
    );
  }
}
