import 'dart:ui';

/// How a [MapMark] is drawn.
enum MapMarkShape {
  /// A dot: the spawn.
  dot,

  /// A square: a structure.
  square,

  /// A diamond: a waypoint.
  diamond,

  /// A ringed dot: a tamed mount.
  ring,
}

/// A place the map marks, named: at block ([x], [z]), drawn as [shape] in
/// [colour], [label] beside it on the whole map.
class MapMark {
  /// A mark of [shape] at ([x], [z]).
  const MapMark(this.shape, this.x, this.z, this.label, this.colour);

  /// How it is drawn.
  final MapMarkShape shape;

  /// Where it is, in blocks.
  final double x, z;

  /// What the whole map names it.
  final String label;

  /// Its colour.
  final Color colour;
}
