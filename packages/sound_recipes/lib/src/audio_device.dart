import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

/// The one audio device every [SoundBank] (and a game that plays SoLoud
/// itself) shares: opened by the first holder to [acquire] it, closed when
/// the last one [release]s it.
///
/// Every open and close runs in one queue, each after the one before, so a
/// [release] that lands while an [acquire] is opening never closes the device
/// under it, and a second holder never re-opens a device already open.
final class AudioDevice {
  /// A device opened by [open] (false: no audio here) and closed by [close].
  /// A test passes its own pair; a game uses [instance].
  AudioDevice({required Future<bool> Function() open, required Future<void> Function() close})
    : _openDevice = open,
      _closeDevice = close;

  /// SoLoud's device: `init` and `deinit`. An open that fails is a
  /// [SoLoudException], and it means no audio here.
  factory AudioDevice.soloud() => AudioDevice(
    open: () async {
      try {
        await SoLoud.instance.init();
        return true;
      } on SoLoudException {
        return false;
      }
    },
    close: () async => SoLoud.instance.deinit(),
  );

  /// The device every bank opens.
  static AudioDevice get instance => _instance;
  static AudioDevice _instance = AudioDevice.soloud();

  /// Replaces [instance]; a test restores the one it found in `tearDown`.
  @visibleForTesting
  static set instance(AudioDevice device) => _instance = device;

  final Future<bool> Function() _openDevice;
  final Future<void> Function() _closeDevice;
  Future<void>? _last;
  bool _open = false;
  int _held = 0;

  /// Whether the device is open now.
  bool get isOpen => _open;

  /// How many holders have it.
  int get held => _held;

  /// Takes a hold of the device, opening it if no one holds it: true when it
  /// is open, false when this platform has no audio (nothing is then held,
  /// and nothing is to be released).
  Future<bool> acquire() => _enqueue(() async {
    if (!_open) _open = await _openDevice();
    if (_open) _held++;
    return _open;
  });

  /// Lets go of a hold an [acquire] gave; the last one closes the device.
  /// Throws [StateError] when no one holds it.
  Future<void> release() => _enqueue(() async {
    if (_held == 0) throw StateError('the audio device is released more often than it was acquired');
    if (--_held > 0) return;
    await _closeDevice();
    _open = false;
  });

  // Idle, a step runs at once; busy, after the last one. The device outlives
  // the zone of any one caller (a test's), so once idle it keeps no future of
  // that zone to chain the next caller's step onto. An error is the caller's,
  // on the future it was handed; the queue goes on.
  Future<T> _enqueue<T>(Future<T> Function() step) {
    final last = _last;
    final done = last == null ? step() : last.then((_) => step());
    late final Future<void> settled;
    settled = done.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
      if (identical(_last, settled)) _last = null;
    });
    _last = settled;
    return done;
  }
}
