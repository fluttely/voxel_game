/// The whole pure-Dart engine in one import.
///
/// Each subject is also a library of its own, for whoever wants only a part:
/// `package:voxel_engine/core.dart`, `/worldgen.dart`, `/content.dart`,
/// `/signals.dart` and `/net.dart`. Nothing here depends on Flutter.
library;

export 'content.dart';
export 'core.dart';
export 'net.dart';
export 'signals.dart';
export 'worldgen.dart';
