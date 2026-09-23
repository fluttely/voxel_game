import 'package:vector_math/vector_math.dart';

/// An integer cell position. Value-equal, so it keys maps and sets.
class IVec3 {
  /// The cell ([x], [y], [z]).
  const IVec3(this.x, this.y, this.z);

  /// The cell holding [v]: each coordinate rounded toward negative infinity.
  factory IVec3.floor(Vector3 v) => IVec3(v.x.floor(), v.y.floor(), v.z.floor());

  /// A coordinate.
  final int x, y, z;

  /// (0, 0, 0).
  static const zero = IVec3(0, 0, 0);

  /// One cell up, +y.
  static const up = IVec3(0, 1, 0);

  /// One cell down, -y.
  static const down = IVec3(0, -1, 0);

  /// One cell toward -x.
  static const left = IVec3(-1, 0, 0);

  /// One cell toward +x.
  static const right = IVec3(1, 0, 0);

  /// One cell toward -z.
  static const forward = IVec3(0, 0, -1);

  /// One cell toward +z.
  static const back = IVec3(0, 0, 1);

  /// The four horizontal neighbours: [left], [right], [forward], [back].
  static const sides = [left, right, forward, back];

  /// The cell offset by [o].
  IVec3 operator +(IVec3 o) => IVec3(x + o.x, y + o.y, z + o.z);

  /// The offset from [o] to this cell.
  IVec3 operator -(IVec3 o) => IVec3(x - o.x, y - o.y, z - o.z);

  /// Every coordinate times [k].
  IVec3 operator *(int k) => IVec3(x * k, y * k, z * k);

  /// The Euclidean length.
  double get length => toVector3().length;

  /// The cell's min corner as a vector.
  Vector3 toVector3() => Vector3(x.toDouble(), y.toDouble(), z.toDouble());

  /// The middle of the cell.
  Vector3 get centre => Vector3(x + 0.5, y + 0.5, z + 0.5);

  /// The distance from the cell's min corner to [v].
  double distanceTo(Vector3 v) => (v - toVector3()).length;

  /// `"x,y,z"`, the form [parse] reads: a JSON-safe map key.
  String get key => '$x,$y,$z';

  /// The position a [key] names. Throws a [FormatException] for anything else.
  static IVec3 parse(String key) {
    final p = key.split(',');
    if (p.length != 3) throw FormatException('an IVec3 key is "x,y,z"', key);
    return IVec3(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  @override
  bool operator ==(Object other) => other is IVec3 && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() => '($x, $y, $z)';
}
