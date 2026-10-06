import 'package:flutter_test/flutter_test.dart';
import 'package:voxel_game/voxel_game.dart';

const _blocks = [
  BlockType('stone', color: 0x808080, hardness: 1.5, tool: 'pickaxe'),
  BlockType('dirt', color: 0x8A5E3B, hardness: 0.5, tool: 'shovel'),
  BlockType('grass', color: 0x4C9437, hardness: 0.6, tool: 'shovel'),
  BlockType('sand', color: 0xDCCB8A, hardness: 0.5, tool: 'shovel', tags: {'step:sand'}),
  BlockType('snow', color: 0xF0F0F0, hardness: 0.2, tool: 'shovel', tags: {'step:snow'}),
  BlockType.liquid('water', color: 0x3366CC),
];

VoxelGameSpec _spec({String top = 'grass', List<BlockType> blocks = _blocks, SoundSpec sounds = const SoundSpec()}) =>
    VoxelGameSpec(
      blocks: blocks,
      world: WorldGenSpec(
        terrain: const TerrainRecipe.flat(20),
        seaLevel: 5,
        caves: CaveSpec.none,
        biomes: [Biome('plains', top: top, under: 'dirt')],
      ),
      sky: SkySpec.alwaysDay,
      sounds: sounds,
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

/// The steps heard walking forward for [seconds].
Future<List<String>> _walk(VoxelGame game, double seconds) async {
  final heard = game.sounds as SilentSounds;
  heard.played.clear();
  game.input.hold(VoxelAction.moveForward, true);
  for (var t = 0.0; t < seconds; t += 1 / 60) {
    game.frame(1 / 60);
    await Future<void>.delayed(Duration.zero);
  }
  game.input.hold(VoxelAction.moveForward, false);
  return [
    for (final s in heard.played)
      if (s.startsWith('step_')) s,
  ];
}

void main() {
  test('a block tagged step:sand steps as sand, not as its family', () async {
    final game = await _start(_spec(top: 'sand'));
    final steps = await _walk(game, 1.0);
    expect(steps.length, greaterThanOrEqualTo(2), reason: 'a step every 0.4 s');
    expect(steps.toSet(), {'step_sand'}, reason: 'sand is dug with a shovel, but its tag wins over earth');
    game.dispose();
  });

  test('an untagged block steps as its sound family', () async {
    final game = await _start(_spec());
    final steps = await _walk(game, 1.0);
    expect(steps.length, greaterThanOrEqualTo(2));
    expect(steps.toSet(), {'step_earth'}, reason: 'grass is dug with a shovel: earth');
    expect(game.stepSound(game.blocks.indexOf('stone')), 'step_stone');
    expect(game.stepSound(game.blocks.indexOf('snow')), 'step_snow');
    game.dispose();
  });

  test('a step: tag naming no sound the game has throws when the game is made', () async {
    final blocks = [
      ..._blocks,
      const BlockType('mud', color: 0x4A3A2C, hardness: 0.5, tags: {'step:mud'}),
    ];
    await expectLater(VoxelGame.startHeadless(_spec(blocks: blocks)), throwsArgumentError);
    expect(
      () => _spec(
        blocks: [
          ..._blocks,
          const BlockType('mud', color: 0, tags: {'step:mud', 'step:sand'}),
        ],
      ).checkSteps(),
      throwsArgumentError,
      reason: 'a block steps one way',
    );
  });

  test('a recipe or recorded takes under step_<kind> make the kind the game\'s', () {
    final blocks = [
      ..._blocks,
      const BlockType('mud', color: 0x4A3A2C, hardness: 0.5, tags: {'step:mud'}),
    ];
    _spec(
      blocks: blocks,
      sounds: SoundSpec(recipes: {'step_mud': StockSounds.all['step_earth']!}),
    ).checkSteps();
    _spec(
      blocks: blocks,
      sounds: const SoundSpec(
        assets: {
          'step_mud': ['assets/mud_1.wav'],
        },
      ),
    ).checkSteps();
  });
}
