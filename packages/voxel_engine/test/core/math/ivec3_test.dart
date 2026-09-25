import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart';

void main() {
  test('value equality and hashing', () {
    expect(const IVec3(1, -2, 3), const IVec3(1, -2, 3));
    expect(const IVec3(1, -2, 3).hashCode, const IVec3(1, -2, 3).hashCode);
    expect(
      (<IVec3>{}
        ..add(const IVec3(0, 0, 0))
        ..add(IVec3.zero)),
      hasLength(1),
    );
    expect(const IVec3(1, 2, 3) == const IVec3(3, 2, 1), isFalse);
  });

  test('floor rounds toward negative infinity, so -0.5 is cell -1', () {
    expect(IVec3.floor(Vector3(-0.5, 0.5, -1.0)), const IVec3(-1, 0, -1));
    expect(IVec3.floor(Vector3(15.999, 127.0, -16.001)), const IVec3(15, 127, -17));
  });

  test('arithmetic follows Godot Vector3i', () {
    expect(const IVec3(1, 2, 3) + IVec3.up, const IVec3(1, 3, 3));
    expect(const IVec3(1, 2, 3) - IVec3.back, const IVec3(1, 2, 2));
    expect(const IVec3(1, -2, 3) * 3, const IVec3(3, -6, 9));
    expect(const IVec3(3, 4, 0).length, closeTo(5.0, 1e-9));
    expect(IVec3.forward, const IVec3(0, 0, -1));
    expect(IVec3.sides, hasLength(4));
  });

  test('centre and distance use the cell middle and origin', () {
    expect(const IVec3(2, 0, -1).centre, Vector3(2.5, 0.5, -0.5));
    expect(const IVec3(0, 0, 0).distanceTo(Vector3(0, 3, 4)), closeTo(5.0, 1e-9));
  });

  test('key round-trips through parse; a malformed key throws', () {
    const b = IVec3(-7, 64, 12);
    expect(IVec3.parse(b.key), b);
    expect(() => IVec3.parse('1,2'), throwsFormatException);
    expect(() => IVec3.parse('1,2,x'), throwsFormatException);
  });
}
