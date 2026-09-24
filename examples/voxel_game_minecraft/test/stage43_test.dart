import 'dart:math' as math;

import 'package:voxel_game_minecraft/src/core/blocks.dart';
import 'package:voxel_game_minecraft/src/player/player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_game/voxel_game.dart' show ShoulderOrbit;

/// Stage 43: the third-person eye never ends up inside a block.
///
/// A wall seen from the inside is not drawn — its faces point the other way —
/// so a near plane one millimetre past a wall shows the whole cave system
/// behind it. These prove the sweep that keeps the eye out: it accounts for
/// the shoulder, the rise, the jolt, the sway and the near plane's own width,
/// it never treats a pocket beyond a wall as room, and it comes in at once
/// instead of easing through the rock.
void main() {
  final stone = Blocks.indexOf('stone');
  const air = Blocks.air;
  // The player's seat, on the kit's orbit.
  final orbit = ShoulderOrbit(distance: Player.orbitDistance, shoulder: Player.orbitShoulder, rise: Player.orbitRise);

  /// The eye path of a player standing at the origin, looking down -Z (yaw 0),
  /// so [Player.backVec] is +Z and the orbit runs away from the wall behind.
  Vector3 Function(double) eyePath({Vector3? jitter}) {
    final pivot = Vector3(0.5, 1.5, 0.5);
    final right = Player.rightFor(0.0);
    final up = Vector3(0, 1, 0);
    final back = Vector3(0, 0, 1);
    final j = jitter ?? Vector3.zero();
    return (double d) => pivot + orbit.offset(right, up, back, d) + j;
  }

  group('the eye is a box, not a point', () {
    test('a cell of stone is refused, air and grass are not', () {
      expect(Player.blocksCamera(stone), isTrue);
      expect(Player.blocksCamera(air), isFalse);
      expect(Player.blocksCamera(Blocks.indexOf('tall_grass')), isFalse);
      expect(Player.blocksCamera(Blocks.indexOf('torch')), isFalse);
      expect(Player.blocksCamera(Blocks.indexOf('water')), isFalse);
      // Non-opaque but a body stops at it: the camera does too.
      expect(Player.blocksCamera(Blocks.indexOf('glass')), isTrue);
      expect(Player.blocksCamera(Blocks.indexOf('door_z')), isTrue);
    });

    test('a box brushing a solid cell is refused even when its centre is clear', () {
      // Cell (0, 0, 0) is solid, everything else is air.
      bool clear(int x, int y, int z) => !(x == 0 && y == 0 && z == 0);
      // A centre well inside the air cell beside it: clear.
      expect(ShoulderOrbit.boxIsClear(Vector3(1.5, 0.5, 0.5), ShoulderOrbit.eyeRadius, clear), isTrue);
      // A centre still in the air cell, but within a radius of the solid one.
      expect(ShoulderOrbit.boxIsClear(Vector3(1.0 + ShoulderOrbit.eyeRadius * 0.5, 0.5, 0.5), ShoulderOrbit.eyeRadius, clear), isFalse);
    });
  });

  group('the orbit sweep', () {
    test('open sky leaves the eye at the full orbit distance', () {
      final d = ShoulderOrbit.clearDistance(Player.orbitDistance, eyePath(), (_, _, _) => true);
      expect(d, Player.orbitDistance);
    });

    test('a wall behind the head stops the eye in front of it', () {
      // Wall filling z >= 3 (the orbit runs toward +z).
      bool clear(int x, int y, int z) => z < 3;
      final d = ShoulderOrbit.clearDistance(Player.orbitDistance, eyePath(), clear);
      expect(d, lessThan(Player.orbitDistance));
      // Every point up to `d` is genuinely clear, the box included.
      for (var t = 0.0; t <= d; t += 0.05) {
        expect(ShoulderOrbit.boxIsClear(eyePath()(t), ShoulderOrbit.eyeRadius, clear), isTrue, reason: 'at $t');
      }
      // And the eye it lands on keeps the whole near-plane box out of the wall.
      expect(eyePath()(d).z + ShoulderOrbit.eyeRadius, lessThan(3.0));
    });

    test('the rise is swept too: a ledge only the risen eye meets still stops it', () {
      // A slab of stone in the cell band y == 1, z >= 2 — the pivot sits at
      // y 1.5, so a ray at pivot height passes clean through the gap the
      // 0.15 m rise does not: the sweep must see what the ray missed.
      bool clear(int x, int y, int z) => !(y == 1 && z >= 2);
      final d = ShoulderOrbit.clearDistance(Player.orbitDistance, eyePath(), clear);
      expect(d, lessThan(2.0));
    });

    test('a jolt toward the wall shortens the orbit, never buries the eye', () {
      bool clear(int x, int y, int z) => z < 3;
      final still = ShoulderOrbit.clearDistance(Player.orbitDistance, eyePath(), clear);
      final jolted = ShoulderOrbit.clearDistance(
        Player.orbitDistance,
        eyePath(jitter: Vector3(0, 0, 0.4)),
        clear,
      );
      expect(jolted, lessThan(still));
      expect(eyePath(jitter: Vector3(0, 0, 0.4))(jolted).z + ShoulderOrbit.eyeRadius, lessThan(3.0));
    });

    test('a pocket beyond a wall is not room the camera may have', () {
      // A one-cell wall at z == 2 with open air past it.
      bool clear(int x, int y, int z) => z != 2;
      final d = ShoulderOrbit.clearDistance(Player.orbitDistance, eyePath(), clear);
      expect(eyePath()(d).z, lessThan(2.0));
    });

    test('a head walled in on every side pins the eye to the head', () {
      final d = ShoulderOrbit.clearDistance(Player.orbitDistance, eyePath(), (_, _, _) => false);
      expect(d, 0.0);
      // And the body is hidden there, so the eye is never inside its own head.
      expect(d, lessThan(Player.modelHideDistance));
    });

    test('the shoulder eases in, so a pinned eye sits on the head and not beside it', () {
      final atHead = orbit.offset(Player.rightFor(0.0), Vector3(0, 1, 0), Vector3(0, 0, 1), 0.0);
      expect(atHead.length, lessThan(1e-5));
      final seated = orbit.offset(Player.rightFor(0.0), Vector3(0, 1, 0), Vector3(0, 0, 1), Player.orbitDistance);
      expect(seated.z, closeTo(Player.orbitDistance, 1e-5));
      expect(seated.y, closeTo(Player.orbitRise, 1e-5));
      expect(math.sqrt(seated.x * seated.x), closeTo(Player.orbitShoulder, 1e-5));
    });

    test('the sweep is fine enough that no step jumps a wall', () {
      // One cell of stone anywhere along the orbit must be caught: a step
      // coarser than the cell could straddle it.
      for (var wall = 1; wall <= 4; wall++) {
        bool clear(int x, int y, int z) => z != wall;
        final d = ShoulderOrbit.clearDistance(Player.orbitDistance, eyePath(), clear);
        expect(eyePath()(d).z + ShoulderOrbit.eyeRadius, lessThanOrEqualTo(wall.toDouble()),
            reason: 'wall at z == $wall');
      }
    });
  });

  group('a wall at head height, from every angle', () {
    // The bug as it was reported: standing in third person with a block wall
    // at the height of the head, turning until the back of the head is against
    // it. Floor under y == 10, and a wall two blocks tall from x == 12 on.
    bool clear(int x, int y, int z) => y >= 10 && !(x >= 12 && y >= 10 && y < 12);
    final pivot = Vector3(11.5, 11.5, 8.5); // the third-person pivot: feet + 1.5

    /// The player's basis at [yaw] / [pitch], as `Player` builds it.
    ({Vector3 right, Vector3 up, Vector3 back}) basis(double yaw, double pitch) {
      final forward = Vector3(
        -math.sin(yaw) * math.cos(pitch),
        math.sin(pitch),
        -math.cos(yaw) * math.cos(pitch),
      );
      return (
        right: Player.rightFor(yaw),
        up: Vector3(math.sin(pitch) * math.sin(yaw), math.cos(pitch), math.sin(pitch) * math.cos(yaw)),
        back: -forward,
      );
    }

    test('the eye never lands inside the wall, at any yaw or pitch', () {
      var inside = 0;
      for (var yi = 0; yi < 360; yi++) {
        final yaw = yi * math.pi / 180.0;
        for (var pi = -8; pi <= 8; pi++) {
          final pitch = pi * 0.09;
          final b = basis(yaw, pitch);
          Vector3 eyeAt(double d) => pivot + orbit.offset(b.right, b.up, b.back, d);
          final d = ShoulderOrbit.clearDistance(Player.orbitDistance, eyeAt, clear);
          if (!ShoulderOrbit.boxIsClear(eyeAt(d), ShoulderOrbit.eyeRadius, clear)) inside++;
        }
      }
      expect(inside, 0);
    });

    test('the ray it replaces did land inside it, which is the bug', () {
      // The old rule: one ray from the shoulder straight down the back vector,
      // the eye seated 0.35 m in front of whatever it hit but never nearer
      // than 0.6 m — a floor that pushes the eye *through* a wall standing
      // closer than 0.95 m — and the shoulder and the rise never swept at all.
      var inside = 0;
      for (var yi = 0; yi < 360; yi++) {
        final yaw = yi * math.pi / 180.0;
        for (var pi = -8; pi <= 8; pi++) {
          final pitch = pi * 0.09;
          final b = basis(yaw, pitch);
          final from = pivot + b.right * Player.orbitShoulder;
          var hit = -1.0;
          for (var t = 0.0; t <= Player.orbitDistance + 0.3; t += 0.01) {
            final at = from + b.back * t;
            if (!clear(at.x.floor(), at.y.floor(), at.z.floor())) {
              hit = t;
              break;
            }
          }
          final d = hit >= 0.0 ? math.max(hit - 0.35, 0.6) : Player.orbitDistance;
          final eye = pivot + b.right * Player.orbitShoulder + b.up * Player.orbitRise + b.back * d;
          if (!clear(eye.x.floor(), eye.y.floor(), eye.z.floor())) inside++;
        }
      }
      expect(inside, greaterThan(0), reason: 'the old rule is what this stage removes');
    });
  });
}
