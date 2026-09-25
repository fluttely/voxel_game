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
//   dart tool/run_benchmark.dart -- --graphics=phone     # after `--`: passed to every run
//   dart tool/run_benchmark.dart --android R5CX... --cooldown 20   # on a phone (adb serial)
//   dart tool/run_benchmark.dart --trace --runs orbit:6  # + the GPU's work, from Instruments
//
// Runs go round-robin (every scenario once, then again) with a cooldown between
// them, so thermal drift spreads over all of them instead of landing on the last.
// On this Mac by default; `--android SERIAL` builds the APK, installs it and runs
// each scenario on that device through its launch intent, reading the line back
// from logcat. A phone heats: give it a longer cooldown, and read `deviceTempC`.
//
// `--trace` (macOS) runs a profile build under a Metal System Trace and adds
// `gpuTrace` to each line: the GPU's busy time per composited frame. It is the
// only GPU cost the benchmark has; the app's own `gpuLatencyMs` includes the
// queue. Instruments cannot attach to a release build, so a traced run is a
// profile build's: keep its lines in their own file.
import 'dart:convert';
import 'dart:io';

const example = 'packages/voxel_game/example';
/// The macOS app of a `release` or `profile` build.
String macApp(String mode) =>
    '$example/build/macos/Build/Products/${mode == 'release' ? 'Release' : 'Profile'}/voxel_game_example.app/Contents/MacOS/voxel_game_example';
const androidPackage = 'com.remottely.voxel_game_example';
const apk = '$example/build/app/outputs/flutter-apk/app-release.apk';
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
  final android = value('--android');
  final trace = args.contains('--trace');
  if (trace && android != null) throw ArgumentError('--trace reads a Metal System Trace: macOS only');
  final mode = trace ? 'profile' : 'release';

  final commit = (await Process.run('git', ['rev-parse', '--short', 'HEAD'])).stdout.toString().trim();
  final dirty = (await Process.run('git', ['status', '--porcelain', '--', 'packages'])).stdout.toString().trim().isNotEmpty;
  final machine = android == null
      ? (await Process.run('sysctl', ['-n', 'machdep.cpu.brand_string'])).stdout.toString().trim()
      : '${await adb(android, ['shell', 'getprop', 'ro.product.model'])} (${await adb(android, ['shell', 'getprop', 'ro.soc.model'])})';

  if (build) {
    final cmd = ['flutter', 'build', android == null ? 'macos' : 'apk', '--$mode', '-t', 'lib/benchmark.dart'];
    stderr.writeln('\$ (cd $example && ${cmd.join(' ')})');
    if (!dryRun) {
      final r = await Process.run(cmd.first, cmd.sublist(1), workingDirectory: example);
      if (r.exitCode != 0) {
        stderr.write(r.stdout);
        stderr.write(r.stderr);
        exit(r.exitCode);
      }
      if (android != null) await adb(android, ['install', '-r', apk]);
    }
  }

  final lines = <Map<String, Object?>>[];
  final sink = out == null || dryRun ? null : File(out).openWrite(mode: FileMode.append);
  var first = true;
  for (var round = 0; round < repeat; round++) {
    for (final run in runs) {
      final [scenario, radius] = run.split(':');
      final flags = ['--scenario=$scenario', '--radius=$radius', '--seconds=$seconds', if (android == null) '--window=$window', ...extra];
      stderr.writeln(android == null ? '\$ ${macApp(mode)} ${flags.join(' ')}' : '\$ adb -s $android shell am start ... ${flags.join(',')}');
      if (dryRun) continue;
      if (!first && cooldown > 0) await Future<void>.delayed(Duration(seconds: cooldown));
      first = false;
      final locked = android == null ? await screenLocked() : await deviceLocked(android);
      if (locked) stderr.writeln('  the screen is locked: the GPU time and fps of this run are not what a player sees');
      final tempC = android == null ? null : await deviceTempC(android);
      final (output, gpuTrace) = android != null
          ? (await runAndroid(android, flags), null)
          : trace
              ? await runTraced(macApp(mode), flags, double.parse(seconds))
              : (await runMac(macApp(mode), flags), null);
      final found = const LineSplitter().convert(output).where((l) => l.startsWith('[bench] {'));
      if (found.isEmpty) {
        stderr.writeln('run failed, no result line:\n$output');
        exit(1);
      }
      final line = <String, Object?>{
        ...jsonDecode(found.last.substring(8)) as Map<String, Object?>,
        'screenLocked': locked,
        if (tempC != null) 'deviceTempC': tempC,
        if (gpuTrace != null) 'gpuTrace': gpuTrace,
        'commit': dirty ? '$commit+dirty' : commit,
        'machine': machine,
        'extra': extra.join(' '),
        'round': round,
      };
      // xctrace launches an app by its bundle id, so it can start another build of it.
      if (line['mode'] != mode) {
        stderr.writeln('the run was a ${line['mode']} build, not the $mode build this script made');
        exit(1);
      }
      lines.add(line);
      sink?.writeln(jsonEncode(line));
      stderr.writeln('  fps ${line['fps']}  gpu latency p50 ${(line['gpuLatencyMs'] as Map)['p50']} ms  build p50 ${(line['buildMs'] as Map)['p50']} ms');
    }
  }
  await sink?.close();
  if (!dryRun) stdout.write(table(lines));
}

/// One run on this Mac: the app's stdout, where it prints its line.
Future<String> runMac(String app, List<String> flags) async {
  final r = await Process.run(app, flags).timeout(const Duration(minutes: 3));
  if (r.exitCode != 0) {
    stderr.writeln('run failed (exit ${r.exitCode}):\n${r.stdout}${r.stderr}');
    exit(1);
  }
  return '${r.stdout}';
}

/// One run on an Android device: the app started afresh with [flags] in its
/// launch intent (`FlutterActivity` hands them to `main`), waited for until its
/// process exits, and logcat's `flutter` lines, where its line lands.
Future<String> runAndroid(String serial, List<String> flags) async {
  await adb(serial, ['logcat', '-c']);
  await adb(serial, ['shell', 'am', 'start', '-S', '-W', '-n', '$androidPackage/.MainActivity', '--esal', 'dart_entrypoint_args', flags.join(',')]);
  final deadline = DateTime.now().add(const Duration(minutes: 3));
  while ((await Process.run('adb', ['-s', serial, 'shell', 'pidof', androidPackage])).exitCode == 0) {
    if (DateTime.now().isAfter(deadline)) throw StateError('the run on $serial did not end in 3 minutes');
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  return adb(serial, ['logcat', '-d', '-v', 'raw', '-s', 'flutter:I']);
}

/// One run on this Mac under a Metal System Trace: the app's stdout, and the
/// GPU's work over the [seconds] it recorded ([gpuFromTrace]). The trace is
/// deleted once read, and so is the raw recording xctrace leaves behind in the
/// user's temporary directory (`instruments*.ktrace`, about 1 GB a run), the
/// one this run added; the time limit bounds both if the app never exits.
Future<(String, Map<String, Object>)> runTraced(String app, List<String> flags, double seconds) async {
  final dir = Directory.systemTemp.createTempSync('run_benchmark_');
  Set<String> recordings() => {
        for (final f in Directory.systemTemp.listSync())
          if (f.uri.pathSegments.last.startsWith('instruments') && f.path.endsWith('.ktrace')) f.path,
      };
  final before = recordings();
  try {
    final trace = '${dir.path}/run.trace', out = '${dir.path}/run.out';
    final r = await Process.run('xcrun', [
      'xctrace', 'record', '--template', 'Metal System Trace', '--time-limit', '${(seconds + 60).round()}s',
      '--output', trace, '--target-stdout', out, '--launch', '--', app, ...flags,
    ]);
    if (r.exitCode != 0) throw StateError('xctrace record failed: ${r.stdout}${r.stderr}');
    final table = await Process.run('xcrun', [
      'xctrace', 'export', '--input', trace,
      '--xpath', '/trace-toc/run[@number="1"]/data/table[@schema="metal-gpu-intervals"]',
    ]);
    if (table.exitCode != 0) throw StateError('xctrace export failed: ${table.stderr}');
    return (File(out).readAsStringSync(), gpuFromTrace('${table.stdout}', seconds));
  } finally {
    dir.deleteSync(recursive: true);
    for (final f in recordings().difference(before)) {
      File(f).deleteSync();
    }
  }
}

/// The app's GPU work over the last [seconds] of an exported
/// `metal-gpu-intervals` table, which is where the recording is (the app exits
/// right after it): the union of its intervals (busy time, passes that overlap
/// counted once) as a share of the window and per frame, a frame being one of
/// Flutter's composites (its `EntityPass Command Buffer` fragment pass).
Map<String, Object> gpuFromTrace(String xml, double seconds) {
  // xctrace writes a value once with an id and later refers to it by that id.
  final byId = <String, (String, String)>{
    for (final m in RegExp(r'<[a-z0-9-]+ id="(\d+)" fmt="([^"]*)">([^<]*)').allMatches(xml)) m[1]!: (m[2]!, m[3]!),
  };
  (String fmt, String text) first(String row, String tag) {
    final m = RegExp('<$tag (?:id="(\\d+)"|ref="(\\d+)")').firstMatch(row);
    if (m == null) throw StateError('a GPU interval without $tag: $row');
    return byId[m[1] ?? m[2]]!;
  }

  final intervals = <({int start, int end, bool frame})>[];
  for (final row in RegExp(r'<row>(.*?)</row>', dotAll: true).allMatches(xml)) {
    final body = row[1]!;
    // The row's first formatted-label is its event label, which names the process.
    final label = first(body, 'formatted-label').$1;
    if (!label.contains('( voxel_game_example (')) continue;
    final start = int.parse(first(body, 'start-time').$2);
    final frame = label.startsWith('EntityPass Command Buffer') && first(body, 'gpu-channel-name').$2 == 'Fragment';
    intervals.add((start: start, end: start + int.parse(first(body, 'duration').$2), frame: frame));
  }
  if (intervals.isEmpty) throw StateError('the trace holds no GPU work of voxel_game_example');
  final windowNs = (seconds * 1e9).round();
  final from = intervals.map((i) => i.end).reduce((a, b) => a > b ? a : b) - windowNs;
  final window = intervals.where((i) => i.start >= from).toList()..sort((a, b) => a.start.compareTo(b.start));
  var busy = 0, start = window.first.start, end = window.first.end;
  for (final i in window.skip(1)) {
    if (i.start > end) {
      busy += end - start;
      (start, end) = (i.start, i.end);
    } else if (i.end > end) {
      end = i.end;
    }
  }
  busy += end - start;
  final frames = window.where((i) => i.frame).length;
  if (frames == 0) throw StateError('no composited frame in the traced window');
  return {'busyPct': (busy / windowNs * 1000).round() / 10, 'msPerFrame': (busy / 1e6 / frames * 100).round() / 100, 'frames': frames};
}

/// `adb -s [serial] [args]`'s stdout, trimmed; a failure ends the script.
Future<String> adb(String serial, List<String> args) async {
  final r = await Process.run('adb', ['-s', serial, ...args]);
  if (r.exitCode != 0) throw StateError('adb ${args.join(' ')} failed: ${r.stdout}${r.stderr}');
  return '${r.stdout}'.trim();
}

/// Wakes the device and says whether its keyguard still shows: a run behind the
/// lock screen draws nothing a player sees, as on a locked Mac.
Future<bool> deviceLocked(String serial) async {
  await adb(serial, ['shell', 'input', 'keyevent', 'KEYCODE_WAKEUP']);
  return (await adb(serial, ['shell', 'dumpsys', 'window'])).contains('isKeyguardShowing=true');
}

/// The battery's temperature in °C, the closest a phone reports to how hot it
/// runs: a hot phone throttles, and its later runs are slower for it.
Future<double> deviceTempC(String serial) async {
  final m = RegExp(r'temperature: (\d+)').firstMatch(await adb(serial, ['shell', 'dumpsys', 'battery']));
  if (m == null) throw StateError('dumpsys battery reported no temperature');
  return int.parse(m.group(1)!) / 10.0;
}

/// Whether the session's screen is locked. A locked Mac still renders the game's
/// frames, but behind the lock screen: the display does not show them, its
/// refresh drops to 60 Hz and the GPU time is paced by the lock screen's. The
/// CPU numbers stay valid; the GPU and fps ones do not (the plan's §Validity).
Future<bool> screenLocked() async {
  final r = await Process.run('swift', [
    '-e',
    'import CoreGraphics; let d = CGSessionCopyCurrentDictionary() as? [String: Any]; '
        'print((d?["CGSSessionScreenIsLocked"] as? Bool) == true)',
  ]);
  if (r.exitCode != 0) throw StateError('could not read the screen lock state: ${r.stderr}');
  return '${r.stdout}'.trim() == 'true';
}

List<Map<String, Object?>> read(String path) =>
    [for (final l in File(path).readAsLinesSync()) if (l.trim().isNotEmpty) jsonDecode(l) as Map<String, Object?>];

String keyOf(Map<String, Object?> l) => '${l['scenario']}:${l['radius']}${(l['extra'] as String? ?? '').isEmpty ? '' : ' ${l['extra']}'}';

/// The columns: a label and how to read one run's value, null where the run
/// did not measure it (the `gpuTrace` ones, taken only with `--trace`; the
/// step ones, missing from runs recorded before PF6).
final columns = <(String, num? Function(Map<String, Object?>))>[
  ('fps', (l) => l['fps'] as num),
  ('hitches', (l) => l['hitches'] as num),
  ('frame p99 ms', (l) => (l['intervalMs'] as Map)['p99'] as num),
  ('GPU latency p50 ms', (l) => (l['gpuLatencyMs'] as Map)['p50'] as num),
  ('GPU latency p99 ms', (l) => (l['gpuLatencyMs'] as Map)['p99'] as num),
  ('UI p50 ms', (l) => (l['buildMs'] as Map)['p50'] as num),
  ('UI p99 ms', (l) => (l['buildMs'] as Map)['p99'] as num),
  ('GPU ms/frame', (l) => (l['gpuTrace'] as Map?)?['msPerFrame'] as num?),
  ('GPU busy %', (l) => (l['gpuTrace'] as Map?)?['busyPct'] as num?),
  ('encode p50 ms', (l) => (l['encodeMs'] as Map)['p50'] as num),
  ('sim p99 ms', (l) => (l['simMs'] as Map)['p99'] as num),
  ('step p50 ms', (l) => (l['stepMs'] as Map?)?['p50'] as num?),
  ('step p99 ms', (l) => (l['stepMs'] as Map?)?['p99'] as num?),
  ('raster p99 ms', (l) => (l['rasterMs'] as Map)['p99'] as num),
  ('fill ms', (l) => l['fillMs'] as num),
  ('faces', (l) => l['faces'] as num),
  ('RSS MB', (l) => l['maxRssMb'] as num),
];

/// The columns every one of [lines] measured.
List<(String, num? Function(Map<String, Object?>))> measured(List<Map<String, Object?>> lines) =>
    [for (final c in columns) if (lines.every((l) => c.$2(l) != null)) c];

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

/// Medians per scenario, with the spread (max - min) of fps and GPU latency p50.
String table(List<Map<String, Object?>> lines) {
  final shown = measured(lines);
  final b = StringBuffer()
    ..writeln('| run | n | ${shown.map((c) => c.$1).join(' | ')} |')
    ..writeln('|:--|--:|${shown.map((_) => '--:').join('|')}|');
  for (final e in byKey(lines).entries) {
    final cells = [
      for (final (name, get) in shown)
        () {
          final xs = [for (final l in e.value) get(l)!];
          final spread = xs.length > 1 && (name == 'fps' || name == 'GPU latency p50 ms')
              ? ' ±${fmt((xs.reduce((a, b) => a > b ? a : b) - xs.reduce((a, b) => a < b ? a : b)) / 2)}'
              : '';
          return '${fmt(median(xs))}$spread';
        }(),
    ];
    b.writeln('| ${e.key} | ${e.value.length} | ${cells.join(' | ')} |');
  }
  final locked = lines.where((l) => l['screenLocked'] == true).length;
  if (locked > 0) {
    b.writeln('\n**Screen locked during $locked of ${lines.length} runs**: their GPU and fps columns are not what a player sees.');
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
  final lockedBefore = before.any((l) => l['screenLocked'] == true), lockedAfter = after.any((l) => l['screenLocked'] == true);
  final warning = lockedBefore == lockedAfter
      ? (lockedBefore ? '**Both sides ran with the screen locked**: compare CPU columns only.\n\n' : '')
      : '**One side ran with the screen locked and the other did not**: the GPU and fps rows are not comparable.\n\n';
  final a = byKey(before), z = byKey(after);
  final b = StringBuffer(warning)
    ..writeln('| run | metric | before | after | change |')
    ..writeln('|:--|:--|--:|--:|--:|');
  final shown = measured([...before, ...after]);
  for (final key in a.keys.where(z.containsKey)) {
    for (final (name, get) in shown) {
      final x = median([for (final l in a[key]!) get(l)!]), y = median([for (final l in z[key]!) get(l)!]);
      final change = x == 0 ? '' : '${y >= x ? '+' : ''}${((y - x) / x * 100).toStringAsFixed(0)}%';
      b.writeln('| $key | $name | ${fmt(x)} | ${fmt(y)} | $change |');
    }
  }
  return b.toString();
}
