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
//   dart tool/run_benchmark.dart --android R5CX... --max-temp 38   # hotter than the 36 °C default
//   dart tool/run_benchmark.dart --trace --runs orbit:6  # + the GPU's work, from Instruments
//
// Runs go round-robin (every scenario once, then again) with a cooldown between
// them, so thermal drift spreads over all of them instead of landing on the last.
// On this Mac by default; `--android SERIAL` builds the APK, installs it and runs
// each scenario on that device through its launch intent, reading the line back
// from logcat. A phone heats: give it a longer cooldown, and read `deviceTempC`.
// Before each run on a phone the script waits for its battery to be under
// `--max-temp` (36 °C by default): at 120 Hz it stays over 33 for minutes
// between runs, so 36 is the base every side can reach.
//
// `--trace` (macOS) runs a profile build under a Metal System Trace and adds
// `gpuTrace` to each line: the GPU's busy time per composited frame. It is the
// only GPU cost the benchmark has; the app's own `gpuLatencyMs` includes the
// queue. Instruments cannot attach to a release build, so a traced run is a
// profile build's: keep its lines in their own file. While it records, every
// other copy of the app (the release build, another worktree's) is hidden from
// LaunchServices, since xctrace launches the app by its bundle id; a trace of
// any other copy is refused.
//
// Every line records what else the machine ran beside the run and the state
// of its CPU, GPU and memory (`machineLoad`, tool/machine_load.dart, PFD1);
// on a phone, the Mac's that drives adb (the phone's own is not read yet). A
// busy machine is never refused: the summary says in how many runs the run was
// alone, and what ran beside the others.
import 'dart:convert';
import 'dart:io';

import 'machine_load.dart';

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
  final maxTempC = double.parse(value('--max-temp') ?? '36');
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
      final tempC = android == null ? null : await coolDown(android, maxTempC);
      // Started just before the launch, so all of the app's time falls within its samples.
      final meter = await LoadMeter.start(MacProbe(), runExecutable: android == null ? File(macApp(mode)).resolveSymbolicLinksSync() : null);
      final (output, gpuTrace, machineLoad) = android != null
          // On a phone the meter reads the Mac that drives adb.
          ? (await runAndroid(android, flags), null, await meter.stop())
          : trace
              ? await runTraced(macApp(mode), flags, double.parse(seconds), meter)
              : await runMac(macApp(mode), flags, meter).then((r) => (r.$1, null, r.$2));
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
        'machineLoad': machineLoad,
        'commit': dirty ? '$commit+dirty' : commit,
        'machine': machine,
        'extra': extra.join(' '),
        'round': round,
      };
      // The line's own word on the build that ran, beside runTraced's check of the bundle.
      if (line['mode'] != mode) {
        stderr.writeln('the run was a ${line['mode']} build, not the $mode build this script made');
        exit(1);
      }
      lines.add(line);
      sink?.writeln(jsonEncode(line));
      stderr.writeln('  fps ${line['fps']}  gpu latency p50 ${(line['gpuLatencyMs'] as Map)['p50']} ms  build p50 ${(line['buildMs'] as Map)['p50']} ms');
      stderr.writeln('  machine: ${describeLoad(machineLoad)}');
    }
  }
  await sink?.close();
  if (!dryRun) stdout.write(table(lines));
}

/// One run on this Mac: the app's stdout, where it prints its line, and
/// [meter]'s reading over it.
Future<(String, Map<String, Object?>)> runMac(String app, List<String> flags, LoadMeter meter) async {
  final (r, load) = await timed(app, flags, meter, const Duration(minutes: 3));
  if (r.exitCode != 0) {
    stderr.writeln('run failed (exit ${r.exitCode}):\n${r.stdout}${r.stderr}');
    exit(1);
  }
  return ('${r.stdout}', load);
}

/// Runs [executable] under `/usr/bin/time -p` and stops [meter] when it
/// exits: the CPU time `time` read for its child to the child's exit stands
/// for the child's samples, which miss up to [pollInterval] of its end. The
/// result's stderr is the child's, `time`'s lines taken off. Past [limit] the
/// child and `time` are killed and the script stops.
Future<(ProcessResult, Map<String, Object?>)> timed(String executable, List<String> args, LoadMeter meter, Duration limit) async {
  final process = await Process.start('/usr/bin/time', ['-p', executable, ...args]);
  final out = process.stdout.transform(utf8.decoder).join(), err = process.stderr.transform(utf8.decoder).join();
  final code = await process.exitCode.timeout(limit, onTimeout: () async {
    // `time` waits for its child: the child goes first, or it outlives the script.
    await Process.run('pkill', ['-KILL', '-P', '${process.pid}']);
    process.kill(ProcessSignal.sigkill);
    throw StateError('$executable did not exit in $limit');
  });
  final (stdoutText, stderrText) = (await out, await err);
  // `-p` ends stderr with `real`, `user` and `sys` lines, in seconds; `real`
  // follows the child's last byte, which may not end its line.
  final times = RegExp(r'real [\d.]+\nuser ([\d.]+)\nsys ([\d.]+)\n?$').allMatches(stderrText).lastOrNull;
  if (times == null) throw StateError('/usr/bin/time printed no times for $executable:\n$stderrText');
  final load = await meter.stop(exited: (parent: process.pid, cpuS: double.parse(times[1]!) + double.parse(times[2]!)));
  return (ProcessResult(process.pid, code, stdoutText, stderrText.substring(0, times.start)), load);
}

/// One run on an Android device: the app started afresh with [flags] in its
/// launch intent (`FlutterActivity` hands them to `main`), waited for until its
/// process exits, and logcat's `flutter` lines, where its line lands. A process
/// that ends without its line died: the reason Android recorded for its exit
/// and the crash log (signal, backtrace) follow, since the `flutter` tag holds
/// neither.
Future<String> runAndroid(String serial, List<String> flags) async {
  await adb(serial, ['logcat', '-c']);
  await adb(serial, ['shell', 'am', 'start', '-S', '-W', '-n', '$androidPackage/.MainActivity', '--esal', 'dart_entrypoint_args', flags.join(',')]);
  final pid = (await Process.run('adb', ['-s', serial, 'shell', 'pidof', androidPackage])).stdout.toString().trim();
  final deadline = DateTime.now().add(const Duration(minutes: 3));
  while ((await Process.run('adb', ['-s', serial, 'shell', 'pidof', androidPackage])).exitCode == 0) {
    if (DateTime.now().isAfter(deadline)) throw StateError('the run on $serial did not end in 3 minutes');
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  final output = await adb(serial, ['logcat', '-d', '-v', 'raw', '-s', 'flutter:I']);
  if (output.contains('[bench] {')) return output;
  // `dumpsys activity exit-info` lists the package's last exits, newest first,
  // each as a `timestamp=... pid=N` line and a `process=... reason=...` one.
  final exits = const LineSplitter().convert(await adb(serial, ['shell', 'dumpsys', 'activity', 'exit-info', androidPackage]));
  final at = exits.indexWhere((l) => l.contains(' pid=$pid '));
  final exit = pid.isEmpty ? 'the process was gone when `am start` returned' : at < 0 ? 'no exit recorded for pid $pid' : exits[at + 1].trim();
  final crash = await adb(serial, ['logcat', '-d', '-v', 'raw', '-b', 'crash']);
  return '$output\n\nexit: $exit\n\ncrash log:\n${crash.isEmpty ? '(empty)' : crash}';
}

/// One run on this Mac under a Metal System Trace: the app's stdout, and the
/// GPU's work over the [seconds] it recorded ([gpuFromTrace]). The trace is
/// deleted once read, and so is the raw recording xctrace leaves behind in the
/// user's temporary directory (`instruments*.ktrace`, about 1 GB a run), the
/// one this run added; the time limit bounds both if the app never exits.
///
/// xctrace spawns the app suspended and then launches it by its bundle id,
/// which LaunchServices resolves to any copy it knows of, whatever path xctrace
/// was handed: this tree's release build, another worktree's. So every other
/// copy is hidden from LaunchServices while it records ([asideCopies]), the run
/// is refused unless the process it traced is [app]'s ([tracedApp]), and the
/// processes of the app it left behind (the suspended one, a copy that never
/// exits) are killed.
///
/// [meter] stops when the recording does, before the trace is read back: the
/// export is the script's work, not the run's.
Future<(String, Map<String, Object>, Map<String, Object?>)> runTraced(String app, List<String> flags, double seconds, LoadMeter meter) async {
  // The trace names the app by the path it was handed: an absolute, resolved one compares.
  final executable = File(app).resolveSymbolicLinksSync();
  final bundle = File(executable).parent.parent.parent.path;
  final dir = Directory.systemTemp.createTempSync('run_benchmark_');
  Set<String> recordings() => {
        for (final f in Directory.systemTemp.listSync())
          if (f.uri.pathSegments.last.startsWith('instruments') && f.path.endsWith('.ktrace')) f.path,
      };
  final before = recordings();
  final running = await appProcesses(app);
  final aside = await asideCopies(bundle);
  try {
    final trace = '${dir.path}/run.trace', out = '${dir.path}/run.out';
    final (r, load) = await timed('xcrun', [
      'xctrace', 'record', '--template', 'Metal System Trace', '--time-limit', '${(seconds + 60).round()}s',
      '--output', trace, '--target-stdout', out, '--launch', '--', executable, ...flags,
    ], meter, Duration(seconds: (seconds + 120).round()));
    if (r.exitCode != 0) throw StateError('xctrace record failed: ${r.stdout}${r.stderr}');
    final toc = await Process.run('xcrun', ['xctrace', 'export', '--input', trace, '--toc']);
    if (toc.exitCode != 0) throw StateError('xctrace export --toc failed: ${toc.stderr}');
    final traced = Directory(tracedApp('${toc.stdout}')).resolveSymbolicLinksSync();
    if (traced != bundle) throw StateError('xctrace traced $traced, not $bundle');
    final table = await Process.run('xcrun', [
      'xctrace', 'export', '--input', trace,
      '--xpath', '/trace-toc/run[@number="1"]/data/table[@schema="metal-gpu-intervals"]',
    ]);
    if (table.exitCode != 0) throw StateError('xctrace export failed: ${table.stderr}');
    return (File(out).readAsStringSync(), gpuFromTrace('${table.stdout}', seconds), load);
  } finally {
    final left = (await appProcesses(app)).difference(running);
    if (left.isNotEmpty) await Process.run('kill', ['-9', ...left]);
    for (final (from, to) in aside) {
      Directory(to).renameSync(from);
    }
    dir.deleteSync(recursive: true);
    for (final f in recordings().difference(before)) {
      File(f).deleteSync();
    }
  }
}

/// The pids of the processes running an executable named as [app]'s, whichever
/// copy of it they run.
Future<Set<String>> appProcesses(String app) async {
  final r = await Process.run('pgrep', ['-x', app.split('/').last]);
  return const LineSplitter().convert('${r.stdout}').toSet();
}

const lsregister = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister';

/// Hides from LaunchServices every copy of [bundle]'s app but [bundle] itself,
/// and returns each move (from, to) for the caller to undo. LaunchServices
/// finds a copy by its bundle id among the ones it registered and the ones
/// Spotlight indexed, and follows a registered one through a rename: so each
/// copy is unregistered, then renamed out of its `.app` extension, which makes
/// it no bundle at all; [bundle] is registered. A copy found already aside is a
/// traced run that never undid its moves: the script stops and names it.
Future<List<(String, String)>> asideCopies(String bundle) async {
  final id = await Process.run('plutil', ['-extract', 'CFBundleIdentifier', 'raw', '$bundle/Contents/Info.plist']);
  if (id.exitCode != 0) throw StateError('no bundle id in $bundle: ${id.stderr}');
  final bundleId = '${id.stdout}'.trim();
  final dump = await Process.run(lsregister, ['-dump']);
  if (dump.exitCode != 0) throw StateError('lsregister -dump failed: ${dump.stderr}');
  final indexed = await Process.run('mdfind', ["kMDItemCFBundleIdentifier == '$bundleId'"]);
  if (indexed.exitCode != 0) throw StateError('mdfind failed: ${indexed.stderr}');
  // Each record of the dump lists its `path:` before its `identifier:`.
  final copies = <String>{...const LineSplitter().convert('${indexed.stdout}')};
  String? path;
  for (final l in const LineSplitter().convert('${dump.stdout}')) {
    final p = RegExp(r'^path:\s+(.*?)(?: \(0x[0-9a-f]+\))?$').firstMatch(l);
    if (p != null) path = p[1];
    if (path != null && RegExp('^identifier:\\s+${RegExp.escape(bundleId)}\$').hasMatch(l)) copies.add(path);
  }
  const suffix = '.run_benchmark_aside';
  for (final copy in copies) {
    final aside = copy.endsWith(suffix) ? copy : '$copy$suffix';
    if (Directory(aside).existsSync()) throw StateError('$aside is left from a traced run that did not finish: move it back');
  }
  final moves = [
    for (final copy in copies)
      if (Directory(copy).existsSync() && Directory(copy).resolveSymbolicLinksSync() != bundle) (copy, '$copy$suffix'),
  ];
  // A copy that LaunchServices does not hold (one Spotlight found) answers
  // `-u` with -10814: not registered, which is what `-u` is for.
  for (final (from, _) in moves) {
    await Process.run(lsregister, ['-u', from]);
  }
  final f = await Process.run(lsregister, ['-f', bundle]);
  if (f.exitCode != 0) throw StateError('lsregister -f $bundle failed: ${f.stderr}');
  for (final (from, to) in moves) {
    Directory(from).renameSync(to);
  }
  return moves;
}

/// The app bundle of the process a trace launched, from its table of contents.
String tracedApp(String toc) {
  final pid = RegExp(r'<process [^>]*type="launched"[^>]*pid="(\d+)"').firstMatch(toc);
  if (pid == null) throw StateError('the trace launched no process');
  final path = RegExp('<process name="[^"]*" pid="${pid[1]}" path="([^"]*)"').firstMatch(toc);
  if (path == null) throw StateError('the trace lists no path for pid ${pid[1]}');
  return path[1]!;
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

/// Waits until the battery is under [maxC] and returns its temperature then: a
/// run taken hotter reads a throttled phone.
Future<double> coolDown(String serial, double maxC) async {
  while (true) {
    final t = await deviceTempC(serial);
    if (t < maxC) return t;
    stderr.writeln('  the battery is at $t °C: waiting for it to be under $maxC');
    await Future<void>.delayed(const Duration(seconds: 30));
  }
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
/// step ones, missing from runs recorded before PF6; the view ones, before PF3).
final columns = <(String, num? Function(Map<String, Object?>))>[
  ('fps', (l) => l['fps'] as num),
  ('hitches', (l) => l['hitches'] as num),
  ('frame p99 ms', (l) => (l['intervalMs'] as Map)['p99'] as num),
  ('view judder', (l) => (l['view'] as Map?)?['judder'] as num?),
  ('still frames', (l) => (l['view'] as Map?)?['stillFrames'] as num?),
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
  if (lines.isNotEmpty) b.write('\n${isolationReport(lines, '**Machine load**')}');
  final first = lines.isEmpty ? null : lines.first;
  if (first != null) {
    b.writeln('\n${first['machine']} · ${first['platform']} · ${first['window']} @${first['dpr']}x · '
        '${first['refreshHz']} Hz · commit ${first['commit']}');
  }
  return b.toString();
}

/// A warning when the sides' lines hold different values of [field] (each side's
/// set of them, as [show] writes one): a run at another pixel ratio draws a
/// different number of pixels, one at another refresh rate has another budget
/// a frame, so neither compares.
String differs(String what, String field, List<Map<String, Object?>> before, List<Map<String, Object?>> after, String Function(Object? v) show) {
  String side(List<Map<String, Object?>> lines) => {for (final l in lines) show(l[field])}.join(', ');
  final x = side(before), y = side(after);
  return x == y ? '' : '**The sides ran at different ${what}s** (before $x, after $y): the fps, GPU and raster rows are not comparable.\n\n';
}

/// Before and after, median against median, with the change in percent.
String comparison(List<Map<String, Object?>> before, List<Map<String, Object?>> after) {
  final lockedBefore = before.any((l) => l['screenLocked'] == true), lockedAfter = after.any((l) => l['screenLocked'] == true);
  final warning = lockedBefore == lockedAfter
      ? (lockedBefore ? '**Both sides ran with the screen locked**: compare CPU columns only.\n\n' : '')
      : '**One side ran with the screen locked and the other did not**: the GPU and fps rows are not comparable.\n\n';
  final a = byKey(before), z = byKey(after);
  final b = StringBuffer(warning)
    ..write(differs('pixel ratio', 'dpr', before, after, (v) => '${v}x'))
    ..write(differs('refresh rate', 'refreshHz', before, after, (v) => '${(v as num).round()} Hz'))
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
  b
    ..write('\n${isolationReport(before, '**Machine load, before**')}')
    ..write('\n${isolationReport(after, '**Machine load, after**')}');
  return b.toString();
}
