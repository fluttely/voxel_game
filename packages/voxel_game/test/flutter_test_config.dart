import 'dart:async';
import 'dart:ui' show Offset;

import 'package:flutter3d_pointer_lock/flutter3d_pointer_lock.dart';
import 'package:voxel_game/voxel_game.dart';

/// Every test runs on a pointer lock and an audio device that are never there,
/// so none opens SoLoud and none depends on how SoLoud fails without its native
/// library.
/// A test that wants a device that opens sets its own and restores this one.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  PointerLockPlatform.instance = _NoPointerLock();
  AudioDevice.instance = AudioDevice(open: () async => false, close: () async {});
  await testMain();
}

/// A test host has no pointer to lock. `flutter3d_pointer_lock` 0.5 opens its
/// event channel on Android, which `flutter test` reports as the platform, and
/// a plain `test` has no binding to open it on.
final class _NoPointerLock extends PointerLockPlatform {
  @override
  bool get isSupported => false;
  @override
  Stream<Offset> get deltas => const Stream<Offset>.empty();
  @override
  Stream<CaptureState> get stateChanges => const Stream<CaptureState>.empty();
  @override
  Future<void> capture() async {}
  @override
  Future<void> release() async {}
  @override
  Future<void> reset() async {}
}
