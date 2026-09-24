import 'dart:math' as math;

import 'package:voxel_game_minecraft/src/core/species.dart';
import 'package:voxel_game_minecraft/src/entities/mob.dart';
import 'package:voxel_game_minecraft/src/player/player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart';

/// Stage 34's pure pieces (`--anim-probe` and `--model-probe` cover the poses
/// on screen): the mirrored wing, the wingbeat, the gait rate per body, the
/// arm a humanoid rests in, and the saddle's multiplier on the view sway.
void main() {
  group('a mirrored part', () {
    test('a voxel at x covers [x, x+1], so its mirror covers [-x-1, -x]', () {
      final wing = <IVec3, Vector3>{};
      VoxelModel.box(wing, const IVec3(0, 0, -2), const IVec3(3, 0, 2), Vector3(1, 0, 0));
      final left = VoxelModel.mirrorX(wing);
      expect(left.length, wing.length);
      // The right wing reaches out over x 0..4, the left one out over -4..0.
      expect(wing.keys.map((k) => k.x).reduce(math.min), 0);
      expect(wing.keys.map((k) => k.x).reduce(math.max), 3);
      expect(left.keys.map((k) => k.x).reduce(math.min), -4);
      expect(left.keys.map((k) => k.x).reduce(math.max), -1);
      // y and z are untouched, and the colour rides along with the voxel.
      for (final e in wing.entries) {
        final mirrored = IVec3(-e.key.x - 1, e.key.y, e.key.z);
        expect(left[mirrored], e.value, reason: '${e.key}');
      }
    });

    test('mirroring twice is the identity', () {
      final v = <IVec3, Vector3>{};
      VoxelModel.box(v, const IVec3(-3, 1, -1), const IVec3(5, 2, 4), Vector3(0.2, 0.4, 0.6));
      final back = VoxelModel.mirrorX(VoxelModel.mirrorX(v));
      expect(back.length, v.length);
      for (final e in v.entries) {
        expect(back[e.key], e.value, reason: '${e.key}');
      }
    });
  });

  group('the wingbeat', () {
    test('a folded wing rests against the body whatever the phase', () {
      for (var i = 0; i < 8; i++) {
        expect(Mob.motion.wingAngle(i * math.pi / 4, 0.0), Mob.wingFold, reason: 'phase $i');
      }
      // Down against the flank, not held out: a wing near level reads as a
      // bird standing with two boards nailed to it.
      expect(Mob.wingFold, lessThan(-0.7));
      // And drawn in, because voxels cannot fold the way feathers do.
      expect(Mob.wingFoldSpan, lessThan(0.6));
      expect(Mob.wingFoldSpan, greaterThan(0.0));
    });

    test('a full beat carries the tip a full sweep up and the same down', () {
      expect(Mob.motion.wingAngle(math.pi / 2, 1.0), closeTo(Mob.wingSweep, 1e-9));
      expect(Mob.motion.wingAngle(-math.pi / 2, 1.0), closeTo(-Mob.wingSweep, 1e-9));
      expect(Mob.motion.wingAngle(0.0, 1.0), closeTo(0.0, 1e-9));
      // Up and down are the same size: a beat that favoured one side would
      // read as a wing stuck part-open.
      var up = 0.0, down = 0.0;
      for (var i = 0; i < 360; i++) {
        final a = Mob.motion.wingAngle(i * math.pi / 180.0, 1.0);
        up = math.max(up, a);
        down = math.min(down, a);
      }
      expect(up, closeTo(-down, 1e-9));
    });

    test('half folded sits halfway between the fold and the beat', () {
      final beat = math.sin(1.0) * Mob.wingSweep;
      expect(Mob.motion.wingAngle(1.0, 0.5), closeTo((Mob.wingFold + beat) / 2, 1e-9));
    });

    test('the beat is fast enough to read as a beat and not a wave', () {
      // Three and a half beats a second or better: under about two the wing
      // looks like it is waving rather than holding the bird up.
      expect(Mob.wingRate / (2 * math.pi), greaterThan(3.0));
    });
  });

  group('the gait', () {
    test('short legs take more steps over the same ground', () {
      expect(Mob.gaitRate('bird'), greaterThan(Mob.gaitRate('spider')));
      expect(Mob.gaitRate('spider'), greaterThan(Mob.gaitRate('quadruped')));
      expect(Mob.gaitRate('quadruped'), greaterThan(Mob.gaitRate('humanoid')));
      expect(Mob.gaitRate('blob'), Mob.gaitRate('humanoid')); // the default
    });

    test('a melee undead walks with its arms out, everything else by its sides', () {
      double rest(String id) => Mob.armRest(Species.def(id));
      expect(rest('zombie'), 1.4);
      expect(rest('troll'), 1.4);
      expect(rest('yeti'), 1.4);
      expect(rest('mummy_king'), 1.4);
      // An archer draws a bow and a villager trades: neither shambles.
      expect(rest('skeleton'), 0.0);
      expect(rest('underworld_lord'), 0.0);
      expect(rest('villager'), 0.0);
    });
  });

  group('the saddle', () {
    test('on foot the sway is exactly what it always was', () {
      expect(Player.gaitAmplitude(mounted: false, sprinting: false), 1.0);
      expect(Player.gaitAmplitude(mounted: false, sprinting: true), 1.0);
    });

    test('riding widens it, and a galloping mount widens it again', () {
      final trot = Player.gaitAmplitude(mounted: true, sprinting: false);
      final gallop = Player.gaitAmplitude(mounted: true, sprinting: true);
      expect(trot, Player.trotAmplitude);
      expect(gallop, closeTo(Player.trotAmplitude * Player.gallopBoost, 1e-9));
      expect(gallop, greaterThan(trot));
      expect(trot, greaterThan(Player.gaitAmplitude(mounted: false, sprinting: false)));
    });

    test('the trot is wider per beat but beats less often than a walk', () {
      // A horse covers more ground per beat than a pair of legs does, so the
      // cadence per metre has to come down as the width goes up — otherwise a
      // mount at 8.5 m/s vibrates instead of trotting.
      expect(Player.trotCadence, lessThan(1.0));
      expect(Player.trotAmplitude, greaterThan(1.0));
      expect(Player.trotRoll, greaterThan(1.0));
    });

    test('a horse is already past the speed clamp, so the gallop needs its own number', () {
      // This is why `gallopBoost` exists: speed alone cannot tell a trot from
      // a gallop once both are over the clamp.
      final horse = Species.def('horse').speed;
      expect((horse / Player.walkSpeed).clamp(0.0, 1.7), 1.7);
      expect((horse * 1.4 / Player.walkSpeed).clamp(0.0, 1.7), 1.7);
      expect(Player.gallopBoost, greaterThan(1.0));
    });
  });
}
