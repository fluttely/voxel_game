import 'package:flutter/widgets.dart';

/// A piece of a HUD rebuilt only when what it shows changes: on every tick of
/// [frames] it runs [select] and rebuilds when the value is not `==` to the
/// last one.
///
/// Select a value with structural equality (a number, a string, a record of
/// them), so that an unchanged value reads as unchanged; for a list of them,
/// pass `listEquals` as [equals].
///
/// ```dart
/// HudSelector(
///   frames: game.frames,
///   select: () => game.player.hp,
///   builder: (context, hp) => Text('$hp'),
/// )
/// ```
class HudSelector<T> extends StatefulWidget {
  /// A piece built by [builder] from [select], checked on every tick of
  /// [frames].
  const HudSelector({
    super.key,
    required this.frames,
    required this.select,
    required this.builder,
    this.equals = _same,
  });

  static bool _same(Object? a, Object? b) => a == b;

  /// Ticks once a frame: `VoxelGame.frames`.
  final Listenable frames;

  /// Reads the value shown.
  final T Function() select;

  /// Builds the piece from the value.
  final Widget Function(BuildContext context, T value) builder;

  /// Whether two values read the same: `==` unless given.
  final bool Function(T a, T b) equals;

  @override
  State<HudSelector<T>> createState() => _HudSelectorState<T>();
}

class _HudSelectorState<T> extends State<HudSelector<T>> {
  late T _value = widget.select();

  @override
  void initState() {
    super.initState();
    widget.frames.addListener(_tick);
  }

  @override
  void didUpdateWidget(HudSelector<T> old) {
    super.didUpdateWidget(old);
    if (!identical(old.frames, widget.frames)) {
      old.frames.removeListener(_tick);
      widget.frames.addListener(_tick);
    }
    _value = widget.select();
  }

  @override
  void dispose() {
    widget.frames.removeListener(_tick);
    super.dispose();
  }

  void _tick() {
    final value = widget.select();
    if (!widget.equals(value, _value)) setState(() => _value = value);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value);
}
