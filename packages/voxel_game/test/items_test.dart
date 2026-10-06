import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_game/voxel_game.dart';

import 'support/heard.dart';

const _blocks = [
  BlockType('stone', color: 0x808080, hardness: 1.5),
  BlockType('dirt', color: 0x74502F, hardness: 0.5),
  BlockType('grass', color: 0x4C9437, hardness: 0.6, drop: 'dirt'),
  BlockType('leaves', color: 0x3F8A2E, hardness: 0.2, tags: {'leaves'}, loot: LootTable([])),
  BlockType('torch', color: 0xFFD070, shape: BlockShape.torch, solid: false, hardness: 0, light: 14),
  BlockType('bed', color: 0xC03030, shape: BlockShape.slab, hardness: 0.5, bed: true),
  BlockType('portal', color: 0x8A3CF0, solid: false, hardness: -1, drop: '', holdable: false),
  BlockType.liquid('water', color: 0x3366CC),
];

const _items = [
  ItemType(
    'bow',
    color: 0x9A7040,
    stack: 1,
    durability: 50,
    launcher: Launcher(shot: 'arrow', ammo: 'arrow'),
  ),
  ItemType('arrow', color: 0xC8B090),
  ItemType('shears', color: 0xC0C0C8, tool: 'shears', stack: 1, durability: 40),
  ItemType('wool', color: 0xEEEEEE),
  ItemType('bucket', color: 0x8A6A40, stack: 16),
  ItemType('milk', color: 0xF4F4F0, stack: 1, food: Food(heal: 2.0, cures: true, leaves: 'bucket')),
  ItemType('lantern', color: 0xFFC060, light: 12),
];

/// A straight shot, so where it goes is where the player looks.
const _arrow = ProjectileSpec(speed: 30.0, gravity: 0.0, damage: 6.0, knockback: 0.0);

const _target = MobSpec('target', hp: 40, brain: []);
const _sheep = MobSpec('sheep', hp: 8, halfWidth: 0.45, height: 1.2, brain: [], fleece: Fleece('wool'));
const _cow = MobSpec('cow', hp: 10, halfWidth: 0.45, height: 1.4, brain: [], yields: {'bucket': 'milk'});

/// Level grass at y 20, no caves, no trees, the clock stopped at noon.
VoxelGameSpec _flat({Map<String, int> start = const {}, bool creative = false}) => VoxelGameSpec(
  blocks: _blocks,
  world: const WorldGenSpec(
    terrain: TerrainRecipe.flat(20),
    seaLevel: 5,
    caves: CaveSpec.none,
    biomes: [Biome('plains', top: 'grass', under: 'dirt')],
  ),
  items: _items,
  shots: const {'arrow': _arrow},
  effects: const [
    EffectType('poison', 'Poison', 0.3, 0.6, 0.2, period: 1.5, damage: 1.0, bad: true),
    EffectType('haste', 'Haste', 0.9, 0.8, 0.2, stats: {'speed': StatModifier.multiply(0.2)}),
  ],
  mining: const MiningRules(
    cuts: {
      'shears': {'leaves'},
    },
  ),
  player: PlayerSpec(startingItems: start, creative: creative),
  mobs: const [_target, _sheep, _cow],
  sky: SkySpec.alwaysDay,
  systems: () => [Heard()],
);

Future<VoxelGame> _start(VoxelGameSpec spec) async {
  final game = await VoxelGame.startHeadless(spec);
  game.spawner.enabled = false;
  for (var i = 0; i < 600 && !game.ready; i++) {
    game.frame(1 / 60);
    await Future<void>.delayed(Duration.zero);
  }
  expect(game.ready, isTrue);
  return game;
}

Future<void> _run(VoxelGame game, double seconds) async {
  for (var t = 0.0; t < seconds; t += 1 / 60) {
    game.frame(1 / 60);
    await Future<void>.delayed(Duration.zero);
  }
}

/// Puts a creature of [id] [ahead] metres in front of the player and turns
/// the player's eye to its middle.
Mob _ahead(VoxelGame game, String id, double ahead) {
  final p = game.player;
  final mob = game.spawnMob(id, p.position + Vector3(0, 0, -ahead));
  final to = mob.centre() - p.eyePosition;
  p.yaw = 0.0;
  p.pitch = math.atan2(to.y, ahead);
  return mob;
}

/// Hands the player one [item] in the hotbar's last slot, clear of what
/// they started with.
void _hold(VoxelGame game, String item) {
  final p = game.player;
  p.selectedSlot = p.inventory.hotbarSize - 1;
  p.inventory.setSlot(p.selectedSlot, ItemStack(item, 1));
}

/// The stack in the player's hand.
ItemStack _inHand(VoxelGame game) => game.player.inventory.slots[game.player.selectedSlot]!;

Iterable<Projectile> _shots(VoxelGame game) => game.entities.whereType<Projectile>().where((s) => !s.removed);

void main() {
  test('a bow shoots its shot where the player looks, spending an arrow and wearing, once a cooldown', () async {
    final game = await _start(_flat(start: {'arrow': 3}));
    final p = game.player;
    _hold(game, 'bow');
    p.yaw = 0.0;
    p.pitch = 0.0;
    await _run(game, 0.1);
    expect(game.input.touchTapPrimary, isTrue, reason: 'a finger\'s tap with a bow in hand shoots');
    game.input.tap(VoxelAction.attack);
    await _run(game, 0.05);
    final shot = _shots(game).single;
    expect(shot.spec, same(_arrow));
    expect(shot.owner, same(p));
    expect(shot.velocity.z, closeTo(-30.0, 1e-6), reason: 'straight on: no aim over a drop');
    expect(shot.velocity.y, closeTo(0.0, 1e-6));
    expect(p.inventory.countOf('arrow'), 2);
    expect(_inHand(game).dur, 49, reason: 'the bow wears a shot');
    // Held, it shoots once a cooldown (0.5 s): two more, and then the bag is out of arrows.
    game.input.hold(VoxelAction.attack, true);
    await _run(game, 0.5);
    expect(p.inventory.countOf('arrow'), 1);
    await _run(game, 1.0);
    game.input.hold(VoxelAction.attack, false);
    expect(p.inventory.countOf('arrow'), 0);
    expect(game.notices.feed.last.text, 'No arrow to shoot', reason: 'told once the hold runs dry');
    expect(p.aimedBlock, isNull, reason: 'it mined nothing: a bow does not dig');
    final told = game.notices.feed.length;
    final before = game.entities.whereType<Projectile>().length;
    await _run(game, 0.6);
    game.input.tap(VoxelAction.attack);
    await _run(game, 0.1);
    expect(game.entities.whereType<Projectile>().length, lessThanOrEqualTo(before), reason: 'no arrow, no shot');
    expect(game.notices.feed.length, told + 1, reason: 'a press is told again');
    game.dispose();
  });

  test('the player\'s shot is multiplied, and filtered by their damage filters, as a swing is', () async {
    final game = await _start(_flat(start: {'arrow': 4}));
    final p = game.player;
    _hold(game, 'bow');
    final target = _ahead(game, 'target', 5.0);
    await _run(game, 0.1);
    p.boosts['class'] = const Boost(damage: 2.0);
    p.damageOut['half'] = (mob, amount) => amount / 2;
    game.input.tap(VoxelAction.attack);
    await _run(game, 0.5);
    expect(target.hp, 40.0 - 6.0 * 2.0 / 2.0);
    expect(target.lastHurtBy, same(p));
    game.dispose();
  });

  test('a game refuses a shot it cannot pay for, saying why, and pays for each that goes', () async {
    final game = await _start(_flat(start: {'arrow': 5}));
    final p = game.player;
    _hold(game, 'bow');
    p.pitch = 0.0;
    await _run(game, 0.1);
    var mana = 1;
    p.shotVetoes['mana'] = (launcher) => launcher.id == 'bow' && mana <= 0 ? 'Not enough mana' : null;
    game.input.tap(VoxelAction.attack);
    await _run(game, 0.05);
    final paid = game.system<Heard>().events.whereType<ShotFired>().toList();
    expect(paid.single.launcher.id, 'bow');
    mana = 0;
    game.input.hold(VoxelAction.attack, true);
    await _run(game, 1.2);
    game.input.hold(VoxelAction.attack, false);
    expect(_shots(game), hasLength(1), reason: 'refused: no shot');
    expect(p.inventory.countOf('arrow'), 4, reason: 'and no arrow spent');
    expect(game.notices.feed.where((n) => n.text == 'Not enough mana'), hasLength(1), reason: 'told once a hold');
    expect(game.system<Heard>().events.whereType<ShotFired>(), hasLength(1));
    game.dispose();
  });

  test('a creative player shoots without arrows', () async {
    final game = await _start(_flat(creative: true));
    _hold(game, 'bow');
    game.player.pitch = 0.0;
    await _run(game, 0.1);
    game.input.tap(VoxelAction.attack);
    await _run(game, 0.05);
    expect(_shots(game), hasLength(1));
    expect(_inHand(game).dur, -1, reason: 'nothing wears in creative');
    game.dispose();
  });

  test('what the hand holds gives its light: a block\'s item its block\'s, an item its own', () async {
    final game = await _start(_flat());
    final p = game.player;
    expect(game.items['torch'].light, 14);
    _hold(game, 'torch');
    expect(p.heldLight, 14);
    _hold(game, 'lantern');
    expect(p.heldLight, 12);
    _hold(game, 'stone');
    expect(p.heldLight, 0);
    p.inventory.setSlot(p.selectedSlot, null);
    expect(p.heldLight, 0, reason: 'an empty hand');
    game.dispose();
  });

  test('a food that cures ends the bad effects, keeps the good ones and the boosts, and is eaten for it', () async {
    final game = await _start(_flat());
    final p = game.player;
    _hold(game, 'milk');
    expect(p.canEat(game.items['milk']), isFalse, reason: 'whole and well: it would do nothing');
    p.effects
      ..apply('poison', 20)
      ..apply('haste', 20);
    p.boosts['class'] = const Boost(speed: 1.5);
    expect(p.canEat(game.items['milk']), isTrue, reason: 'something to cure');
    expect(p.eatHeld(), isTrue);
    expect(p.effects.has('poison'), isFalse);
    expect(p.effects.has('haste'), isTrue);
    expect(p.boosts, contains('class'));
    expect(p.inventory.countOf('bucket'), 1, reason: 'the milk leaves its bucket');
    game.dispose();
  });

  test('shears cut leaves at once and get the leaves, whatever the leaves drop', () async {
    final game = await _start(_flat());
    final p = game.player;
    final cell = IVec3.floor(p.position) + IVec3(0, 0, -2);
    game.world.setBlockNamed(cell, 'leaves');
    p.yaw = 0.0;
    p.pitch = -0.45;
    _hold(game, 'shears');
    await _run(game, 0.1);
    expect(p.aimedBlock?.block, cell);
    game.input.hold(VoxelAction.attack, true);
    await _run(game, 0.2);
    game.input.hold(VoxelAction.attack, false);
    expect(game.world.blockNameAt(cell), 'air');
    expect(game.entities.whereType<ItemPickup>().map((d) => d.stack.id), ['leaves']);
    expect(_inHand(game).dur, 39);
    // By hand the leaves' own loot drops: nothing.
    game.world.setBlockNamed(cell, 'leaves');
    final drops = game.entities.whereType<ItemPickup>().length;
    game.breakBlock(cell, dropFor: null);
    expect(game.world.blockNameAt(cell), 'air');
    expect(game.entities.whereType<ItemPickup>(), hasLength(drops));
    game.dispose();
  });

  test('shears shear a creature\'s fleece, which grows back', () async {
    final game = await _start(_flat());
    final p = game.player;
    final sheep = _ahead(game, 'sheep', 2.0);
    await _run(game, 0.1);
    expect(p.aimedMob, same(sheep));
    expect(p.usableOn(sheep), isFalse, reason: 'nothing in hand shears it');
    _hold(game, 'shears');
    expect(p.usableOn(sheep), isTrue);
    game.input.tap(VoxelAction.use);
    await _run(game, 0.1);
    expect(sheep.shorn, isTrue);
    final wool = game.entities.whereType<ItemPickup>().where((d) => d.stack.id == 'wool').single;
    expect(wool.stack.count, inInclusiveRange(1, 3));
    expect(_inHand(game).dur, 39, reason: 'the shears wear');
    expect(p.usableOn(sheep), isFalse, reason: 'shorn: nothing to shear');
    expect(sheep.shear, throwsStateError);
    expect(sheep.hp, 8.0, reason: 'a use, not a blow');
    sheep.shornLeft = 0.5;
    await _run(game, 0.6);
    expect(sheep.shorn, isFalse, reason: 'grown back');
    expect(p.usableOn(sheep), isTrue);
    game.dispose();
  });

  test('a creature yields for the item in hand: a bucket on a cow is milk', () async {
    final game = await _start(_flat(start: {'bucket': 2}));
    final p = game.player;
    p.selectedSlot = p.inventory.slots.indexWhere((s) => s?.id == 'bucket');
    final cow = _ahead(game, 'cow', 2.0);
    await _run(game, 0.1);
    expect(p.usableOn(cow), isTrue);
    game.input.tap(VoxelAction.use);
    await _run(game, 0.1);
    expect(p.inventory.countOf('bucket'), 1);
    expect(p.inventory.countOf('milk'), 1);
    expect(p.usableOn(game.spawnMob('sheep', cow.position + Vector3(3, 0, 0))), isFalse);
    game.dispose();
  });

  test('a bed sets the spawn; at night the player sleeps, and when all sleep the night passes', () async {
    final game = await _start(_flat());
    final heard = game.system<Heard>();
    final p = game.player;
    final stand = p.position.clone();
    final bed = IVec3.floor(p.position) + IVec3(0, 0, -2);
    game.world.setBlockNamed(bed, 'bed');
    p.yaw = 0.0;
    p.pitch = -0.45;
    await _run(game, 0.1);
    expect(p.aimedBlock?.block, bed);
    game.input.tap(VoxelAction.use);
    await _run(game, 0.1);
    expect(p.sleeping, isFalse, reason: 'a bed sleeps only at night');
    expect(p.spawnPoint.x, bed.x + 0.5);
    expect(p.spawnPoint.z, bed.z + 0.5);
    game.timeOfDay = 0.9;
    game.input.tap(VoxelAction.use);
    await _run(game, 0.1);
    expect(p.sleeping, isTrue);
    expect(p.bed, bed);
    expect(p.eyePosition.y - p.position.y, closeTo(0.3, 1e-5), reason: 'the head on the pillow');
    // A jump gets up before the night passes.
    game.input.tap(VoxelAction.jump);
    await _run(game, 0.1);
    expect(p.sleeping, isFalse);
    p.placeAt(stand);
    await _run(game, 0.1);
    game.input.tap(VoxelAction.use);
    await _run(game, 0.1);
    expect(p.sleeping, isTrue);
    await _run(game, VoxelGame.sleepSeconds + 0.2);
    expect(game.timeOfDay, VoxelGame.morning);
    expect(p.sleeping, isFalse, reason: 'up with the morning');
    expect(heard.events.whereType<Slept>().single.bed, bed);
    game.dispose();
  });

  test('a blow wakes the sleeper, and nobody sleeps while hunted', () async {
    final game = await _start(_flat());
    final p = game.player;
    final bed = IVec3.floor(p.position) + IVec3(0, 0, -2);
    game.world.setBlockNamed(bed, 'bed');
    game.timeOfDay = 0.1;
    p.yaw = 0.0;
    p.pitch = -0.45;
    await _run(game, 0.1);
    final hunter = game.spawnMob('target', p.position + Vector3(4, 0, 0))..target = p;
    game.input.tap(VoxelAction.use);
    await _run(game, 0.1);
    expect(p.sleeping, isFalse, reason: 'something hunts them');
    hunter.target = null;
    game.input.tap(VoxelAction.use);
    await _run(game, 0.1);
    expect(p.sleeping, isTrue);
    p.takeDamage(const Damage(1.0, source: 'test'));
    expect(p.sleeping, isFalse);
    expect(p.wake, throwsStateError);
    game.dispose();
  });

  test('a block only the world makes is no item, and what a block drops must be one', () {
    final spec = _flat();
    final items = spec.buildItems(spec.buildBlocks());
    expect(items.has('portal'), isFalse);
    expect(items.has('bed'), isTrue);
    final selfDrop = spec.copyWith(
      blocks: [..._blocks, const BlockType('rail_ne', color: 0x8A8478, hardness: 0.7, holdable: false)],
    );
    expect(() => selfDrop.buildItems(selfDrop.buildBlocks()), throwsArgumentError, reason: 'it drops itself');
    final dropsRail = spec.copyWith(
      blocks: [
        ..._blocks,
        const BlockType('rail_ne', color: 0x8A8478, hardness: 0.7, drop: 'rail', holdable: false),
      ],
    );
    expect(() => dropsRail.buildItems(dropsRail.buildBlocks()), throwsArgumentError, reason: 'no rail item');
    final cutHidden = spec.copyWith(
      blocks: [
        ..._blocks,
        const BlockType('vine', color: 0x3F8A2E, hardness: 0.2, tags: {'leaves'}, drop: '', holdable: false),
      ],
    );
    expect(() => cutHidden.buildItems(cutHidden.buildBlocks()), throwsArgumentError, reason: 'shears would get it');
  });

  test('shots, fleeces, yields and beds are checked when the game is made', () async {
    final spec = _flat();
    final items = spec.buildItems(spec.buildBlocks());
    spec.checkShots(items);
    spec.checkMobs(items);
    expect(() => spec.copyWith(shots: const {}).checkShots(items), throwsArgumentError, reason: 'no such shot');
    VoxelGameSpec withItems(List<ItemType> more) => spec.copyWith(items: [..._items, ...more]);
    void shots(VoxelGameSpec s) => s.checkShots(s.buildItems(s.buildBlocks()));
    expect(
      () => shots(
        withItems(const [
          ItemType(
            'sling',
            color: 0,
            launcher: Launcher(shot: 'arrow', ammo: 'pebble'),
          ),
        ]),
      ),
      throwsArgumentError,
      reason: 'no such ammo',
    );
    void mobs(MobSpec m) => spec.copyWith(mobs: [m]).checkMobs(items);
    expect(() => mobs(const MobSpec('goat', yields: {'bucket': 'cream'})), throwsArgumentError);
    expect(
      () => mobs(const MobSpec('goat', yields: {'bucket': 'milk'}, tameWith: ['bucket'], tamedBrain: [Heel()])),
      throwsArgumentError,
      reason: 'the bucket tames it',
    );
    expect(() => mobs(const MobSpec('goat', fleece: Fleece('mohair'))), throwsArgumentError);
    expect(() => mobs(const MobSpec('goat', fleece: Fleece('wool', tool: 'clippers'))), throwsArgumentError);
    void uses(VoxelGameSpec s) => s.checkUses(s.buildBlocks());
    expect(() => uses(spec.copyWith(blockUses: {'bed': (game, cell) {}})), throwsArgumentError);
    expect(() => uses(spec.copyWith(mobUses: {'sheep': (game, mob) {}})), throwsArgumentError);
    expect(() => uses(spec.copyWith(mobUses: {'cow': (game, mob) {}})), throwsArgumentError);
    await expectLater(VoxelGame.startHeadless(spec.copyWith(shots: const {})), throwsArgumentError);
  });
}
