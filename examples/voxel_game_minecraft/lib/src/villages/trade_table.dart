import 'villages.dart';

/// What villagers offer: each villager rolls three distinct rows of it. Gold
/// ingots are their coin: wheat, melon slices and raw gold sell for them, and
/// they buy food, ingots, arrows, potions, tools and a glider.
const List<TradeOffer> tradeTable = [
  (take: 'wheat', takeCount: 3, give: 'gold_ingot', giveCount: 1),
  (take: 'gold_ingot', takeCount: 1, give: 'bread', giveCount: 4),
  (take: 'gold_ingot', takeCount: 1, give: 'iron_ingot', giveCount: 3),
  (take: 'gold_ingot', takeCount: 1, give: 'arrow', giveCount: 12),
  (take: 'gold_ingot', takeCount: 2, give: 'magic_dust', giveCount: 3),
  (take: 'gold_ingot', takeCount: 2, give: 'health_potion', giveCount: 1),
  (take: 'gold_ingot', takeCount: 5, give: 'iron_pickaxe', giveCount: 1),
  (take: 'raw_gold', takeCount: 2, give: 'gold_ingot', giveCount: 1),
  (take: 'leather', takeCount: 4, give: 'leather_armor', giveCount: 1),
  (take: 'wool', takeCount: 6, give: 'glider', giveCount: 1),
  (take: 'diamond', takeCount: 1, give: 'crystal_staff', giveCount: 1),
  (take: 'gem_shard', takeCount: 3, give: 'diamond', giveCount: 1),
  (take: 'gold_ingot', takeCount: 2, give: 'speed_potion', giveCount: 1),
  (take: 'melon_slice', takeCount: 6, give: 'gold_ingot', giveCount: 1),
  (take: 'gold_ingot', takeCount: 3, give: 'shears', giveCount: 1),
];
