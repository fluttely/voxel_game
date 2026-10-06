import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voxel_game/voxel_game.dart';

const _music = MusicSpec(
  tracks: {
    'meadow': MusicTrack(score: StockMusic.pastoral, title: 'Meadow'),
    'deep': MusicTrack(score: StockMusic.cavern),
  },
  day: 'meadow',
  cave: 'deep',
);

VoxelGameSpec _spec({MusicSpec? music = _music, bool sound = true}) => VoxelGameSpec(
  blocks: const [
    BlockType('stone', color: 0x808080, hardness: 1.5, tool: 'pickaxe'),
    BlockType('dirt', color: 0x74502F, hardness: 0.5, tool: 'shovel'),
    BlockType('grass', color: 0x4C9437, hardness: 0.6, tool: 'shovel', drop: 'dirt'),
    BlockType.liquid('water', color: 0x3366CC),
  ],
  world: const WorldGenSpec(
    terrain: TerrainRecipe.flat(20),
    seaLevel: 5,
    caves: CaveSpec.none,
    biomes: [Biome('plains', top: 'grass', under: 'dirt')],
  ),
  seed: 7,
  sky: SkySpec.alwaysDay,
  sounds: SoundSpec(enabled: sound, music: music, musicVolume: 0.5),
);

/// Worlds and settings in a fresh folder.
(WorldSaves, SettingsStore) _store() {
  final dir = Directory.systemTemp.createTempSync('voxel_title_music');
  addTearDown(() => dir.deleteSync(recursive: true));
  return (WorldSaves(dir), SettingsStore(File('${dir.path}/settings.json')));
}

/// The title of [spec] under [menu] until a world is picked, then [world],
/// as `VoxelGameHome` swaps them.
class _Home extends StatefulWidget {
  const _Home(this.spec, this.menu, this.saves, this.settings, this.world, {super.key});

  final VoxelGameSpec spec;
  final TitleSpec menu;
  final WorldSaves saves;
  final SettingsStore settings;
  final Widget world;

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  bool _playing = false;

  @override
  Widget build(BuildContext context) => _playing
      ? widget.world
      : TitleScreen(
          spec: widget.spec,
          menu: widget.menu,
          saves: widget.saves,
          settings: widget.settings,
          onChoice: (_) => setState(() => _playing = true),
        );
}

/// A world's widget as far as the music goes: what it finds playing when it
/// first looks, after its first await, as `VoxelGameWidget` opens its bank.
class _World extends StatefulWidget {
  const _World(this.found);

  final List<GameMusic?> found;

  @override
  State<_World> createState() => _WorldState();
}

class _WorldState extends State<_World> {
  @override
  void initState() {
    super.initState();
    unawaited(Future.microtask(() => widget.found.add(GameMusic.playing.value)));
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

/// A world's widget as `VoxelGameWidget` starts its audio: a bank on the
/// device, then the world's music once the bank is open. It names no track:
/// the fake device opens, SoLoud does not, and a track would reach SoLoud.
class _SoundWorld extends StatefulWidget {
  const _SoundWorld();

  @override
  State<_SoundWorld> createState() => _SoundWorldState();
}

class _SoundWorldState extends State<_SoundWorld> {
  final SoundBank _bank = SoundBank(recipes: const {});
  GameMusic? _playing;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    final open = await _bank.init();
    if (!mounted) return _bank.dispose();
    if (open) _playing = GameMusic(_music, GameSettings.of(_spec()));
  }

  @override
  void dispose() {
    _playing?.close();
    _bank.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  Future<void> mount(WidgetTester tester, VoxelGameSpec spec, TitleSpec menu, {Widget world = const SizedBox()}) async {
    final (saves, settings) = _store();
    saves.create('Home', seed: 1);
    await tester.pumpWidget(MaterialApp(home: _Home(spec, menu, saves, settings, world, key: UniqueKey())));
    await tester.pump();
  }

  testWidgets('the title plays the track it names, at the player\'s music gain', (tester) async {
    await mount(tester, _spec(), const TitleSpec(name: 'Blocks', music: 'meadow'));
    final music = GameMusic.playing.value!;
    expect(music.track, 'meadow');
    expect(music.gain, GameSettings.of(_spec()).musicGain);
    await tester.pumpWidget(const SizedBox());
    expect(GameMusic.playing.value, isNull, reason: 'closed with the screen');
    expect(music.track, isNull);
  });

  testWidgets('no track named, or the sound off, plays nothing', (tester) async {
    await mount(tester, _spec(), const TitleSpec(name: 'Blocks'));
    expect(GameMusic.playing.value, isNull);
    await mount(tester, _spec(sound: false), const TitleSpec(name: 'Blocks', music: 'meadow'));
    expect(GameMusic.playing.value, isNull);
  });

  testWidgets('a track the game does not have throws', (tester) async {
    await mount(tester, _spec(), const TitleSpec(name: 'Blocks', music: 'jazz'));
    expect(tester.takeException(), isArgumentError);
    await mount(tester, _spec(music: null), const TitleSpec(name: 'Blocks', music: 'meadow'));
    expect(tester.takeException(), isArgumentError);
  });

  testWidgets('the music slider in the title\'s settings reaches the track at once', (tester) async {
    await mount(tester, _spec(), const TitleSpec(name: 'Blocks', music: 'meadow'));
    final music = GameMusic.playing.value!;
    await tester.tap(find.text('Settings'));
    await tester.pump();
    final slider = find.descendant(
      of: find.ancestor(of: find.text('Music'), matching: find.byType(Column)).first,
      matching: find.byType(Slider),
    );
    tester.widget<Slider>(slider).onChanged!(0.2);
    await tester.pump();
    expect(music.gain, closeTo(0.2, 1e-9), reason: 'the volume is 1: the gain is the music volume');
    expect(identical(GameMusic.playing.value, music), isTrue, reason: 'the same track, not reopened');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('entering a world stops the title\'s music before the world looks for the device', (tester) async {
    final found = <GameMusic?>[GameMusic.playing.value];
    await mount(
      tester,
      _spec(),
      const TitleSpec(name: 'Blocks', music: 'meadow'),
      world: _World(found),
    );
    final music = GameMusic.playing.value!;
    await tester.tap(find.text('Play'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Play'));
    await tester.pump();
    expect(found, [null, null], reason: 'nothing before the title, nothing left once the world looks');
    expect(music.track, isNull);
  });

  testWidgets('a world entered while the title opens the device finds it open, and makes its music', (tester) async {
    final absent = AudioDevice.instance;
    addTearDown(() => AudioDevice.instance = absent);
    final opening = Completer<bool>();
    final log = <String>[];
    final device = AudioDevice.instance = AudioDevice(
      open: () {
        log.add('open');
        return opening.future;
      },
      close: () async => log.add('close'),
    );
    await mount(
      tester,
      _spec(),
      const TitleSpec(name: 'Blocks', music: 'meadow'),
      world: const _SoundWorld(),
    );
    expect(GameMusic.playing.value, isNull, reason: 'the title is still opening the device');
    await tester.tap(find.text('Play'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Play'));
    await tester.pump();
    opening.complete(true);
    await tester.pump();
    expect(log, ['open'], reason: "the title's release comes after the world's hold");
    expect(device.isOpen, isTrue);
    expect(device.held, 1);
    expect(GameMusic.playing.value, isNotNull, reason: "the world's bank opened, and its music is made");
    await tester.pumpWidget(const SizedBox());
    expect(log, ['open', 'close']);
    expect(GameMusic.playing.value, isNull);
  });

  test('GameMusic is one at a time', () {
    final settings = GameSettings.of(_spec());
    final music = GameMusic(_music, settings)..play('deep');
    expect(music.track, 'deep');
    expect(() => GameMusic(_music, settings), throwsStateError);
    music
      ..follow(settings.copyWith(volume: 0.5))
      ..close();
    expect(music.gain, 0.25);
    expect(GameMusic.playing.value, isNull);
    GameMusic(_music, settings).close();
  });
}
