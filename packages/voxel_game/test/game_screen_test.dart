import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Vector3;
import 'package:voxel_game/voxel_game.dart';

Widget _journal(BuildContext context, VoxelGame game) => const Text('journal page');

Widget _trade(BuildContext context, VoxelGame game) => const Text('trade');

/// Level grass at y 20, a bench to craft at, a chest, and two screens of the
/// game's own: a journal in the menu, a trade only code opens.
const _spec = VoxelGameSpec(
  blocks: [
    BlockType('stone', color: 0x808080, hardness: 1.5, tool: 'pickaxe'),
    BlockType('dirt', color: 0x74502F, hardness: 0.5, tool: 'shovel'),
    BlockType('grass', color: 0x4C9437, hardness: 0.6, tool: 'shovel', drop: 'dirt'),
    BlockType('bench', color: 0xB08850, hardness: 1.0, tool: 'axe'),
    BlockType('chest', color: 0x8A5A2A, hardness: 1.0, tool: 'axe', storage: Storage()),
    BlockType.liquid('water', color: 0x3366CC),
    BlockType.liquid('water_flow', color: 0x3366CC, kind: 'water', source: false),
  ],
  recipes: [
    Recipe('chest', 1, {'bench': 2}, station: 'bench'),
  ],
  world: WorldGenSpec(
    terrain: TerrainRecipe.flat(20),
    seaLevel: 5,
    caves: CaveSpec.none,
    biomes: [Biome('plains', top: 'grass', under: 'dirt')],
  ),
  sky: SkySpec.alwaysDay,
  player: PlayerSpec(respawnDelay: 0.5),
  screens: {
    'journal': ScreenSpec(_journal, menu: 'Journal'),
    'trade': ScreenSpec(_trade),
  },
);

Future<VoxelGame> _start({SavedWorld? save}) async {
  final game = await VoxelGame.startHeadless(_spec, save: save);
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

/// A press of [action], and the steps that read it.
Future<void> _press(VoxelGame game, VoxelAction action) async {
  game.input.tap(action);
  await _run(game, 0.05);
}

void _die(VoxelGame game) => game.player.takeDamage(const Damage(1000, source: 'test'));

void main() {
  test('pause opens the game menu and closes it; the bag does not close it', () async {
    final game = await _start();
    await _press(game, VoxelAction.pause);
    expect(game.screen.value, const PauseScreen());
    await _press(game, VoxelAction.inventory);
    expect(game.screen.value, const PauseScreen(), reason: 'the bag\'s button is not the menu\'s');
    await _press(game, VoxelAction.pause);
    expect(game.screen.value, isNull);
  });

  test('pause closes the bag as its own button does', () async {
    final game = await _start();
    await _press(game, VoxelAction.inventory);
    expect(game.screen.value, const BagScreen());
    await _press(game, VoxelAction.pause);
    expect(game.screen.value, isNull, reason: 'one press closes, it does not also open the menu');
  });

  test('the world keeps stepping behind a screen', () async {
    final game = await _start();
    game.openScreen(const PauseScreen());
    final t = game.time;
    await _run(game, 0.5);
    expect(game.time, greaterThan(t + 0.4));
  });

  test('use on a station opens its crafting; a chest opens its store', () async {
    final game = await _start();
    game.world
      ..setBlockNamed(const IVec3(0, 20, -2), 'stone')
      ..setBlockNamed(const IVec3(0, 21, -2), 'bench');
    game.player
      ..position = Vector3(0.5, 20.0, 0.5)
      ..velocity = Vector3.zero()
      ..yaw = 0.0
      ..pitch = 0.0;
    await _press(game, VoxelAction.use);
    expect(game.screen.value, const BagScreen(station: 'bench'));
    game.closeScreen();
    game.world.setBlockNamed(const IVec3(0, 21, -2), 'chest');
    await _run(game, 0.3);
    await _press(game, VoxelAction.use);
    expect(game.screen.value, const StorageScreen(IVec3(0, 21, -2)));
  });

  test('a death replaces the screen open, and only a respawn leaves it', () async {
    final game = await _start();
    game.openScreen(const BagScreen());
    _die(game);
    expect(game.screen.value, const DeathScreen());
    await _press(game, VoxelAction.pause);
    await _press(game, VoxelAction.inventory);
    expect(game.screen.value, const DeathScreen());
    expect(game.closeScreen, throwsStateError);
    expect(() => game.openScreen(const PauseScreen()), throwsStateError);

    expect(game.canRespawn, isFalse);
    expect(game.respawn, throwsStateError, reason: 'not before the delay');
    await _press(game, VoxelAction.jump);
    expect(game.player.isDead, isTrue, reason: 'a jump before the delay is spent on nothing');

    await _run(game, 0.5);
    expect(game.canRespawn, isTrue);
    await _press(game, VoxelAction.jump);
    expect(game.player.isDead, isFalse, reason: 'jump stands up: a keyboard\'s and a pad\'s respawn');
    expect(game.screen.value, isNull);
    expect(game.player.hp, game.player.maxHp);
  });

  test('a respawn is no fall, however far below the death the spawn lies', () async {
    final game = await _start();
    final p = game.player;
    p.position = p.spawnPoint + Vector3(0, 20, 0);
    await _run(game, 0.1);
    _die(game);
    await _run(game, 0.5);
    game.respawn();
    await _run(game, 0.5);
    expect(p.hp, p.maxHp);
  });

  test('a game\'s own screen opens by its id; pause closes it', () async {
    final game = await _start();
    game.openScreen(const DeclaredScreen('trade'));
    expect(game.screen.value, const DeclaredScreen('trade'));
    await _press(game, VoxelAction.inventory);
    expect(game.screen.value, const DeclaredScreen('trade'));
    await _press(game, VoxelAction.pause);
    expect(game.screen.value, isNull);
  });

  test('a screen that cannot be is refused', () async {
    final game = await _start();
    expect(game.closeScreen, throwsStateError, reason: 'nothing is open');
    expect(() => game.openScreen(const DeathScreen()), throwsArgumentError);
    expect(() => game.openScreen(const BagScreen(station: 'stone')), throwsArgumentError);
    expect(() => game.openScreen(const StorageScreen(IVec3(0, 10, 0))), throwsArgumentError);
    expect(() => game.openScreen(const DeclaredScreen('map')), throwsArgumentError);
    expect(game.screen.value, isNull);
  });

  test('a player saved dead loads on the death screen', () async {
    final dir = Directory.systemTemp.createTempSync('voxel_screens');
    addTearDown(() => dir.deleteSync(recursive: true));
    final saves = WorldSaves(dir);
    final game = await _start();
    _die(game);
    saves.save(game, 'slot');

    final back = await _start(save: saves.read('slot'));
    expect(back.player.isDead, isTrue);
    expect(back.screen.value, const DeathScreen());
    await _run(back, 0.5);
    back.respawn();
    expect(back.player.hp, back.player.maxHp);
  });

  group('on the surface', () {
    Future<VoxelGame> mount(WidgetTester tester, {VoidCallback? onQuit}) async {
      final game = (await tester.runAsync(_start))!;
      await tester.pumpWidget(
        MaterialApp(
          home: GameSurface(game: game, world: const ColoredBox(color: Colors.black), onQuit: onQuit),
        ),
      );
      return game;
    }

    testWidgets('the game menu resumes, lists the game\'s own screens, and quits when it can', (tester) async {
      final game = await mount(tester);
      game.openScreen(const PauseScreen());
      await tester.pump();
      expect(find.text('Game menu'), findsOneWidget);
      expect(find.text('Quit'), findsNothing, reason: 'no quit without somewhere to go');
      expect(find.text('Journal'), findsOneWidget);
      expect(find.text('trade'), findsNothing, reason: 'a screen with no menu label is not listed');
      await tester.tap(find.text('Journal'));
      await tester.pump();
      expect(game.screen.value, const DeclaredScreen('journal'));
      expect(find.text('journal page'), findsOneWidget);
      game.closeScreen();
      game.openScreen(const PauseScreen());
      await tester.pump();
      await tester.tap(find.text('Resume'));
      await tester.pump();
      expect(game.screen.value, isNull);
      expect(find.text('Game menu'), findsNothing);
      game.dispose();

      var quits = 0;
      final quitting = await mount(tester, onQuit: () => quits++);
      quitting.openScreen(const PauseScreen());
      await tester.pump();
      await tester.tap(find.text('Quit'));
      expect(quits, 1);
      quitting.dispose();
    });

    testWidgets('the death screen wakes its respawn after the delay', (tester) async {
      final game = await mount(tester);
      _die(game);
      await tester.pump();
      expect(find.text('You died'), findsOneWidget);
      Finder respawn() => find.widgetWithText(FilledButton, 'Respawn');
      expect(tester.widget<FilledButton>(respawn()).onPressed, isNull);
      for (var i = 0; i < 40; i++) {
        game.frame(1 / 60);
      }
      await tester.pump();
      expect(tester.widget<FilledButton>(respawn()).onPressed, isNotNull);
      await tester.tap(respawn());
      await tester.pump();
      expect(game.player.isDead, isFalse);
      expect(find.text('You died'), findsNothing);
      game.dispose();
    });

    testWidgets('a death over the bag gives back the stack on its cursor', (tester) async {
      final game = await mount(tester);
      final bag = game.player.inventory;
      for (var i = 0; i < bag.capacity; i++) {
        bag.setSlot(i, null);
      }
      bag.setSlot(0, ItemStack('stone', 5));
      game.openScreen(const BagScreen());
      await tester.pump();
      final slots = find.byWidgetPredicate((w) => w is GestureDetector && w.onSecondaryTap != null);
      await tester.tap(slots.at(bag.capacity - bag.hotbarSize));
      await tester.pump();
      expect(bag.countOf('stone'), 0, reason: 'the stack is on the cursor');
      _die(game);
      await tester.pump();
      expect(bag.countOf('stone'), 5);
      game.dispose();
    });
  });
}
