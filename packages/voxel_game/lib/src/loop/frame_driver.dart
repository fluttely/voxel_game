import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Which of [FrameDriver]'s two sources runs the frames.
enum FrameSource {
  /// The display's ticker: the window shows.
  ticker,

  /// The driver's timer: the window is hidden.
  timer,

  /// The ticker again, before its first frame after a hidden spell.
  handOver,
}

/// The one source of a game's frames: the display's ticker while the window
/// shows, a [Timer] while it is hidden.
///
/// Flutter turns frames off for [AppLifecycleState.hidden] — a desktop window
/// covered by another or minimised — and its tickers stop with them, so a game
/// stepped only by them stops its world, a host's for every client (rule 12).
/// While the lifecycle says hidden, a periodic timer calls [onFrame] in their
/// place and nothing is drawn; any other state stops it, `paused` and
/// `detached` included: a phone in the background is suspended by its system
/// anyway. The lifecycle is read when the driver is made too, since a desktop
/// app launched behind another window starts hidden.
///
/// One source at a time. A ticker's frame while the timer runs (a metrics
/// change forces one even hidden) runs nothing, and the ticker's first frame
/// after a hidden spell runs with no time: its own delta would carry the whole
/// spell, which the timer has already run.
class FrameDriver with WidgetsBindingObserver {
  /// A driver of [onFrame], listening to the app's lifecycle until [dispose].
  FrameDriver(this.onFrame, {this.period = const Duration(milliseconds: 16), this.maxCatchUp = 60}) {
    WidgetsBinding.instance.addObserver(this);
    _follow(WidgetsBinding.instance.lifecycleState);
  }

  /// Runs one frame, `dt` seconds after the last.
  final void Function(double dt) onFrame;

  /// The timer's period, whole milliseconds: what the platform's timers keep.
  final Duration period;

  /// The most periods one timer event runs. A timer the system held back (App
  /// Nap, on the Mac) runs the periods it missed, up to this many; a longer
  /// stall is lost, as a long frame's is.
  final int maxCatchUp;

  /// Which source runs the frames now.
  FrameSource get source => _source;
  FrameSource _source = FrameSource.ticker;

  Timer? _timer;
  int _ticks = 0;

  /// A frame from the display's ticker, [dt] seconds after its last one.
  void tickerFrame(double dt) {
    switch (_source) {
      case FrameSource.timer:
        return;
      case FrameSource.handOver:
        _source = FrameSource.ticker;
        onFrame(0.0);
      case FrameSource.ticker:
        onFrame(dt);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _follow(state);

  void _follow(AppLifecycleState? state) {
    final hidden = state == AppLifecycleState.hidden;
    if (hidden && _source != FrameSource.timer) {
      _ticks = 0;
      _timer = Timer.periodic(period, _timerFrame);
      _source = FrameSource.timer;
    } else if (!hidden && _source == FrameSource.timer) {
      _timer!.cancel();
      _timer = null;
      _source = FrameSource.handOver;
    }
  }

  // The timer's tick counts the periods gone by, the ones a late event
  // skipped included.
  void _timerFrame(Timer timer) {
    final periods = math.min(timer.tick - _ticks, maxCatchUp);
    _ticks = timer.tick;
    final dt = period.inMicroseconds / Duration.microsecondsPerSecond;
    for (var i = 0; i < periods; i++) {
      onFrame(dt);
    }
  }

  /// Stops the timer and the listening.
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
  }
}
