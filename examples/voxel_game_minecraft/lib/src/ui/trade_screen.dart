import 'package:flutter/material.dart';

import '../core/items.dart';
import '../entities/mob.dart';
import '../game/game.dart';
import 'hud.dart';

/// Stage 26: a villager's three offers. One row per offer, `take x N -> give x
/// M`; click a row to trade when the bag holds the asked items. Escape (or F)
/// closes it through `Game`.
class TradeScreen extends StatefulWidget {
  const TradeScreen({super.key, required this.game});
  final Game game;

  @override
  State<TradeScreen> createState() => _TradeScreenState();
}

class _TradeScreenState extends State<TradeScreen> {
  Game get game => widget.game;

  @override
  Widget build(BuildContext context) {
    final villager = game.tradeVillager;
    return Material(
      type: MaterialType.transparency,
      child: Container(
        color: const Color.fromRGBO(0, 0, 0, 0.55),
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Container(
            width: 640,
            height: 380,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
            decoration: BoxDecoration(
              color: const Color.fromRGBO(31, 31, 38, 0.96),
              border: Border.all(color: const Color.fromRGBO(153, 153, 166, 1), width: 2),
            ),
            child: ValueListenableBuilder<int>(
              valueListenable: game.frame,
              builder: (context, _, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("${villager?.displayName() ?? 'Villager'}'s trades",
                      style: const TextStyle(fontSize: 24, color: Colors.white)),
                  const SizedBox(height: 4),
                  const Text('Click a row to trade   Esc / F: close',
                      style: TextStyle(fontSize: 13, color: Color.fromRGBO(179, 179, 179, 1))),
                  const SizedBox(height: 12),
                  for (var i = 0; i < (villager?.trades.length ?? 0); i++) _row(villager!, i),
                  const Spacer(),
                  const Text('Gold ingots are the villagers\' coin: sell wheat or melon slices to earn them.',
                      style: TextStyle(fontSize: 12, color: Color.fromRGBO(166, 166, 179, 1))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(Mob villager, int i) {
    final o = villager.trades[i];
    final have = game.player.inventory.countOf(o.take);
    final can = have >= o.takeCount;
    var bg = can ? const Color.fromRGBO(51, 77, 51, 1) : const Color.fromRGBO(56, 51, 51, 1);
    final flash = game.tradeFlash[i];
    if (flash != null) bg = flash ? const Color.fromRGBO(64, 153, 64, 1) : const Color.fromRGBO(153, 64, 64, 1);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => setState(() => game.tradeRow(i)),
        child: Container(
          height: 74,
          width: double.infinity, // a CustomPaint row gets no width of its own in the Column
          decoration: BoxDecoration(color: bg, border: Border.all(color: const Color.fromRGBO(115, 115, 128, 1))),
          child: CustomPaint(painter: _OfferPainter(o, have, can)),
        ),
      ),
    );
  }
}

class _OfferPainter extends CustomPainter {
  _OfferPainter(this.o, this.have, this.can);
  final TradeOffer o;
  final int have;
  final bool can;

  @override
  void paint(Canvas canvas, Size size) {
    Hud.drawItemIcon(canvas, const Rect.fromLTWH(14, 12, 50, 50), o.take);
    Hud.text(canvas, 'x ${o.takeCount}', const Offset(74, 44), size: 20);
    Hud.text(canvas, '${Items.displayName(o.take)} (you have $have)', const Offset(74, 62),
        size: 12, color: can ? const Color.fromRGBO(204, 204, 204, 1) : const Color.fromRGBO(255, 153, 153, 1));
    final mid = size.width * 0.5;
    Hud.text(canvas, '->', Offset(mid - 20, 46), size: 28, color: const Color.fromRGBO(255, 230, 128, 1));
    Hud.drawItemIcon(canvas, Rect.fromLTWH(mid + 40, 12, 50, 50), o.give);
    Hud.text(canvas, 'x ${o.giveCount}', Offset(mid + 100, 44), size: 20);
    Hud.text(canvas, Items.displayName(o.give), Offset(mid + 100, 62), size: 12, color: const Color.fromRGBO(204, 204, 204, 1));
  }

  @override
  bool shouldRepaint(_OfferPainter old) => old.o != o || old.have != have || old.can != can;
}
