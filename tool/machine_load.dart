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
// On a phone (`--android`) the meter reads the Mac that drives adb; the
// phone's own load is not read yet (PFD1).
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
  final parts = [
    for (final row in (load['beside'] as List).cast<Map<String, Object?>>())
      if (row['counted'] == true)
        '${(row['coreShare'] as num).toStringAsFixed(2)} core ${((row['gpuShare'] as num) * 100).toStringAsFixed(1)}% gpu '
            '${_shorten(row['command'] as String, 100)}',
    if ((load['unnamedCores'] as num) >= unnamedMax)
      '${(load['unnamedCores'] as num).toStringAsFixed(2)} core unnamed (short-lived processes)',
    if (load['swappedPages'] != 0) '${load['swappedPages']} pages swapped',
  ];
  return 'beside: ${parts.join('; ')}';
}

String _shorten(String text, int chars) => text.length <= chars ? text : '${text.substring(0, chars)}…';

/// How many of [lines] ran alone, and each other run with the work beside it:
/// the line a report quotes. [name] says whose lines they are.
String isolationReport(List<Map<String, Object?>> lines, String name) {
  final loads = [for (final l in lines) l['machineLoad'] as Map<String, Object?>?];
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
