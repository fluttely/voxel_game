import 'dart:async';

import 'package:voxel_game/voxel_game.dart';

/// Every test runs on an audio device that is never there, so none opens
/// SoLoud and none depends on how SoLoud fails without its native library.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  AudioDevice.instance = AudioDevice(open: () async => false, close: () async {});
  await testMain();
}
