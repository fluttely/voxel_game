// Tests for machine_load.dart (PFD1), from the repository's root:
//   dart test tool/
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

  test('this Mac reads', () async {
    final probe = MacProbe();
    final state = await probe.state();
    expect(state['memoryTotalMb'] as int, greaterThan(0));
    expect((await probe.processes()).keys, contains(pid));
    final (busy, total) = probe.cpuTicks();
    expect(busy, lessThanOrEqualTo(total));
  }, skip: Platform.isMacOS ? false : 'the meter reads macOS\'s tools');
}
