import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'game_state.dart';

/// One row of the world list: what `world.json` says, overlaid with what the
/// save knows.
class WorldEntry {
  WorldEntry({
    required this.slot,
    required this.name,
    required this.seed,
    required this.mode,
    required this.playerClass,
    required this.dimension,
    required this.playSeconds,
    required this.lastPlayed,
    required this.hasSave,
    this.playground = false,
  });
  final String slot;
  String name;
  int seed;
  String mode; // 'survival' | 'creative'
  String playerClass;
  int dimension;
  double playSeconds;
  int lastPlayed; // unix seconds
  bool hasSave;

  /// Stage 33: `world.json` says `"type": "playground"`.
  bool playground;

  bool get creative => mode == 'creative';
}

/// Stage 30: the save slots under `worlds/<slot>/` (Godot's `user://worlds`).
/// A slot carries `world.json` (the display name, seed, mode and class chosen
/// on the New World form; the same keys as Godot's) beside the `player.json`
/// the session writes; the list reads both. Every entry point of the title
/// screen's world list (create, rename, delete, start) is a static here so the
/// probe and the unit tests drive the same code.
class Worlds {
  Worlds._();

  /// The folder holding the slots; `main` points it at `<support>/worlds`.
  static String root = '';
  static const String meta = 'world.json';
  static const String save = 'player.json';

  static String _slotPath(String slot) => '$root/$slot';

  static List<WorldEntry> list() {
    final out = <WorldEntry>[];
    final dir = Directory(root);
    if (root == '' || !dir.existsSync()) return out;
    for (final e in dir.listSync()) {
      if (e is! Directory) continue;
      final slot = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (slot.startsWith('.')) continue;
      final w = entry(slot);
      if (w != null) out.add(w);
    }
    out.sort((a, b) => b.lastPlayed.compareTo(a.lastPlayed));
    return out;
  }

  /// A folder with neither file is not a world.
  static WorldEntry? entry(String slot) {
    final m = readMeta(slot);
    final saveFile = File('${_slotPath(slot)}/$save');
    final hasSave = saveFile.existsSync();
    if (m.isEmpty && !hasSave) return null;
    final e = WorldEntry(
      slot: slot,
      name: m['name']?.toString() ?? slot,
      seed: (m['seed'] as num?)?.toInt() ?? 0,
      mode: m['mode']?.toString() ?? 'survival',
      playerClass: m['class']?.toString() ?? 'warrior',
      dimension: 0,
      playSeconds: 0.0,
      lastPlayed: (m['created'] as num?)?.toInt() ?? 0,
      hasSave: hasSave,
      playground: m['type'] == 'playground',
    );
    if (hasSave) {
      try {
        final data = jsonDecode(saveFile.readAsStringSync());
        if (data is Map<String, dynamic>) {
          final stats = (data['stats'] as Map<String, dynamic>?) ?? const {};
          e.seed = (data['seed'] as num?)?.toInt() ?? e.seed;
          e.dimension = (data['dimension'] as num?)?.toInt() ?? 0;
          e.playSeconds = (stats['play_time'] as num?)?.toDouble() ?? 0.0;
          e.playerClass = stats['class']?.toString() ?? e.playerClass;
          if (stats['creative'] == true) e.mode = 'creative';
          if (stats['playground'] == true) e.playground = true;
        }
      } on FormatException {
        // An unreadable save still lists by its meta.
      }
      e.lastPlayed = saveFile.lastModifiedSync().millisecondsSinceEpoch ~/ 1000;
    }
    return e;
  }

  static Map<String, dynamic> readMeta(String slot) {
    final f = File('${_slotPath(slot)}/$meta');
    if (!f.existsSync()) return {};
    try {
      final data = jsonDecode(f.readAsStringSync());
      return data is Map<String, dynamic> ? data : {};
    } on FormatException {
      return {};
    }
  }

  static void writeMeta(String slot, Map<String, dynamic> m) {
    Directory(_slotPath(slot)).createSync(recursive: true);
    File('${_slotPath(slot)}/$meta').writeAsStringSync(jsonEncode(m), flush: true);
  }

  static final math.Random _rng = math.Random();

  /// The seed a player typed: a number as itself, anything else hashed, empty
  /// = random. Godot hashes with its own `hash()`; Dart's `hashCode` is seeded
  /// per process, so the text goes through FNV-1a (a typed word gives the same
  /// seed every run, just not Godot's).
  static int seedFromText(String text) {
    final t = text.trim();
    if (t == '') return _rng.nextInt(1000000);
    if (RegExp(r'^[+-]?\d+$').hasMatch(t)) return int.parse(t);
    return fnv1a(t) % 1000000;
  }

  static int fnv1a(String s) {
    var h = 0x811c9dc5;
    for (final c in utf8.encode(s)) {
      h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }

  /// Godot's `String.validate_filename()`: the characters a file name cannot
  /// hold become `_`.
  static String validateFilename(String s) => s.replaceAll(RegExp(r'[:/\\?*"|%<>]'), '_');

  /// The folder name for a display name (Godot's `to_lower().validate_filename()`
  /// with spaces as underscores).
  static String slugOf(String name) => validateFilename(name.toLowerCase()).replaceAll(' ', '_');

  /// The New World form's Start: a fresh slot named after the world (a number
  /// appended when the name is taken), its `world.json` written. Returns the slot.
  static String create(String name, String seedText, String mode, String cls, {String slotPrefix = '', int? now, String type = ''}) {
    var clean = name.trim();
    if (clean == '') clean = 'New World';
    final base = slotPrefix + slugOf(clean);
    var slot = base;
    var n = 2;
    while (Directory(_slotPath(slot)).existsSync()) {
      slot = '${base}_$n';
      n += 1;
    }
    writeMeta(slot, {
      'name': clean,
      'seed': seedFromText(seedText),
      'mode': mode,
      'class': cls,
      'created': now ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      if (type != '') 'type': type,
    });
    return slot;
  }

  /// Stage 33: the title's Playground button. Always a new creative slot on
  /// seed [playgroundSeed], so every playground starts from the same world.
  static const int playgroundSeed = 42;
  static String createPlayground(String cls, {int? now}) =>
      create('Playground', '$playgroundSeed', 'creative', cls, now: now, type: 'playground');

  static bool rename(String slot, String name) {
    final clean = name.trim();
    if (clean == '' || entry(slot) == null) return false;
    final m = readMeta(slot);
    m['name'] = clean;
    writeMeta(slot, m);
    return true;
  }

  static bool delete(String slot) {
    final dir = Directory(_slotPath(slot));
    if (slot == '' || slot.contains('/') || slot.contains('..') || !dir.existsSync()) return false;
    dir.deleteSync(recursive: true);
    return true;
  }

  /// Play: the session state a `Game` boot reads (`GameState.worldName` is the
  /// slot). A world with no save yet is fresh; one with a save loads it.
  ///
  /// Unlike Godot (whose `GameState` autoload keeps the previous world's
  /// counters until a save overwrites them), the counters are cleared first, so
  /// a fresh world never starts with another world's stats.
  static void start(String slot) {
    final e = entry(slot);
    if (e == null) throw ArgumentError('unknown world slot $slot');
    final gs = GameState.instance;
    gs.resetStats();
    gs.worldName = slot;
    gs.seedValue = e.seed;
    gs.playerClass = e.playerClass;
    gs.creative = e.creative;
    gs.playground = e.playground;
    gs.freshWorld = !e.hasSave;
  }

  static String modeLabel(WorldEntry e) => e.playground ? 'Playground' : (e.creative ? 'Creative' : 'Survival');

  static String playTimeLabel(double seconds) {
    final s = seconds.toInt();
    if (s < 60) return '$s s';
    if (s < 3600) return '${s ~/ 60} min';
    return '${s ~/ 3600}h ${((s % 3600) ~/ 60).toString().padLeft(2, '0')}m';
  }

  static String lastPlayedLabel(int unix) {
    if (unix <= 0) return 'never';
    final d = DateTime.fromMillisecondsSinceEpoch(unix * 1000);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }
}
