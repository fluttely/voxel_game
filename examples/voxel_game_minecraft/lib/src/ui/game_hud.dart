import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:voxel_game/voxel_game.dart';

import '../classes/class_system.dart';
import '../journal/quest_log.dart';
import '../journal/tutorial_card.dart';
import '../player/heartbeat.dart';

/// The kit's HUD ([DefaultHud]) with the game's own pieces on it: the clock
/// line at the top ([clockOf]), the name and health of the creature in the
/// crosshair over it ([aimedOf]), the class's stamina and mana as bars under
/// the hearts and its abilities at the bottom left ([abilitiesOf]), the
/// quest at hand at the top right ([questOf]), the tutorial's card under the
/// clock (`TutorialCard`), and while the player's health is low
/// (`Heartbeat.isLow`) a red edge pulsing under it all, as the heart beats.
///
/// Every piece of the game's but the tutorial's card (its skip button) is
/// behind an [IgnorePointer]: a finger still reaches the kit's hotbar and the
/// world.
class GameHud extends StatelessWidget {
  /// The HUD of [game].
  const GameHud(this.game, {super.key});

  /// A `HudBuilder` of this HUD.
  static Widget builder(BuildContext context, VoxelGame game) => GameHud(game);

  /// The game shown.
  final VoxelGame game;

  /// Pixels the clock line moves down while the kit's boss bar is at the top.
  static const double underBossBar = 44.0;

  /// Pixels from the top to the tutorial's card, under the clock line.
  static const double cardTop = 42.0;

  /// Pixels the quest moves down on a phone, under the buttons at the top
  /// right.
  static const double underTouchButtons = 64.0;

  static const _shadow = [Shadow(offset: Offset(1, 1), blurRadius: 2)];

  /// The clock line: the hour, the biome the player stands in, `(night)`
  /// after sunset and the weather when it is not clear, three spaces between
  /// them. In a dimension with a still sky (`SkySpec.dimensions`) there is no
  /// hour and no weather: the line is the dimension's name.
  static String clockOf(VoxelGame game) {
    if (game.dimensionSky != null) return _named(game.dimension);
    final hours = game.timeOfDay * 24.0;
    final cell = IVec3.floor(game.player.position);
    final weather = game.weather.kind;
    return [
      '${_two(hours.floor())}:${_two(((hours % 1.0) * 60.0).floor())}',
      _named(game.world.generator.biomeAt(cell.x, cell.z).name),
      if (game.isNight) '(night)',
      if (weather != WeatherKind.clear) _named(weather.name),
    ].join('   ');
  }

  /// What the crosshair is on, as the HUD names it: the creature's name and
  /// its health (`Zombie  12/20`), or null on none or a dead one.
  static String? aimedOf(VoxelGame game) {
    final m = game.player.aimedMob;
    if (m == null || m.isDead) return null;
    return '${m.name}  ${m.hp.ceil()}/${m.maxHp.ceil()}';
  }

  /// The class's abilities as the HUD lists them, a line each: the key
  /// and the name, and the seconds left while one comes back
  /// (`[F] Shield Bash  4s`).
  static List<String> abilitiesOf(VoxelGame game) {
    final classes = ClassSystem.of(game);
    return [
      for (final MapEntry(key: action, value: a) in classes.playerClass.abilities.entries)
        '[${_keys[action]}] ${a.name}${classes.cooldownOf(action) > 0.0 ? '  ${classes.cooldownOf(action).ceil()}s' : ''}',
      '[Alt] Dodge',
    ];
  }

  /// The quest at hand as the HUD shows it, its title then what to do and
  /// how far it is (`Quest: Miner` over `Mine 10 coal  (3/10)`); null once
  /// the chain is done.
  static (String, String)? questOf(VoxelGame game) {
    final log = QuestLog.of(game);
    final q = log.current;
    if (q == null) return null;
    return ('Quest: ${q.title}', '${q.text}  (${log.progressOf(game)}/${q.count})');
  }

  // The key that casts each ability (`gameSpec.actions`).
  static const _keys = {'ability': 'R', 'ability2': 'F'};

  /// The stamina bar's colour.
  static const Color staminaColor = Color(0xFF40BF40);

  /// The mana bar's colour.
  static const Color manaColor = Color(0xFF4D73F2);

  static final List<HudBar> _bars = [
    HudBar('Stamina', color: staminaColor, fill: (game) => ClassSystem.of(game).staminaShare),
    HudBar('Mana', color: manaColor, fill: (game) => ClassSystem.of(game).manaShare),
  ];

  static String _two(int n) => n.toString().padLeft(2, '0');

  // An id as a name: `frozen_shore` is Frozen Shore.
  static String _named(String id) =>
      id.split('_').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');

  @override
  Widget build(BuildContext context) {
    final frames = game.frames;
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: HudSelector(
            frames: frames,
            select: () => Heartbeat.isLow(game.player),
            builder: (context, low) => low ? CustomPaint(painter: LowHealthEdge(game)) : const SizedBox.shrink(),
          ),
        ),
        DefaultHud(game, bars: _bars),
        IgnorePointer(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: HudSelector(
                  frames: frames,
                  select: () => (line: clockOf(game), boss: game.boss != null),
                  builder: (context, s) => Padding(
                    padding: EdgeInsets.only(top: 12 + (s.boss ? underBossBar : 0)),
                    child: Text(s.line, style: const TextStyle(fontSize: 16, shadows: _shadow)),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.topRight,
                child: HudSelector(
                  frames: frames,
                  select: () => (quest: questOf(game), touch: game.input.lastDevice == InputDevice.touch),
                  builder: (context, s) {
                    final quest = s.quest;
                    if (quest == null) return const SizedBox.shrink();
                    return Container(
                      margin: EdgeInsets.only(top: 12 + (s.touch ? underTouchButtons : 0), right: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      color: Colors.black45,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(quest.$1, style: const TextStyle(fontSize: 15, color: Color(0xFFFFE699))),
                          Text(quest.$2, style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Positioned(
                left: 16,
                bottom: 16,
                child: HudSelector(
                  frames: frames,
                  select: () => abilitiesOf(game).join('\n'),
                  builder: (context, lines) => Text(lines, style: const TextStyle(fontSize: 14, shadows: _shadow)),
                ),
              ),
              Center(
                child: HudSelector(
                  frames: frames,
                  select: () => aimedOf(game),
                  builder: (context, aimed) => aimed == null
                      ? const SizedBox.shrink()
                      : Transform.translate(
                          offset: const Offset(0, -40),
                          child: Text(
                            aimed,
                            style: const TextStyle(fontSize: 16, color: Color(0xFFFFCCCC), shadows: _shadow),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.topCenter,
          child: HudSelector(
            frames: frames,
            select: () => game.boss != null,
            builder: (context, boss) => Padding(
              padding: EdgeInsets.only(top: cardTop + (boss ? underBossBar : 0), left: 16, right: 16),
              child: TutorialCard(game),
            ),
          ),
        ),
      ],
    );
  }
}

/// The red edge of a player low on health: clear to 45 % of the way from the
/// centre to the screen's edge, red at it and past it, its strength pulsing
/// about once a second on the game's clock ([strength]).
class LowHealthEdge extends CustomPainter {
  /// The edge of [game]'s player, repainted on every frame.
  LowHealthEdge(this.game) : super(repaint: game.frames);

  /// The game whose clock the edge pulses on.
  final VoxelGame game;

  /// How strong the edge is at [time] seconds of game time: 0.15 .. 0.55.
  static double strength(double time) => 0.35 + 0.2 * math.sin(time * 1000.0 / 150.0);

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    canvas.save();
    canvas.translate(size.width * 0.5, h * 0.5);
    canvas.scale(size.width / h, 1.0);
    canvas.drawRect(
      Rect.fromCenter(center: Offset.zero, width: h, height: h),
      Paint()
        ..shader = ui.Gradient.radial(
          Offset.zero,
          h * 0.5,
          [const Color(0x00CC0000), const Color(0xFFCC0000).withValues(alpha: 0.85 * strength(game.time))],
          const [0.45, 1.0],
        ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(LowHealthEdge old) => old.game != game;
}
