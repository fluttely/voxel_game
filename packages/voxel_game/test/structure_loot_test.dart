import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_game/voxel_game.dart';

const _blocks = [
  BlockType('stone', color: 0x808080, hardness: 1.5),
  BlockType('dirt', color: 0x74502F, hardness: 0.5),
  BlockType('grass', color: 0x4C9437, hardness: 0.6, drop: 'dirt'),
  BlockType('sandstone', color: 0xD8C88A, hardness: 0.8),
  // A chest's own loot: what a store outside any structure is found with.
  BlockType(
    'chest',
    color: 0x8A5A2A,
    hardness: 2.0,
    storage: Storage(loot: LootTable([LootEntry('stone', 1, 1, 1.0)])),
  ),
  BlockType.liquid('water', color: 0x3366CC),
];

const _items = [
  ItemType('gem', color: 0x40E0D0),
  ItemType('sword', color: 0xC0C0C8, tool: 'sword', damage: 4, stack: 1),
  ItemType(
    'bow',
    color: 0x9A7040,
    stack: 1,
    launcher: Launcher(shot: 'arrow', ammo: 'arrow'),
  ),
  ItemType('arrow', color: 0xC8B090),
];

const _temple = Temple(stone: 'sandstone', chest: 'chest');

/// A flat world with a temple in every region two chunks a side, its chests
/// holding gems and, every time, a sword with a bonus of 2 to 3.
const _spec = VoxelGameSpec(
  blocks: _blocks,
  items: _items,
  world: WorldGenSpec(
    terrain: TerrainRecipe.flat(20),
    seaLevel: 5,
    caves: CaveSpec.none,
    biomes: [Biome('plains', top: 'grass', under: 'dirt')],
    structures: [StructureSpec('temple', _temple, chance: 1.0, regionChunks: 2)],
  ),
  structureLoot: {
    'temple': StructureLoot(
      LootTable([LootEntry('gem', 2, 4, 1.0)]),
      bonus: LootBonus(['sword'], chance: 1.0, min: 2, max: 3),
    ),
  },
  shots: {'arrow': ProjectileSpec(speed: 30.0, gravity: 0.0, damage: 6.0, knockback: 0.0)},
  mobs: [MobSpec('target', hp: 40, brain: [])],
  sky: SkySpec.alwaysDay,
);

Future<VoxelGame> _start([VoxelGameSpec spec = _spec]) async {
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

/// The nearest temple to the player, and its two chests' cells.
(PlacedStructure, List<IVec3>) _nearestTemple(VoxelGame game) {
  final at = IVec3.floor(game.player.position);
  final chunk = (x: at.x >> 4, z: at.z >> 4);
  final sites = game.world.generator.structuresNear(chunk.x, chunk.z)
    ..sort((a, b) => (a.x - at.x).abs() + (a.z - at.z).abs() - (b.x - at.x).abs() - (b.z - at.z).abs());
  final s = sites.first;
  return (s, [IVec3(s.x - 1, s.y + 1, s.z - 1), IVec3(s.x + 1, s.y + 1, s.z - 1)]);
}

/// What [inv] holds, a `id x count +bonus` a slot, sorted.
List<String> _held(Inventory inv) =>
    [for (final s in inv.slots.whereType<ItemStack>()) '${s.id} x${s.count} +${s.bonus}']..sort();

void main() {
  test('a structure\'s store holds the structure\'s loot and its bonus, the same in every game', () async {
    final game = await _start();
    final (site, chests) = _nearestTemple(game);
    expect(game.structureAt(chests.first)?.name, 'temple');
    expect(game.structureAt(IVec3(site.x + 6, site.y, site.z)), isNull, reason: 'past its reach of 5');
    for (final c in chests) {
      expect(game.world.isLoaded(c), isTrue);
      expect(game.world.blockNameAt(c), 'chest');
    }
    final first = _held(game.blockRules.storeAt(chests.first));
    expect(first, hasLength(2));
    expect(first.first, matches(RegExp(r'^gem x[234] \+0$')));
    expect(first.last, matches(RegExp(r'^sword x1 \+[23]$')), reason: 'the bonus roll');
    final again = await _start();
    expect(_held(again.blockRules.storeAt(chests.first)), first, reason: 'seeded by the cell and the world');
    game.dispose();
    again.dispose();
  });

  test('a store outside any structure is found with its block\'s loot; one placed starts empty', () async {
    final game = await _start();
    final (site, _) = _nearestTemple(game);
    final away = IVec3(site.x + 8, site.y, site.z + 8);
    expect(game.structureAt(away), isNull);
    game.world.setBlockNamed(away, 'chest');
    expect(game.blockRules.storeAt(away).slots.whereType<ItemStack>(), isEmpty, reason: 'placed: empty');
    game.dispose();
    // A spec whose temples hold nothing of their own: the chest's own loot.
    final plain = await _start(_spec.copyWith(structureLoot: const {}));
    final (_, chests) = _nearestTemple(plain);
    expect(_held(plain.blockRules.storeAt(chests.first)), ['stone x1 +0']);
    plain.dispose();
  });

  test('a stack\'s bonus adds to the blow it deals and to the shot it looses', () async {
    final game = await _start();
    final p = game.player;

    /// A fresh target 2 m in front of the player, looked at.
    Mob ahead() {
      final m = game.spawnMob('target', p.position + Vector3(0, 0, -2.0));
      final to = m.centre() - p.eyePosition;
      p
        ..yaw = 0.0
        ..pitch = math.atan2(to.y, 2.0);
      return m;
    }

    p.selectedSlot = p.inventory.hotbarSize - 1;
    p.inventory.setSlot(p.selectedSlot, ItemStack('sword', 1, bonus: 3));
    final struck = ahead();
    await _run(game, 0.1);
    game.input.tap(VoxelAction.attack);
    await _run(game, 0.1);
    final hit = 40.0 - struck.hp;
    expect(
      hit == 7.0 || hit > 7.0 && hit <= 7.0 * 2.0,
      isTrue,
      reason: 'the sword\'s 4 and its 3, or a critical of it: $hit',
    );
    struck.removed = true;
    p.inventory.setSlot(p.selectedSlot, ItemStack('bow', 1, bonus: 2));
    p.inventory.add('arrow', 1);
    await _run(game, 0.6);
    final shotAt = ahead();
    await _run(game, 0.1);
    game.input.tap(VoxelAction.attack);
    await _run(game, 0.5);
    final shot = 40.0 - shotAt.hp;
    expect(shot == 8.0 || shot > 8.0 && shot <= 8.0 * 2.0, isTrue, reason: 'the arrow\'s 6 and its 2: $shot');
    game.dispose();
  });

  test('structure loot is checked when the game is made', () async {
    Future<void> refused(Map<String, StructureLoot> loot) =>
        expectLater(VoxelGame.startHeadless(_spec.copyWith(structureLoot: loot)), throwsArgumentError);
    await refused(const {'tower': StructureLoot(LootTable([]))});
    await refused(const {
      'temple': StructureLoot(LootTable([LootEntry('ruby', 1, 1, 1.0)])),
    });
    await refused(const {
      'temple': StructureLoot(LootTable([]), bonus: LootBonus(['ruby'])),
    });
    await refused(const {'temple': StructureLoot(LootTable([]), bonus: LootBonus([]))});
    await refused(const {
      'temple': StructureLoot(LootTable.oneOf([LootEntry('gem', 1, 1, 0.7), LootEntry('gem', 2, 2, 0.7)])),
    });
  });
}
