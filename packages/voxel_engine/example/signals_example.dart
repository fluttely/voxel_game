// A lever, a wire and a lamp, then a rail line that lays itself, on a tiny
// world kept in a map.
//
//   dart run example/signals_example.dart
import 'package:voxel_engine/core.dart';
import 'package:voxel_engine/signals.dart';

const int stone = 1, wireOff = 2, wireOn = 3, leverOff = 4, leverOn = 5, lampOff = 6, lampOn = 7;
const int railNs = 8, railEw = 9, railNe = 10, railNw = 11, railSe = 12, railSw = 13;

/// Air, stone, then every circuit and rail block (see-through, not solid).
final VoxelBlockTable blockTable = VoxelBlockTable([
  const VoxelBlockDef(shape: BlockShape.cube, solid: false, opaque: false, r: 0, g: 0, b: 0, a: 0),
  const VoxelBlockDef(shape: BlockShape.cube, solid: true, opaque: true, r: 0.5, g: 0.5, b: 0.5),
  for (var i = 2; i <= railSw; i++) const VoxelBlockDef(shape: BlockShape.cube, solid: false, opaque: false, r: 0.6, g: 0.2, b: 0.2),
]);

/// A stone floor below y 10 and whatever was placed above it. Every edit is
/// told to the signal network, as a game's world does.
class MapWorld implements VoxelEditor {
  /// The cells placed so far.
  final Map<IVec3, int> cells = {};

  /// The network to tell about edits.
  SignalNetwork? signals;

  @override
  VoxelBlockTable get table => blockTable;

  @override
  int getBlockXYZ(int x, int y, int z) => cells[IVec3(x, y, z)] ?? (y < 10 ? stone : 0);

  @override
  bool setBlock(IVec3 cell, int id) {
    final old = getBlockXYZ(cell.x, cell.y, cell.z);
    cells[cell] = id;
    signals?.touch(cell, old, id);
    return true;
  }
}

/// Runs the network for [seconds] at 60 steps a second.
void run(SignalNetwork net, double seconds) {
  for (var t = 0.0; t < seconds; t += 1 / 60) {
    net.tick(1 / 60);
  }
}

void main() {
  // 1. Declare which blocks are wires, sources, switches and what reacts.
  final world = MapWorld();
  final net = world.signals = SignalNetwork(
    world,
    SignalRules(
      wireOff: wireOff,
      wireOn: wireOn,
      sources: const {leverOn},
      toggles: const {leverOff: leverOn, leverOn: leverOff},
      reactions: {lampOff: SignalReactions.swap(lampOff, lampOn), lampOn: SignalReactions.swap(lampOff, lampOn)},
    ),
  );

  // 2. Build a lever, five wires and a lamp.
  world.setBlock(const IVec3(0, 10, 0), leverOff);
  for (var x = 1; x <= 5; x++) {
    world.setBlock(IVec3(x, 10, 0), wireOff);
  }
  world.setBlock(const IVec3(6, 10, 0), lampOff);

  // 3. Pull the lever: power runs down the wire, one less a cell, and lights the lamp.
  net.use(const IVec3(0, 10, 0));
  run(net, 0.2);
  print('wire strength: ${[for (var x = 1; x <= 5; x++) net.strengthAt(IVec3(x, 10, 0))]}');
  print('the lamp is ${world.getBlockXYZ(6, 10, 0) == lampOn ? 'on' : 'off'}');

  net.use(const IVec3(0, 10, 0));
  run(net, 0.2);
  print('lever back: the lamp is ${world.getBlockXYZ(6, 10, 0) == lampOn ? 'on' : 'off'}');

  // 4. Rails: name each shape once, then place any rail and it turns to meet its neighbours.
  final rails = RailGraph({
    railNs: const RailVariant('rail', 'ns'),
    railEw: const RailVariant('rail', 'ew'),
    railNe: const RailVariant('rail', 'ne'),
    railNw: const RailVariant('rail', 'nw'),
    railSe: const RailVariant('rail', 'se'),
    railSw: const RailVariant('rail', 'sw'),
  });
  for (var x = 0; x < 4; x++) {
    rails.place(world, IVec3(x, 10, 4), railNs);
  }
  rails.place(world, const IVec3(3, 10, 5), railNs);
  print('the line runs ${rails.shapeOf(world.getBlockXYZ(1, 10, 4))} and bends ${rails.shapeOf(world.getBlockXYZ(3, 10, 4))} at its end');

  // 5. A cart follows the track until it ends.
  var cell = const IVec3(0, 10, 4);
  var heading = RailGraph.e;
  final path = [cell];
  while (true) {
    final next = rails.nextCell(world, cell, heading);
    if (next == cell) break;
    // Leave the next rail by the end that does not point back where it came from.
    final back = rails.endToward(world, next, cell);
    heading = rails.connections(world.getBlockXYZ(next.x, next.y, next.z)).firstWhere((end) => end != back);
    cell = next;
    path.add(cell);
  }
  print('a cart rolls ${path.join(' -> ')}');
}
