// Measures the frame rate of the kit's example game: builds `lib/benchmark.dart`
// in release, runs each scenario several times, and prints the medians. The
// method, the metrics and what to compare are in docs/VOXEL_PERF_PLAN_2026-09-25.md.
//
//   dart tool/run_benchmark.dart                         # build, run the default set, print
//   dart tool/run_benchmark.dart --out docs/perf/x.jsonl # also keep every run's line
//   dart tool/run_benchmark.dart --runs orbit:12 --repeat 5 --no-build
//   dart tool/run_benchmark.dart --summarize docs/perf/x.jsonl
//   dart tool/run_benchmark.dart --compare docs/perf/a.jsonl docs/perf/b.jsonl
//   dart tool/run_benchmark.dart --dry-run               # print what it would run
//   dart tool/run_benchmark.dart -- --graphics=low       # after `--`: passed to every run
//
// Runs go round-robin (every scenario once, then again) with a cooldown between
// them, so thermal drift spreads over all of them instead of landing on the last.
// macOS only for now: a phone runs `lib/benchmark.dart` by hand (see its header).
import 'dart:convert';
import 'dart:io';

const example = 'packages/voxel_game/example';
const app = '$example/build/macos/Build/Products/Release/voxel_game_example.app/Contents/MacOS/voxel_game_example';
const defaultRuns = ['orbit:6', 'orbit:12', 'fly:6', 'fly:12', 'mobs:6'];

Future<void> main(List<String> argv) async {
  Directory.current = File.fromUri(Platform.script).parent.parent.path;
  final split = argv.indexOf('--');
  final args = split < 0 ? argv : argv.sublist(0, split);
  final extra = split < 0 ? <String>[] : argv.sublist(split + 1);
  String? value(String name) {
    final i = args.indexOf(name);
    return i < 0 ? null : args[i + 1];
  }

  final summarize = value('--summarize');
  if (summarize != null) {
    stdout.write(table(read(summarize)));
    return;
  }
  final compare = args.indexOf('--compare');
  if (compare >= 0) {
    stdout.write(comparison(read(args[compare + 1]), read(args[compare + 2])));
    return;
  }

  final runs = value('--runs')?.split(',') ?? defaultRuns;
  final repeat = int.parse(value('--repeat') ?? '3');
  final cooldown = int.parse(value('--cooldown') ?? '5');
  final seconds = value('--seconds') ?? '12';
  final window = value('--window') ?? '1600x900';
  final out = value('--out');
  final dryRun = args.contains('--dry-run');
  final build = !args.contains('--no-build');

  final commit = (await Process.run('git', ['rev-parse', '--short', 'HEAD'])).stdout.toString().trim();
  final dirty = (await Process.run('git', ['status', '--porcelain', '--', 'packages'])).stdout.toString().trim().isNotEmpty;
  final machine = (await Process.run('sysctl', ['-n', 'machdep.cpu.brand_string'])).stdout.toString().trim();

  if (build) {
    final cmd = ['flutter', 'build', 'macos', '--release', '-t', 'lib/benchmark.dart'];
    stderr.writeln('\$ (cd $example && ${cmd.join(' ')})');
    if (!dryRun) {
      final r = await Process.run(cmd.first, cmd.sublist(1), workingDirectory: example);
      if (r.exitCode != 0) {
        stderr.write(r.stdout);
        stderr.write(r.stderr);
        exit(r.exitCode);
      }
    }
  }

  final lines = <Map<String, Object?>>[];
  final sink = out == null || dryRun ? null : File(out).openWrite(mode: FileMode.append);
  var first = true;
  for (var round = 0; round < repeat; round++) {
    for (final run in runs) {
      final [scenario, radius] = run.split(':');
      final cmd = [app, '--scenario=$scenario', '--radius=$radius', '--seconds=$seconds', '--window=$window', ...extra];
      stderr.writeln('\$ ${cmd.join(' ')}');
      if (dryRun) continue;
      if (!first && cooldown > 0) await Future<void>.delayed(Duration(seconds: cooldown));
      first = false;
      final r = await Process.run(cmd.first, cmd.sublist(1)).timeout(const Duration(minutes: 3));
      final found = const LineSplitter().convert('${r.stdout}').where((l) => l.startsWith('[bench] '));
      if (r.exitCode != 0 || found.isEmpty) {
        stderr.writeln('run failed (exit ${r.exitCode}):\n${r.stdout}${r.stderr}');
        exit(1);
      }
      final line = <String, Object?>{
        ...jsonDecode(found.last.substring(8)) as Map<String, Object?>,
        'commit': dirty ? '$commit+dirty' : commit,
        'machine': machine,
        'extra': extra.join(' '),
        'round': round,
      };
      lines.add(line);
      sink?.writeln(jsonEncode(line));
      stderr.writeln('  fps ${line['fps']}  gpu p50 ${(line['gpuMs'] as Map)['p50']} ms  build p50 ${(line['buildMs'] as Map)['p50']} ms');
    }
  }
  await sink?.close();
  if (!dryRun) stdout.write(table(lines));
}

List<Map<String, Object?>> read(String path) =>
    [for (final l in File(path).readAsLinesSync()) if (l.trim().isNotEmpty) jsonDecode(l) as Map<String, Object?>];

String keyOf(Map<String, Object?> l) => '${l['scenario']}:${l['radius']}${(l['extra'] as String? ?? '').isEmpty ? '' : ' ${l['extra']}'}';

/// The columns: a label and how to read one run's value.
final columns = <(String, num Function(Map<String, Object?>))>[
  ('fps', (l) => l['fps'] as num),
  ('hitches', (l) => l['hitches'] as num),
  ('frame p99 ms', (l) => (l['intervalMs'] as Map)['p99'] as num),
  ('GPU p50 ms', (l) => (l['gpuMs'] as Map)['p50'] as num),
  ('GPU p99 ms', (l) => (l['gpuMs'] as Map)['p99'] as num),
  ('UI p50 ms', (l) => (l['buildMs'] as Map)['p50'] as num),
  ('UI p99 ms', (l) => (l['buildMs'] as Map)['p99'] as num),
  ('encode p50 ms', (l) => (l['encodeMs'] as Map)['p50'] as num),
  ('sim p99 ms', (l) => (l['simMs'] as Map)['p99'] as num),
  ('raster p99 ms', (l) => (l['rasterMs'] as Map)['p99'] as num),
  ('fill ms', (l) => l['fillMs'] as num),
  ('faces', (l) => l['faces'] as num),
  ('RSS MB', (l) => l['maxRssMb'] as num),
];

num median(List<num> xs) {
  final s = List.of(xs)..sort();
  final n = s.length;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

String fmt(num v) => v is int || v == v.roundToDouble() && v.abs() >= 100 ? '${v.round()}' : v.toStringAsFixed(v.abs() >= 10 ? 1 : 2);

Map<String, List<Map<String, Object?>>> byKey(List<Map<String, Object?>> lines) {
  final m = <String, List<Map<String, Object?>>>{};
  for (final l in lines) {
    (m[keyOf(l)] ??= []).add(l);
  }
  return m;
}

/// Medians per scenario, with the spread (max - min) of fps and GPU p50.
String table(List<Map<String, Object?>> lines) {
  final b = StringBuffer()
    ..writeln('| run | n | ${columns.map((c) => c.$1).join(' | ')} |')
    ..writeln('|:--|--:|${columns.map((_) => '--:').join('|')}|');
  for (final e in byKey(lines).entries) {
    final cells = [
      for (final (name, get) in columns)
        () {
          final xs = [for (final l in e.value) get(l)];
          final spread = xs.length > 1 && (name == 'fps' || name == 'GPU p50 ms')
              ? ' ±${fmt((xs.reduce((a, b) => a > b ? a : b) - xs.reduce((a, b) => a < b ? a : b)) / 2)}'
              : '';
          return '${fmt(median(xs))}$spread';
        }(),
    ];
    b.writeln('| ${e.key} | ${e.value.length} | ${cells.join(' | ')} |');
  }
  final first = lines.isEmpty ? null : lines.first;
  if (first != null) {
    b.writeln('\n${first['machine']} · ${first['platform']} · ${first['window']} @${first['dpr']}x · '
        '${first['refreshHz']} Hz · commit ${first['commit']}');
  }
  return b.toString();
}

/// Before and after, median against median, with the change in percent.
String comparison(List<Map<String, Object?>> before, List<Map<String, Object?>> after) {
  final a = byKey(before), z = byKey(after);
  final b = StringBuffer()
    ..writeln('| run | metric | before | after | change |')
    ..writeln('|:--|:--|--:|--:|--:|');
  for (final key in a.keys.where(z.containsKey)) {
    for (final (name, get) in columns) {
      final x = median([for (final l in a[key]!) get(l)]), y = median([for (final l in z[key]!) get(l)]);
      final change = x == 0 ? '' : '${y >= x ? '+' : ''}${((y - x) / x * 100).toStringAsFixed(0)}%';
      b.writeln('| $key | $name | ${fmt(x)} | ${fmt(y)} | $change |');
    }
  }
  return b.toString();
}
