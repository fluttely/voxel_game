/// What some work costs a vertex, from the samples of it so far: their
/// microseconds over their vertices, older samples fading by [fade] at each
/// new one. Weighed by vertices, a small sample's fixed cost (creating a node,
/// a geometry) barely moves the rate a large one set, where a mean of each
/// sample's own rate would take a 128-vertex upload's 130 ns a vertex for the
/// rate of a 60,000-vertex one that costs 3.
class VertexRate {
  /// A rate with no sample yet, fading older samples by [fade] (0 < fade < 1).
  VertexRate({this.fade = 0.8}) : assert(fade > 0 && fade < 1, 'a fade is a fraction');

  /// What an older sample keeps of its weight at each new one.
  final double fade;

  double _us = 0, _vertices = 0;

  /// Microseconds a vertex; 0 before a sample with vertices.
  double get usPerVertex => _vertices > 0 ? _us / _vertices : 0.0;

  /// Adds work over [vertices] that took [us] microseconds.
  void add(num us, int vertices) {
    if (vertices <= 0) throw ArgumentError.value(vertices, 'vertices', 'a sample has vertices');
    _us = _us * fade + us;
    _vertices = _vertices * fade + vertices;
  }
}
