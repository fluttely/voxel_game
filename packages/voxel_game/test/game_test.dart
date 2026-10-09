import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart' show ChunkMesher;
import 'package:voxel_game/voxel_game.dart';

const _blocks = [
  BlockType('stone', color: 0x808080, hardness: 1.5, tool: 'pickaxe', tier: 1, drop: 'cobblestone'),
  BlockType('cobblestone', color: 0x707070, hardness: 2.0, tool: 'pickaxe'),
  BlockType('dirt', color: 0x74502F, hardness: 0.5, tool: 'shovel'),
  BlockType('grass', color: 0x4C9437, hardness: 0.6, tool: 'shovel', drop: 'dirt'),
  BlockType('planks', color: 0xB08850, hardness: 1.0, tool: 'axe'),
  BlockType.liquid('water', color: 0x3366CC),
  BlockType.liquid('water_flow', color: 0x3366CC, kind: 'water', source: false),
];

/// Level grass at y 20 (the first air cell), no caves, no trees.
VoxelGameSpec _flat({
  List<MobSpec> mobs = const [],
  PlayerSpec player = const PlayerSpec(),
  SkySpec sky = SkySpec.alwaysDay,
}) => VoxelGameSpec(
  blocks: _blocks,
  world: const WorldGenSpec(
    terrain: TerrainRecipe.flat(20),
    seaLevel: 5,
    caves: CaveSpec.none,
    biomes: [Biome('plains', top: 'grass', under: 'dirt')],
  ),
  items: const [
    ItemType('wooden_pickaxe', color: 0xB08850, tool: 'pickaxe', tier: 1, stack: 1, durability: 60, damage: 3),
  ],
  player: player,
  mobs: mobs,
  sky: sky,
);

Future<VoxelGame> _start(VoxelGameSpec spec) async {
  final game = await VoxelGame.startHeadless(spec);
  game.spawner.enabled = false;
  for (var i = 0; i < 600 && !game.ready; i++) {
    game.frame(1 / 60);
    await Future<void>.delayed(Duration.zero);
  }
  expect(game.ready, isTrue, reason: 'the spawn chunk loads and the player stands on it');
  return game;
}

/// [seconds] of simulation, letting the chunk jobs land between frames.
Future<void> _run(VoxelGame game, double seconds) async {
  for (var t = 0.0; t < seconds; t += 1 / 60) {
    game.frame(1 / 60);
    await Future<void>.delayed(Duration.zero);
  }
}

/// A system that calls [step] every step.
class _EveryStep extends GameSystem {
  _EveryStep(this.step);

  final void Function() step;

  @override
  void tick(VoxelGame game, double dt) => step();
}

void main() {
  test('the on-screen stick walks and, pushed to the rim, runs', () async {
    final game = await _start(_flat());
    final p = game.player;
    await _run(game, 0.5);
    final start = p.position.clone();
    game.input.touchMove(0.0, -1.0);
    await _run(game, 1.0);
    final walked = ((p.position - start)..y = 0).length;
    expect(p.position.z, lessThan(start.z), reason: 'up on the stick is forward');
    game.input.setTouchHeld(VoxelAction.sprint, true);
    final from = p.position.clone();
    await _run(game, 1.0);
    game.input
      ..touchMove(0.0, 0.0)
      ..setTouchHeld(VoxelAction.sprint, false);
    expect(
      ((p.position - from)..y = 0).length,
      greaterThan(walked),
      reason: 'a second of running outruns one of walking',
    );
  });

  test('the player stands on the ground, walks forward and jumps', () async {
    final game = await _start(_flat());
    final p = game.player;
    await _run(game, 0.5);
    expect(p.position.y, closeTo(20.0 + 0.001, 0.01));
    expect(p.onFloor, isTrue);
    final start = p.position.clone();
    game.input.hold(VoxelAction.moveForward, true);
    await _run(game, 1.0);
    game.input.hold(VoxelAction.moveForward, false);
    final walked = (p.position - start)..y = 0;
    expect(walked.length, greaterThan(3.0), reason: '4.6 m/s for a second, after the ease-in');
    expect(p.position.z, lessThan(start.z), reason: 'yaw 0 walks toward -z');
    game.input.hold(VoxelAction.jump, true);
    var peak = p.position.y;
    for (var i = 0; i < 30; i++) {
      await _run(game, 1 / 60);
      peak = peak > p.position.y ? peak : p.position.y;
    }
    game.input.hold(VoxelAction.jump, false);
    expect(peak - 20.0, greaterThan(1.2));
  });

  test('the game is filled once the player stands and the whole window has its meshes', () async {
    final game = await VoxelGame.startHeadless(_flat());
    game.spawner.enabled = false;
    expect(game.filled, isFalse, reason: 'nothing is loaded before the first frame');
    for (var i = 0; i < 600 && !game.filled; i++) {
      game.frame(1 / 60);
      await Future<void>.delayed(Duration.zero);
    }
    expect(game.filled, isTrue);
    expect(game.ready, isTrue);
    const side = 2 * 2 + 1;
    expect(game.world.meshCount, greaterThanOrEqualTo(side * side), reason: 'every chunk of the window');

    game.breakBlock(IVec3.floor(game.player.position) - IVec3(0, 1, 0));
    expect(game.filled, isFalse, reason: 'the edited chunk waits for its new mesh');
    await _run(game, 0.5);
    expect(game.filled, isTrue);
    game.dispose();
  });

  test('a fall of more than four blocks hurts; a creative player never', () async {
    final game = await _start(_flat());
    final p = game.player;
    p.position = Vector3(p.position.x, 32, p.position.z);
    await _run(game, 2.0);
    expect(p.onFloor, isTrue);
    expect(p.hp, lessThan(p.spec.hp), reason: 'twelve blocks: (12 - 4) x 1.2 = 9');
    final creative = await _start(_flat(player: const PlayerSpec(creative: true)));
    creative.player.position.y = 32;
    await _run(creative, 2.0);
    expect(creative.player.hp, creative.player.spec.hp);
  });

  test('the motor glides (a capped fall that never hurts) and flies (no gravity)', () async {
    final game = await _start(_flat());
    final p = game.player;
    final motor = p.motor;
    p.position = Vector3(p.position.x, 40, p.position.z);
    motor.resetFall();
    var landed = 0.0;
    for (var i = 0; i < 60 * 20 && !p.onFloor; i++) {
      landed = motor.step(1 / 60, wish: Vector3.zero(), speed: 0.0, glide: motor.canGlide).landedAfter;
      expect(p.velocity.y, greaterThanOrEqualTo(-motor.tuning.glideFall - 1e-5));
    }
    expect(p.onFloor, isTrue);
    expect(landed, lessThan(0.1), reason: 'a glide is footing: twenty blocks down, nothing fallen');
    final y = p.position.y;
    for (var i = 0; i < 30; i++) {
      motor.fly(1 / 60, wish: Vector3.zero(), speed: 0.0, rise: true);
    }
    expect(p.position.y, closeTo(y + motor.tuning.flySpeed * 0.5, 0.05));
    for (var i = 0; i < 30; i++) {
      motor.fly(1 / 60, wish: Vector3.zero(), speed: 0.0);
    }
    expect(p.position.y, closeTo(y + motor.tuning.flySpeed * 0.5, 0.05), reason: 'a flyer hangs where it stops');
    expect(motor.step(1 / 60, wish: Vector3.zero(), speed: 0.0).landedAfter, 0.0);
  });

  test('a jump off the floor launches at the step\'s jumpSpeed, or the tuning\'s', () async {
    final game = await _start(_flat());
    final p = game.player;
    final motor = p.motor;
    for (var i = 0; i < 60 && !p.onFloor; i++) {
      motor.idle(1 / 60);
    }
    expect(p.onFloor, isTrue);
    expect(motor.step(1 / 60, wish: Vector3.zero(), speed: 0.0, jump: true, jumpSpeed: 9.0).jumped, isTrue);
    expect(p.velocity.y, closeTo(9.0, 1e-5), reason: 'the launch is set after the step\'s gravity');
    for (var i = 0; i < 120 && !p.onFloor; i++) {
      motor.idle(1 / 60);
    }
    motor.step(1 / 60, wish: Vector3.zero(), speed: 0.0, jump: true);
    expect(p.velocity.y, closeTo(motor.tuning.jumpVelocity, 1e-5));
  });

  test('mining the block underfoot drops its item, which is picked up', () async {
    final game = await _start(_flat());
    final p = game.player;
    p.pitch = -1.5; // straight down
    game.input.hold(VoxelAction.attack, true);
    await _run(game, 2.0);
    game.input.hold(VoxelAction.attack, false);
    await _run(game, 1.5);
    expect(
      p.inventory.countOf('dirt'),
      greaterThanOrEqualTo(1),
      reason: 'grass drops dirt, and the drop flies to the player',
    );
  });

  test('a worn tool dropped and picked up again is the same tool, wear and all', () async {
    final game = await _start(_flat(player: const PlayerSpec(startingItems: {'wooden_pickaxe': 1})));
    final p = game.player;
    final slot = p.inventory.find('wooden_pickaxe');
    p.selectedSlot = slot;
    p.inventory.wear(slot, 53);
    expect(p.inventory.durAt(slot), 7);
    game.input.tap(VoxelAction.drop);
    await _run(game, 0.1);
    expect(p.inventory.countOf('wooden_pickaxe'), 0);
    final drop = game.entities.whereType<ItemPickup>().single;
    expect(drop.stack.dur, 7, reason: 'the stack on the ground is the one that left the slot');
    await _run(game, 3.0);
    final back = p.inventory.find('wooden_pickaxe');
    expect(back, isNot(-1), reason: 'the drop flies back to the player that threw it');
    expect(p.inventory.durAt(back), 7, reason: 'not a new pickaxe');
  });

  test('a held block is placed against the aimed face and used up', () async {
    final game = await _start(_flat(player: const PlayerSpec(startingItems: {'planks': 3})));
    final p = game.player;
    p.pitch = -0.9;
    await _run(game, 0.2);
    final aimed = p.aimedBlock!;
    game.input.tap(VoxelAction.use);
    await _run(game, 0.1);
    expect(game.world.blockNameAt(aimed.block + aimed.normal), 'planks');
    expect(p.inventory.countOf('planks'), 2);
  });

  test('stone needs a pickaxe; with one it breaks into cobblestone', () async {
    final game = await _start(_flat(player: const PlayerSpec(startingItems: {'wooden_pickaxe': 1})));
    final stone = game.blocks[game.blocks.indexOf('stone')];
    expect(game.mining.mineTime(stone, null), -1);
    expect(game.mining.mineTime(stone, game.items['wooden_pickaxe']), closeTo(0.75, 1e-9));
  });

  test('a hunter chases the player and strikes; the player hits back and it drops its loot', () async {
    const zombie = MobSpec(
      'zombie',
      hp: 6,
      speed: 3.0,
      brain: [MeleeAttack(damage: 2), Hunt(range: 20), Wander()],
      loot: LootTable([LootEntry('dirt', 2, 2, 1.0)]),
    );
    final game = await _start(
      _flat(
        mobs: const [zombie],
        player: const PlayerSpec(startingItems: {'wooden_pickaxe': 1}),
      ),
    );
    final p = game.player;
    final m = game.spawnMob('zombie', p.position + Vector3(0, 0, -8));
    await _run(game, 4.0);
    expect(p.hp, lessThan(p.spec.hp), reason: 'it walked eight blocks and bit');
    expect(m.running.whereType<Hunt>(), isNotEmpty);
    // Face it and swing until it falls.
    for (var i = 0; i < 20 && !m.isDead; i++) {
      final to = m.centre() - p.eyePosition;
      p.yaw = -Vector3(0, 0, -1).angleToSigned(Vector3(to.x, 0, to.z).normalized(), Vector3(0, 1, 0));
      p.pitch = 0.0;
      game.input.tap(VoxelAction.attack);
      await _run(game, 0.5);
    }
    expect(m.isDead, isTrue);
    await _run(game, 2.0);
    expect(p.inventory.countOf('dirt'), greaterThanOrEqualTo(2));
    expect(game.mobs, isEmpty, reason: 'a dead mob leaves the world');
  });

  test('a finger\'s tap swings at a creature in reach, and uses anything else', () async {
    const cow = MobSpec('cow', hp: 10, brain: []);
    final game = await _start(_flat(mobs: const [cow]));
    final p = game.player;
    final m = game.spawnMob('cow', p.position + Vector3(0, 0, -2));
    final to = m.centre() - p.eyePosition;
    p.yaw = -Vector3(0, 0, -1).angleToSigned(Vector3(to.x, 0, to.z).normalized(), Vector3(0, 1, 0));
    p.pitch = 0.0;
    await _run(game, 0.1);
    expect(p.aimedMob, same(m));
    expect(game.input.touchTapPrimary, isTrue);
    game.input
      ..onPointerDown(const PointerDownEvent(pointer: 1, kind: PointerDeviceKind.touch))
      ..onPointerUp(const PointerUpEvent(pointer: 1, kind: PointerDeviceKind.touch));
    await _run(game, 0.1);
    expect(m.hp, lessThan(10), reason: 'the tap was the primary button, a swing');
    p.yaw += math.pi;
    await _run(game, 0.1);
    expect(p.aimedMob, isNull);
    expect(game.input.touchTapPrimary, isFalse, reason: 'with no creature aimed, a tap uses');
  });

  test('a hunter that cannot reach its target plans on a timer, not every step', () async {
    const zombie = MobSpec('zombie', hp: 6, speed: 3.0, brain: [Hunt(range: 20)]);
    final game = await _start(_flat(mobs: const [zombie]));
    final p = game.player;
    final at = p.position + Vector3(0, 0, -6);
    final cell = IVec3.floor(at);
    // Walled in three high: every path toward the player ends inside the box.
    for (var dx = -1; dx <= 1; dx++) {
      for (var dz = -1; dz <= 1; dz++) {
        if (dx == 0 && dz == 0) continue;
        for (var dy = 0; dy < 3; dy++) {
          game.world.setBlockNamed(cell + IVec3(dx, dy, dz), 'stone');
        }
      }
    }
    final m = game.spawnMob('zombie', Vector3(cell.x + 0.5, at.y, cell.z + 0.5));
    await _run(game, 3.0);
    expect(m.running.whereType<Hunt>(), isNotEmpty);
    expect(m.pathBlocked, isTrue);
    expect(
      m.pathsPlanned,
      inInclusiveRange(3, (3.0 / Mob.replanEvery).ceil() + 1),
      reason: 'a partial path walked to its end waits for the timer (180 steps ran)',
    );
  });

  test('hunters that all want a path at once share a budget of searches a step', () async {
    const zombie = MobSpec('zombie', hp: 6, speed: 3.0, brain: [Hunt(range: 20)]);
    final game = await _start(_flat(mobs: const [zombie]));
    final p = game.player;
    final pack = [
      for (var i = 0; i < 24; i++)
        game.spawnMob(
          'zombie',
          p.position + Vector3(math.cos(i * math.pi / 12) * 10, 0, math.sin(i * math.pi / 12) * 10),
        ),
    ];
    var before = 0, most = 0;
    for (var i = 0; i < 90; i++) {
      game.step(1 / 60);
      final planned = pack.fold<int>(0, (n, m) => n + m.pathsPlanned);
      most = math.max(most, planned - before);
      before = planned;
      await Future<void>.delayed(Duration.zero);
    }
    expect(most, lessThanOrEqualTo(Mob.searchesPerStep));
    expect(pack.where((m) => m.pathsPlanned == 0), isEmpty, reason: 'a mob that waited plans on a later step');
  });

  test('a wanderer whose last walk was blocked walks again once it is let out', () async {
    const cow = MobSpec('cow', hp: 4, speed: 2.0, brain: [Wander(radius: 8, speed: 1.0)]);
    final game = await _start(_flat(mobs: const [cow]));
    final at = game.player.position + Vector3(0, 0, -6);
    final cell = IVec3.floor(at);
    final walls = [
      for (var dx = -1; dx <= 1; dx++)
        for (var dz = -1; dz <= 1; dz++)
          if (dx != 0 || dz != 0)
            for (var dy = 0; dy < 3; dy++) cell + IVec3(dx, dy, dz),
    ];
    for (final w in walls) {
      game.world.setBlockNamed(w, 'stone');
    }
    final m = game.spawnMob('cow', Vector3(cell.x + 0.5, at.y, cell.z + 0.5));
    await _run(game, 6.0);
    expect(m.pathBlocked, isTrue, reason: 'every walk it tried ended inside the box');
    for (final w in walls) {
      game.world.setBlock(w, BlockRegistry.air);
    }
    final planned = m.pathsPlanned, start = m.position.clone();
    await _run(game, 12.0);
    expect(m.pathsPlanned, greaterThan(planned), reason: 'a new goal is planned, not dropped on the old verdict');
    expect(m.position.distanceTo(start), greaterThan(1.0));
  });

  test('a frightened animal runs from what hurt it', () async {
    const sheep = MobSpec('sheep', hp: 8, speed: 2.0, rig: Rig.quadruped(), brain: [FleeWhenHurt(), Wander()]);
    final game = await _start(_flat(mobs: const [sheep]));
    final p = game.player;
    final m = game.spawnMob('sheep', p.position + Vector3(2, 0, 0));
    await _run(game, 0.3);
    m.takeDamage(Damage(1, from: p.position, attacker: p));
    await _run(game, 2.0);
    expect(m.position.distanceTo(p.position), greaterThan(4.0));
  });

  test('a creeper that reaches the player blows a hole in the ground', () async {
    const creeper = MobSpec('creeper', hp: 10, speed: 3.0, brain: [Explode(fuse: 0.8, radius: 2.5, damage: 6), Hunt()]);
    final game = await _start(_flat(mobs: const [creeper]));
    final p = game.player;
    final m = game.spawnMob('creeper', p.position + Vector3(4, 0, 0));
    final hpBefore = p.hp;
    await _run(game, 4.0);
    expect(m.isDead, isTrue);
    expect(p.hp, lessThan(hpBefore));
    final c = IVec3.floor(m.position);
    expect(game.world.getBlock(c + IVec3.down), BlockRegistry.air, reason: 'the grass under it is gone');
  });

  test('at night the spawner fills the dark with what the rules allow', () async {
    const night = MobSpec('ghoul', hp: 4, brain: [Wander()], spawn: SpawnRule.dark(maxAlive: 4));
    const day = MobSpec('cow', hp: 4, brain: [Wander()], spawn: SpawnRule.daylight(maxAlive: 4));
    final game = await _start(_flat(mobs: const [night, day], sky: const SkySpec(startTime: 0.0, cycle: false)));
    game.spawner
      ..enabled = true
      ..minDistance = 6
      ..maxDistance = 14;
    await _run(game, 20.0);
    expect(game.mobs.where((m) => m.spec.id == 'ghoul'), isNotEmpty);
    expect(game.mobs.where((m) => m.spec.id == 'cow'), isEmpty);
  });

  test('water poured on the ground flows and a system runs every step', () async {
    var steps = 0;
    final spec = _flat();
    final withSystem = VoxelGameSpec(
      blocks: spec.blocks,
      world: spec.world,
      sky: spec.sky,
      systems: () => [_EveryStep(() => steps++)],
    );
    final game = await _start(withSystem);
    final at = IVec3.floor(game.player.position) + const IVec3(3, 0, 3);
    game.world.setBlockNamed(at, 'water');
    await _run(game, 3.0);
    expect(game.world.blockNameAt(at + const IVec3(1, 0, 0)), 'water_flow');
    expect(steps, greaterThan(100));
  });

  test('a saved world comes back: its edits, its player, its bag and its clock', () async {
    final dir = Directory.systemTemp.createTempSync('voxel_saves');
    addTearDown(() => dir.deleteSync(recursive: true));
    final saves = WorldSaves(dir);
    final game = await _start(_flat(player: const PlayerSpec(startingItems: {'planks': 5})));
    final p = game.player;
    final cell = IVec3.floor(p.position) + const IVec3(2, 0, 0);
    game.world.setBlockNamed(cell, 'planks');
    p.inventory.remove('planks', 2);
    game.input.hold(VoxelAction.moveForward, true);
    await _run(game, 0.5);
    game.input.hold(VoxelAction.moveForward, false);
    await _run(game, 0.3);
    p.yaw = 1.25;
    game.timeOfDay = 0.8;
    final where = p.position.clone();
    saves.save(game, 'slot1');
    expect(saves.list(), ['slot1']);

    final back = await VoxelGame.startHeadless(
      _flat(player: const PlayerSpec(startingItems: {'planks': 5})),
      save: saves.read('slot1'),
    );
    back.spawner.enabled = false;
    for (var i = 0; i < 600 && !back.ready; i++) {
      back.frame(1 / 60);
      await Future<void>.delayed(Duration.zero);
    }
    expect(back.world.blockNameAt(cell), 'planks');
    expect(back.player.position.distanceTo(where), lessThan(0.05));
    expect(back.player.yaw, 1.25);
    expect(back.player.inventory.countOf('planks'), 3);
    expect(back.timeOfDay, closeTo(0.8, 1e-9));
    saves.delete('slot1');
    expect(saves.list(), isEmpty);
  });

  test('the player is heard: steps by the ground, digging, breaking and placing by material', () async {
    final game = await _start(_flat(player: const PlayerSpec(startingItems: {'planks': 2})));
    final heard = game.sounds as SilentSounds;
    final p = game.player;
    game.input.hold(VoxelAction.moveForward, true);
    await _run(game, 1.0);
    game.input.hold(VoxelAction.moveForward, false);
    expect(
      heard.played.where((s) => s == 'step_earth').length,
      greaterThanOrEqualTo(2),
      reason: 'grass is dug with a shovel: earth',
    );
    p.pitch = -1.5;
    game.input.hold(VoxelAction.attack, true);
    await _run(game, 2.0);
    game.input.hold(VoxelAction.attack, false);
    expect(heard.played, contains('dig'));
    expect(heard.played, contains('break_earth'));
    p.pitch = -0.9;
    await _run(game, 0.2);
    game.input.tap(VoxelAction.use);
    await _run(game, 0.1);
    expect(heard.played, contains('place_wood'), reason: 'planks are cut with an axe: wood');
    expect(game.soundFamily(game.blocks.indexOf('water')), SoundFamily.liquid);
    expect(game.soundFamily(game.blocks.indexOf('stone')), SoundFamily.stone);
  });

  test('declared circuits: a lever lights a lamp down a wire, a plate under the player too, TNT blows', () async {
    const blocks = [
      ..._blocks,
      BlockType('wire', color: 0x701010, shape: BlockShape.wire, solid: false, hardness: 0),
      BlockType('wire_lit', color: 0xFF3020, shape: BlockShape.wire, solid: false, hardness: 0, light: 3),
      BlockType('lever', color: 0x806040, shape: BlockShape.torch, solid: false, hardness: 0),
      BlockType('lever_on', color: 0xA08060, shape: BlockShape.torch, solid: false, hardness: 0),
      BlockType('lamp', color: 0x604020),
      BlockType('lamp_lit', color: 0xFFD080, light: 15),
      BlockType('plate', color: 0x909090, shape: BlockShape.slab, hardness: 0.5),
      BlockType('tnt', color: 0xD03020, hardness: 0),
    ];
    final spec = _flat();
    final game = await _start(
      VoxelGameSpec(
        blocks: blocks,
        world: spec.world,
        sky: spec.sky,
        signals: const SignalSpec(
          wire: ('wire', 'wire_lit'),
          levers: {'lever': 'lever_on'},
          plates: {'plate'},
          lamps: {'lamp': 'lamp_lit'},
          explosives: {'tnt': Explosive(radius: 2.0, damage: 8.0)},
        ),
      ),
    );
    final w = game.world;
    final base = IVec3.floor(game.player.position) + const IVec3(3, 0, 0);
    w.setBlockNamed(base, 'lever');
    for (var i = 1; i <= 4; i++) {
      w.setBlockNamed(base + IVec3(i, 0, 0), 'wire');
    }
    w.setBlockNamed(base + const IVec3(5, 0, 0), 'lamp');
    await _run(game, 0.3);
    expect(w.blockNameAt(base + const IVec3(5, 0, 0)), 'lamp');
    game.signals!.use(base);
    await _run(game, 0.3);
    expect(w.blockNameAt(base + const IVec3(2, 0, 0)), 'wire_lit');
    expect(w.blockNameAt(base + const IVec3(5, 0, 0)), 'lamp_lit');

    // A plate under the player's feet powers the lamp beside it.
    final feet = IVec3.floor(game.player.position);
    w.setBlockNamed(feet + const IVec3(0, -1, 0), 'stone');
    w.setBlockNamed(feet + const IVec3(0, 0, -2), 'lamp');
    w.setBlockNamed(feet + const IVec3(0, 0, -1), 'plate');
    game.player.position = Vector3(feet.x + 0.5, feet.y + 0.6, feet.z - 0.5);
    await _run(game, 0.5);
    expect(w.blockNameAt(feet + const IVec3(0, 0, -2)), 'lamp_lit');

    // TNT beside the lit wire is lit, and goes off when its fuse runs out.
    w.setBlockNamed(base + const IVec3(2, 0, 1), 'tnt');
    await _run(game, 0.3);
    expect(w.blockNameAt(base + const IVec3(2, 0, 1)), 'air');
    expect(game.entities.whereType<LitExplosive>(), hasLength(1));
    expect(w.blockNameAt(base + const IVec3(2, -1, 1)), isNot('air'), reason: 'still burning');
    await _run(game, 3.0);
    expect(game.entities.whereType<LitExplosive>(), isEmpty);
    expect(w.blockNameAt(base + const IVec3(2, -1, 1)), 'air', reason: 'the ground under it went with it');
  });

  const pistonBlocks = [
    ..._blocks,
    BlockType('wire', color: 0x701010, shape: BlockShape.wire, solid: false, hardness: 0),
    BlockType('wire_lit', color: 0xFF3020, shape: BlockShape.wire, solid: false, hardness: 0, light: 3),
    BlockType('lever', color: 0x806040, shape: BlockShape.torch, solid: false, hardness: 0),
    BlockType('lever_on', color: 0xA08060, shape: BlockShape.torch, solid: false, hardness: 0),
    BlockType(
      'piston',
      color: 0x9E8056,
      hardness: 1.5,
      facing: Facing.compass(north: 'piston', east: 'piston_e', south: 'piston_s', west: 'piston_w'),
    ),
    BlockType('piston_e', color: 0x9E8056, hardness: 1.5, drop: 'piston'),
    BlockType('piston_s', color: 0x9E8056, hardness: 1.5, drop: 'piston'),
    BlockType('piston_w', color: 0x9E8056, hardness: 1.5, drop: 'piston'),
    BlockType('piston_out', color: 0x808088, hardness: 1.5, drop: 'piston'),
    BlockType('piston_e_out', color: 0x808088, hardness: 1.5, drop: 'piston'),
    BlockType('piston_s_out', color: 0x808088, hardness: 1.5, drop: 'piston'),
    BlockType('piston_w_out', color: 0x808088, hardness: 1.5, drop: 'piston'),
    BlockType('bedrock', color: 0x2A2A2E, hardness: -1),
    BlockType('chest', color: 0x8A5A2A, hardness: 2.0, storage: Storage()),
    BlockType('powered_rail', color: 0xB09048, shape: BlockShape.railEw, solid: false, hardness: 0.5),
    BlockType(
      'powered_rail_on',
      color: 0xFF8C40,
      shape: BlockShape.railEw,
      solid: false,
      hardness: 0.5,
      light: 4,
      drop: 'powered_rail',
    ),
    // A rail kind lays both straights (`Rails`).
    BlockType(
      'powered_rail_ns',
      color: 0xB09048,
      shape: BlockShape.railNs,
      solid: false,
      hardness: 0.5,
      drop: 'powered_rail',
    ),
    BlockType(
      'powered_rail_ns_on',
      color: 0xFF8C40,
      shape: BlockShape.railNs,
      solid: false,
      hardness: 0.5,
      light: 4,
      drop: 'powered_rail',
    ),
  ];
  const pistonSignals = SignalSpec(
    wire: ('wire', 'wire_lit'),
    levers: {'lever': 'lever_on'},
    pistons: {
      'piston': 'piston_out',
      'piston_e': 'piston_e_out',
      'piston_s': 'piston_s_out',
      'piston_w': 'piston_w_out',
    },
    poweredRails: {'powered_rail': 'powered_rail_on', 'powered_rail_ns': 'powered_rail_ns_on'},
  );
  VoxelGameSpec pistonSpec({List<BlockType> blocks = pistonBlocks, SignalSpec signals = pistonSignals}) {
    final flat = _flat();
    return VoxelGameSpec(blocks: blocks, world: flat.world, sky: flat.sky, signals: signals);
  }

  test('declared pistons push the way they face, pull their head back, and stop at what will not move', () async {
    final game = await _start(pistonSpec());
    final w = game.world;
    final base = IVec3.floor(game.player.position) + const IVec3(3, 0, 0);

    // East: a lever behind, a cobblestone in front.
    w.setBlockNamed(base, 'lever');
    w.setBlockNamed(base + const IVec3(1, 0, 0), 'piston_e');
    w.setBlockNamed(base + const IVec3(2, 0, 0), 'cobblestone');
    await _run(game, 0.3);
    expect(w.blockNameAt(base + const IVec3(1, 0, 0)), 'piston_e');
    game.signals!.use(base);
    await _run(game, 0.3);
    expect(w.blockNameAt(base + const IVec3(1, 0, 0)), 'piston_e_out');
    expect(w.blockNameAt(base + const IVec3(2, 0, 0)), 'air');
    expect(w.blockNameAt(base + const IVec3(3, 0, 0)), 'cobblestone', reason: 'pushed one cell east');
    game.signals!.use(base);
    await _run(game, 0.3);
    expect(w.blockNameAt(base + const IVec3(1, 0, 0)), 'piston_e', reason: 'unpowered, the head goes back');
    expect(w.blockNameAt(base + const IVec3(3, 0, 0)), 'cobblestone', reason: 'and pulls nothing with it');

    // North (the compass's first variant): bedrock, a chest, or a wall past the block keep it retracted.
    for (final (i, front, past) in [(0, 'bedrock', 'air'), (1, 'chest', 'air'), (2, 'cobblestone', 'stone')]) {
      final at = base + IVec3(-4 + i * 3, 0, 5);
      w.setBlockNamed(at + const IVec3(0, 0, 1), 'lever');
      w.setBlockNamed(at, 'piston');
      w.setBlockNamed(at + const IVec3(0, 0, -1), front);
      w.setBlockNamed(at + const IVec3(0, 0, -2), past);
      game.signals!.use(at + const IVec3(0, 0, 1));
      await _run(game, 0.3);
      expect(w.blockNameAt(at), 'piston', reason: '$front before $past does not move');
      expect(w.blockNameAt(at + const IVec3(0, 0, -1)), front);
    }

    // Nothing in front: the head comes out all the same.
    final free = base + const IVec3(0, 0, 10);
    w.setBlockNamed(free + const IVec3(0, 0, -1), 'lever_on');
    w.setBlockNamed(free, 'piston_s');
    await _run(game, 0.3);
    expect(w.blockNameAt(free), 'piston_s_out');
  });

  test('a declared run of powered rails is lit as far as its reach from the power', () async {
    final game = await _start(pistonSpec());
    final w = game.world;
    final base = IVec3.floor(game.player.position) + const IVec3(3, 0, 2);
    w.setBlockNamed(base, 'lever');
    for (var i = 1; i <= 12; i++) {
      w.setBlockNamed(base + IVec3(i, 0, 0), 'powered_rail');
    }
    await _run(game, 0.3);
    game.signals!.use(base);
    await _run(game, 0.3);
    for (var i = 1; i <= 12; i++) {
      expect(
        w.blockNameAt(base + IVec3(i, 0, 0)),
        i <= 9 ? 'powered_rail_on' : 'powered_rail',
        reason: 'rail $i: the first is powered, eight more carry it',
      );
    }
    game.signals!.use(base);
    await _run(game, 0.3);
    for (var i = 1; i <= 12; i++) {
      expect(w.blockNameAt(base + IVec3(i, 0, 0)), 'powered_rail');
    }
  });

  test('a declared piston must face somewhere', () async {
    final blocks = [
      for (final b in pistonBlocks) b.id == 'piston' ? const BlockType('piston', color: 0x9E8056, hardness: 1.5) : b,
    ];
    await expectLater(VoxelGame.startHeadless(pistonSpec(blocks: blocks)), throwsArgumentError);
  });

  test('the shoulder orbit comes in at once at a wall and goes out gently', () {
    final orbit = ShoulderOrbit();
    final pivot = Vector3(0.5, 1.5, 0.5), right = Vector3(1, 0, 0), up = Vector3(0, 1, 0), back = Vector3(0, 0, 1);
    bool open(int x, int y, int z) => true;
    bool walled(int x, int y, int z) => z != 2;
    orbit.settle(1 / 60, pivot: pivot, right: right, up: up, back: back, jitter: Vector3.zero(), cellIsClear: walled);
    expect(pivot.z + orbit.offset(right, up, back, orbit.current).z + ShoulderOrbit.eyeRadius, lessThanOrEqualTo(2.0));
    final pinned = orbit.current;
    orbit.settle(1 / 60, pivot: pivot, right: right, up: up, back: back, jitter: Vector3.zero(), cellIsClear: open);
    expect(orbit.current, greaterThan(pinned));
    expect(orbit.current, lessThan(orbit.distance));
    expect(
      orbit.offset(right, up, back, 0.0).length,
      lessThan(1e-9),
      reason: 'an eye pulled all the way in sits on the head',
    );
  });

  test('the view bob sways a walker and settles a stander', () {
    final bob = ViewBob();
    final right = Vector3(1, 0, 0), up = Vector3(0, 1, 0);
    for (var i = 0; i < 60; i++) {
      bob.update(1 / 60, walking: true, speed: 4.3, walkSpeed: 4.3, right: right, up: up);
    }
    expect(bob.weight, greaterThan(0.9));
    expect(bob.offset.y, lessThanOrEqualTo(0.0), reason: 'the eye drops, never rises');
    for (var i = 0; i < 120; i++) {
      bob.update(1 / 60, walking: false, speed: 0.0, walkSpeed: 4.3, right: right, up: up);
    }
    expect(bob.offset.length, 0.0);
    expect(bob.roll, 0.0);
  });

  test('a rig motion folds its wings at rest and beats a full sweep in the air', () {
    const motion = RigMotion(wingSweep: 0.95, wingFold: -0.95);
    expect(motion.wingAngle(1.3, 0.0), -0.95);
    expect(motion.wingAngle(1.5707963267948966, 1.0), closeTo(0.95, 1e-9));
    expect(
      RigMotion.gaitRateOf(RigKind.bird),
      greaterThan(RigMotion.gaitRateOf(RigKind.quadruped)),
      reason: 'short legs take more steps',
    );
  });

  test('frames moves once a frame, whether or not the frame ran a step', () async {
    final game = await _start(_flat());
    final before = game.frames.value;
    game.frame(1 / 240);
    game.frame(1 / 240);
    game.frame(1 / 60);
    expect(game.frames.value, before + 3);
  });

  test('a press waits for the step that reads it, however fast the frames come', () async {
    final game = await _start(_flat());
    await _run(game, 0.5);
    final slot = game.player.selectedSlot;
    // Two frames that each carry half a step: neither runs one, and above
    // 60 fps that is most of them. The press must survive to the third.
    game.input.touchDigit(slot == 3 ? 4 : 3);
    game.frame(1 / 240);
    game.frame(1 / 240);
    expect(game.player.selectedSlot, slot, reason: 'no step ran, so nothing read it');
    expect(game.input.digitPressed(), isNot(-1), reason: 'and nothing threw it away either');
    game.frame(1 / 60);
    expect(game.player.selectedSlot, slot == 3 ? 4 : 3, reason: 'the first step to run reads it');
    expect(game.input.digitPressed(), -1, reason: 'and that step drains it');
  });

  test('above 60 fps every frame moves the drawn player by the time it took, and turns the view', () async {
    final game = await _start(_flat());
    final p = game.player;
    await _run(game, 0.5);
    game.input.hold(VoxelAction.moveForward, true);
    await _run(game, 0.5);
    // 120 frames a second: a step every other frame.
    final drawn = <double>[];
    for (var i = 0; i < 24; i++) {
      game.frame(1 / 120);
      drawn.add(p.drawnPosition.z);
      final behind = p.drawnPosition.z - p.position.z; // walking toward -z
      expect(behind, greaterThanOrEqualTo(0.0), reason: 'drawn between the last two steps, never past the last');
      expect(behind, lessThan(p.spec.walkSpeed / 60 * 1.01), reason: 'at most a step behind');
    }
    game.input.hold(VoxelAction.moveForward, false);
    final moves = [for (var i = 1; i < drawn.length; i++) drawn[i - 1] - drawn[i]];
    final mean = moves.reduce((a, b) => a + b) / moves.length;
    expect(mean, greaterThan(0.0));
    for (final m in moves) {
      expect(m / mean, inInclusiveRange(0.8, 1.2), reason: 'a frame with no step still moves the drawn player');
    }
    expect(p.drawnEye.y - p.drawnPosition.y, closeTo(p.spec.eyeHeight, 1e-6));
    // The look is the frame's, not the step's: two frames too short for a
    // step each turn the view.
    final yaw = p.yaw;
    game.input.look(-10, 0);
    game.frame(1 / 480);
    expect(p.yaw, closeTo(yaw + 10 * game.input.lookSensitivity, 1e-9));
    game.input.look(-10, 0);
    game.frame(1 / 480);
    expect(p.yaw, closeTo(yaw + 20 * game.input.lookSensitivity, 1e-9));
    game.gameplay = false;
    game.input.look(-10, 0);
    game.frame(1 / 480);
    expect(p.yaw, closeTo(yaw + 20 * game.input.lookSensitivity, 1e-9), reason: 'no look behind a screen');
  });

  test('a respawn is drawn where the player stands up, not on the way there', () async {
    final game = await _start(_flat());
    final p = game.player;
    await _run(game, 0.5);
    game.input.hold(VoxelAction.moveForward, true);
    await _run(game, 1.0);
    game.input.hold(VoxelAction.moveForward, false);
    expect(p.position.distanceTo(p.spawnPoint), greaterThan(3.0));
    p.takeDamage(const Damage(1000, source: 'test'));
    expect(p.isDead, isTrue);
    for (var i = 0; i < 2000 && !game.canRespawn; i++) {
      game.frame(1 / 120);
    }
    game.respawn();
    expect(p.isDead, isFalse);
    expect(p.drawnPosition.distanceTo(p.spawnPoint), lessThan(1e-4));
    game.frame(1 / 120);
    expect(p.drawnPosition.distanceTo(p.spawnPoint), lessThan(0.05));
  });

  test('one press, one arbiter: the step opens and closes the bag, and only it', () async {
    final game = await _start(_flat());
    await _run(game, 0.5);
    game.input.tap(VoxelAction.inventory);
    await _run(game, 1 / 60);
    expect(game.screen.value, const BagScreen(), reason: 'the bag opens on the press the step read');
    game.input.tap(VoxelAction.inventory);
    await _run(game, 1 / 60);
    expect(game.screen.value, isNull, reason: 'and the same button closes it');
    // A press is spent once: the steps that follow read nothing.
    await _run(game, 0.2);
    expect(game.screen.value, isNull);
  });

  test('a frame builds one camera, the one the scene and the HUD project through', () async {
    final game = await _start(_flat());
    final p = game.player;
    p.pitch = 0.0;
    await _run(game, 0.1);
    final camera = game.camera();
    expect(game.camera(), same(camera), reason: 'asked twice in a frame, the same view');
    const size = Size(800, 600);
    final ahead = camera.worldToScreen(camera.position + p.forward * 5.0, size)!;
    expect(ahead.dx, closeTo(400, 1));
    expect(ahead.dy, closeTo(300, 1));
    final right = camera.worldToScreen(camera.position + p.forward * 5.0 + p.right, size)!;
    expect(right.dx, greaterThan(400), reason: 'the mirrored lens keeps right on the right');
    game.frame(1 / 60);
    expect(game.camera(), isNot(same(camera)));
    game.dispose();
  });

  test(
    "the frame culls by the camera's eye, which in third person is not the player's, and not before warm-up",
    () async {
      final game = await _start(_flat());
      game.player.cameraMode = CameraMode.thirdPerson;
      await _run(game, 0.5);
      expect(game.warmedUp, isFalse);
      expect(game.cullEye, isNull, reason: 'the warm-up must see every terrain pipeline');
      game.warmedUp = true;
      game.frame(1 / 60);
      expect(game.cullEye, game.camera().position);
      expect(game.cullEye!.distanceTo(game.player.eyePosition), greaterThan(1.0), reason: 'the orbit sits behind');
      game.dispose();
    },
  );

  test('a hit on a creature shows what it took', () async {
    const cow = MobSpec('cow', hp: 5, brain: []);
    final game = await _start(_flat(mobs: const [cow]));
    final m = game.spawnMob('cow', game.player.position + Vector3(0, 0, -3));
    m.takeDamage(const Damage(3));
    m.takeDamage(const Damage(4));
    expect([for (final n in game.damageNumbers.shown) n.amount], [3, 2], reason: 'no more than it had');
    expect(game.damageNumbers.shown.first.at.y, greaterThan(m.position.y + m.height), reason: 'over its head');
    await _run(game, DamageNumbers.seconds + 0.05);
    expect(game.damageNumbers.shown, isEmpty);
    game.dispose();
  });

  test('the boss is the nearest living one', () async {
    const cow = MobSpec('cow', brain: []);
    const brute = MobSpec('brute', hp: 40, brain: [], boss: true);
    final game = await _start(_flat(mobs: const [cow, brute]));
    final at = game.player.position;
    game.spawnMob('cow', at + Vector3(0, 0, -2));
    expect(game.boss, isNull);
    final far = game.spawnMob('brute', at + Vector3(0, 0, -12));
    final near = game.spawnMob('brute', at + Vector3(0, 0, 6));
    expect(game.boss, same(near));
    near.kill();
    expect(game.boss, same(far));
    game.dispose();
  });

  test('the camera in a liquid is in its block', () async {
    final game = await _start(_flat());
    await _run(game, 0.1);
    expect(game.eyeLiquid, isNull);
    game.world.setBlockNamed(IVec3.floor(game.camera().position), 'water');
    expect(game.eyeLiquid?.id, 'water');
    expect(game.liquid('water').tint, 0.25);
    expect(game.liquid('lava').tint, 0.55, reason: 'a kind not declared takes its default');
    expect(game.haze, same(LiquidSpec.water), reason: 'the view closes in under water');
    expect(game.liquid('lava').haze, same(LiquidSpec.lava));
    game.world.setBlockNamed(IVec3.floor(game.camera().position), 'air');
    expect(game.haze, isNull, reason: 'out of it, the distance fog');
    game.dispose();
    final clear = await _start(_flat().copyWith(liquids: const {'water': LiquidSpec(haze: null)}));
    await _run(clear, 0.1);
    clear.world.setBlockNamed(IVec3.floor(clear.camera().position), 'water');
    expect(clear.haze, isNull, reason: 'a liquid declared with none');
    clear.dispose();
  });

  test("an eye in a pool's top cell is in it under the drawn surface only, and in it under more water", () async {
    for (final (eyeHeight, under) in [(1.62, true), (1.95, false)]) {
      final game = await _start(_flat(player: PlayerSpec(eyeHeight: eyeHeight)));
      await _run(game, 0.5);
      final eye = game.camera().position;
      final cell = IVec3.floor(eye);
      expect(eye.y - cell.y > ChunkMesher.liquidTop, !under, reason: 'the eye ${eye.y} where the test wants it');
      game.world.setBlockNamed(cell, 'water');
      expect(game.eyeLiquid?.id, under ? 'water' : null, reason: 'the surface is drawn ${ChunkMesher.liquidTop} up');
      game.world.setBlockNamed(cell + const IVec3(0, 1, 0), 'water');
      expect(game.eyeLiquid?.id, 'water', reason: 'with water above, the cell is full');
      game.dispose();
    }
  });
}
