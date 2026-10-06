import 'dart:typed_data';

import 'package:voxel_engine/core.dart';

import 'spec_generator.dart';
import 'world_gen_spec.dart';

/// A world of several dimensions, one [WorldGenSpec] each, compiled for one
/// seed: the [ChunkGenerator] the worker isolates run, handing each chunk to
/// the generator of the dimension it is asked for. Dimension `d` is
/// `specs[d]`; the first is the world a game starts in.
class DimensionGenerator implements ChunkGenerator {
  /// Compiles every one of [specs] for [seed] against [ids]; throws
  /// [ArgumentError] for none, and as [SpecGenerator] does for a spec.
  DimensionGenerator(List<WorldGenSpec> specs, Map<String, int> ids, int seed)
    : dimensions = List.unmodifiable([for (final s in specs) SpecGenerator(s, ids, seed)]) {
    if (dimensions.isEmpty) throw ArgumentError.value(specs, 'specs', 'a world needs at least one dimension');
  }

  /// The generator of each dimension, by number.
  final List<SpecGenerator> dimensions;

  /// The generator of dimension [d].
  SpecGenerator operator [](int d) => dimensions[d];

  /// The world seed.
  int get seed => dimensions.first.seed;

  @override
  Uint8List generateIn(int chunkX, int chunkZ, int dimension) {
    if (dimension < 0 || dimension >= dimensions.length) {
      throw ArgumentError.value(dimension, 'dimension', 'the world has ${dimensions.length}');
    }
    return dimensions[dimension].generateIn(chunkX, chunkZ, dimension);
  }
}
