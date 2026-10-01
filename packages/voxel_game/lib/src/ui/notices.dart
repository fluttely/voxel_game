/// One line of [Notices] as a HUD shows it: [id] keeps its widget across
/// rebuilds, [fading] turns on for its last [Notices.fadeSeconds].
typedef NoticeLine = ({int id, String text, bool fading});

/// What the HUD tells the player for a few seconds: the notification feed a
/// game writes to with `VoxelGame.notify`, and the pickups, one line per
/// item: a repeat within [mergeSeconds] of the last adds to its line and
/// shows it afresh.
///
/// Its clock is the frame's (`VoxelGame.frame` advances it): a line is shown
/// for [seconds] of real time, whatever screen is open.
class Notices {
  /// Seconds a line is shown.
  static const double seconds = 3.0;

  /// Its last seconds, while it fades.
  static const double fadeSeconds = 0.5;

  /// A pickup of the same item this soon after the last adds to its line.
  static const double mergeSeconds = 1.0;

  /// The most lines of each list; a new one pushes out the oldest.
  static const int kept = 5;

  final List<_Notice> _feed = [];
  final List<_Notice> _pickups = [];
  int _nextId = 0;

  /// Adds [text] to the feed. Throws for empty text.
  void add(String text) {
    if (text.isEmpty) throw ArgumentError.value(text, 'text', 'a notice says something');
    _push(_feed, _Notice(_nextId++, text));
  }

  /// [count] of [item], named [name], went into the bag. Throws for a count
  /// below 1.
  void picked(String item, String name, int count) {
    if (count < 1) throw ArgumentError.value(count, 'count', 'a pickup is of one or more');
    for (final n in _pickups) {
      if (n.item == item && n.age < mergeSeconds) {
        n
          ..count += count
          ..text = '+${n.count} $name'
          ..age = 0.0;
        return;
      }
    }
    _push(_pickups, _Notice(_nextId++, '+$count $name', item: item, count: count));
  }

  static void _push(List<_Notice> list, _Notice n) {
    list.add(n);
    if (list.length > kept) list.removeRange(0, list.length - kept);
  }

  /// Ages every line by [dt] seconds and drops those past [seconds].
  void advance(double dt) {
    for (final n in [..._feed, ..._pickups]) {
      n.age += dt;
    }
    _feed.removeWhere((n) => n.age >= seconds);
    _pickups.removeWhere((n) => n.age >= seconds);
  }

  /// The feed, oldest first.
  List<NoticeLine> get feed => [for (final n in _feed) n.line];

  /// The pickups, oldest first.
  List<NoticeLine> get pickups => [for (final n in _pickups) n.line];
}

class _Notice {
  _Notice(this.id, this.text, {this.item = '', this.count = 0});

  final int id;
  String text;
  final String item;
  int count;
  double age = 0.0;

  NoticeLine get line => (id: id, text: text, fading: age >= Notices.seconds - Notices.fadeSeconds);
}
