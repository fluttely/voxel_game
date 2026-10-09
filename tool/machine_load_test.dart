// Tests for machine_load.dart (PFD1), from the repository's root:
//   dart test tool/
// The phone's tests read adb output cut from the Galaxy S24's.
// `package:test` resolves through the workspace (voxel_engine's dev dependency).
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import 'machine_load.dart';

const runner = 100;
const startState = <String, Object?>{'swapins': 10, 'swapouts': 20};

ProcessSample process(int pid, double cpuS, {double gpuS = 0.0, int ppid = 1, String executable = '/usr/bin/tool'}) =>
    ProcessSample(pid, ppid, cpuS, gpuS, 10.0, executable, '$executable --pid $pid');

/// A machine that answers from fixed tables: one table a sample, the first at
/// the start and the last at the stop, 10 s apart, on 10 cores.
final class FakeProbe implements MachineProbe {
  FakeProbe(this.tables, this.ticks, {this.endState = startState});

  final List<Map<int, ProcessSample>> tables;
  final List<(int, int)> ticks;
  final Map<String, Object?> endState;
  var _tables = 0, _ticks = 0, _states = 0, _clock = 0;

  @override
  Duration now() => const [Duration.zero, Duration(seconds: 10)][_clock++];

  @override
  (int, int) cpuTicks() => ticks[_ticks++];

  @override
  int get processors => 10;

  @override
  Future<Map<int, ProcessSample>> processes() async => tables[_tables++];

  @override
  Future<int> gpuUtilization() async => 40;

  @override
  Future<Map<String, Object?>> state() async => [startState, endState][_states++];

  @override
  Future<Map<String, Object?>> facts() async => {
    'machine': 'Apple M2 Pro',
    'cores': {'performance': 8, 'efficiency': 4},
  };
}

Future<Map<String, Object?>> read(
  List<Map<int, ProcessSample>> tables,
  List<(int, int)> ticks, {
  Map<String, Object?> endState = startState,
  String? runExecutable,
  ({int parent, double cpuS})? exited,
}) async {
  final meter = await LoadMeter.start(
    FakeProbe(tables, ticks, endState: endState),
    root: runner,
    runExecutable: runExecutable,
    interval: const Duration(hours: 1),
  );
  return meter.stop(exited: exited);
}

Map<int, Map<String, Object?>> besideByPid(Map<String, Object?> load) => {
  for (final row in (load['beside'] as List).cast<Map<String, Object?>>()) row['pid'] as int: row,
};

/// The device's cumulative counters as [AdbProbe.counters] prints them, on 2 cores and 2 GPU clock levels.
String counters({
  required double uptimeS,
  required int busyTicks,
  required List<int> gpuBusyUs,
  required Map<int, int> gpuActiveNs,
  int cpuSome = 0,
  (int, int) swapPages = (0, 0),
}) =>
    '@@ uptime\n$uptimeS 700.00\n'
    // user nice system idle iowait irq softirq steal guest guest_nice: busy is all but idle and iowait.
    '@@ stat\ncpu  ${busyTicks - 100} 50 50 9000 300 0 0 0 7 0\ncpu0 1 0 0 1 0 0 0 0 0 0\ncpu1 1 0 0 1 0 0 0 0 0 0\nintr 1 2 3\n'
    '@@ gpuclock\n${gpuBusyUs.join(' ')} \n'
    '@@ gpulevels\n1000000000 500000000 \n'
    '@@ cpupressure\nsome avg10=10.21 avg60=8.23 avg300=6.76 total=$cpuSome\nfull avg10=0.00 avg60=0.00 avg300=0.00 total=0\n'
    '@@ memorypressure\nsome avg10=0.33 avg60=0.34 avg300=0.19 total=0\nfull avg10=0.18 avg60=0.15 avg300=0.08 total=0\n'
    '@@ vmstat\npswpin ${swapPages.$1}\npswpout ${swapPages.$2}\n'
    '@@ gpuwork\nGPU work information.\ngpu_id uid total_active_duration_ns total_inactive_duration_ns\n'
    '${[for (final MapEntry(:key, :value) in gpuActiveNs.entries) '1 $key $value 99999'].join('\n')}\n';

/// One row of `ps -A -o PID,PPID,UID,TIME+,RSS,NAME,ARGS`, 10 MB resident.
String psRow(int pid, int ppid, int uid, String name, double cpuS) {
  final minutes = cpuS ~/ 60, seconds = (cpuS - minutes * 60).toStringAsFixed(2).padLeft(5, '0');
  return '${'$pid'.padLeft(5)} ${'$ppid'.padLeft(5)} ${'$uid'.padLeft(5)} ${'$minutes:$seconds'.padLeft(9)} '
      '${ppid == 2 ? '    0' : '10240'} ${name.padRight(27)} $name';
}

/// The device's state as [AdbProbe.state] prints it, cut from the S24's.
String state(List<String> ps) =>
    '@@ ps\n  PID  PPID   UID     TIME+    RSS NAME                        ARGS\n${ps.join('\n')}\n'
    '@@ meminfo\nMemTotal:       11350704 kB\nMemFree:          750960 kB\nMemAvailable:    3295536 kB\n'
    'SwapTotal:       8388604 kB\nSwapFree:        4292604 kB\n'
    '@@ gpumem\nMemory snapshot for GPU 0:\nGlobal total: 545112064\nProc 684 total: 11747328\n'
    '@@ gpubusy\n13 %\n'
    '@@ thermal\nThermal Status: 0\nCached temperatures:\n'
    '\tTemperature{mValue=45.0, mType=0, mName=AP, mStatus=0}\n'
    'HAL Ready: true\nCurrent temperatures from HAL:\n'
    '\tTemperature{mValue=40.7, mType=0, mName=AP, mStatus=0}\n'
    '\tTemperature{mValue=32.2, mType=2, mName=BAT, mStatus=0}\n'
    '\tTemperature{mValue=34.6, mType=3, mName=SKIN, mStatus=0}\n'
    '\tTemperature{mValue=0.0, mType=2, mName=SUBBAT, mStatus=0}\n'
    'Current cooling devices from HAL:\n'
    '@@ battery\nCurrent Battery Service state:\n  AC powered: true\n  USB powered: false\n  Wireless powered: false\n'
    '  Dock powered: false\n  status: 2\n  level: 53\n  scale: 100\n  temperature: 326\n  technology: Li-ion\n'
    '@@ lowpower\n0\n';

DeviceReading readingOf(String countersText, String stateText) {
  final sections = parseSections(stateText);
  final (table, uids) = parseDeviceProcesses(sections['ps']!);
  return (table, uids, parseCounters(parseSections(countersText)), deviceState(sections));
}

/// A phone that answers from fixed text, in the order the meter asks.
final class FakeDeviceProbe implements DeviceProbe {
  FakeDeviceProbe(this._counters, this._states, this._packages);

  final List<String> _counters, _states;
  final String _packages;
  final calls = <String>[];

  @override
  Future<String> counters() async {
    calls.add('counters');
    return _counters.removeAt(0);
  }

  @override
  Future<String> state() async {
    calls.add('state');
    return _states.removeAt(0);
  }

  @override
  Future<String> packages() async {
    calls.add('packages');
    return _packages;
  }
}

void main() {
  group('a reading', () {
    test('a quiet machine is isolated, and the app the run launched is the run', () async {
      final app = process(500, 15.0, gpuS: 8.0, ppid: runner, executable: '/build/voxel_game_example');
      final first = {runner: process(runner, 1.0), 2: process(2, 3.0)};
      final last = {runner: process(runner, 1.0), 2: process(2, 3.05), 500: app};
      // 10 cores over 10 s at 1.6 busy cores: the app's 1.5 and a trace.
      final load = await read([first, last], [(0, 0), (1600, 10000)]);
      expect(load['isolated'], isTrue, reason: '$load');
      expect((load['runCores'], load['runGpuShare'], load['unnamedCores']), (1.5, 0.8, 0.1));
      expect(load['beside'], isEmpty);
      expect(load['gpuUtilizationPercent'], {'before': 40, 'median': 40, 'max': 40});
      expect((load['machine'], load['samples'], load['wallS']), ('Apple M2 Pro', 2, 10.0));
      expect(describeLoad(load), 'isolated');
    });

    test('the CPU time read to the app\'s exit stands for its samples', () async {
      const time = 400;
      final first = {runner: process(runner, 1.0)};
      final last = {
        runner: process(runner, 1.0),
        time: process(time, 0.0, ppid: runner),
        500: process(500, 10.0, ppid: time),
      };
      final load = await read([first, last], [(0, 0), (1500, 10000)], exited: (parent: time, cpuS: 15.0));
      expect((load['runCores'], load['unnamedCores']), (1.5, 0.0));
    });

    test('another copy of the app counts by its GPU, and a build by its CPU', () async {
      const otherApp = '/Users/me/wt/build/voxel_game_example';
      final first = {runner: process(runner, 1.0), 7: process(7, 1.0, gpuS: 2.0, executable: otherApp)};
      final last = {
        runner: process(runner, 1.0),
        7: process(7, 1.05, gpuS: 3.0, executable: otherApp),
        8: process(8, 4.0, executable: '/usr/bin/clang'),
      };
      final load = await read([first, last], [(0, 0), (500, 10000)], runExecutable: '/build/voxel_game_example');
      expect(load['isolated'], isFalse);
      final rows = besideByPid(load);
      expect((rows[7]!['gpuShare'], rows[7]!['coreShare'], rows[7]!['counted']), (0.1, 0.005, true));
      expect((rows[8]!['coreShare'], rows[8]!['counted']), (0.4, true));
      expect(describeLoad(load), contains('0.40 core 0.0% gpu /usr/bin/clang'));
      expect(describeLoad(load), contains('0.01 core 10.0% gpu $otherApp'));
    });

    test('the app xctrace has launchd start is the run\'s, a copy running before it is not', () async {
      const app = '/build/voxel_game_example';
      final first = {runner: process(runner, 1.0), 7: process(7, 0.0, executable: app)};
      final last = {
        runner: process(runner, 1.0),
        7: process(7, 0.0, gpuS: 1.0, executable: app),
        9: process(9, 5.0, gpuS: 6.0, executable: app),
      };
      final load = await read([first, last], [(0, 0), (500, 10000)], runExecutable: app);
      expect((load['runCores'], load['runGpuShare']), (0.5, 0.6));
      expect(besideByPid(load).keys, [7]);
      expect(load['isolated'], isFalse);
    });

    test('the system\'s servers are listed but never counted', () async {
      const server = '/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer';
      final first = {runner: process(runner, 1.0), 9: process(9, 0.0, executable: server)};
      final last = {runner: process(runner, 1.0), 9: process(9, 3.0, gpuS: 1.0, executable: server)};
      final load = await read([first, last], [(0, 0), (300, 10000)]);
      expect(load['isolated'], isTrue, reason: '$load');
      expect([for (final row in besideByPid(load).values) row['counted']], [false]);
    });

    test('a process under the listed shares is not listed, and is named', () async {
      final first = {runner: process(runner, 1.0), 3: process(3, 1.0)};
      final last = {runner: process(runner, 1.0), 3: process(3, 1.05)};
      final load = await read([first, last], [(0, 0), (5, 10000)]);
      expect(load['beside'], isEmpty);
      expect(load['unnamedCores'], 0.0);
    });

    test('CPU no process names counts when it is large', () async {
      final table = {runner: process(runner, 1.0)};
      final load = await read([table, table], [(0, 0), (5000, 10000)]);
      expect(load['isolated'], isFalse);
      expect(load['unnamedCores'], 5.0);
      expect(describeLoad(load), contains('5.00 core unnamed'));
    });

    test('swapping during the run breaks isolation', () async {
      final table = {runner: process(runner, 1.0)};
      final load = await read([table, table], [(0, 0), (0, 10000)], endState: {'swapins': 13, 'swapouts': 20});
      expect(load['isolated'], isFalse);
      expect(load['swappedPages'], 3);
      expect(describeLoad(load), 'beside: 3 pages swapped');
    });

    test('a wrapped tick counter still reads', () async {
      final table = {runner: process(runner, 1.0)};
      const top = 1 << 32;
      final load = await read([table, table], [(top - 100, top - 1000), (900, 9000)]);
      expect(load['busyCores'], 1.0);
    });
  });

  group('the report', () {
    test('a line from before the meter says so', () {
      expect(describeLoad(null), 'not recorded (before PFD1)');
      final old = {'scenario': 'orbit', 'radius': 6, 'round': 0};
      expect(isolationReport([old], 'machine'), 'machine: isolated in 0 of 1 runs (1 not recorded, before PFD1)\n');
    });

    test('names each run that was not alone', () async {
      final table = {runner: process(runner, 1.0)};
      final busy = await read([table, table], [(0, 0), (5000, 10000)]);
      final quiet = await read([table, table], [(0, 0), (100, 10000)]);
      final lines = [
        {'scenario': 'orbit', 'radius': 6, 'round': 0, 'machineLoad': quiet},
        {'scenario': 'fly', 'radius': 6, 'round': 0, 'machineLoad': busy},
      ];
      expect(
        isolationReport(lines, 'machine'),
        'machine: isolated in 1 of 2 runs\n'
        '- run 2 (fly:6, round 0): beside: 5.00 core unnamed (short-lived processes)\n',
      );
    });
  });

  group('macOS\'s output', () {
    test('every form of ps\'s CPU time reads', () {
      expect(cpuSeconds('0:11.29'), closeTo(11.29, 1e-9));
      expect(cpuSeconds('2:03:04.50'), closeTo(7384.5, 1e-9));
      expect(cpuSeconds('1-00:00:01.00'), closeTo(86401.0, 1e-9));
    });

    test('a process table joins its commands, spaces kept, and its GPU time', () {
      const usage =
          '  440     1   4:30.39  30544 /System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer\n'
          ' 1295  1165   5:44.18 287312 /Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper (Plugin).app/Contents/MacOS/Code Helper (Plugin)\n'
          ' 9999     1   0:00.01   1024 /usr/bin/gone\n';
      const commands =
          '  440 /System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer -daemon\n'
          ' 1295 /Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper (Plugin).app/Contents/MacOS/Code Helper (Plugin) --type=utility\n';
      final table = parseProcesses(usage, commands, {440: 2.5});
      expect(table.keys, [440, 1295]);
      final helper = table[1295]!;
      expect(helper.executable, endsWith('MacOS/Code Helper (Plugin)'));
      expect(helper.command, endsWith('Code Helper (Plugin) --type=utility'));
      expect((helper.ppid, helper.rssMb, helper.gpuS), (1165, 280.578125, 0.0));
      expect(helper.cpuS, closeTo(344.18, 1e-9));
      expect(table[440]!.gpuS, 2.5);
    });

    test('the GPU time is each record\'s creator\'s, summed over a pid\'s clients', () {
      // ioreg sorts a record's keys: its AppUsage comes before its creator.
      const ioreg = '''
+-o AGXDeviceUserClient  <class AGXDeviceUserClient, id 0x100002dbc, !registered, !matched, active, busy 0, retain 5>
    {
      "AppUsage" = ()
      "IOUserClientCreator" = "pid 444, runningboardd"
    }
    
+-o AGXDeviceUserClient  <class AGXDeviceUserClient, id 0x100002dbd, !registered, !matched, active, busy 0, retain 5>
    {
      "AppUsage" = ({"API"="Metal","lastSubmittedTime"=3062414094833,"accumulatedGPUTime"=38738170958},{"API"="Metal","lastSubmittedTime"=2864548123916,"accumulatedGPUTime"=76336458})
      "IOUserClientCreator" = "pid 440, WindowServer"
      "CommandQueueCount" = 1
    }
    
+-o AGXDeviceUserClient  <class AGXDeviceUserClient, id 0x100002dbe, !registered, !matched, active, busy 0, retain 5>
    {
      "AppUsage" = ({"API"="Metal","lastSubmittedTime"=0,"accumulatedGPUTime"=1000000000})
      "IOUserClientCreator" = "pid 440, WindowServer"
    }
    
+-o AGXDeviceUserClient  <class AGXDeviceUserClient, id 0x100002dbf, !registered, !matched, active, busy 0, retain 5>
    {
      "AppUsage" = ({"API"="Metal","lastSubmittedTime"=4025767141333,"accumulatedGPUTime"=3992585375})
      "IOUserClientCreator" = "pid 31299, voxel_game_examp"
    }
''';
      expect(parseGpuSeconds(ioreg), {444: 0.0, 440: closeTo(39.814507416, 1e-9), 31299: closeTo(3.992585375, 1e-9)});
    });

    test('the accelerator\'s statistics read', () {
      const ioreg =
          '"PerformanceStatistics" = {"In use system memory (driver)"=0,"Device Utilization %"=9,'
          '"In use system memory"=133644288}';
      expect(parseGpuStatistics(ioreg), (utilization: 9, memoryMb: 127.453125));
    });

    test('memory, swap, thermal notes and power read', () {
      const vm =
          'Mach Virtual Memory Statistics: (page size of 16384 bytes)\n'
          'Pages free:                               32546.\n'
          '"Translation faults":                 157742757.\n'
          'Swapins:                                 550806.\n';
      final (page, pages) = parseVmStat(vm);
      expect(page, 16384);
      expect(pages, {'Pages free': 32546, 'Translation faults': 157742757, 'Swapins': 550806});
      expect(parseSwapUsedMb('total = 10240.00M  used = 8666.94M  free = 1573.06M  (encrypted)'), 8666.94);
      expect(
        parseThermal(
          'Note: No thermal warning level has been recorded\n'
          'Note: No performance warning level has been recorded\n'
          'CPU_Speed_Limit \t= 80\n',
        ),
        ['CPU_Speed_Limit \t= 80'],
      );
      expect(
        parsePowerSource("Now drawing from 'AC Power'\n -InternalBattery-0 (id=24969315)\t100%; charged"),
        'AC Power',
      );
      expect(parseLowPowerMode(' standby              1\n lowpowermode         0\n'), isFalse);
      expect(() => parseLowPowerMode(' standby 1\n'), throwsStateError);
    });
  });

  group('a phone\'s reading', () {
    const app = 10528;
    final start = readingOf(
      counters(uptimeS: 100.0, busyTicks: 1000, gpuBusyUs: [0, 100], gpuActiveNs: {1000: 0, app: 50, 10049: 0}),
      state([
        psRow(2680, 1635, 1000, 'system_server', 100.0),
        psRow(1184, 2, 0, '[crtc_commit:201]', 50.0),
        psRow(4840, 2, 0, '[kworker/u16:12-adb]', 10.0),
        psRow(21953, 1635, 10218, 'com.whatsapp', 20.0),
        psRow(700, 1635, 10300, 'com.example.quiet', 5.0),
      ]),
    );

    test('reads the counters and the state adb printed', () {
      final (table, uids, before, state) = start;
      expect((before.uptimeS, before.busyTicks, before.processors), (100.0, 1000, 2));
      expect(
        [before.gpuBusyUs, before.gpuLevelsHz],
        [
          [0, 100],
          [1000000000, 500000000],
        ],
      );
      expect(before.pressureUs, {'cpuSome': 0, 'memorySome': 0, 'memoryFull': 0});
      expect(before.swapPages, (0, 0));
      expect(before.gpuActiveNs, {1000: 0, app: 50, 10049: 0});
      final server = table[(pid: 2680, ppid: 1635, uid: 1000)]!;
      expect(
        (server.ppid, server.executable, server.command, server.rssMb),
        (1635, 'system_server', 'system_server', 10.0),
      );
      expect(uids[(pid: 21953, ppid: 1635, uid: 10218)], 10218);
      expect(state, {
        'memoryTotalMb': 11085,
        'memoryAvailableMb': 3218,
        'memoryFreeMb': 733,
        'swapUsedMb': 4000,
        'gpuMemoryMb': 520,
        'gpuBusyPercent': 13,
        'thermalStatus': 0,
        'temperaturesC': {'AP': 40.7, 'BAT': 32.2, 'SKIN': 34.6},
        'battery': {'levelPercent': 53, 'power': 'AC', 'temperatureC': 32.6},
        'lowPowerMode': false,
      });
    });

    test('a quiet phone is isolated: its servers and kernel threads are listed, the app\'s GPU is the run\'s', () {
      final end = readingOf(
        counters(
          uptimeS: 110.0,
          busyTicks: 3000,
          gpuBusyUs: [2000000, 4000100],
          gpuActiveNs: {1000: 1000000000, app: 5000000050, 10049: 1000000},
          cpuSome: 500000,
          swapPages: (51, 1303),
        ),
        state([
          psRow(2680, 1635, 1000, 'system_server', 103.0),
          psRow(1184, 2, 0, '[crtc_commit:201]', 52.0),
          // The same kernel worker, renamed by the work it took: the same process.
          psRow(4840, 2, 0, '[kworker/u16:12-memlat_wq]', 10.5),
          psRow(21953, 1635, 10218, 'com.whatsapp', 20.5),
          psRow(700, 1635, 10300, 'com.example.quiet', 5.05),
        ]),
      );
      final load = deviceLoad(start, end, runUid: app);
      expect(load['isolated'], isTrue, reason: '$load');
      // 2 cores busy over 10 s; the named processes 0.30 + 0.20 + 0.05 + 0.05 + 0.005.
      expect((load['wallS'], load['busyCores'], load['appAndUnnamedCores']), (10.0, 2.0, 1.4));
      expect((load['runGpuShare'], load['gpuBusyShare'], load['gpuMeanBusyMhz']), (0.5, 0.6, 667));
      expect((load['cpuPressureSomeShare'], load['pagesSwappedIn'], load['pagesSwappedOut']), (0.05, 51, 1303));
      final rows = [
        for (final row in (load['beside'] as List).cast<Map<String, Object?>>()) (row['command'], row['counted']),
      ];
      expect(rows, [
        ('system_server', false),
        ('system_server', false),
        ('[crtc_commit:201]', false),
        ('[kworker/u16:12-memlat_wq]', false),
        ('com.whatsapp', false),
      ]);
      expect((load['beside'] as List).first, {
        'uid': 1000,
        'command': 'system_server',
        'gpuShare': 0.1,
        'counted': false,
      });
      expect(describeLoad(load), 'isolated');
    });

    test('another app counts by its CPU, by its uid\'s GPU, and a process born or reborn during the run by all its time', () {
      final end = readingOf(
        counters(
          uptimeS: 110.0,
          busyTicks: 1500,
          gpuBusyUs: [0, 100],
          gpuActiveNs: {1000: 0, app: 50, 10049: 200000000, 10777: 300000000},
        ),
        state([
          psRow(2680, 1635, 1000, 'system_server', 100.0),
          psRow(21953, 1635, 10218, 'com.whatsapp', 22.0),
          psRow(800, 1635, 10301, 'com.example.updater', 1.5),
          // The quiet app's pid, parent and uid, with less CPU time than it had: another process.
          psRow(700, 1635, 10300, 'com.example.reborn', 1.2),
        ]),
      );
      final load = deviceLoad(start, end, runUid: app, packages: {10777: 'com.example.gone'});
      expect(load['isolated'], isFalse);
      expect(
        describeLoad(load),
        'beside: 3.0% gpu com.example.gone; 2.0% gpu uid 10049; 0.20 core com.whatsapp; 0.15 core com.example.updater; '
        '0.12 core com.example.reborn',
      );
    });

    test('the meter reads the state before the counters at the start, after them at the stop, and names a uid by its packages', () async {
      final probe = FakeDeviceProbe(
        [
          counters(uptimeS: 100.0, busyTicks: 1000, gpuBusyUs: [0, 0], gpuActiveNs: {app: 0}),
          counters(uptimeS: 110.0, busyTicks: 1000, gpuBusyUs: [0, 0], gpuActiveNs: {app: 0, 10777: 500000000}),
        ],
        [state([]), state([])],
        'package:com.example.b uid:10777\npackage:com.example.a uid:10777\npackage:other uid:10001\n',
      );
      final meter = await DeviceMeter.start(probe, runUid: app);
      expect(probe.calls, ['state', 'counters']);
      final load = await meter.stop();
      expect(probe.calls, ['state', 'counters', 'counters', 'state', 'packages']);
      expect(describeLoad(load), 'beside: 5.0% gpu com.example.a, com.example.b');
    });

    test('the report names each phone run that was not alone', () {
      final end = readingOf(
        counters(uptimeS: 110.0, busyTicks: 1000, gpuBusyUs: [0, 100], gpuActiveNs: {1000: 0, app: 50, 10049: 0}),
        state([psRow(21953, 1635, 10218, 'com.whatsapp', 22.0)]),
      );
      final lines = [
        {
          'scenario': 'orbit',
          'radius': 6,
          'round': 0,
          'machineLoad': null,
          'deviceLoad': deviceLoad(start, end, runUid: app),
        },
      ];
      expect(
        isolationReport(lines, 'device', key: 'deviceLoad'),
        'device: isolated in 0 of 1 runs\n'
        '- run 1 (orbit:6, round 0): beside: 0.20 core com.whatsapp\n',
      );
    });

    test('a uid running many processes is named by three', () {
      final end = readingOf(
        counters(
          uptimeS: 110.0,
          busyTicks: 1000,
          gpuBusyUs: [0, 100],
          gpuActiveNs: {1000: 0, app: 50, 10049: 500000000},
        ),
        state([
          for (final (i, name) in ['d', 'c', 'b', 'a'].indexed) psRow(900 + i, 1, 10049, name, 0.0),
        ]),
      );
      expect(describeLoad(deviceLoad(start, end, runUid: app)), 'beside: 5.0% gpu a, b, c +1');
    });

    test('a GPU work table missing from dumpsys fails', () {
      expect(
        () => parseCounters(parseSections('@@ uptime\n1.0 2.0\n@@ gpuwork\nGPU work information.\n')),
        throwsStateError,
      );
    });
  });

  test('this Mac reads', () async {
    final probe = MacProbe();
    final state = await probe.state();
    expect(state['memoryTotalMb'] as int, greaterThan(0));
    expect((await probe.processes()).keys, contains(pid));
    final (busy, total) = probe.cpuTicks();
    expect(busy, lessThanOrEqualTo(total));
  }, skip: Platform.isMacOS ? false : 'the meter reads macOS\'s tools');
}
