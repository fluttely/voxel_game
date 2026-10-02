import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_game/voxel_game.dart';

/// Fishing with a wait of exactly one second and a catch that is always a
/// fish, unless [catches] says otherwise.
FishingSpec _fishing({LootTable? catches}) => FishingSpec(
  rod: 'fishing_rod',
  catches: catches ?? const LootTable.oneOf([LootEntry('raw_fish', 1, 1, 1.0)]),
  minWait: 1.0,
  maxWait: 1.0,
);

/// Level grass at y 20 (the first air cell), no caves, no trees; water and
/// lava; a rod in the first slot, experience declared.
VoxelGameSpec _spec({FishingSpec? fishing}) => VoxelGameSpec(
  blocks: const [
    BlockType('stone', color: 0x808080, hardness: 1.5),
    BlockType('dirt', color: 0x74502F, hardness: 0.5),
    BlockType('grass', color: 0x4C9437, hardness: 0.6, drop: 'dirt'),
    BlockType.liquid('water', color: 0x3366CC),
    BlockType.liquid('lava', color: 0xE05010, light: 15),
  ],
  world: const WorldGenSpec(
    terrain: TerrainRecipe.flat(20),
    seaLevel: 5,
    caves: CaveSpec.none,
    biomes: [Biome('plains', top: 'grass', under: 'dirt')],
  ),
  items: const [
    ItemType('fishing_rod', color: 0x9E7340, stack: 1),
    ItemType('raw_fish', color: 0x99B3BF, food: Food(hunger: 2)),
    ItemType('stick', color: 0x9A7040, stack: 64),
  ],
  fishing: fishing ?? _fishing(),
  player: const PlayerSpec(xp: XpSpec(), startingItems: {'fishing_rod': 1}),
  sky: SkySpec.alwaysDay,
);

Future<VoxelGame> _start(VoxelGameSpec spec) async {
  final game = await VoxelGame.startHeadless(spec);
  game.spawner.enabled = false;
  for (var i = 0; i < 600 && !game.ready; i++) {
    game.frame(1 / 60);
    await Future<void>.delayed(Duration.zero);
  }
  expect(game.ready, isTrue, reason: 'the spawn chunk loads and the player stands on it');
  game.player.selectedSlot = game.player.inventory.find('fishing_rod');
  return game;
}

/// [seconds] of simulation, letting the chunk jobs land between frames.
Future<void> _run(VoxelGame game, double seconds) async {
  for (var t = 0.0; t < seconds; t += 1 / 60) {
    game.frame(1 / 60);
    await Future<void>.delayed(Duration.zero);
  }
}

/// A pool of [liquid] two deep (y 18..19) east of the player, x +3..+8 and z
/// -2..+2 from its feet; returns its middle column's top cell.
IVec3 _pool(VoxelGame game, {String liquid = 'water'}) {
  final feet = IVec3.floor(game.player.position);
  for (var x = 3; x <= 8; x++) {
    for (var z = -2; z <= 2; z++) {
      for (var y = 18; y <= 19; y++) {
        game.world.setBlockNamed(IVec3(feet.x + x, y, feet.z + z), liquid);
      }
    }
  }
  return IVec3(feet.x + 5, 19, feet.z);
}

/// Turns the player to look at [at].
void _lookAt(VoxelGame game, Vector3 at) {
  final p = game.player;
  final to = at - p.eyePosition;
  p.yaw = math.atan2(-to.x, -to.z);
  p.pitch = math.atan2(to.y, Vector3(to.x, 0, to.z).length);
}

/// Looks at [cell]'s top and uses what is in hand.
Future<void> _useAt(VoxelGame game, IVec3 cell) async {
  _lookAt(game, Vector3(cell.x + 0.5, cell.y + 0.9, cell.z + 0.5));
  game.input.tap(VoxelAction.use);
  await _run(game, 0.05);
}

void main() {
  test('the rod casts at the water along the aim: the float arcs there and floats; on land it says where to', () async {
    final game = await _start(_spec());
    final p = game.player;
    final pool = _pool(game);
    await _useAt(game, IVec3.floor(p.position) + const IVec3(-3, -1, 0));
    expect(p.bobber, isNull);
    expect(game.notices.feed.last.text, 'Cast at water');

    await _useAt(game, pool);
    final b = p.bobber!;
    expect(game.entities, contains(b));
    expect(b.target, Vector3(pool.x + 0.5, pool.y + 0.85, pool.z + 0.5), reason: 'on the surface');
    expect(b.landed, isFalse);
    var highest = b.position.y;
    for (var i = 0; i < 40 && !b.landed; i++) {
      await _run(game, 1 / 60);
      highest = math.max(highest, b.position.y);
    }
    expect(b.landed, isTrue, reason: 'a flight takes under half a second');
    expect(highest, greaterThan(b.target.y + 1.0), reason: 'it flies in an arc');
    await _run(game, 0.5);
    expect(b.position.x, b.target.x);
    expect(b.position.z, b.target.z);
    expect(b.position.y, closeTo(b.target.y, 0.06), reason: 'bobbing on the surface');
    expect(b.biting, isFalse, reason: 'nothing bites before the wait');
    expect(() => Bobber(b.spec, p, b.target, b.target).bite(), throwsStateError, reason: 'not landed');
  });

  test('something bites after the wait; a use then lands the catch in the bag and experience, a use before or after reels in empty', () async {
    final game = await _start(_spec());
    final p = game.player;
    final pool = _pool(game);
    await _useAt(game, pool);
    await _run(game, 0.5);
    game.input.tap(VoxelAction.use);
    await _run(game, 0.05);
    expect(p.bobber, isNull, reason: 'nothing bit');
    expect(game.notices.feed.last.text, 'Reeled in');
    expect(p.inventory.countOf('raw_fish'), 0);

    await _useAt(game, pool);
    final b = p.bobber!;
    for (var i = 0; i < 120 && !b.biting; i++) {
      await _run(game, 1 / 60);
    }
    expect(b.biting, isTrue, reason: 'a second after it landed');
    expect(game.notices.feed.last.text, 'Something bites!');
    await _run(game, 0.5);
    expect(b.position.y, lessThan(b.target.y - 0.1), reason: 'it dips');
    final xp = p.xp;
    game.input.tap(VoxelAction.use);
    await _run(game, 0.05);
    expect(p.inventory.countOf('raw_fish'), 1);
    expect(p.xp, xp + 2);
    expect(p.bobber, isNull);
    expect(b.removed, isTrue);
    await _run(game, 0.05);
    expect(game.entities, isNot(contains(b)));

    // A bite let pass: the float comes up, and a use reels in empty.
    await _useAt(game, pool);
    final again = p.bobber!;
    for (var i = 0; i < 120 && !again.biting; i++) {
      await _run(game, 1 / 60);
    }
    await _run(game, again.spec.bite + 0.1);
    expect(again.biting, isFalse);
    game.input.tap(VoxelAction.use);
    await _run(game, 0.05);
    expect(p.inventory.countOf('raw_fish'), 1, reason: 'too late');
  });

  test('a catch the bag cannot hold falls on the ground', () async {
    final game = await _start(_spec(fishing: _fishing(catches: const LootTable([LootEntry('stick', 3, 3, 1.0)]))));
    final p = game.player;
    final pool = _pool(game);
    // Every slot but the rod's full of sticks, the last but two.
    p.inventory.add('stick', (p.inventory.capacity - 1) * 64 - 2);
    await _useAt(game, pool);
    for (var i = 0; i < 120 && !p.bobber!.biting; i++) {
      await _run(game, 1 / 60);
    }
    game.input.tap(VoxelAction.use);
    await _run(game, 0.05);
    final dropped = game.entities.whereType<ItemPickup>().where((d) => d.stack.id == 'stick');
    expect(dropped.fold(0, (n, d) => n + d.stack.count), 1, reason: 'two filled the last stack');
  });

  test('the line is reeled in when the rod leaves the hand, and when the player leaves it behind', () async {
    final game = await _start(_spec());
    final p = game.player;
    final pool = _pool(game);
    await _useAt(game, pool);
    expect(p.bobber, isNotNull);
    p.selectedSlot = (p.selectedSlot + 1) % p.inventory.hotbarSize;
    await _run(game, 0.05);
    expect(p.bobber, isNull);

    p.selectedSlot = p.inventory.find('fishing_rod');
    await _useAt(game, pool);
    final b = p.bobber!;
    p.position = p.position + Vector3(-2 * b.spec.reach - 2, 0, 0);
    await _run(game, 0.1);
    expect(p.bobber, isNull);
    expect(b.removed, isTrue);
  });

  test('a line is cast only at the spec\'s liquids', () async {
    final game = await _start(_spec());
    final pool = _pool(game, liquid: 'lava');
    await _useAt(game, pool);
    expect(game.player.bobber, isNull);
    expect(game.notices.feed.last.text, 'Cast at water');
  });

  test('fishing is checked at start: the rod, the catches, the liquids, the experience', () {
    void check(VoxelGameSpec spec) {
      final blocks = spec.buildBlocks();
      spec.checkFishing(blocks, spec.buildItems(blocks));
    }

    final spec = _spec();
    check(spec);
    check(spec.copyWith(fishing: () => null));
    FishingSpec f({String rod = 'fishing_rod', LootTable? catches, Set<String> liquids = const {'water'}}) =>
        FishingSpec(
          rod: rod,
          catches: catches ?? const LootTable.oneOf([LootEntry('raw_fish', 1, 1, 0.7)]),
          liquids: liquids,
        );
    expect(
      () => check(spec.copyWith(fishing: () => f(rod: 'net'))),
      throwsArgumentError,
      reason: 'no such item',
    );
    expect(
      () => check(spec.copyWith(fishing: () => f(rod: 'stone'))),
      throwsArgumentError,
      reason: 'a block',
    );
    expect(
      () => check(spec.copyWith(fishing: () => f(catches: const LootTable([LootEntry('pearl', 1, 1, 0.1)])))),
      throwsArgumentError,
      reason: 'a catch that is no item',
    );
    expect(
      () => check(
        spec.copyWith(
          fishing: () =>
              f(catches: const LootTable.oneOf([LootEntry('raw_fish', 1, 1, 0.7), LootEntry('stick', 1, 1, 0.5)])),
        ),
      ),
      throwsArgumentError,
      reason: 'one-of chances over 1',
    );
    expect(
      () => check(spec.copyWith(fishing: () => f(liquids: {'oil'}))),
      throwsArgumentError,
      reason: 'no oil',
    );
    expect(
      () => check(spec.copyWith(player: const PlayerSpec())),
      throwsArgumentError,
      reason: 'experience with no curve declared',
    );
    check(
      spec.copyWith(
        player: const PlayerSpec(),
        fishing: () => const FishingSpec(rod: 'fishing_rod', catches: LootTable([]), xp: 0),
      ),
    );
  });
}
