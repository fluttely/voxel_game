// What else the machine ran while a benchmark run ran, and the state of its
// CPU, GPU and memory (PFD1, docs/VOXEL_PERF_PLAN_2026-09-25.md §Machine
// load): every line says whether it was measured alone and, when it was not,
// what ran beside it. Nothing here refuses a busy machine: the meter records,
// and the summary says which runs ran alone.
//
// A meter samples every [pollInterval], from just before the launch until the
// run ends:
//   - the process table (`ps`): each process's CPU time and resident memory;
//   - each process's GPU time (`ioreg`, the GPU's user clients' `AppUsage`
//     `accumulatedGPUTime`);
//   - the GPU's device utilization (`ioreg`, the accelerator's
//     `PerformanceStatistics`);
// and at both ends the machine's CPU ticks (`host_statistics`), memory
// (`vm_stat`, swap, the kernel's free-memory level), the GPU's memory in use,
// thermal notes, the power source and low-power mode. A process's CPU or GPU
// time grown over the run, divided by the run's wall time, is its share of one
// core or of the GPU. The runner's own tree (itself, the app it launched,
// xctrace) is the run; everything else is beside it:
//   - a process at or above [countedCpu] of a core, or [countedGpu] of the
//     GPU, counts as parallel work;
//   - the system's servers that work for whoever draws or plays sound
//     ([onBehalf]), the run included, are listed but never counted;
//   - CPU the process table cannot name (processes born and gone between two
//     samples, such as a build's compilers, and the meter's own `ps` and
//     `ioreg`) is the machine's busy cores minus every named process's, and
//     counts at or above [unnamedMax] of a core.
// A run is isolated when nothing counts and the machine swapped nothing during
// it. A process gone between two samples keeps its last reading, so the run's
// GPU share misses up to [pollInterval] of its end. macOS only; every failure
// is fatal.
//
// On a phone (`--android`) this meter reads the Mac that drives adb, and
// [DeviceMeter] the phone's own load (`deviceLoad`), from two reads over adb.
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

const pollInterval = Duration(seconds: 2);
const countedCpu = 0.10;
const countedGpu = 0.01;
// A process under the counted shares is still listed from these up, to read the noise floor by.
const listedCpu = 0.01;
const listedGpu = 0.001;
const unnamedMax = 0.25;
const commandChars = 300;
const onBehalf = {'WindowServer', 'kernel_task', 'coreaudiod'};
const decision = 'PFD1';
const notRecorded = 'not recorded (before $decision)';
const _mb = 1024.0 * 1024.0;

/// One process at one sample.
class ProcessSample {
  const ProcessSample(this.pid, this.ppid, this.cpuS, this.gpuS, this.rssMb, this.executable, this.command);
  final int pid, ppid;
  final double cpuS, gpuS, rssMb;
  final String executable, command;
}

/// What the meter reads from the machine: [MacProbe] on this Mac, a fake in
/// the tests.
abstract interface class MachineProbe {
  /// A monotonic clock.
  Duration now();

  /// The machine's (busy, total) CPU ticks since boot, summed over its cores.
  (int, int) cpuTicks();

  /// The logical cores the ticks are summed over.
  int get processors;

  Future<Map<int, ProcessSample>> processes();

  /// The GPU's device utilization, in percent.
  Future<int> gpuUtilization();

  /// Memory, the GPU's memory, thermal notes and power, at one moment.
  Future<Map<String, Object?>> state();

  /// The machine's name and its performance and efficiency cores.
  Future<Map<String, Object?>> facts();
}

/// Samples the machine from [start] until [stop].
class LoadMeter {
  LoadMeter._(this._probe, this._root, this._runExecutable, this._interval, this._start, this._ticks, this._began);

  /// Reads the machine's state and first sample, then samples every
  /// [interval]. [root] is the run's process (this script by default); a
  /// process running [runExecutable] that started during the run is the run's
  /// too, wherever it hangs: xctrace has LaunchServices start the app, which
  /// makes it launchd's child.
  static Future<LoadMeter> start(
    MachineProbe probe, {
    int? root,
    String? runExecutable,
    Duration interval = pollInterval,
  }) async {
    final start = await probe.state();
    final meter = LoadMeter._(probe, root ?? pid, runExecutable, interval, start, probe.cpuTicks(), probe.now());
    await meter._sample();
    meter._polling = meter._poll();
    return meter;
  }

  final MachineProbe _probe;
  final int _root;
  final String? _runExecutable;
  final Duration _interval;
  final Map<String, Object?> _start;
  final (int, int) _ticks;
  final Duration _began;
  // Keyed by pid and command, so a pid reused mid-run is another process.
  final _first = <(int, String), (int, ProcessSample)>{};
  final _last = <(int, String), ProcessSample>{};
  final _own = <(int, String)>{};
  final _utilization = <int>[];
  var _samples = 0;
  final _stopped = Completer<void>();
  late final Future<void> _polling;

  Future<void> _sample() async {
    final table = await _probe.processes();
    _utilization.add(await _probe.gpuUtilization());
    final tree = descendants(_root, table);
    for (final process in table.values) {
      final key = (process.pid, _truncate(process.command));
      final (since, _) = _first.putIfAbsent(key, () => (_samples, process));
      _last[key] = process;
      if (tree.contains(process.pid) || process.executable == _runExecutable && since > 0) _own.add(key);
    }
    _samples++;
  }

  Future<void> _poll() async {
    while (true) {
      final tick = Completer<void>();
      final timer = Timer(_interval, tick.complete);
      await Future.any([tick.future, _stopped.future]);
      timer.cancel();
      if (_stopped.isCompleted) return;
      await _sample();
    }
  }

  /// Takes the last sample and returns what ran beside the run and the
  /// machine's state, as its line records them. [exited]: the CPU time the
  /// children of one of the run's processes spent to their exit, as that
  /// parent read it (`/usr/bin/time`); it stands for their samples, which miss
  /// up to [pollInterval] of their end.
  Future<Map<String, Object?>> stop({({int parent, double cpuS})? exited}) async {
    _stopped.complete();
    await _polling;
    await _sample();
    final wallS = (_probe.now() - _began).inMicroseconds / 1e6;
    final (busy, total) = _probe.cpuTicks();
    // The counters are 32-bit and wrap; their difference modulo 2^32 does not.
    const wrap = 1 << 32;
    final ticks = (total - _ticks.$2) % wrap;
    if (ticks == 0) throw StateError('machine_load: no CPU ticks passed during the run');
    final busyCores = (busy - _ticks.$1) % wrap / ticks * _probe.processors;

    var runCpu = exited == null ? 0.0 : exited.cpuS / wallS, runGpu = 0.0, named = 0.0;
    final beside = <Map<String, Object?>>[];
    for (final MapEntry(:key, value: process) in _last.entries) {
      final (since, first) = _first[key]!;
      // A process first seen after the first sample started during the run: all its time counts.
      final cpuShare = (process.cpuS - (since == 0 ? first.cpuS : 0.0)) / wallS;
      final gpuShare = (process.gpuS - (since == 0 ? first.gpuS : 0.0)) / wallS;
      if (_own.contains(key)) {
        if (exited != null && process.ppid == exited.parent) {
          if (since == 0) throw StateError('machine_load: ${process.command} ran before the run it is read for');
        } else {
          runCpu += cpuShare;
        }
        runGpu += gpuShare;
        continue;
      }
      named += cpuShare;
      if (cpuShare >= listedCpu || gpuShare >= listedGpu) {
        beside.add({
          'pid': process.pid,
          'command': _truncate(process.command),
          'coreShare': _round(cpuShare, 3),
          'gpuShare': _round(gpuShare, 4),
          'rssMb': _round(process.rssMb, 1),
          'counted':
              !onBehalf.contains(process.executable.split('/').last) &&
              (cpuShare >= countedCpu || gpuShare >= countedGpu),
        });
      }
    }
    int rank(Map<String, Object?> row) => row['counted'] == true ? 1 : 0;
    beside.sort(
      (a, b) => [
        rank(b).compareTo(rank(a)),
        (b['gpuShare'] as double).compareTo(a['gpuShare'] as double),
        (b['coreShare'] as double).compareTo(a['coreShare'] as double),
      ].firstWhere((c) => c != 0, orElse: () => 0),
    );
    final unnamed = math.max(0.0, busyCores - runCpu - named);
    final end = await _probe.state();
    final swapped =
        (end['swapins'] as int) - (_start['swapins'] as int) + (end['swapouts'] as int) - (_start['swapouts'] as int);
    final sorted = List.of(_utilization)..sort();
    return {
      ...await _probe.facts(),
      'isolated': !beside.any((row) => row['counted'] == true) && unnamed < unnamedMax && swapped == 0,
      'wallS': _round(wallS, 1),
      'samples': _samples,
      'busyCores': _round(busyCores, 2),
      'runCores': _round(runCpu, 2),
      'unnamedCores': _round(unnamed, 2),
      'runGpuShare': _round(runGpu, 3),
      'gpuUtilizationPercent': {'before': _utilization.first, 'median': _median(sorted), 'max': sorted.last},
      'swappedPages': swapped,
      'beside': beside,
      'start': _start,
      'end': end,
    };
  }
}

/// [root] and every process under it in [table].
Set<int> descendants(int root, Map<int, ProcessSample> table) {
  final tree = {root}, frontier = [root];
  while (frontier.isNotEmpty) {
    final parent = frontier.removeLast();
    for (final process in table.values) {
      if (process.ppid == parent && tree.add(process.pid)) frontier.add(process.pid);
    }
  }
  return tree;
}

String _truncate(String command) => command.length <= commandChars ? command : command.substring(0, commandChars);

double _round(double value, int digits) {
  final scale = math.pow(10, digits);
  return (value * scale).round() / scale;
}

num _median(List<int> sorted) {
  final n = sorted.length;
  return n.isOdd ? sorted[n ~/ 2] : (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
}

/// One line: isolated, or what counted beside the run.
String describeLoad(Map<String, Object?>? load) {
  if (load == null) return notRecorded;
  if (load['isolated'] == true) return 'isolated';
  // A device's rows hold a process's CPU or a uid's GPU, never both, and its
  // unnamed CPU and swapping are not counted (DeviceMeter): it has neither key.
  final parts = [
    for (final row in (load['beside'] as List).cast<Map<String, Object?>>())
      if (row['counted'] == true)
        [
          if (row['coreShare'] case final num core) '${core.toStringAsFixed(2)} core',
          if (row['gpuShare'] case final num gpu) '${(gpu * 100).toStringAsFixed(1)}% gpu',
          _shorten(row['command'] as String, 100),
        ].join(' '),
    if (load['unnamedCores'] case final num unnamed when unnamed >= unnamedMax)
      '${unnamed.toStringAsFixed(2)} core unnamed (short-lived processes)',
    if (load['swappedPages'] case final int swapped when swapped != 0) '$swapped pages swapped',
  ];
  return 'beside: ${parts.join('; ')}';
}

String _shorten(String text, int chars) => text.length <= chars ? text : '${text.substring(0, chars)}…';

/// How many of [lines] ran alone, and each other run with the work beside it:
/// the line a report quotes. [name] says whose lines they are, [key] which
/// load: the machine's that ran the benchmark, or a phone's (`deviceLoad`).
String isolationReport(List<Map<String, Object?>> lines, String name, {String key = 'machineLoad'}) {
  final loads = [for (final l in lines) l[key] as Map<String, Object?>?];
  final recorded = loads.whereType<Map<String, Object?>>().length;
  final isolated = loads.where((l) => l != null && l['isolated'] == true).length;
  final b = StringBuffer(
    '$name: isolated in $isolated of ${lines.length} runs'
    '${recorded < lines.length ? ' (${lines.length - recorded} not recorded, before $decision)' : ''}\n',
  );
  for (final (i, l) in lines.indexed) {
    final load = loads[i];
    if (load != null && load['isolated'] != true) {
      b.writeln('- run ${i + 1} (${l['scenario']}:${l['radius']}, round ${l['round']}): ${describeLoad(load)}');
    }
  }
  return b.toString();
}

// ---------------------------------------------------------------- macOS

/// [MachineProbe] on this Mac, with no root: `ps`, `ioreg`, `vm_stat`,
/// `sysctl`, `pmset`, and `host_statistics` through FFI.
final class MacProbe implements MachineProbe {
  final _clock = Stopwatch()..start();

  @override
  Duration now() => _clock.elapsed;

  @override
  int get processors => Platform.numberOfProcessors;

  @override
  (int, int) cpuTicks() => _HostStatistics.instance.cpuTicks();

  @override
  Future<Map<int, ProcessSample>> processes() async {
    // A process born or gone between the listings is in some only, and is read next sample.
    final [usage, commands, gpu] = await Future.wait([
      _shell('ps', ['-Ao', 'pid=,ppid=,time=,rss=,comm=']),
      _shell('ps', ['-Ao', 'pid=,args=']),
      _shell('ioreg', ['-r', '-c', 'AGXDeviceUserClient', '-l']),
    ]);
    return parseProcesses(usage, commands, parseGpuSeconds(gpu));
  }

  @override
  Future<int> gpuUtilization() async => parseGpuStatistics(await _accelerator()).utilization;

  Future<String> _accelerator() => _shell('ioreg', ['-r', '-d', '1', '-c', 'IOAccelerator']);

  @override
  Future<Map<String, Object?>> state() async {
    final [vm, load, swap, level, memsize, thermal, battery, power, accelerator] = await Future.wait([
      _shell('vm_stat', []),
      _sysctl('vm.loadavg'),
      _sysctl('vm.swapusage'),
      _sysctl('kern.memorystatus_level'),
      _sysctl('hw.memsize'),
      _shell('pmset', ['-g', 'therm']),
      _shell('pmset', ['-g', 'batt']),
      _shell('pmset', ['-g']),
      _accelerator(),
    ]);
    final (page, pages) = parseVmStat(vm);
    int mb(String name) => (pages[name]! * page / _mb).round();
    return {
      'loadAvg1m': double.parse(load.replaceAll(RegExp(r'[{}]'), '').trim().split(RegExp(r'\s+')).first),
      'memoryTotalMb': (int.parse(memsize) / _mb).round(),
      'memoryFreeMb': ((pages['Pages free']! + pages['Pages speculative']!) * page / _mb).round(),
      'memoryInactiveMb': mb('Pages inactive'),
      'memoryWiredMb': mb('Pages wired down'),
      'memoryCompressedMb': mb('Pages occupied by compressor'),
      // The kernel's own reading of memory pressure: the share of memory it counts as free.
      'memoryFreePercent': int.parse(level),
      'swapUsedMb': parseSwapUsedMb(swap),
      'swapins': pages['Swapins']!,
      'swapouts': pages['Swapouts']!,
      'gpuMemoryInUseMb': parseGpuStatistics(accelerator).memoryMb.round(),
      'thermal': parseThermal(thermal),
      'power': parsePowerSource(battery),
      'lowPowerMode': parseLowPowerMode(power),
    };
  }

  @override
  Future<Map<String, Object?>> facts() async => {
    'machine': await _sysctl('machdep.cpu.brand_string'),
    'cores': {
      'performance': int.parse(await _sysctl('hw.perflevel0.logicalcpu')),
      'efficiency': int.parse(await _sysctl('hw.perflevel1.logicalcpu')),
    },
  };
}

Future<String> _shell(String command, List<String> args) async {
  final r = await Process.run(command, args);
  if (r.exitCode != 0) throw StateError('machine_load: $command ${args.join(' ')} failed (${r.exitCode}): ${r.stderr}');
  return '${r.stdout}';
}

Future<String> _sysctl(String name) async => (await _shell('sysctl', ['-n', name])).trim();

/// `ps`'s cumulative CPU time, `[[dd-]hh:]mm:ss.cc`, in seconds.
double cpuSeconds(String text) {
  final dash = text.indexOf('-');
  final days = dash < 0 ? 0 : int.parse(text.substring(0, dash));
  var seconds = 0.0;
  for (final part in text.substring(dash + 1).split(':')) {
    seconds = seconds * 60 + double.parse(part);
  }
  return seconds + days * 86400;
}

/// A `ps` row's [count] columns, the last one whole (it may hold spaces).
List<String> _columns(String row, int count) {
  final columns = <String>[];
  var rest = row.trimLeft();
  while (columns.length < count - 1 && rest.isNotEmpty) {
    final space = rest.indexOf(RegExp(r'\s'));
    columns.add(space < 0 ? rest : rest.substring(0, space));
    rest = space < 0 ? '' : rest.substring(space).trimLeft();
  }
  return columns..add(rest);
}

/// The process table from `ps -Ao pid=,ppid=,time=,rss=,comm=` ([usage]),
/// `ps -Ao pid=,args=` ([commands]) and each pid's GPU seconds.
Map<int, ProcessSample> parseProcesses(String usage, String commands, Map<int, double> gpuS) {
  final args = <int, String>{
    for (final row in const LineSplitter().convert(commands))
      if (row.trim().isNotEmpty) int.parse(_columns(row, 2)[0]): _columns(row, 2)[1],
  };
  final table = <int, ProcessSample>{};
  for (final row in const LineSplitter().convert(usage)) {
    if (row.trim().isEmpty) continue;
    final [pid, ppid, time, rss, executable] = _columns(row, 5);
    final id = int.parse(pid);
    final command = args[id];
    if (command == null) continue;
    table[id] = ProcessSample(
      id,
      int.parse(ppid),
      cpuSeconds(time),
      gpuS[id] ?? 0.0,
      int.parse(rss) / 1024.0,
      executable,
      command,
    );
  }
  return table;
}

final _clientCreator = RegExp(r'"IOUserClientCreator" = "pid (\d+),');
final _gpuTime = RegExp(r'"accumulatedGPUTime"=(\d+)');

/// Each process's GPU time since it opened the GPU, summed over its user
/// clients, from `ioreg -r -c AGXDeviceUserClient -l`. Each client is a
/// record of its own (`+-o AGXDeviceUserClient`) whose keys come sorted, so
/// its `AppUsage` precedes its `IOUserClientCreator`: a usage is its record's
/// creator's, never the one printed above it.
Map<int, double> parseGpuSeconds(String ioreg) {
  final seconds = <int, double>{};
  for (final record in ioreg.split(RegExp(r'^\+-o ', multiLine: true)).skip(1)) {
    final creator = _clientCreator.firstMatch(record);
    if (creator == null) throw StateError('machine_load: a GPU client with no creator: $record');
    final owner = int.parse(creator[1]!);
    final ns = _gpuTime.allMatches(record).fold(0, (sum, m) => sum + int.parse(m[1]!));
    seconds[owner] = (seconds[owner] ?? 0.0) + ns / 1e9;
  }
  return seconds;
}

/// The GPU's device utilization (%) and the system memory it holds in use
/// (MB), from `ioreg -r -d 1 -c IOAccelerator`.
({int utilization, double memoryMb}) parseGpuStatistics(String ioreg) {
  final utilization = RegExp(r'"Device Utilization %"=(\d+)').firstMatch(ioreg);
  final memory = RegExp(r'"In use system memory"=(\d+)').firstMatch(ioreg);
  if (utilization == null || memory == null)
    throw StateError('machine_load: the accelerator reports no PerformanceStatistics');
  return (utilization: int.parse(utilization[1]!), memoryMb: int.parse(memory[1]!) / _mb);
}

/// `vm_stat`'s page size and its counters by name.
(int, Map<String, int>) parseVmStat(String text) {
  final page = RegExp(r'page size of (\d+) bytes').firstMatch(text);
  if (page == null) throw StateError('machine_load: vm_stat gave no page size');
  return (
    int.parse(page[1]!),
    {
      for (final line in const LineSplitter().convert(text).skip(1))
        if (line.contains(':'))
          line.substring(0, line.indexOf(':')).trim().replaceAll('"', ''): int.parse(
            line.substring(line.indexOf(':') + 1).trim().replaceAll('.', ''),
          ),
    },
  );
}

/// The swap in use, in MB, from `sysctl vm.swapusage`.
double parseSwapUsedMb(String text) {
  final used = RegExp(r'used = ([\d.]+)M').firstMatch(text);
  if (used == null) throw StateError('machine_load: vm.swapusage gave no "used": $text');
  return double.parse(used[1]!);
}

/// `pmset -g therm`'s lines, its "No ... has been recorded" notes left out.
List<String> parseThermal(String text) => [
  for (final line in const LineSplitter().convert(text))
    if (line.trim().isNotEmpty && !line.contains('has been recorded')) line.trim(),
];

/// The power source `pmset -g batt` names on its first line.
String parsePowerSource(String text) {
  final source = RegExp(r"Now drawing from '([^']+)'").firstMatch(text);
  if (source == null) throw StateError('machine_load: pmset -g batt named no power source: $text');
  return source[1]!;
}

/// Whether `pmset -g` has low-power mode on.
bool parseLowPowerMode(String text) {
  final mode = RegExp(r'^\s*lowpowermode\s+(\d)', multiLine: true).firstMatch(text);
  if (mode == null) throw StateError('machine_load: pmset -g has no lowpowermode');
  return mode[1] == '1';
}

typedef _HostSelf = Uint32 Function();
typedef _HostStatisticsC = Int32 Function(Uint32 host, Int32 flavor, Pointer<Uint32> info, Pointer<Uint32> count);
typedef _HostStatisticsDart = int Function(int host, int flavor, Pointer<Uint32> info, Pointer<Uint32> count);

/// `host_statistics(HOST_CPU_LOAD_INFO)`: the machine's CPU ticks since boot.
/// No command prints them (`top` and `iostat` print rates over their own
/// interval), and two readings of the counters average exactly over the run,
/// however long it is; libSystem's `malloc`, so no `package:ffi`.
final class _HostStatistics {
  _HostStatistics._(DynamicLibrary lib)
    : _hostSelf = lib.lookupFunction<_HostSelf, int Function()>('mach_host_self'),
      _statistics = lib.lookupFunction<_HostStatisticsC, _HostStatisticsDart>('host_statistics'),
      _deallocate = lib.lookupFunction<Int32 Function(Uint32, Uint32), int Function(int, int)>('mach_port_deallocate'),
      _task = lib.lookup<Uint32>('mach_task_self_').value,
      _malloc = lib.lookupFunction<Pointer<Uint32> Function(IntPtr), Pointer<Uint32> Function(int)>('malloc'),
      _free = lib.lookupFunction<Void Function(Pointer<Uint32>), void Function(Pointer<Uint32>)>('free');

  static final instance = _HostStatistics._(DynamicLibrary.open('/usr/lib/libSystem.dylib'));

  static const _cpuLoadInfo = 3; // HOST_CPU_LOAD_INFO
  static const _states = 4; // CPU_STATE_MAX: user, system, idle, nice
  static const _idle = 2;

  final int Function() _hostSelf;
  final _HostStatisticsDart _statistics;
  final int Function(int, int) _deallocate;
  final int _task;
  final Pointer<Uint32> Function(int) _malloc;
  final void Function(Pointer<Uint32>) _free;

  (int, int) cpuTicks() {
    // The four counters, then the count host_statistics reads and writes.
    final buffer = _malloc((_states + 1) * sizeOf<Uint32>());
    final host = _hostSelf();
    try {
      buffer[_states] = _states;
      final code = _statistics(host, _cpuLoadInfo, buffer, buffer + _states);
      if (code != 0) throw StateError('machine_load: host_statistics failed with $code');
      var total = 0;
      for (var i = 0; i < _states; i++) {
        total += buffer[i];
      }
      return (total - buffer[_idle], total);
    } finally {
      _deallocate(_task, host);
      _free(buffer);
    }
  }
}

// ---------------------------------------------------------------- Android

/// The servers that work for whoever draws, plays sound or answers adb on an
/// Android device, the run included (the S24's names): listed, never counted.
/// So are the kernel's threads (`kthreadd` and its children), and `gpuservice`,
/// which answers the meter's own `dumpsys gpu`.
const deviceOnBehalf = {
  'surfaceflinger',
  'system_server',
  'vendor.qti.hardware.display.composer-service',
  'audioserver',
  'android.hardware.audio.service_64',
  'gpuservice',
  'adbd',
  'logd',
};

/// The uid whose GPU time is the compositor's: surfaceflinger and the composer
/// run as `system`, and so do system_server and the Settings app.
const systemUid = 1000;

/// `/proc/stat`'s and `ps`'s clock: Android's ABI fixes USER_HZ at 100.
const ticksPerSecond = 100;

/// What [DeviceMeter] reads from a device: [AdbProbe] over adb, fixed text in
/// the tests. Each read is one `adb shell` whose sections [parseSections]
/// splits.
abstract interface class DeviceProbe {
  /// The cumulative counters: uptime, `/proc/stat`, the GPU's busy time per
  /// clock level, pressure stall, swap, and each uid's GPU time.
  Future<String> counters();

  /// The process table and the device's state at one moment.
  Future<String> state();

  /// The packages each uid holds, `cmd package list packages -U`.
  Future<String> packages();
}

/// One reading's cumulative counters.
class DeviceCounters {
  const DeviceCounters(
    this.uptimeS,
    this.busyTicks,
    this.processors,
    this.gpuBusyUs,
    this.gpuLevelsHz,
    this.pressureUs,
    this.swapPages,
    this.gpuActiveNs,
  );

  final double uptimeS;
  final int busyTicks, processors;

  /// The GPU's busy time at each clock level, [gpuLevelsHz]'s order.
  final List<int> gpuBusyUs, gpuLevelsHz;

  /// `/proc/pressure`'s totals: `cpuSome`, `memorySome`, `memoryFull`.
  final Map<String, int> pressureUs;

  /// `pswpin` and `pswpout`.
  final (int, int) swapPages;

  /// Each uid's GPU time since boot, `dumpsys gpu --gpuwork`.
  final Map<int, int> gpuActiveNs;
}

/// What an Android device ran beside a run, read before the launch and after
/// the app exits (`deviceLoad`). Two reads, never a poll: a poll is an `adb
/// shell` on the phone every interval, itself load. So the app is gone by the
/// second read, and its CPU time with it: the device's busy cores minus every
/// named process's is the app's and the short-lived processes' together
/// (`appAndUnnamedCores`, the meter's own `adb shell`s included), never
/// counted. The app's uid keeps its GPU time after it exits: the run's GPU
/// share is its uid's.
class DeviceMeter {
  DeviceMeter._(this._probe, this._runUid, this._table, this._uids, this._counters, this._state);

  /// Reads the process table and state first and the counters last, so the
  /// reading's own cost falls before the run's window.
  static Future<DeviceMeter> start(DeviceProbe probe, {required int runUid}) async {
    final state = parseSections(await probe.state());
    final (table, uids) = parseDeviceProcesses(state['ps']!);
    final counters = parseCounters(parseSections(await probe.counters()));
    return DeviceMeter._(probe, runUid, table, uids, counters, deviceState(state));
  }

  final DeviceProbe _probe;
  final int _runUid;
  final Map<DeviceProcess, ProcessSample> _table;
  final Map<DeviceProcess, int> _uids;
  final DeviceCounters _counters;
  final Map<String, Object?> _state;

  /// Reads the counters first, then the process table and state, and returns
  /// what ran beside the run and the device's state, as its line records them.
  Future<Map<String, Object?>> stop() async {
    final counters = parseCounters(parseSections(await _probe.counters()));
    final state = parseSections(await _probe.state());
    final (table, uids) = parseDeviceProcesses(state['ps']!);
    final gpuNames = <int, String>{};
    final unnamedUids = {
      for (final uid in counters.gpuActiveNs.keys)
        if (!uids.values.contains(uid) && !_uids.values.contains(uid)) uid,
    };
    if (unnamedUids.isNotEmpty) gpuNames.addAll(parsePackageUids(await _probe.packages()));
    return deviceLoad(
      (_table, _uids, _counters, _state),
      (table, uids, counters, deviceState(state)),
      runUid: _runUid,
      packages: gpuNames,
    );
  }
}

typedef DeviceReading = (
  Map<DeviceProcess, ProcessSample> table,
  Map<DeviceProcess, int> uids,
  DeviceCounters counters,
  Map<String, Object?> state,
);

/// What ran beside a run between two readings of a device ([DeviceMeter]).
/// [packages] names the uids no process in either table runs as.
Map<String, Object?> deviceLoad(
  DeviceReading start,
  DeviceReading end, {
  required int runUid,
  Map<int, String> packages = const {},
}) {
  final (startTable, startUids, before, _) = start;
  final (endTable, endUids, after, _) = end;
  final wallS = after.uptimeS - before.uptimeS;
  if (wallS <= 0) throw StateError('machine_load: the device\'s uptime did not advance');
  final busyCores = (after.busyTicks - before.busyTicks) / ticksPerSecond / wallS;

  var named = 0.0;
  final beside = <Map<String, Object?>>[];
  for (final MapEntry(:key, value: process) in endTable.entries) {
    if (endUids[key] == runUid) continue;
    // A process first seen at the end, or whose pid was reused, started during the run: all its time counts.
    final since = startTable[key]?.cpuS ?? 0.0;
    final cpuShare = (process.cpuS - (since <= process.cpuS ? since : 0.0)) / wallS;
    named += cpuShare;
    if (cpuShare >= listedCpu) {
      beside.add({
        'pid': process.pid,
        'command': _truncate(process.command),
        'coreShare': _round(cpuShare, 3),
        'rssMb': _round(process.rssMb, 1),
        'counted': !_deviceOnBehalf(process) && cpuShare >= countedCpu,
      });
    }
  }

  String uidName(int uid) {
    final names = {
      for (final table in [(endTable, endUids), (startTable, startUids)])
        for (final MapEntry(:key, value: uidOf) in table.$2.entries)
          if (uidOf == uid) table.$1[key]!.executable,
    };
    if (names.isEmpty) return packages[uid] ?? 'uid $uid';
    // A system uid runs dozens of processes: three name it.
    final sorted = names.toList()..sort();
    return sorted.length <= 3 ? sorted.join(', ') : '${sorted.take(3).join(', ')} +${sorted.length - 3}';
  }

  var runGpu = 0.0;
  for (final MapEntry(key: uid, value: ns) in after.gpuActiveNs.entries) {
    final gpuShare = (ns - (before.gpuActiveNs[uid] ?? 0)) / 1e9 / wallS;
    if (uid == runUid) {
      runGpu = gpuShare;
    } else if (gpuShare >= listedGpu) {
      beside.add({
        'uid': uid,
        'command': _truncate(uidName(uid)),
        'gpuShare': _round(gpuShare, 4),
        'counted': uid != systemUid && gpuShare >= countedGpu,
      });
    }
  }
  int rank(Map<String, Object?> row) => row['counted'] == true ? 1 : 0;
  double share(Map<String, Object?> row, String key) => (row[key] as double?) ?? 0.0;
  beside.sort(
    (a, b) => [
      rank(b).compareTo(rank(a)),
      share(b, 'gpuShare').compareTo(share(a, 'gpuShare')),
      share(b, 'coreShare').compareTo(share(a, 'coreShare')),
    ].firstWhere((c) => c != 0, orElse: () => 0),
  );

  final gpuBusy = [for (final (i, us) in after.gpuBusyUs.indexed) us - before.gpuBusyUs[i]];
  final gpuBusyUs = gpuBusy.fold(0, (a, b) => a + b);
  double pressure(String name) => _round((after.pressureUs[name]! - before.pressureUs[name]!) / 1e6 / wallS, 4);
  return {
    'cores': after.processors,
    'isolated': !beside.any((row) => row['counted'] == true),
    'wallS': _round(wallS, 1),
    'busyCores': _round(busyCores, 2),
    'appAndUnnamedCores': _round(math.max(0.0, busyCores - named), 2),
    'runGpuShare': _round(runGpu, 3),
    'gpuBusyShare': _round(gpuBusyUs / 1e6 / wallS, 3),
    'gpuMeanBusyMhz': gpuBusyUs == 0
        ? 0
        : (gpuBusy.indexed.fold(0.0, (sum, e) => sum + e.$2 * after.gpuLevelsHz[e.$1]) / gpuBusyUs / 1e6).round(),
    'cpuPressureSomeShare': pressure('cpuSome'),
    'memoryPressureSomeShare': pressure('memorySome'),
    'memoryPressureFullShare': pressure('memoryFull'),
    'pagesSwappedIn': after.swapPages.$1 - before.swapPages.$1,
    'pagesSwappedOut': after.swapPages.$2 - before.swapPages.$2,
    'beside': beside,
    'start': start.$4,
    'end': end.$4,
  };
}

bool _deviceOnBehalf(ProcessSample process) =>
    process.pid == 2 || process.ppid == 2 || deviceOnBehalf.contains(process.executable);

/// [AdbProbe]'s output, cut at its `@@ name` lines.
Map<String, String> parseSections(String text) {
  final sections = <String, String>{};
  for (final part in text.split(RegExp(r'^@@ ', multiLine: true)).skip(1)) {
    final newline = part.indexOf('\n');
    sections[(newline < 0 ? part : part.substring(0, newline)).trim()] = newline < 0 ? '' : part.substring(newline + 1);
  }
  return sections;
}

/// A device's process, as two reads tell it from another: a kernel worker's
/// name changes with the work it takes, and `ps`'s start time (`STIME`) is
/// worked out from the clock at each read and moves by a second between two.
/// A pid reused during the run by the same parent and uid is told by its CPU
/// time going down ([deviceLoad]).
typedef DeviceProcess = ({int pid, int ppid, int uid});

/// The process table from `ps -A -o PID,PPID,UID,TIME+,RSS,NAME,ARGS`, and
/// each process's uid.
(Map<DeviceProcess, ProcessSample>, Map<DeviceProcess, int>) parseDeviceProcesses(String ps) {
  final table = <DeviceProcess, ProcessSample>{}, uids = <DeviceProcess, int>{};
  for (final row in const LineSplitter().convert(ps).skip(1)) {
    if (row.trim().isEmpty) continue;
    final [pid, ppid, uid, time, rss, name, args] = _columns(row, 7);
    final key = (pid: int.parse(pid), ppid: int.parse(ppid), uid: int.parse(uid));
    table[key] = ProcessSample(key.pid, key.ppid, cpuSeconds(time), 0.0, int.parse(rss) / 1024.0, name, args);
    uids[key] = int.parse(uid);
  }
  return (table, uids);
}

/// The counters' sections ([AdbProbe.counters]).
DeviceCounters parseCounters(Map<String, String> sections) {
  String section(String name) => sections[name] ?? (throw StateError('machine_load: the device gave no $name'));
  final stat = const LineSplitter().convert(section('stat'));
  // cpu  user nice system idle iowait irq softirq steal guest guest_nice: guest is inside user.
  final cpu = stat.first.split(RegExp(r'\s+')).skip(1).take(8).map(int.parse).toList();
  final busy = cpu.fold(0, (a, b) => a + b) - cpu[3] - cpu[4];
  int pressureTotal(String text, String kind) {
    final m = RegExp('^$kind .*total=(\\d+)', multiLine: true).firstMatch(text);
    if (m == null) throw StateError('machine_load: no "$kind" pressure in $text');
    return int.parse(m[1]!);
  }

  final vmstat = {
    for (final line in const LineSplitter().convert(section('vmstat')))
      if (line.contains(' ')) line.split(' ').first: int.parse(line.split(' ').last),
  };
  final gpuwork = const LineSplitter().convert(section('gpuwork'));
  if (!gpuwork.any((l) => l.startsWith('gpu_id uid total_active_duration_ns')))
    throw StateError('machine_load: dumpsys gpu --gpuwork has no table: ${section('gpuwork')}');
  final gpuActiveNs = <int, int>{};
  for (final line in gpuwork) {
    final m = RegExp(r'^\d+ (\d+) (\d+) \d+$').firstMatch(line.trim());
    if (m != null) gpuActiveNs[int.parse(m[1]!)] = (gpuActiveNs[int.parse(m[1]!)] ?? 0) + int.parse(m[2]!);
  }
  List<int> numbers(String text) => text.trim().split(RegExp(r'\s+')).map(int.parse).toList();
  final gpuBusyUs = numbers(section('gpuclock')), gpuLevelsHz = numbers(section('gpulevels'));
  if (gpuBusyUs.length != gpuLevelsHz.length)
    throw StateError('machine_load: the GPU\'s clock levels do not match its busy times');
  return DeviceCounters(
    double.parse(section('uptime').trim().split(' ').first),
    busy,
    stat.where((l) => RegExp(r'^cpu\d').hasMatch(l)).length,
    gpuBusyUs,
    gpuLevelsHz,
    {
      'cpuSome': pressureTotal(section('cpupressure'), 'some'),
      'memorySome': pressureTotal(section('memorypressure'), 'some'),
      'memoryFull': pressureTotal(section('memorypressure'), 'full'),
    },
    (vmstat['pswpin']!, vmstat['pswpout']!),
    gpuActiveNs,
  );
}

/// The device's memory, GPU, thermal state and power at one moment, from
/// [AdbProbe.state]'s sections.
Map<String, Object?> deviceState(Map<String, String> sections) {
  String section(String name) => sections[name] ?? (throw StateError('machine_load: the device gave no $name'));
  final meminfo = {
    for (final line in const LineSplitter().convert(section('meminfo')))
      if (line.contains(':'))
        line.substring(0, line.indexOf(':')): int.parse(line.substring(line.indexOf(':') + 1).trim().split(' ').first),
  };
  int mb(String name) => (meminfo[name]! / 1024).round();
  final gpuMemory = RegExp(r'Global total: (\d+)').firstMatch(section('gpumem'));
  if (gpuMemory == null) throw StateError('machine_load: dumpsys gpu --gpumem has no global total');
  final busy = RegExp(r'^(\d+) %').firstMatch(section('gpubusy').trim());
  if (busy == null) throw StateError('machine_load: gpu_busy_percentage reads ${section('gpubusy')}');
  final lowPower = section('lowpower').trim();
  if (lowPower != '0' && lowPower != '1') throw StateError('machine_load: settings low_power reads $lowPower');
  return {
    'memoryTotalMb': mb('MemTotal'),
    'memoryAvailableMb': mb('MemAvailable'),
    'memoryFreeMb': mb('MemFree'),
    'swapUsedMb': mb('SwapTotal') - mb('SwapFree'),
    'gpuMemoryMb': (int.parse(gpuMemory[1]!) / _mb).round(),
    // The driver's own busy percentage over its last short window: what the GPU was doing at this moment.
    'gpuBusyPercent': int.parse(busy[1]!),
    ...parseThermalService(section('thermal')),
    'battery': parseBattery(section('battery')),
    'lowPowerMode': lowPower == '1',
  };
}

/// `dumpsys thermalservice`'s status (0 none … 6 shutdown) and the HAL's
/// current temperatures by sensor.
Map<String, Object?> parseThermalService(String text) {
  final status = RegExp(r'^Thermal Status: (\d+)', multiLine: true).firstMatch(text);
  final current = text.indexOf('Current temperatures from HAL:');
  if (status == null || current < 0)
    throw StateError('machine_load: dumpsys thermalservice has no status or temperatures');
  final block = text.substring(current).split(RegExp(r'\n(?=\S)')).first;
  return {
    'thermalStatus': int.parse(status[1]!),
    'temperaturesC': {
      for (final m in RegExp(r'mValue=([\d.-]+), mType=\d+, mName=(\w+)').allMatches(block))
        if (double.parse(m[1]!) != 0.0) m[2]!: double.parse(m[1]!),
    },
  };
}

/// `dumpsys battery`'s level, power source and temperature.
Map<String, Object?> parseBattery(String text) {
  String field(String name) {
    final m = RegExp('^  $name: (.+)\$', multiLine: true).firstMatch(text);
    if (m == null) throw StateError('machine_load: dumpsys battery has no "$name"');
    return m[1]!.trim();
  }

  final sources = [
    for (final source in ['AC', 'USB', 'Wireless', 'Dock'])
      if (field('$source powered') == 'true') source,
  ];
  return {
    'levelPercent': int.parse(field('level')),
    'power': sources.isEmpty ? 'battery' : sources.join(', '),
    'temperatureC': int.parse(field('temperature')) / 10,
  };
}

/// Each uid's packages from `cmd package list packages -U`.
Map<int, String> parsePackageUids(String text) {
  final names = <int, List<String>>{};
  for (final m in RegExp(r'^package:(\S+) uid:(\d+)', multiLine: true).allMatches(text)) {
    names.putIfAbsent(int.parse(m[2]!), () => []).add(m[1]!);
  }
  return {for (final MapEntry(:key, :value) in names.entries) key: (value..sort()).join(', ')};
}

/// [DeviceProbe] over `adb -s [serial] shell`, with no root.
final class AdbProbe implements DeviceProbe {
  AdbProbe(this.serial);

  final String serial;
  static const _kgsl = '/sys/class/kgsl/kgsl-3d0';

  @override
  Future<String> counters() => _adbShell(serial, {
    '@@ uptime': 'cat /proc/uptime',
    '@@ stat': 'cat /proc/stat',
    '@@ gpuclock': 'cat $_kgsl/gpu_clock_stats',
    '@@ gpulevels': 'cat $_kgsl/gpu_available_frequencies',
    '@@ cpupressure': 'cat /proc/pressure/cpu',
    '@@ memorypressure': 'cat /proc/pressure/memory',
    '@@ vmstat': 'grep -E "^pswp(in|out) " /proc/vmstat',
    '@@ gpuwork': 'dumpsys gpu --gpuwork',
  });

  @override
  Future<String> state() => _adbShell(serial, {
    '@@ ps': 'ps -A -o PID,PPID,UID,TIME+,RSS,NAME,ARGS',
    '@@ meminfo': 'cat /proc/meminfo',
    '@@ gpumem': 'dumpsys gpu --gpumem',
    '@@ gpubusy': 'cat $_kgsl/gpu_busy_percentage',
    '@@ thermal': 'dumpsys thermalservice',
    '@@ battery': 'dumpsys battery',
    '@@ lowpower': 'settings get global low_power',
  });

  @override
  Future<String> packages() => _adbShell(serial, {'': 'cmd package list packages -U --user 0'});
}

/// One `adb shell` running each command after its marker line, failing on the
/// first that fails.
Future<String> _adbShell(String serial, Map<String, String> commands) async {
  final script = [
    for (final MapEntry(:key, :value) in commands.entries) "${key.isEmpty ? '' : "echo '$key' && "}$value",
  ].join(' && ');
  final r = await Process.run('adb', ['-s', serial, 'shell', script]);
  if (r.exitCode != 0) throw StateError('machine_load: adb shell failed (${r.exitCode}): ${r.stdout}${r.stderr}');
  return '${r.stdout}';
}
