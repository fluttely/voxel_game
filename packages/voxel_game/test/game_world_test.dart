import 'package:flutter_test/flutter_test.dart';
import 'package:voxel_game/voxel_game.dart';

void main() {
  const spec = VoxelGameSpec(
    blocks: [BlockType('stone', color: 0x808080), BlockType.liquid('water', color: 0x3366CC)],
    world: WorldGenSpec(
      terrain: TerrainRecipe.flat(20),
      caves: CaveSpec.none,
      biomes: [Biome('plain', top: 'stone')],
    ),
  );

  test('the clear zone holds an edit at the player\'s reach and the remesh around it', () {
    expect(GameWorld.settleClearFor(const PlayerSpec().reach), 2, reason: '5 m lands in the chunk beside, at most');
    expect(GameWorld.settleClearFor(0), 1);
    expect(GameWorld.settleClearFor(16), 2);
    expect(GameWorld.settleClearFor(16.5), 3);
    expect(() => GameWorld.settleClearFor(-1), throwsArgumentError);
  });

  test('the view a world draws with is built with the clear zone it is given; a headless one has none', () {
    final blocks = spec.buildBlocks();
    expect(GameWorld(blocks, spec.dimensionWorlds, 1, settleClear: 3).settleClear, 3);
    expect(GameWorld(blocks, spec.dimensionWorlds, 1).settleClear, 2);
    expect(GameWorld.headless(blocks, spec.dimensionWorlds, 1).settleClear, isNull);
  });
}
