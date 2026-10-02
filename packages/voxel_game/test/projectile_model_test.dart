import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_game/voxel_game.dart';

void main() {
  test('shots of one size, colour and glow share one model', () {
    final arrow = ProjectileModel.of(ProjectileSpec.arrow);
    expect(ProjectileModel.of(ProjectileSpec.arrow), same(arrow));
    // Declared apart, harder and faster: the same look, so the same model.
    expect(ProjectileModel.of(const ProjectileSpec(damage: 9.0, speed: 40.0)), same(arrow));
    expect(ProjectileModel.of(const ProjectileSpec(color: 0x404040)), isNot(same(arrow)));

    final bolt = ProjectileModel.of(ProjectileSpec.bolt);
    expect(bolt, isNot(same(arrow)));
    expect(bolt.size.x, 0.5);
    expect(
      ProjectileModel.of(const ProjectileSpec(kind: 'bolt', thickness: 0.5, length: 0.5, color: 0x70A0FF)),
      isNot(same(bolt)),
      reason: 'lit, not glowing',
    );
  });

  test("a shot's shape is its spec's, not its kind's name", () {
    final arrow = ProjectileModel.of(ProjectileSpec.arrow);
    expect(arrow.size, Vector3(0.06, 0.06, 0.6));
    // A spear under another name keeps the arrow's look.
    expect(ProjectileModel.of(const ProjectileSpec(kind: 'spear')), same(arrow));
    // A fireball named 'arrow' is drawn as its own box, not a stick.
    final ball = ProjectileModel.of(const ProjectileSpec(thickness: 0.4, length: 0.4, color: 0xFF6020, glow: true));
    expect(ball.size, Vector3.all(0.4));
  });

  test('a trail is part of the look: one more model, not one a shot', () {
    final bolt = ProjectileModel.of(ProjectileSpec.bolt);
    expect(bolt.trail, 1.6);
    expect(ProjectileModel.of(ProjectileSpec.arrow).trail, 0.0);
    // The bolt's box and colour without its streak.
    final bare = ProjectileModel.of(
      const ProjectileSpec(kind: 'bolt', thickness: 0.5, length: 0.5, color: 0x70A0FF, glow: true),
    );
    expect(bare, isNot(same(bolt)));
    // A light, a fire or an effect changes what it does, not how it is drawn.
    expect(
      ProjectileModel.of(const ProjectileSpec(light: 6.0, burns: 3.0)),
      same(ProjectileModel.of(ProjectileSpec.arrow)),
    );
    expect(ProjectileSpec.fireball.burns, greaterThan(0.0));
    expect(ProjectileModel.of(ProjectileSpec.fireball).rgb.x, 1.0);
  });
}
