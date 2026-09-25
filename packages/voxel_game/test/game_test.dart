import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
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
VoxelGameSpec _flat({List<MobSpec> mobs = const [], PlayerSpec player = const PlayerSpec(), SkySpec sky = SkySpec.alwaysDay}) =>
    VoxelGameSpec(
      blocks: _blocks,
      world: const WorldGenSpec(
        terrain: TerrainRecipe.flat(20),
        seaLevel: 5,
        caves: CaveSpec.none,
        biomes: [Biome('plains', top: 'grass', under: 'dirt')],
      ),
      items: const [ItemType('wooden_pickaxe', color: 0xB08850, tool: 'pickaxe', tier: 1, stack: 1, durability: 60, damage: 3)],
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

void main() {
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
    expect(p.inventory.countOf('dirt'), greaterThanOrEqualTo(1), reason: 'grass drops dirt, and the drop flies to the player');
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
    const zombie = MobSpec('zombie',
        hp: 6, speed: 3.0, brain: [MeleeAttack(damage: 2), Hunt(range: 20), Wander()], drops: [Drop('dirt', 2, 2)]);
    final game = await _start(_flat(mobs: const [zombie], player: const PlayerSpec(startingItems: {'wooden_pickaxe': 1})));
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
    expect(m.pathsPlanned, inInclusiveRange(3, (3.0 / Mob.replanEvery).ceil() + 1),
        reason: 'a partial path walked to its end waits for the timer (180 steps ran)');
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
      onTick: (game, dt) => steps++,
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

    final back = await VoxelGame.startHeadless(_flat(player: const PlayerSpec(startingItems: {'planks': 5})), save: saves.read('slot1'));
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
    expect(heard.played.where((s) => s == 'step_earth').length, greaterThanOrEqualTo(2), reason: 'grass is dug with a shovel: earth');
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
    final game = await _start(VoxelGameSpec(
      blocks: blocks,
      world: spec.world,
      sky: spec.sky,
      signals: const SignalSpec(
        wire: ('wire', 'wire_lit'),
        levers: {'lever': 'lever_on'},
        plates: {'plate'},
        lamps: {'lamp': 'lamp_lit'},
        explosives: {'tnt': 2.0},
      ),
    ));
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

    // TNT beside the lit wire goes off.
    w.setBlockNamed(base + const IVec3(2, 0, 1), 'tnt');
    await _run(game, 0.3);
    expect(w.blockNameAt(base + const IVec3(2, 0, 1)), 'air');
    expect(w.blockNameAt(base + const IVec3(2, -1, 1)), 'air', reason: 'the ground under it went with it');
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
    expect(orbit.offset(right, up, back, 0.0).length, lessThan(1e-9), reason: 'an eye pulled all the way in sits on the head');
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
    expect(RigMotion.gaitRateOf(RigKind.bird), greaterThan(RigMotion.gaitRateOf(RigKind.quadruped)), reason: 'short legs take more steps');
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

  test('one press, one arbiter: the step opens and closes the bag, and only it', () async {
    final game = await _start(_flat());
    await _run(game, 0.5);
    game.input.tap(VoxelAction.inventory);
    await _run(game, 1 / 60);
    expect(game.openScreen.value, '', reason: 'the bag opens on the press the step read');
    game.input.tap(VoxelAction.inventory);
    await _run(game, 1 / 60);
    expect(game.openScreen.value, isNull, reason: 'and the same button closes it');
    // A press is spent once: the steps that follow read nothing.
    await _run(game, 0.2);
    expect(game.openScreen.value, isNull);
  });
}
