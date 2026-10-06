import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:voxel_engine/core.dart';
import 'package:voxel_engine/worldgen.dart';

const List<String> _names = [
  'stone', 'dirt', 'grass', 'sand', 'water', 'log', 'leaves', 'planks', 'cobblestone', 'bricks', //
  'mossy', 'ladder', 'lamp', 'spawner', 'chest', 'bones', 'gold', 'iron', 'slab', 'glass', 'bed',
  'torch', 'table', 'furnace', 'fence', 'gravel', 'farmland', 'wheat', 'rail', 'flower', 'bedrock',
  'sandstone', 'plate', 'tnt',
];
final Map<String, int> _ids = {for (var i = 0; i < _names.length; i++) _names[i]: i + 1};
int _id(String name) => _ids[name]!;

const _dungeon = Dungeon(
  walls: 'bricks',
  mossy: 'mossy',
  ladder: 'ladder',
  light: 'lamp',
  spawner: 'spawner',
  chest: 'chest',
  relic: 'bones',
  treasure: 'gold',
);
const _tower = Tower(walls: 'bricks', mossy: 'mossy', floor: 'planks', ladder: 'ladder', chest: 'chest', light: 'lamp');
const _well = Well(rim: 'cobblestone', water: 'water', posts: 'fence', roof: 'planks');
const _camp = Camp(cloth: 'planks', poles: 'log', chest: 'chest', light: 'lamp');
const _temple = Temple(stone: 'sandstone', chest: 'chest', light: 'lamp', plate: 'plate', trap: 'tnt');
const _ruins = Ruins(
  floor: 'cobblestone',
  ground: 'grass',
  walls: 'bricks',
  mossy: 'mossy',
  plants: ['flower'],
  chest: 'chest',
);
const _mine = Mine(
  frame: 'cobblestone',
  posts: 'fence',
  roof: 'planks',
  ladder: 'ladder',
  beams: 'log',
  walls: 'stone',
  rail: 'rail',
  light: 'torch',
  chest: 'chest',
  spawner: 'spawner',
  veins: {'gold': 5, 'iron': 13},
);
const _village = Village(
  floor: 'cobblestone',
  walls: 'planks',
  corners: 'log',
  roof: 'planks',
  path: 'gravel',
  wellRim: 'bricks',
  water: 'water',
  roofRim: 'slab',
  window: 'glass',
  chest: 'chest',
  bed: 'bed',
  torch: 'torch',
  workbench: 'table',
  furnace: 'furnace',
  light: 'lamp',
  farm: VillageFarm(soil: 'dirt', tilled: 'farmland', crop: 'wheat', fence: 'fence', torch: 'torch'),
);

/// Ground at [ground] (the first air cell) everywhere: stone under dirt under
/// grass, drawn on by one structure at (0, [ground], 0).
class _Flat {
  _Flat(Structure s, {this.ground = 40, int seed = 1})
    : site = StructureSite(
        name: 's',
        x: 0,
        y: ground - s.depth,
        z: 0,
        seed: seed,
        writer: ChunkWriter(Uint8List(ChunkSize.volume), 0, 0),
        block: _id,
        surfaceAt: (x, z) => ground,
      ) {
    final reach = floorDiv(s.radius, 16) + 1;
    for (var cz = -reach; cz <= reach; cz++) {
      for (var cx = -reach; cx <= reach; cx++) {
        final blocks = Uint8List(ChunkSize.volume);
        for (var i = 0; i < 256; i++) {
          for (var y = 0; y < ground; y++) {
            blocks[ChunkSize.index(i % 16, y, i ~/ 16)] = y == ground - 1
                ? _id('grass')
                : (y >= ground - 3 ? _id('dirt') : _id('stone'));
          }
        }
        final w = ChunkWriter(blocks, cx, cz);
        _chunks[(cx, cz)] = w;
        s.build(
          StructureSite(
            name: 's',
            x: 0,
            y: ground - s.depth,
            z: 0,
            seed: seed,
            writer: w,
            block: (n) => _ids[n] ?? (throw ArgumentError.value(n)),
            surfaceAt: (x, z) => ground,
            isRock: (id) => id == _id('stone'),
            isLiquid: (id) => id == _id('water'),
          ),
        );
      }
    }
  }

  final int ground;
  final Map<(int, int), ChunkWriter> _chunks = {};

  /// The structure's site, for its rolls and its plan.
  final StructureSite site;

  /// The block at world ([x], [y], [z]).
  int at(int x, int y, int z) => _chunks[(floorDiv(x, 16), floorDiv(z, 16))]!.get(x, y, z)!;

  /// Every cell holding [name], in world coordinates.
  List<(int, int, int)> all(String name) => [
    for (final w in _chunks.values)
      for (var i = 0; i < ChunkSize.volume; i++)
        if (w.blocks[i] == _id(name)) (w.ox + (i & 15), i >> 8, w.oz + ((i >> 4) & 15)),
  ];
}

void main() {
  test('every stock structure names its blocks, and a world fails to compile without one', () {
    for (final s in [_dungeon, _tower, _well, _camp, _ruins, _mine, _village, _temple]) {
      expect(s.blockNames, isNotEmpty);
      expect(s.blockNames.every(_ids.containsKey), isTrue, reason: '$s');
    }
    expect(_village.blockNames, containsAll(['farmland', 'wheat', 'fence', 'dirt']));
    expect(_mine.blockNames, containsAll(['gold', 'iron']));
    final spec = WorldGenSpec(
      biomes: const [Biome('plains', top: 'grass')],
      structures: [StructureSpec('well', const Well(rim: 'marble', water: 'water', posts: 'fence', roof: 'planks'))],
    );
    expect(spec.blockNames, contains('marble'));
    expect(() => spec.compile(_ids, 1), throwsA(isA<ArgumentError>().having((e) => e.invalidValue, 'block', 'marble')));
  });

  test('a dungeon: three rooms under the ground, two guarded, a chest at the end, a ladder up', () {
    final f = _Flat(_dungeon);
    expect(f.all('spawner'), hasLength(2));
    expect(f.all('chest'), hasLength(1));
    final (cx, cy, cz) = f.all('chest').single;
    expect(cx, 12);
    expect(cz, 0);
    expect(cy, lessThanOrEqualTo(40 - 14 + 1));
    expect(f.at(cx, cy + 1, cz), 0, reason: 'the room is hollow');
    final ladder = f.all('ladder');
    expect(ladder.map((c) => (c.$1, c.$3)).toSet(), {(-15, -3)});
    expect(ladder.map((c) => c.$2).reduce((a, b) => a > b ? a : b), 40, reason: 'the shaft opens on the surface');
    expect(f.all('mossy'), isNotEmpty);
  });

  test("a dungeon's plan is where its parts are drawn, for every seed and depth", () {
    for (var seed = 1; seed <= 8; seed++) {
      for (final ground in const [40, 20]) {
        final f = _Flat(_dungeon, ground: ground, seed: seed);
        final plan = DungeonPlan.of(_dungeon, f.site.placed, f.site.roll);
        final why = 'seed $seed, ground $ground';
        expect(plan.floor, ground == 20 ? 8 : inInclusiveRange(40 - 14 - 13, 40 - 14), reason: why);
        expect({for (final (x, y, z) in f.all('spawner')) IVec3(x, y, z)}, plan.spawners.toSet(), reason: why);
        expect(plan.spawners, hasLength(2));
        final (cx, cy, cz) = f.all('chest').single;
        expect(IVec3(cx, cy, cz), plan.chest, reason: why);
        expect(plan.rooms.map((r) => r.centre.x), [-12, 0, 12]);
        const furniture = {'lamp', 'spawner', 'chest', 'bones', 'gold', 'ladder'};
        for (final (:centre, :half) in plan.rooms) {
          expect([_id('bricks'), _id('mossy')], contains(f.at(centre.x, plan.floor, centre.z)), reason: why);
          expect([_id('bricks'), _id('mossy')], contains(f.at(centre.x, plan.floor + half, centre.z)), reason: why);
          for (var y = plan.floor + 1; y < plan.floor + half; y++) {
            for (var z = centre.z - half + 1; z < centre.z + half; z++) {
              for (var x = centre.x - half + 1; x < centre.x + half; x++) {
                final id = f.at(x, y, z);
                final open = id == 0 || (y == plan.floor + 1 && furniture.map(_id).contains(id)) || id == _id('ladder');
                expect(open, isTrue, reason: '$why: ($x, $y, $z) in a room holds $id');
              }
            }
          }
        }
      }
    }
    final bare = DungeonPlan.of(const Dungeon(walls: 'bricks', ladder: 'ladder'), (
      name: 's',
      x: 0,
      y: 26,
      z: 0,
    ), (_) => 0);
    expect(bare.spawners, isEmpty);
    expect(bare.chest, isNull);
  });

  test("a dungeon's rooms are joined: the shaft's foot reaches inside every room, for every seed and depth", () {
    for (var seed = 1; seed <= 8; seed++) {
      for (final ground in const [40, 20]) {
        final f = _Flat(_dungeon, ground: ground, seed: seed);
        final plan = DungeonPlan.of(_dungeon, f.site.placed, f.site.roll);
        // Through air and ladder, kept under the rooms' ceilings so the fill
        // never climbs the shaft out onto the surface.
        final top = plan.floor + plan.rooms.map((r) => r.half).reduce((a, b) => a > b ? a : b);
        final foot = IVec3(-15, plan.floor + 1, -3);
        expect(f.at(foot.x, foot.y, foot.z), _id('ladder'));
        final reached = {foot};
        final open = [foot];
        while (open.isNotEmpty) {
          final cell = open.removeLast();
          for (final step in const [
            IVec3(1, 0, 0),
            IVec3(-1, 0, 0),
            IVec3(0, 1, 0),
            IVec3(0, -1, 0),
            IVec3(0, 0, 1),
            IVec3(0, 0, -1),
          ]) {
            final next = cell + step;
            if (next.y > top || reached.contains(next)) continue;
            final id = f.at(next.x, next.y, next.z);
            if (id != 0 && id != _id('ladder')) continue;
            reached.add(next);
            open.add(next);
          }
        }
        expect(
          [for (final room in plan.rooms) reached.contains(room.centre + const IVec3(0, 1, 0))],
          [true, true, true],
          reason: 'seed $seed, ground $ground',
        );
      }
    }
  });

  test("a mine's plan is where its parts are drawn, for every seed and depth", () {
    final spawned = <bool>{};
    for (var seed = 1; seed <= 12; seed++) {
      for (final ground in const [40, 28]) {
        final f = _Flat(_mine, ground: ground, seed: seed);
        final plan = MinePlan.of(_mine, f.site.placed, f.site.roll);
        final why = 'seed $seed, ground $ground';
        expect(plan.floor, ground == 28 ? 20 : 24, reason: why);
        expect(plan.length, inInclusiveRange(20, 30), reason: why);
        final (cx, cy, cz) = f.all('chest').single;
        expect(IVec3(cx, cy, cz), plan.chest, reason: why);
        expect(plan.end, plan.chest);
        final spawners = [for (final (x, y, z) in f.all('spawner')) IVec3(x, y, z)];
        expect(spawners, [?plan.spawner], reason: why);
        spawned.add(plan.spawner != null);
        expect(f.at(plan.end.x, plan.end.y + 1, plan.end.z), 0, reason: '$why: headroom at the end');
        expect(f.all('rail'), hasLength(plan.length - 1 - spawners.length), reason: why);
      }
    }
    expect(spawned, {true, false}, reason: 'some mines are guarded and some are not');
  });

  test('a tower: a door, a ladder to the top floor, the chest up there', () {
    final f = _Flat(_tower);
    expect(f.at(0, 41, 2), 0);
    expect(f.at(0, 42, 2), 0);
    expect(f.at(0, 49, 0), _id('chest'));
    expect(f.at(-1, 48, -1), 0, reason: 'the hatch');
    expect(f.all('ladder'), hasLength(7));
    expect(f.at(0, 48, 1), _id('planks'));
  });

  test('a well: a rim a block over the ground around water down to its depth', () {
    final f = _Flat(_well);
    expect([for (var y = 36; y <= 40; y++) f.at(0, y, 0)], everyElement(_id('water')));
    expect(f.at(0, 35, 0), _id('stone'), reason: 'the ground under the water');
    expect(f.at(1, 40, 1), _id('cobblestone'));
    expect(f.at(0, 43, 0), _id('planks'));
    expect(f.all('fence'), hasLength(4));
  });

  test('a camp: a tent on poles, a chest under it, a light off to the side', () {
    final f = _Flat(_camp);
    expect(f.at(0, 40, 0), _id('chest'));
    expect(f.at(0, 44, 0), _id('planks'));
    expect(f.at(6, 40, 0), _id('lamp'));
    expect(f.at(3, 40, 2), _id('log'));
    expect(f.at(0, 41, 0), 0, reason: 'headroom');
  });

  test('ruins: a floor in the ground, broken walls, the ground through the cracks', () {
    final f = _Flat(_ruins);
    var floor = 0, ground = 0;
    for (var z = -3; z <= 3; z++) {
      for (var x = -3; x <= 3; x++) {
        final id = f.at(x, 39, z);
        if (id == _id('cobblestone')) floor++;
        if (id == _id('grass')) ground++;
      }
    }
    expect(floor + ground, 49);
    expect(ground, greaterThan(0));
    expect(f.all('bricks').length + f.all('mossy').length, greaterThan(10));
    for (final (x, _, z) in [...f.all('bricks'), ...f.all('mossy')]) {
      expect(x.abs() == 3 || z.abs() == 3, isTrue, reason: 'walls stand on the edge');
    }
  });

  test('a mine: a ladder down to a corridor with a rail to its chest, ore in its walls', () {
    final f = _Flat(_mine);
    final (cx, cy, cz) = f.all('chest').single;
    expect((cy, cz), (25, 0), reason: 'on the floor at floorY');
    expect(cx, inInclusiveRange(20, 30));
    final rails = f.all('rail');
    expect(rails.length + f.all('spawner').length, cx - 1);
    expect(f.all('ladder').map((c) => c.$2).toSet(), {for (var y = 25; y <= 40; y++) y});
    expect(f.all('gold').length + f.all('iron').length, greaterThan(0));
    expect(f.all('torch'), isNotEmpty);
    expect(f.at(5, 26, 0), 0, reason: 'headroom over the rail');
    final low = _Flat(_mine, ground: 28);
    expect(low.all('chest').single.$2, 28 - 8 + 1, reason: 'eight under a ground lower than floorY');
  });

  test('a village: huts around a well, each with its door to the well and a path, and a farm', () {
    final f = _Flat(_village);
    final chests = f.all('chest');
    expect(chests.length, inInclusiveRange(4, 7));
    expect(f.all('bed'), hasLength(chests.length));
    expect(f.all('table'), hasLength(1));
    expect(f.all('furnace'), hasLength(chests.length > 3 ? 1 : 0));
    expect(f.all('gravel'), isNotEmpty);
    expect(f.at(0, 40, 0), _id('water'));
    expect(f.all('wheat'), hasLength(7 * 4));
    expect(f.all('farmland'), hasLength(7 * 4));
    // Every chest is at a hut's back, away from the well: its door faces the well along z.
    for (final (x, _, z) in chests) {
      final bed = f.all('bed').firstWhere((b) => b.$3 == z && (b.$1 - x) == 2);
      expect(bed.$2, 41);
    }
  });

  test('a temple: a step pyramid over a chamber, two chests, a plate on its trap, a way in from the south', () {
    final f = _Flat(_temple);
    expect(f.at(0, 39, 0), _id('tnt'));
    expect(f.at(0, 40, 0), _id('plate'));
    expect(f.all('chest'), unorderedEquals([(-1, 41, -1), (1, 41, -1)]));
    expect(f.at(0, 44, 0), _id('lamp'));
    for (var y = 41; y <= 43; y++) {
      expect(f.at(0, y, 1), 0, reason: 'the chamber at $y');
    }
    expect([f.at(0, 41, 4), f.at(0, 42, 4)], [0, 0], reason: 'the corridor opens on the south face');
    expect(f.at(0, 43, 3), _id('sandstone'), reason: 'over the corridor');
    expect(f.at(4, 40, 4), _id('sandstone'), reason: 'the base is 9 x 9');
    expect(f.at(5, 40, 0), 0);
    expect(f.at(0, 49, 0), _id('sandstone'), reason: 'the top step');
    expect(f.at(1, 49, 0), 0);
    expect(f.at(0, 50, 0), 0);
    final bare = _Flat(const Temple(stone: 'sandstone'));
    expect(bare.at(0, 39, 0), _id('grass'), reason: 'no trap: the ground stays');
    expect(bare.all('chest'), isEmpty);
  });

  group('in a world', () {
    final spec = WorldGenSpec(
      biomes: const [Biome('plains', top: 'grass', under: 'dirt')],
      ores: const [Ore('gold', share: 0.05)],
      structures: [
        const StructureSpec('village', _village, chance: 0.5),
        const StructureSpec('mine', _mine, chance: 0.6, regionChunks: 5),
        const StructureSpec('dungeon', _dungeon, chance: 0.6),
        const StructureSpec('tower', _tower, chance: 0.6, regionChunks: 3),
        const StructureSpec('well', _well, chance: 0.6, regionChunks: 3),
        const StructureSpec('camp', _camp, chance: 0.6, regionChunks: 3),
        const StructureSpec('ruins', _ruins, chance: 0.6, regionChunks: 3),
      ],
    );

    test('structures keep apart: none within reach of another', () {
      final g = spec.compile(_ids, 21);
      final radius = {for (final s in spec.structures) s.name: s.structure.radius};
      final sites = <PlacedStructure>{};
      for (var cx = -30; cx <= 30; cx += 2) {
        for (var cz = -30; cz <= 30; cz += 2) {
          sites.addAll(g.structuresNear(cx, cz));
        }
      }
      expect(sites.map((s) => s.name).toSet(), hasLength(7), reason: 'every kind appears');
      final list = sites.toList();
      for (var i = 0; i < list.length; i++) {
        for (var j = i + 1; j < list.length; j++) {
          final a = list[i], b = list[j];
          final d = radius[a.name]! + radius[b.name]!;
          expect((a.x - b.x).abs() > d || (a.z - b.z).abs() > d, isTrue, reason: '$a and $b');
        }
      }
    });

    test("a world's dungeons and mines are drawn where the generator's rolls plan them", () {
      final g = spec.compile(_ids, 21);
      final sites = <PlacedStructure>{};
      for (var cx = -30; cx <= 30; cx += 2) {
        for (var cz = -30; cz <= 30; cz += 2) {
          sites.addAll(g.structuresNear(cx, cz).where((s) => s.name == 'dungeon' || s.name == 'mine'));
        }
      }
      final byName = {
        for (final name in const ['dungeon', 'mine']) name: sites.where((s) => s.name == name).take(2).toList(),
      };
      expect(byName.values.every((l) => l.length == 2), isTrue, reason: 'two of each to look at');
      for (final site in byName.values.expand((l) => l)) {
        final reach = site.name == 'dungeon' ? _dungeon.radius : _mine.radius;
        final cells = <String, Set<IVec3>>{'spawner': {}, 'chest': {}};
        for (var cz = floorDiv(site.z - reach, 16); cz <= floorDiv(site.z + reach, 16); cz++) {
          for (var cx = floorDiv(site.x - reach, 16); cx <= floorDiv(site.x + reach, 16); cx++) {
            final blocks = g.generateIn(cx, cz, 0);
            for (var i = 0; i < ChunkSize.volume; i++) {
              final cell = IVec3(cx * 16 + (i & 15), i >> 8, cz * 16 + ((i >> 4) & 15));
              if ((cell.x - site.x).abs() > reach || (cell.z - site.z).abs() > reach) continue;
              if (blocks[i] == _id('spawner')) cells['spawner']!.add(cell);
              if (blocks[i] == _id('chest')) cells['chest']!.add(cell);
            }
          }
        }
        final roll = g.rollOf(site);
        final (spawners, chest) = site.name == 'dungeon'
            ? (DungeonPlan.of(_dungeon, site, roll).spawners, DungeonPlan.of(_dungeon, site, roll).chest)
            : ([?MinePlan.of(_mine, site, roll).spawner], MinePlan.of(_mine, site, roll).chest);
        expect(cells['spawner'], spawners.toSet(), reason: '$site');
        expect(cells['chest'], {chest}, reason: '$site');
      }
    });

    test('a world of structures is pure whatever order its chunks come in', () {
      final a = spec.compile(_ids, 21), b = spec.compile(_ids, 21);
      final first = [for (var cx = -4; cx <= 4; cx++) a.generateIn(cx, 2, 0)];
      final second = [for (var cx = 4; cx >= -4; cx--) b.generateIn(cx, 2, 0)].reversed.toList();
      expect(second, first);
    });

    test('two structures of one name are refused', () {
      expect(
        () => WorldGenSpec(
          biomes: const [Biome('plains', top: 'grass')],
          structures: const [StructureSpec('a', _well), StructureSpec('a', _camp)],
        ).compile(_ids, 1),
        throwsArgumentError,
      );
    });
  });
}
