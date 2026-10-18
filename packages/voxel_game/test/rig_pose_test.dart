import 'package:flutter_scene/scene.dart' show Node;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_game/voxel_game.dart';
import 'package:voxel_scene/voxel_scene.dart' show RigPart;

const _dash = RigPose(
  parts: {
    'leg0': (rx: 0.75, ry: 0.0, rz: 0.0),
    'arm0': (rx: -1.35, ry: 0.0, rz: -0.3),
    'body': (rx: 0.0, ry: 0.0, rz: 0.2),
  },
  lean: -0.45,
);

const _wave = RigPose(parts: {'arm0': (rx: 0.0, ry: 0.0, rz: -2.6)}, rate: 5.0);

(RigAnimator, Map<String, RigPart>) _humanoid() {
  final parts = {
    for (final n in ['leg0', 'leg1', 'body', 'arm0', 'arm1', 'head']) n: RigPart(Node(), Vector3.zero()),
  };
  return (RigAnimator(RigKind.humanoid, parts), parts);
}

/// [frames] frames of a humanoid walking at 5 m/s, holding [held].
void _walk(RigAnimator animator, int frames, RigPose? held, {double from = 0.0}) {
  for (var i = 0; i < frames; i++) {
    animator.pose(1 / 60, age: from + i / 60, speed: 5.0, held: held);
  }
}

final _spec = VoxelGameSpec(
  blocks: const [
    BlockType('stone', color: 0x808080, hardness: 1.5),
    BlockType('dirt', color: 0x74502F, hardness: 0.5),
    BlockType('grass', color: 0x4C9437, hardness: 0.6, drop: 'dirt'),
    BlockType.liquid('water', color: 0x3366CC),
  ],
  world: const WorldGenSpec(
    terrain: TerrainRecipe.flat(20),
    seaLevel: 5,
    caves: CaveSpec.none,
    biomes: [Biome('plains', top: 'grass', under: 'dirt')],
  ),
  player: const PlayerSpec(poses: {'dash': _dash, 'wave': _wave}),
  sky: SkySpec.alwaysDay,
);

Future<VoxelGame> _start() async {
  final game = await VoxelGame.startHeadless(_spec);
  game.spawner.enabled = false;
  for (var i = 0; i < 600 && !game.ready; i++) {
    game.frame(1 / 60);
    await Future<void>.delayed(Duration.zero);
  }
  expect(game.ready, isTrue);
  return game;
}

void main() {
  test("a held pose's weight goes in, and out once let go, at its own rate", () {
    final (animator, _) = _humanoid();
    _walk(animator, 1, _wave);
    expect(animator.heldWeight, closeTo(5.0 / 60, 1e-12), reason: 'rate × dt of the way in');
    _walk(animator, 1, _wave);
    expect(animator.heldWeight, closeTo(1 - (1 - 5.0 / 60) * (1 - 5.0 / 60), 1e-12));
    _walk(animator, 240, _wave);
    expect(animator.heldWeight, closeTo(1.0, 1e-6));
    _walk(animator, 1, null);
    expect(animator.heldWeight, closeTo(1 - 5.0 / 60, 1e-6), reason: "let go, it fades at the last pose's rate");
    _walk(animator, 240, null);
    expect(animator.heldWeight, 0.0, reason: 'gone, not a sliver');

    final (fast, _) = _humanoid();
    _walk(fast, 1, _dash);
    expect(fast.heldWeight, closeTo(20.0 / 60, 1e-12), reason: 'the default rate is 20');
  });

  test("at full weight a posed part's angles are the pose's, over the walk; let go, the walk has them back", () {
    final (animator, parts) = _humanoid();
    final (plain, plainParts) = _humanoid();
    _walk(animator, 120, _dash);
    _walk(plain, 120, null);
    final arm = parts['arm0']!, leg = parts['leg0']!;
    expect([arm.rx, arm.ry, arm.rz], [closeTo(-1.35, 1e-9), closeTo(0.0, 1e-9), closeTo(-0.3, 1e-9)]);
    expect(leg.rx, closeTo(0.75, 1e-9));
    expect(parts['body']!.rz, closeTo(0.2, 1e-9), reason: 'a part the walk does not drive');
    expect(parts['arm1']!.rx, plainParts['arm1']!.rx, reason: 'a part the pose does not name keeps its walk');

    _walk(animator, 120, null, from: 2.0);
    _walk(plain, 120, null, from: 2.0);
    expect(arm.rx, closeTo(plainParts['arm0']!.rx, 1e-6), reason: 'the swing again');
    expect(parts['body']!.rz, closeTo(0.0, 1e-6), reason: 'back to where it was, though the walk never set it');
  });

  test("the held pose's lean is in the topple a rig is placed with, by its weight", () {
    final (animator, _) = _humanoid();
    expect(RigInstance.toppleOf(animator, 0.3), 0.3);
    _walk(animator, 1, _dash);
    expect(RigInstance.toppleOf(animator, 0.0), closeTo(-0.45 * 20.0 / 60, 1e-12));
    _walk(animator, 120, _dash);
    expect(RigInstance.toppleOf(animator, 0.0), closeTo(-0.45, 1e-9));
    expect(RigInstance.toppleOf(animator, 1.0), closeTo(1.0 - 0.45, 1e-9), reason: 'added to a death or a bed');
    _walk(animator, 120, null);
    expect(RigInstance.toppleOf(animator, 0.0), 0.0);
  });

  test('a pose of a part the rig lacks throws', () {
    final (animator, _) = _humanoid();
    const tail = RigPose(parts: {'tail': (rx: 1.0, ry: 0.0, rz: 0.0)});
    expect(() => animator.pose(1 / 60, age: 0.0, speed: 0.0, held: tail), throwsArgumentError);
  });

  test(
    'the player holds a declared pose for its seconds, a new hold replacing the old; an unknown one throws',
    () async {
      final game = await _start();
      final p = game.player;
      expect(p.heldPose, isNull);
      expect(() => p.holdPose('bow', 1.0), throwsArgumentError, reason: 'not in PlayerSpec.poses');
      expect(() => p.holdPose('dash', 0.0), throwsArgumentError);

      p.holdPose('dash', 0.4);
      for (var i = 0; i < 20; i++) {
        game.frame(1 / 60);
      }
      expect(p.heldPose, 'dash', reason: 'a third of a second in');
      for (var i = 0; i < 6; i++) {
        game.frame(1 / 60);
      }
      expect(p.heldPose, isNull, reason: 'over after its 0.4 s');

      p.holdPose('dash', 0.4);
      game.frame(1 / 60);
      p.holdPose('wave', 1.0);
      for (var i = 0; i < 30; i++) {
        game.frame(1 / 60);
      }
      expect(p.heldPose, 'wave', reason: 'replaced, and held for its own seconds');
      for (var i = 0; i < 33; i++) {
        game.frame(1 / 60);
      }
      expect(p.heldPose, isNull);
    },
  );
}
