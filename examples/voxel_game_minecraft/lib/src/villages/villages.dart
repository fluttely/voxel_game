import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart' show ChunkStreamer;
import 'package:voxel_game/voxel_game.dart';

import 'trade_table.dart';

/// One of a villager's offers: [takeCount] of [take] for [giveCount] of
/// [give].
typedef TradeOffer = ({String take, int takeCount, String give, int giveCount});

/// The trade the trade screen shows: whose ([name]) and its [offers].
typedef OpenTrade = ({String name, List<TradeOffer> offers});

/// The world's villages and their people. The first time the player comes
/// within [reach] of a village, [fewest] to [most] villagers are born on a
/// ring about its centre, each with three distinct offers from
/// [tradeTable]; they stroll about their village (`Wander` about `Mob.home`)
/// and take no harm (`MobSpec.invulnerable`). A villager used opens its
/// trade ([screen]); a trade asks its price of the bag and room there for
/// what it gives ([trade]), with no restock and no limit.
///
/// On a client a villager is the host's: its use asks the host for the
/// offers ([askMessage]) and the trade opens on the answer ([offersMessage]);
/// the bag traded with is the client's own. Only the host peoples a village.
///
/// Saved with the world (under `villages`): the villages peopled. A
/// villager keeps its offers on itself (`Mob.data`, under [offersKey]),
/// and the kit keeps them with it, home and all, in the save and across a
/// trip to another dimension.
class Villages extends SavedSystem {
  /// The key of the villages in the save.
  static const String key = 'villages';

  /// The structure that is a village.
  static const String structure = 'village';

  /// The creature that is a villager.
  static const String villager = 'villager';

  /// The key of a villager's offers in its `Mob.data`.
  static const String offersKey = 'offers';

  /// The screen a villager's use opens.
  static const String screen = 'trade';

  /// The game's message a client asks the host for a villager's offers with
  /// (`n`: its number), and the host's answer (`n`, `name`, `o`: the offers).
  static const String askMessage = 'trades_ask', offersMessage = 'trades';

  /// Metres from a village's centre within which the player peoples it.
  static const double reach = 40.0;

  /// How many villagers a village gets, at the fewest and the most.
  static const int fewest = 3, most = 5;

  /// Metres from the centre of the ring the villagers are born on.
  static const double ring = 4.0;

  /// How many offers a villager has.
  static const int offerCount = 3;

  /// Seconds between two looks for a village near.
  static const double lookEvery = 1.0;

  /// The villages of [game].
  static Villages of(VoxelGame game) => game.system<Villages>();

  final Set<IVec3> _peopled = {};
  OpenTrade? _open;
  int? _asked;
  double _lookIn = 0.0;

  /// The centres of the villages peopled.
  Set<IVec3> get peopled => Set.unmodifiable(_peopled);

  /// The villagers alive in [game]'s world, the host's replicas on a
  /// client among them.
  static Iterable<Mob> villagersIn(VoxelGame game) => game.mobs.where((m) => m.spec.id == villager && !m.gone);

  /// [mob]'s offers, kept on it; throws for a creature that has none (a
  /// replica's are the host's), and for an offer of an item [game] lacks.
  static List<TradeOffer> offersOf(VoxelGame game, Mob mob) {
    final rows = mob.data[offersKey];
    if (rows == null) throw ArgumentError.value(mob.spec.id, 'mob', 'a creature with no offers');
    return [for (final row in rows as List<Object?>) _offerOf(game, row)];
  }

  /// The trade the trade screen shows; throws when none was opened.
  OpenTrade get open => _open ?? (throw StateError('no trade was opened'));

  /// [offerCount] distinct offers of [tradeTable].
  static List<TradeOffer> roll(math.Random random) {
    final pool = [...tradeTable];
    return [for (var i = 0; i < offerCount; i++) pool.removeAt(random.nextInt(pool.length))];
  }

  /// A villager's use (`VoxelGameSpec.mobUses`): opens its trade; on a
  /// client, asks the host for it.
  static void use(VoxelGame game, Mob mob) {
    final villages = of(game);
    if (mob.replica) {
      villages._asked = mob.netId;
      game.session!.sendToHost(askMessage, {'n': mob.netId});
      return;
    }
    villages._show(game, mob.name, offersOf(game, mob));
  }

  /// The host hears a client ask for villager `n`'s offers, and answers it.
  /// One gone since the client used it gets no answer.
  static void heardAsk(VoxelGame game, int from, NetMessage message) {
    final n = message['n']! as int;
    final mob = game.mobs.where((m) => m.netId == n && !m.gone).firstOrNull;
    if (mob == null) return;
    game.session!.sendTo(from, offersMessage, {
      'n': n,
      'name': mob.name,
      'o': [for (final o in offersOf(game, mob)) _offerRow(o)],
    });
  }

  /// A client hears the host's answer: the trade opens, unless the player
  /// used another villager since.
  static void heardOffers(VoxelGame game, int from, NetMessage message) {
    final villages = of(game);
    if (message['n'] != villages._asked) return;
    villages._asked = null;
    villages._show(game, message['name']! as String, [
      for (final row in message['o']! as List<Object?>) _offerOf(game, row),
    ]);
  }

  void _show(VoxelGame game, String name, List<TradeOffer> offers) {
    _open = (name: name, offers: offers);
    game.openScreen(const DeclaredScreen(screen));
  }

  /// Trades offer [i] of the open trade with the player's bag: true when the
  /// items changed hands; false, and nothing changes, when the bag lacks the
  /// price or has no room for what is given.
  bool trade(VoxelGame game, int i) {
    final offers = open.offers;
    if (i < 0 || i >= offers.length) throw RangeError.index(i, offers, 'offer');
    final o = offers[i];
    final bag = game.player.inventory;
    if (!affords(bag, o)) return false;
    bag.remove(o.take, o.takeCount);
    bag.add(o.give, o.giveCount);
    game.playSound('pickup', volumeDb: -8.0);
    return true;
  }

  /// Whether [bag] holds [o]'s price and has room for what it gives.
  static bool affords(Inventory bag, TradeOffer o) =>
      bag.countOf(o.take) >= o.takeCount && bag.roomFor(o.give, o.giveCount) >= o.giveCount;

  @override
  void tick(VoxelGame game, double dt) {
    if (!game.authority) return;
    _lookIn -= dt;
    if (_lookIn > 0.0) return;
    _lookIn = lookEvery;
    final here = game.player.position;
    final chunk = ChunkStreamer.chunkOf(IVec3.floor(here));
    for (final s in game.world.generator.structuresNear(chunk.x, chunk.z)) {
      if (s.name != structure) continue;
      final centre = IVec3(s.x, s.y, s.z);
      if (_peopled.contains(centre) || _homeOf(centre).distanceTo(here) >= reach) continue;
      final born = _ringAbout(centre);
      if (!born.every((b) => game.world.isLoaded(IVec3.floor(b)))) continue;
      _people(game, centre, born);
    }
  }

  void _people(VoxelGame game, IVec3 centre, List<Vector3> ring) {
    _peopled.add(centre);
    final home = _homeOf(centre);
    final count = fewest + game.random.nextInt(most - fewest + 1);
    for (var i = 0; i < count; i++) {
      final at = ring[i];
      at.y = game.world.groundHeight(at.x.floor(), at.z.floor()).toDouble();
      settle(game, at, home);
    }
    game.notify('A village! Use a villager to trade');
  }

  /// A villager of [game] at [at], wandering about [home], with offers of
  /// its own ([roll]): a village's, or a playground's market stall's.
  static Mob settle(VoxelGame game, Vector3 at, Vector3 home) {
    final mob = game.spawnMob(villager, at)..home = home.clone();
    mob.data[offersKey] = [for (final o in roll(game.random)) _offerRow(o)];
    return mob;
  }

  static Vector3 _homeOf(IVec3 centre) => Vector3(centre.x + 0.5, centre.y.toDouble(), centre.z + 0.5);

  // Where a village's villagers are born, the most it can get, a fifth of a turn apart.
  static List<Vector3> _ringAbout(IVec3 centre) {
    final home = _homeOf(centre);
    return [
      for (var i = 0; i < most; i++)
        Vector3(
          home.x + math.cos(i * math.pi * 2 / most) * ring,
          home.y,
          home.z + math.sin(i * math.pi * 2 / most) * ring,
        ),
    ];
  }

  static List<Object> _offerRow(TradeOffer o) => [o.take, o.takeCount, o.give, o.giveCount];

  static TradeOffer _offerOf(VoxelGame game, Object? row) {
    final r = row! as List<Object?>;
    final o = (take: r[0]! as String, takeCount: r[1]! as int, give: r[2]! as String, giveCount: r[3]! as int);
    if (!game.items.has(o.take) || !game.items.has(o.give)) throw FormatException('an offer of no item: $r');
    return o;
  }

  @override
  String get saveKey => key;

  @override
  Object? save(VoxelGame game) => {
    'villages': [
      for (final c in _peopled) [c.x, c.y, c.z],
    ],
  };

  /// Puts back the villages peopled. Throws for a villager the kit put
  /// back with no offers (a world saved before they were kept on it).
  @override
  void restore(VoxelGame game, Object? saved) {
    final s = saved! as Map<String, Object?>;
    _peopled
      ..clear()
      ..addAll([
        for (final c in (s['villages']! as List<Object?>).cast<List<Object?>>())
          IVec3(c[0]! as int, c[1]! as int, c[2]! as int),
      ]);
    for (final m in villagersIn(game)) {
      if (!m.data.containsKey(offersKey)) throw FormatException('a villager saved with no offers at ${m.position}');
    }
  }
}
