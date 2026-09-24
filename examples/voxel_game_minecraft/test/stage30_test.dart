import 'dart:convert';
import 'dart:io';

import 'package:voxel_game_minecraft/src/game/game_state.dart';
import 'package:voxel_game_minecraft/src/game/settings.dart';
import 'package:voxel_game_minecraft/src/game/tutorial.dart';
import 'package:voxel_game_minecraft/src/game/worlds.dart';
import 'package:voxel_game_minecraft/src/ui/credits_screen.dart';
import 'package:voxel_game_minecraft/src/ui/settings_panel.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stage 30's pure pieces (Godot `--stage30` covers the rest in the app): the
/// world slots (create / list / rename / delete / start in a temp dir, the slug,
/// `world.json` with Godot's keys), the typed seed, the list labels, the
/// tutorial chain, the credits parse of this project's ROADMAP.md, the
/// creative flag and the new counters in the stats save, the tutorial flag in
/// settings.cfg.
void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('stage30_worlds');
    Worlds.root = '${tmp.path}/worlds';
    Settings.instance.path = '${tmp.path}/settings.cfg';
    Tutorial.instance.persist = false;
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('Worlds', () {
    test('create writes world.json with Godot keys under a slug, list reads it back', () {
      expect(Worlds.list(), isEmpty); // no worlds/ folder yet
      final slot = Worlds.create('  My World  ', '4242', 'creative', 'mage', now: 1000);
      expect(slot, 'my_world');
      final meta = jsonDecode(File('${Worlds.root}/$slot/world.json').readAsStringSync()) as Map<String, dynamic>;
      expect(meta, {'name': 'My World', 'seed': 4242, 'mode': 'creative', 'class': 'mage', 'created': 1000});
      final e = Worlds.entry(slot)!;
      expect([e.name, e.seed, e.mode, e.playerClass, e.dimension, e.hasSave, e.lastPlayed], ['My World', 4242, 'creative', 'mage', 0, false, 1000]);
      expect(Worlds.list().map((w) => w.slot), [slot]);
    });

    test('a taken name gets a number, an empty name is New World, a prefix goes first', () {
      expect(Worlds.create('Home', '1', 'survival', 'warrior'), 'home');
      expect(Worlds.create('Home', '1', 'survival', 'warrior'), 'home_2');
      expect(Worlds.create('Home', '1', 'survival', 'warrior'), 'home_3');
      expect(Worlds.create('   ', '1', 'survival', 'warrior'), 'new_world');
      expect(Worlds.create('Stats', '42', 'creative', 'mage', slotPrefix: 'probe30_'), 'probe30_stats');
    });

    test('slot names are sanitised like Godot validate_filename', () {
      expect(Worlds.validateFilename('a:b/c\\d?e*f"g|h%i<j>k'), 'a_b_c_d_e_f_g_h_i_j_k');
      expect(Worlds.slugOf('My Castle: Part 2/3'), 'my_castle__part_2_3');
      final slot = Worlds.create('Dark/Tower?', '', 'survival', 'rogue');
      expect(slot, 'dark_tower_');
      expect(Directory('${Worlds.root}/$slot').existsSync(), isTrue);
    });

    test('rename keeps the slot and the other keys; empty names and unknown slots refuse', () {
      final slot = Worlds.create('Old', '7', 'survival', 'ranger', now: 5);
      expect(Worlds.rename(slot, '  New Name '), isTrue);
      final meta = Worlds.readMeta(slot);
      expect(meta, {'name': 'New Name', 'seed': 7, 'mode': 'survival', 'class': 'ranger', 'created': 5});
      expect(Worlds.rename(slot, '   '), isFalse);
      expect(Worlds.rename('nope', 'x'), isFalse);
    });

    test('delete removes the folder and its files; unknown or unsafe slots refuse', () {
      final slot = Worlds.create('Doomed', '1', 'survival', 'warrior');
      File('${Worlds.root}/$slot/blocks.bin').writeAsBytesSync([1, 2, 3]);
      File('${Worlds.root}/$slot/player.json').writeAsStringSync('{}');
      final keep = Worlds.create('Keep', '1', 'survival', 'warrior');
      expect(Worlds.delete(slot), isTrue);
      expect(Directory('${Worlds.root}/$slot').existsSync(), isFalse);
      expect(Worlds.delete(slot), isFalse);
      expect(Worlds.delete('../worlds'), isFalse);
      expect(Worlds.list().map((w) => w.slot), [keep]);
    });

    test('the save overlays seed, dimension, play time, class and creative; a bare folder is no world', () {
      final slot = Worlds.create('Saved', '11', 'survival', 'warrior', now: 1);
      File('${Worlds.root}/$slot/player.json').writeAsStringSync(jsonEncode({
        'seed': 99,
        'dimension': 1,
        'stats': {'play_time': 3725.0, 'class': 'rogue', 'creative': true},
      }));
      Directory('${Worlds.root}/empty_folder').createSync(recursive: true);
      Directory('${Worlds.root}/.hidden').createSync(recursive: true);
      File('${Worlds.root}/.hidden/world.json').writeAsStringSync('{"name":"x"}');
      final e = Worlds.entry(slot)!;
      expect([e.seed, e.dimension, e.playSeconds, e.playerClass, e.mode, e.hasSave], [99, 1, 3725.0, 'rogue', 'creative', true]);
      expect(e.lastPlayed, greaterThan(1)); // the save's mtime wins over `created`
      expect(Worlds.entry('empty_folder'), isNull);
      expect(Worlds.list().map((w) => w.slot), [slot]);
      // A folder with only a save (a pre-stage-30 world) still lists, by its slot name.
      Directory('${Worlds.root}/legacy').createSync();
      File('${Worlds.root}/legacy/player.json').writeAsStringSync(jsonEncode({'seed': 5}));
      final legacy = Worlds.entry('legacy')!;
      expect([legacy.name, legacy.seed, legacy.mode], ['legacy', 5, 'survival']);
    });

    test('the list is newest first', () {
      final a = Worlds.create('A', '1', 'survival', 'warrior', now: 100);
      final b = Worlds.create('B', '1', 'survival', 'warrior', now: 300);
      final c = Worlds.create('C', '1', 'survival', 'warrior', now: 200);
      expect(Worlds.list().map((w) => w.slot), [b, c, a]);
    });

    test('start fills GameState: slot, seed, class, creative, fresh; counters cleared', () {
      final gs = GameState.instance;
      gs
        ..blocksMined = 50
        ..distanceWalked = 12.0
        ..dimensionVisits = 3
        ..creative = false;
      final slot = Worlds.create('Fresh', '321', 'creative', 'mage');
      Worlds.start(slot);
      expect([gs.worldName, gs.seedValue, gs.playerClass, gs.creative, gs.freshWorld], [slot, 321, 'mage', true, true]);
      expect([gs.blocksMined, gs.distanceWalked, gs.dimensionVisits], [0, 0.0, 0]);
      File('${Worlds.root}/$slot/player.json').writeAsStringSync(jsonEncode({'seed': 321, 'stats': {'creative': true, 'class': 'mage'}}));
      Worlds.start(slot);
      expect(gs.freshWorld, isFalse);
      expect(() => Worlds.start('missing'), throwsArgumentError);
    });

    test('the typed seed: a number as itself, text hashed the same every time, empty random', () {
      expect(Worlds.seedFromText(' 4242 '), 4242);
      expect(Worlds.seedFromText('-17'), -17);
      final h = Worlds.seedFromText('hello world');
      expect(h, Worlds.seedFromText('hello world'));
      expect(h, inInclusiveRange(0, 999999));
      expect(h, Worlds.fnv1a('hello world') % 1000000);
      expect(Worlds.seedFromText('hello world!'), isNot(h));
      for (var i = 0; i < 20; i++) {
        expect(Worlds.seedFromText(''), inInclusiveRange(0, 999999));
      }
    });

    test('labels: mode, play time, last played', () {
      final e = WorldEntry(slot: 's', name: 'n', seed: 0, mode: 'creative', playerClass: 'warrior', dimension: 0, playSeconds: 0, lastPlayed: 0, hasSave: false);
      expect(Worlds.modeLabel(e), 'Creative');
      e.mode = 'survival';
      expect(Worlds.modeLabel(e), 'Survival');
      expect(Worlds.playTimeLabel(42.9), '42 s');
      expect(Worlds.playTimeLabel(125), '2 min');
      expect(Worlds.playTimeLabel(3725), '1h 02m');
      expect(Worlds.lastPlayedLabel(0), 'never');
      expect(Worlds.lastPlayedLabel(1757000000), matches(RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$')));
    });
  });

  group('Tutorial', () {
    test('ten steps in Godot order; only the current step\'s event advances', () {
      final t = Tutorial.instance;
      expect(Tutorial.steps.map((s) => s.id), ['move', 'look', 'jump', 'break', 'inventory', 'craft', 'place', 'eat', 'sleep', 'journal']);
      Settings.instance.tutorialDone = false;
      t.begin();
      expect([t.active, t.index, t.currentId], [true, 0, 'move']);
      t.event('jump'); // not yet
      t.event('look');
      expect(t.index, 0);
      t.event('move');
      t.event('move'); // a second walk does nothing more
      expect([t.index, t.currentId, t.current!.title], [1, 'look', 'Look']);
      for (final id in ['look', 'jump', 'break', 'inventory', 'craft', 'place']) {
        t.event(id);
      }
      expect(t.completed, ['move', 'look', 'jump', 'break', 'inventory', 'craft', 'place']);
      expect(t.currentId, 'eat');
      String? said;
      t.notify = (s) => said = s;
      for (final id in ['eat', 'sleep', 'journal']) {
        t.event(id);
      }
      expect([t.active, Settings.instance.tutorialDone, said], [false, true, 'Tutorial complete. Go explore!']);
      t.event('move'); // inactive: ignored
      expect(t.completed.length, 10);
      t.notify = null;
    });

    test('skip marks it done and saves; done never begins again; stop keeps it undone', () {
      final t = Tutorial.instance;
      Settings.instance.tutorialDone = false;
      t.begin();
      t.event('move');
      t.stop();
      expect([t.active, Settings.instance.tutorialDone, t.current], [false, false, null]);
      t.begin();
      expect([t.active, t.index], [true, 0]);
      t.persist = true; // the skip writes settings.cfg (the Sfx call is a no-op without a device)
      t.skipAll();
      t.persist = false;
      expect([t.active, Settings.instance.tutorialDone], [false, true]);
      expect(File(Settings.instance.path).readAsStringSync(), contains('[tutorial]\n\ndone=true'));
      t.begin();
      expect(t.active, isFalse);
      t.skipAll(); // inactive: nothing
    });
  });

  test('settings.cfg carries [tutorial] done and reads it back', () {
    final s = Settings.instance;
    s.tutorialDone = true;
    expect(s.save(), isTrue);
    s.tutorialDone = false;
    expect(s.loadFile(), isTrue);
    expect(s.tutorialDone, isTrue);
    s.fromConfig('[tutorial]\n\ndone=false\n');
    expect(s.tutorialDone, isFalse);
    s.fromConfig('[video]\n\nfov=80.0\n'); // a stage 24 file keeps the value
    expect(s.tutorialDone, isFalse);
  });

  group('Credits', () {
    test('every stage row of ROADMAP.md: the bold lead, else the cell cut at its first sentence', () {
      final text = File('ROADMAP.md').readAsStringSync();
      final stages = CreditsScreen.parseStages(text);
      final rows = text.split('\n').where((l) => RegExp(r'^\|\s*\d+[ab]?\s*\|').hasMatch(l)).length;
      expect(stages.length, rows);
      expect(stages.length, greaterThanOrEqualTo(33));
      expect(stages.first, 'Stage 0 — Worktree + project skeleton');
      expect(stages, contains('Stage 13b — Ranged combat: simulation-owned projectiles, staff spray / arc, bow / fan, 8-way volley'));
      expect(stages, contains('Stage 29 — The Underworld, a second dimension'));
      expect(stages, contains('Stage 30 — Title screen, world list, creative mode, tutorial, credits, stats'));
      expect(stages.any((s) => s.contains('**') || s.endsWith('.')), isFalse);
    });

    test('the parse rules on hand-written rows', () {
      const text = '| # | Stage | Status |\n|:--|:---|:---|\n'
          '| 3 | Streaming world + delta save. More words (x) | ✅ | |\n'
          '| 21a | **Four structures.** Details | ✅ | |\n'
          '| 7 | Day/night (with hunger) and death | ✅ | |\n'
          'not a row | 9 | nope |\n';
      expect(CreditsScreen.parseStages(text), ['Stage 3 — Streaming world + delta save', 'Stage 21a — Four structures', 'Stage 7 — Day/night']);
    });

    test('the credits frame the stages', () {
      final lines = CreditsScreen.creditsLines(['Stage 1 — A', 'Stage 2 — B']);
      expect(lines.first, 'VOXEL MINECRAFT');
      expect(lines, containsAllInOrder(['Engine', 'Fonts', 'Music and sound', 'Lineage', 'Stages', 'Stage 1 — A', 'Stage 2 — B', 'Thanks for playing.']));
      expect(lines.last, 'Esc closes');
    });
  });

  group('Creative and stats', () {
    test('the stats block saves creative, metres walked and portal trips under Godot keys', () {
      final gs = GameState.instance;
      gs
        ..resetStats()
        ..creative = true
        ..distanceWalked = 123.5
        ..dimensionVisits = 2
        ..blocksMined = 4
        ..blocksPlaced = 3
        ..playTime = 61.0;
      final d = jsonDecode(jsonEncode(gs.toJson())) as Map<String, dynamic>;
      expect([d['creative'], d['distance_walked'], d['dimension_visits']], [true, 123.5, 2]);
      gs.resetStats();
      expect([gs.creative, gs.distanceWalked, gs.dimensionVisits, gs.blocksMined], [false, 0.0, 0, 0]);
      gs.fromJson(d);
      expect([gs.creative, gs.distanceWalked, gs.dimensionVisits, gs.blocksMined, gs.blocksPlaced], [true, 123.5, 2, 4, 3]);
      expect(SettingsPanel.statsText(), 'Play time 1 min · walked 123 m\nBlocks broken 4 · placed 3\nMobs killed 0 · deaths 0 · dimension trips 2');
      gs.fromJson(const {'blocks_mined': 1}); // a save from before stage 30
      expect([gs.creative, gs.distanceWalked, gs.dimensionVisits], [false, 0.0, 0]);
    });
  });
}
