import 'dart:ui' as ui;

import 'package:flutter_scene/scene.dart';

/// Remembers what sized a scene's last render — the region, the pixel ratio,
/// the render scale and each view's viewport and scale, everything flutter_scene
/// sizes its targets from — and says when a render is sized differently.
///
/// It allocates nothing a render: the views' part is kept in lists it reuses.
class RenderSizeWatch {
  bool _seen = false;
  ui.Rect? _region;
  double? _pixelRatio;
  double _renderScale = 0.0;
  final List<ui.Rect?> _viewports = [];
  final List<double?> _viewScales = [];

  /// Whether a render of [views] into [region] at [pixelRatio] and
  /// [renderScale] is sized differently from the last one this watch saw; the
  /// first one is. It becomes the one the next call compares against.
  bool changed(
    List<RenderView> views, {
    required ui.Rect? region,
    required double? pixelRatio,
    required double renderScale,
  }) {
    var same =
        _seen &&
        _region == region &&
        _pixelRatio == pixelRatio &&
        _renderScale == renderScale &&
        _viewports.length == views.length;
    for (var i = 0; same && i < views.length; i++) {
      same = _viewports[i] == views[i].viewport && _viewScales[i] == views[i].renderScale;
    }
    if (same) return false;
    _seen = true;
    _region = region;
    _pixelRatio = pixelRatio;
    _renderScale = renderScale;
    _viewports
      ..clear()
      ..addAll(views.map((v) => v.viewport));
    _viewScales
      ..clear()
      ..addAll(views.map((v) => v.renderScale));
    return true;
  }
}
