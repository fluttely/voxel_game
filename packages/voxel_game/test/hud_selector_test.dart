import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voxel_game/voxel_game.dart';

void main() {
  testWidgets('a HudSelector rebuilds when the value it selects changes, not on every tick', (tester) async {
    final frames = ValueNotifier(0);
    var hp = 20.0;
    var builds = 0, selects = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: HudSelector(
          frames: frames,
          select: () {
            selects++;
            return (hp: hp, dead: hp <= 0);
          },
          builder: (context, value) {
            builds++;
            return Text('${value.hp}');
          },
        ),
      ),
    );
    expect(builds, 1);

    for (var i = 0; i < 5; i++) {
      frames.value++;
      await tester.pump();
    }
    expect(builds, 1, reason: 'five ticks with the same record build nothing');

    hp = 12.0;
    frames.value++;
    await tester.pump();
    expect(builds, 2, reason: 'a changed value rebuilds once');
    expect(find.text('12.0'), findsOneWidget);

    frames.value++;
    await tester.pump();
    expect(builds, 2, reason: 'and the next tick sees it unchanged');

    await tester.pumpWidget(const SizedBox.shrink());
    final seen = selects;
    frames.value++;
    expect(selects, seen, reason: 'a selector that goes away stops listening');
  });
}
