import 'package:flutter_test/flutter_test.dart';
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
      ProjectileModel.of(const ProjectileSpec(kind: 'bolt', radius: 0.25, color: 0x70A0FF)),
      isNot(same(bolt)),
      reason: 'lit, not glowing',
    );
  });
}
