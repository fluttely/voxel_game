import 'package:flutter_test/flutter_test.dart';
import 'package:voxel_game/voxel_game.dart';

void main() {
  test('one colour is one model, whichever item it is', () {
    final model = PickupModel.of(0.5, 0.4, 0.3);
    expect(PickupModel.of(0.5, 0.4, 0.3), same(model));
    expect(PickupModel.of(0.5, 0.4, 0.31), isNot(same(model)));
    expect(model.voxels, hasLength(64));
  });
}
