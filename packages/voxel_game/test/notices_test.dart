import 'package:flutter_test/flutter_test.dart';
import 'package:voxel_game/voxel_game.dart';

void main() {
  test('a notice is shown for its seconds, fading in the last of them', () {
    final n = Notices()..add('Night falls');
    expect(n.feed.single.text, 'Night falls');
    expect(n.feed.single.fading, isFalse);
    n.advance(Notices.seconds - Notices.fadeSeconds);
    expect(n.feed.single.fading, isTrue);
    n.advance(Notices.fadeSeconds);
    expect(n.feed, isEmpty);
  });

  test('a pickup of the same item soon after adds to its line, and shows it afresh', () {
    final n = Notices()..picked('dirt', 'Dirt', 3);
    final id = n.pickups.single.id;
    n
      ..advance(Notices.mergeSeconds - 0.1)
      ..picked('dirt', 'Dirt', 2);
    expect(n.pickups.single, (id: id, text: '+5 Dirt', fading: false));
    n.advance(Notices.seconds - 0.1);
    expect(n.pickups, hasLength(1), reason: 'the merge restarted its clock');
    // Past the merge window, a new line.
    n
      ..advance(0.05)
      ..picked('dirt', 'Dirt', 1);
    expect([for (final p in n.pickups) p.text], ['+5 Dirt', '+1 Dirt']);
    n.picked('stone', 'Stone', 1);
    expect([for (final p in n.pickups) p.text], ['+5 Dirt', '+1 Dirt', '+1 Stone']);
  });

  test('a new line pushes out the oldest past the most kept', () {
    final n = Notices();
    for (var i = 0; i < Notices.kept + 2; i++) {
      n.add('line $i');
    }
    expect(n.feed.first.text, 'line 2');
    expect(n.feed, hasLength(Notices.kept));
    expect(n.pickups, isEmpty, reason: 'the feed and the pickups are kept apart');
  });

  test('an empty notice and a pickup of nothing are refused', () {
    expect(() => Notices().add(''), throwsArgumentError);
    expect(() => Notices().picked('dirt', 'Dirt', 0), throwsArgumentError);
  });
}
