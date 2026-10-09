import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:voxel_engine/core.dart';

const _negX = ChunkVisibility.negX, _posX = ChunkVisibility.posX;
const _negY = ChunkVisibility.negY, _posY = ChunkVisibility.posY;
const _negZ = ChunkVisibility.negZ, _posZ = ChunkVisibility.posZ;

/// The window every test searches: 9 × 9 chunks around the origin.
const ChunkPos _min = (x: -4, z: -4), _max = (x: 4, z: 4);
const ChunkPos _origin = (x: 0, z: 0);

Set<ChunkPos> _window() => {
  for (var z = _min.z; z <= _max.z; z++)
    for (var x = _min.x; x <= _max.x; x++) (x: x, z: z),
};

/// A visibility joining [pairs] in the given sections, nothing elsewhere.
ChunkVisibility _with(Map<int, List<(int, int)>> pairs) {
  final masks = Uint16List(ChunkVisibility.sections);
  pairs.forEach((s, list) {
    for (final (a, b) in list) {
      masks[s] |= 1 << ChunkVisibility.pairBit(a, b);
    }
  });
  return ChunkVisibility(masks);
}

/// Stone up to y 64, open sky above: sections 0–3 closed, 4–7 open.
final ChunkVisibility _ground = ChunkVisibility(
  Uint16List.fromList([0, 0, 0, 0, for (var s = 4; s < 8; s++) ChunkVisibility.allPairs]),
);

/// [_ground] with a cave in section 1 open to the west and a shaft from it up
/// to the sky.
final ChunkVisibility _shaft = () {
  final cave = _with({
    1: [(_negX, _posY)],
    2: [(_negY, _posY)],
    3: [(_negY, _posY)],
  });
  return ChunkVisibility(Uint16List.fromList([for (var s = 0; s < 8; s++) cave.masks[s] | _ground.masks[s]]));
}();

/// Every chunk of the window is [base] unless [world] names it; a key mapped
/// to null is a chunk with no mesh yet.
SectionOcclusion _search(ChunkVisibility base, [Map<ChunkPos, ChunkVisibility?> world = const {}]) =>
    SectionOcclusion((pos) => world.containsKey(pos) ? world[pos] : base);

Set<ChunkPos> _from(SectionOcclusion search, ChunkPos camera, int section) {
  search.update(camera, section, min: _min, max: _max);
  return search.reached;
}

/// The camera's chunk and its four side neighbours: what a camera sees from a
/// section that leads nowhere.
const Set<ChunkPos> _cell = {(x: 0, z: 0), (x: -1, z: 0), (x: 1, z: 0), (x: 0, z: -1), (x: 0, z: 1)};

void main() {
  test('an open world reaches every chunk', () {
    expect(_from(_search(ChunkVisibility.open), _origin, 5), _window());
    expect(_from(_search(_ground), _origin, 5), _window());
  });

  test('a sealed cave reaches only its own chunk and the walls around it', () {
    final search = _search(_ground, {
      _origin: _with({1: []}),
    });
    expect(_from(search, _origin, 1), _cell);
  });

  test('a cave with a shaft to the surface reaches everything through it', () {
    final reached = _from(_search(_ground, {_origin: _shaft}), _origin, 1);
    expect(reached, _window());
  });

  test('a chunk with no mesh is crossed as open', () {
    final tunnel = _with({
      1: [(_negX, _posX)],
    });
    final world = <ChunkPos, ChunkVisibility?>{
      for (var x = _min.x; x <= _max.x; x++) (x: x, z: 0): tunnel,
      (x: 2, z: 0): null,
    };
    final reached = _from(_search(_with({}), world), _origin, 1);
    expect(reached, containsAll(<ChunkPos>[(x: 4, z: 0), (x: -4, z: 0), (x: 2, z: 1), (x: 2, z: -1)]));
    expect(reached, isNot(contains((x: 4, z: 1))));
    final closed = _from(_search(_with({}), {...world, (x: 2, z: 0): _with({})}), _origin, 1);
    expect(closed, isNot(contains((x: 3, z: 0))));
  });

  test('the camera reaches out of a section of solid stone (a third-person camera inside a hill)', () {
    final reached = _from(_search(_with({})), _origin, 3);
    expect(reached, _cell);
  });

  test('a U tunnel does not see past its bend', () {
    // From the camera's chunk east to x 3, north to z 2, then back west: the
    // last leg runs against the first one's direction.
    final world = <ChunkPos, ChunkVisibility>{
      (x: 1, z: 0): _with({
        1: [(_negX, _posX)],
      }),
      (x: 2, z: 0): _with({
        1: [(_negX, _posX)],
      }),
      (x: 3, z: 0): _with({
        1: [(_negX, _posZ)],
      }),
      (x: 3, z: 1): _with({
        1: [(_negZ, _posZ)],
      }),
      (x: 3, z: 2): _with({
        1: [(_negZ, _negX)],
      }),
      (x: 2, z: 2): _with({
        1: [(_posX, _negX)],
      }),
      (x: 1, z: 2): _with({
        1: [(_posX, _negX)],
      }),
    };
    final reached = _from(_search(_with({}), world), _origin, 1);
    expect(reached, {..._cell, (x: 2, z: 0), (x: 3, z: 0), (x: 3, z: 1), (x: 3, z: 2)});
  });

  test('the search never leaves the window', () {
    final reached = _from(_search(ChunkVisibility.open), (x: 4, z: -4), 7);
    expect(reached, _window());
  });

  test('the same inputs twice do not rerun; a new section, window or camera chunk does', () {
    final search = _search(ChunkVisibility.open);
    expect(search.update(_origin, 2, min: _min, max: _max), isTrue);
    expect(search.update(_origin, 2, min: _min, max: _max), isFalse);
    expect(search.update(_origin, 3, min: _min, max: _max), isTrue);
    expect(search.update((x: 1, z: 0), 3, min: _min, max: _max), isTrue);
    expect(search.update((x: 1, z: 0), 3, min: _min, max: (x: 5, z: 4)), isTrue);
    expect(search.update((x: 1, z: 0), 3, min: _min, max: (x: 5, z: 4)), isFalse);
  });

  test('markChanged reruns, but only for a chunk in the window', () {
    final world = <ChunkPos, ChunkVisibility?>{
      _origin: _with({1: []}),
    };
    final search = _search(_ground, world);
    expect(_from(search, _origin, 1), _cell);
    search.markChanged((x: 9, z: 9));
    expect(search.update(_origin, 1, min: _min, max: _max), isFalse);
    world[_origin] = _shaft;
    search.markChanged(_origin);
    expect(search.update(_origin, 1, min: _min, max: _max), isTrue);
    expect(search.reached, _window());
  });

  test('sectionAt clamps a camera above or below the world into its end sections', () {
    expect(SectionOcclusion.sectionAt(0), 0);
    expect(SectionOcclusion.sectionAt(15.9), 0);
    expect(SectionOcclusion.sectionAt(16), 1);
    expect(SectionOcclusion.sectionAt(127.5), 7);
    expect(SectionOcclusion.sectionAt(300), 7);
    expect(SectionOcclusion.sectionAt(-20), 0);
  });

  test('a camera outside the window or a section past the world is refused', () {
    final search = _search(ChunkVisibility.open);
    expect(() => search.update((x: 5, z: 0), 0, min: _min, max: _max), throwsArgumentError);
    expect(() => search.update(_origin, 8, min: _min, max: _max), throwsRangeError);
  });
}
