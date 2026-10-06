import 'dart:ui' as ui;

/// Holds each picture of a scene back until the GPU has finished drawing it,
/// so no Flutter frame waits on the 3D render.
///
/// A scene frame is recorded into a picture, not drawn: the picture only
/// references the texture flutter_scene renders into, and is put on screen once
/// the GPU reports its submissions done. Until then every Flutter frame draws
/// the newest finished picture, and no new scene frame is recorded: the
/// renderer draws into a ring of two textures, and a second frame in flight
/// would write the one on screen. So the scene shows one frame late, and is
/// rendered on the vsyncs that find the last one finished.
///
/// Pure: the submission ids are handed in, so [GpuPacedScene] reads them from
/// flutter_scene's tracker and a test makes them up.
final class ScenePacer {
  ({int submission, ui.Picture picture})? _inFlight;
  ui.Picture? _showing;

  /// Whether a recorded picture is still on the GPU.
  bool get inFlight => _inFlight != null;

  /// The picture each Flutter frame draws now; null until the first finishes.
  ui.Picture? get showing => _showing;

  /// One Flutter frame onto [canvas]. The picture in flight is shown from now
  /// on once [completed] (every submission through that id is done) reaches
  /// its last submission; with none in flight, [render] records the next one
  /// onto the canvas it is handed and returns the id of the last submission it
  /// made. Then the newest finished picture is drawn, if any is.
  void paint(ui.Canvas canvas, {required int completed, required int Function(ui.Canvas canvas) render}) {
    final flight = _inFlight;
    if (flight != null && flight.submission <= completed) {
      _showing?.dispose();
      _showing = flight.picture;
      _inFlight = null;
    }
    if (_inFlight == null) {
      final recorder = ui.PictureRecorder();
      final submission = render(ui.Canvas(recorder));
      _inFlight = (submission: submission, picture: recorder.endRecording());
    }
    final picture = _showing;
    if (picture != null) canvas.drawPicture(picture);
  }

  /// Lets go of both pictures.
  void dispose() {
    _showing?.dispose();
    _inFlight?.picture.dispose();
    _showing = null;
    _inFlight = null;
  }
}
