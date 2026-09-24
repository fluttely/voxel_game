import 'package:voxel_engine/core.dart';
import 'package:voxel_engine/signals.dart';

import '../core/blocks.dart';
import '../world/voxel_world.dart';
import 'sfx.dart';

/// Stage 27: redstone-lite (Godot `src/game/circuits.gd`). Host-only, owned by
/// [VoxelWorld] and ticked from the simulation step inside the flow's `blocks`
/// batch. VK7.3: voxel_signals' [SignalNetwork], told this game's blocks:
///
/// - sources `lever_on`, `button_on` (a press, 1 s), a `pressure_plate` while
///   a body stands on it ([setPressedPlates], fed by `Game`'s plate check);
/// - `wire_off` / `wire_on` carry the strength, 15 beside a source, one less a
///   cell, on the staircase rule;
/// - what reacts: a lamp lights, an iron door opens (both halves), a piston
///   pushes, a run of powered rails lights within eight cells, TNT ignites
///   ([onTntPowered]).
class Circuits {
  Circuits(this.world) {
    int id(String name) => Blocks.indexOf(name);
    final lampOff = id('redstone_lamp_off'), lampOn = id('redstone_lamp_on');
    final lamp = SignalReactions.swap(lampOff, lampOn);
    final doors = {id('iron_door_z'): id('iron_door_z_open'), id('iron_door_x'): id('iron_door_x_open')};
    final door = SignalReactions.door(doors, onSwing: (_) => Sfx.play('door', -6.0));
    final pistons = {for (final f in const ['n', 'e', 's', 'w']) id('piston_$f'): id('piston_${f}_on')};
    final piston = SignalReactions.piston(
      pistons,
      facing: Blocks.pistonDir,
      pushable: (b) => Blocks.hardness(b) >= 0.0,
      givesWay: Blocks.isReplaceable,
      onExtend: (_) => Sfx.play('place', -8.0, 0.7),
    );
    final rails = {id('powered_rail_ns'): id('powered_rail_ns_on'), id('powered_rail_ew'): id('powered_rail_ew_on')};
    final run = SignalReactions.poweredRun(rails);
    final tnt = SignalReactions.trigger((c) => onTntPowered?.call(c));
    _net = SignalNetwork(
      world,
      SignalRules(
        wireOff: id('wire_off'),
        wireOn: id('wire_on'),
        sources: {id('lever_on'), id('button_on')},
        pressSources: {id('pressure_plate')},
        toggles: {id('lever_off'): id('lever_on'), id('lever_on'): id('lever_off')},
        buttons: {id('button'): (pressed: id('button_on'), seconds: buttonSeconds)},
        reactions: {
          lampOff: lamp,
          lampOn: lamp,
          id('tnt'): tnt,
          for (final e in doors.entries) ...{e.key: door, e.value: door},
          for (final e in pistons.entries) ...{e.key: piston, e.value: piston},
          for (final e in rails.entries) ...{e.key: run, e.value: run},
        },
        maxStrength: maxStrength,
        period: period,
        networkCap: networkCap,
      ),
    );
  }

  static const double period = 0.1;
  static const int maxStrength = 15;
  static const int networkCap = 400;
  static const double buttonSeconds = 1.0;

  final VoxelWorld world;
  late final SignalNetwork _net;

  /// Networks rebuilt, for the probes.
  int get recomputes => _net.recomputes;

  /// Godot's `tnt_powered` signal: TNT beside a live wire or a source.
  void Function(IVec3 at)? onTntPowered;

  /// The player's use action on a lever or a button.
  bool useBlock(IVec3 b) => _net.use(b);

  /// Every block edit passes here (from `VoxelWorld.setBlock`).
  void touch(IVec3 b, int old, int id) => _net.touch(b, old, id);

  /// The plates with a body on them this simulation tick.
  void setPressedPlates(Set<IVec3> pressed) => _net.setPressed(pressed);

  void tick(double dt) => _net.tick(dt);

  /// The strength a wire cell carries (0 for no wire or an unpowered one).
  int strengthAt(IVec3 b) => _net.strengthAt(b);

  int get pending => _net.pending;
}
