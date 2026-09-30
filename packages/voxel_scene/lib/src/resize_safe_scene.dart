import 'dart:ui' as ui;

import 'package:flutter_scene/scene.dart';

import 'render_size_watch.dart';

/// A [Scene] whose sun drops its static shadow cache on the frame the scene is
/// rendered at a new size, so no cached tile outlives the depth texture it was
/// drawn with.
///
/// flutter_scene draws the sun's static shadow casters into persistent tiles,
/// each paired with a depth texture from the view's transient pool, and a
/// resize clears that pool. Impeller's Vulkan backend caches a framebuffer on
/// the tile keyed by the tile alone (flutter/flutter#192538), so the next
/// refresh of a tile begins a render pass on the freed depth's image view:
/// a null dereference in the Adreno driver's `vkCmdBeginRenderPass`, within
/// the first seconds of a phone game that turns to landscape while its chunks
/// stream in. With the cache off for that one frame flutter_scene discards
/// the tiles, and the next frame builds new ones on the new depth. That frame
/// draws the static casters with the dynamic ones, as a scene without the
/// cache always does.
///
/// Remove it once the Flutter the kit requires keys the framebuffer cache on
/// every attachment (flutter/flutter#192539).
base class ResizeSafeScene extends Scene {
  final RenderSizeWatch _size = RenderSizeWatch();

  @override
  void renderViews(List<RenderView> views, ui.Canvas canvas, {ui.Rect? region, double? pixelRatio}) {
    final sun = sunLight;
    final resized = _size.changed(views, region: region, pixelRatio: pixelRatio, renderScale: renderScale);
    if (sun == null || !resized || !sun.cacheStaticShadows) {
      super.renderViews(views, canvas, region: region, pixelRatio: pixelRatio);
      return;
    }
    sun.cacheStaticShadows = false;
    super.renderViews(views, canvas, region: region, pixelRatio: pixelRatio);
    sun.cacheStaticShadows = true;
  }
}
