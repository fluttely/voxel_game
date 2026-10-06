import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:voxel_game/voxel_game.dart';

import 'villages.dart';

/// A villager's offers (`Villages.open`), a row each: what it asks, how
/// many, and how many the bag holds (red when short), an arrow, and what it
/// gives. A row is green when the bag can pay for it and has room for what
/// it gives, grey-red when not; a tap trades, and the row flashes green for
/// a trade made, red for one refused. A pad and the keys walk the rows
/// through the focus, the focused one ringed, and A or Enter trades; it
/// opens on the first.
class TradeScreen extends StatefulWidget {
  /// [game]'s open trade.
  const TradeScreen(this.game, {super.key});

  /// A `ScreenBuilder` of this screen: what a villager's use opens.
  static Widget builder(BuildContext context, VoxelGame game) => TradeScreen(game);

  /// The game whose trade it shows.
  final VoxelGame game;

  /// Seconds a row flashes after a tap.
  static const double flashSeconds = 0.5;

  /// The height of a row.
  static const double rowHeight = 74.0;

  @override
  State<TradeScreen> createState() => _TradeScreenState();
}

class _TradeScreenState extends State<TradeScreen> {
  static const Color _can = Color(0xFF334D33),
      _cannot = Color(0xFF383333),
      _made = Color(0xFF409940),
      _refused = Color(0xFF994040),
      _short = Color(0xFFFF9999),
      _plain = Color(0xFFCCCCCC),
      _arrow = Color(0xFFFFE680);

  // The last tap on each row: whether it traded, and the game's time then.
  final Map<int, ({bool made, double at})> _taps = {};

  VoxelGame get game => widget.game;

  bool? _flashOf(int i) {
    final tap = _taps[i];
    return tap != null && game.time - tap.at < TradeScreen.flashSeconds ? tap.made : null;
  }

  @override
  Widget build(BuildContext context) {
    final trade = Villages.of(game).open;
    final bag = game.player.inventory;
    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: Card(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: HudSelector(
                frames: game.frames,
                select: () => [
                  for (var i = 0; i < trade.offers.length; i++)
                    (
                      have: bag.countOf(trade.offers[i].take),
                      can: Villages.affords(bag, trade.offers[i]),
                      flash: _flashOf(i),
                    ),
                ],
                equals: listEquals,
                builder: (context, rows) => Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("${trade.name}'s trades", style: const TextStyle(fontSize: 22)),
                    const Text('Tap a row to trade'),
                    const SizedBox(height: 12),
                    for (var i = 0; i < trade.offers.length; i++)
                      _row(i, trade.offers[i], rows[i].have, rows[i].can, rows[i].flash),
                    const SizedBox(height: 4),
                    const Text(
                      "Gold ingots are the villagers' coin: sell wheat or melon slices to earn them.",
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: FilledButton(onPressed: game.closeScreen, child: const Text('Back to the game')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(int i, TradeOffer o, int have, bool can, bool? flash) {
    final background = switch (flash) {
      true => _made,
      false => _refused,
      null => can ? _can : _cannot,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: background,
        shape: const Border.fromBorderSide(BorderSide(color: Color(0xFF737380))),
        child: InkWell(
          autofocus: i == 0,
          onTap: () => setState(() => _taps[i] = (made: Villages.of(game).trade(game, i), at: game.time)),
          // The ring over the row's own border, so the focus does not move it.
          child: Builder(
            builder: (context) => Container(
              height: TradeScreen.rowHeight,
              foregroundDecoration: Focus.of(context).hasFocus
                  ? const BoxDecoration(border: Border.fromBorderSide(ScreenFocus.ring))
                  : null,
              child: Row(
                children: [
                  Expanded(
                    child: _side(
                      o.take,
                      o.takeCount,
                      '${game.items[o.take].name} (you have $have)',
                      can: have >= o.takeCount,
                    ),
                  ),
                  const Text('->', style: TextStyle(fontSize: 28, color: _arrow)),
                  Expanded(child: _side(o.give, o.giveCount, game.items[o.give].name)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _side(String item, int count, String label, {bool can = true}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14),
    child: Row(
      children: [
        ItemIcon(game.itemModel(item), size: 50),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('x $count', style: const TextStyle(fontSize: 20, color: Colors.white)),
              Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: can ? _plain : _short),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
