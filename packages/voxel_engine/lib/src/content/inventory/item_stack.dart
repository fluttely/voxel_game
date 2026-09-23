/// One inventory slot's worth: an item, how many, and what is particular to
/// this stack (its wear, a rolled bonus).
class ItemStack {
  /// [count] of item [id]; [dur] -1 means never worn (full).
  ItemStack(this.id, this.count, {this.bonus = 0, this.dur = -1});

  /// A stack read back from [toJson].
  factory ItemStack.fromJson(Map<String, Object?> json) => ItemStack(
        json['id']! as String,
        (json['count']! as num).toInt(),
        bonus: (json['bonus'] as num?)?.toInt() ?? 0,
        dur: (json['dur'] as num?)?.toInt() ?? -1,
      );

  /// The item.
  String id;

  /// How many.
  int count;

  /// A number rolled for this stack (a loot weapon's bonus damage); 0 for none.
  int bonus;

  /// Uses left on a tool or weapon; -1 when never worn.
  int dur;

  /// An independent copy.
  ItemStack copy() => ItemStack(id, count, bonus: bonus, dur: dur);

  /// `id` and `count`, plus `bonus` and `dur` when set.
  Map<String, Object> toJson() => {'id': id, 'count': count, if (bonus > 0) 'bonus': bonus, if (dur >= 0) 'dur': dur};
}
