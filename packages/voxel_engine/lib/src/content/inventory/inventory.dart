import 'item_stack.dart';

/// Slots of [ItemStack]s, the first [hotbarSize] of them the hotbar. How many
/// of an item fit a slot and how long it lasts are the game's, asked through
/// [stackSize] and [maxDurability].
class Inventory {
  /// [capacity] empty slots.
  Inventory({required this.stackSize, int Function(String id)? maxDurability, this.capacity = 36, this.hotbarSize = 9})
    : maxDurability = maxDurability ?? _never,
      slots = List<ItemStack?>.filled(capacity, null);

  static int _never(String id) => 0;

  /// How many of item `id` fit one slot.
  final int Function(String id) stackSize;

  /// Uses item `id` survives; 0 for one that never wears.
  final int Function(String id) maxDurability;

  /// How many slots.
  final int capacity;

  /// How many of the first slots are the hotbar.
  final int hotbarSize;

  /// The slots; null is empty.
  final List<ItemStack?> slots;

  /// Called after every change.
  final List<void Function()> listeners = [];

  void _changed() {
    for (final l in List.of(listeners)) {
      l();
    }
  }

  /// Tells the listeners a slot changed from outside (a stack edited in
  /// place).
  void emitChanged() => _changed();

  /// Whether slot [i] is empty.
  bool isEmptySlot(int i) => slots[i] == null;

  /// The item in slot [i], `''` when empty.
  String idAt(int i) => slots[i]?.id ?? '';

  /// How many in slot [i].
  int countAt(int i) => slots[i]?.count ?? 0;

  /// The bonus of slot [i]'s stack.
  int bonusAt(int i) => slots[i]?.bonus ?? 0;

  /// Uses left on slot [i]'s tool or weapon (its maximum when never worn), 0
  /// for an item that never wears or an empty slot.
  int durAt(int i) {
    final s = slots[i];
    if (s == null) return 0;
    final maxDur = maxDurability(s.id);
    if (maxDur <= 0) return 0;
    return s.dur >= 0 ? s.dur : maxDur;
  }

  /// Wears slot [i]'s item by [uses]; true when it broke (the slot empties).
  bool wear(int i, [int uses = 1]) {
    var left = durAt(i);
    if (left <= 0) return false;
    left -= uses;
    if (left <= 0) {
      slots[i] = null;
      _changed();
      return true;
    }
    slots[i]!.dur = left;
    _changed();
    return false;
  }

  /// How many of [id] in every slot.
  int countOf(String id) {
    var total = 0;
    for (final s in slots) {
      if (s != null && s.id == id) total += s.count;
    }
    return total;
  }

  /// Adds up to [count] of [id], topping up stacks before opening slots;
  /// returns what did not fit.
  int add(String id, int count) {
    final maxStack = stackSize(id);
    for (final s in slots) {
      if (count <= 0) break;
      if (s != null && s.id == id && s.count < maxStack) {
        final room = maxStack - s.count;
        final take = room < count ? room : count;
        s.count += take;
        count -= take;
      }
    }
    for (var i = 0; i < capacity; i++) {
      if (count <= 0) break;
      if (slots[i] == null) {
        final take = maxStack < count ? maxStack : count;
        slots[i] = ItemStack(id, take);
        count -= take;
      }
    }
    _changed();
    return count;
  }

  /// How many of [count] [id] would fit right now.
  int roomFor(String id, int count) {
    final maxStack = stackSize(id);
    var room = 0;
    for (final s in slots) {
      if (s == null) {
        room += maxStack;
      } else if (s.id == id) {
        room += maxStack - s.count;
      }
    }
    return room < count ? room : count;
  }

  /// Whether any slot is empty.
  bool get hasEmptySlot => slots.contains(null);

  /// Puts a copy of [stack] (bonus and wear kept) in the first empty slot;
  /// false when none is.
  bool addStack(ItemStack stack) {
    for (var i = 0; i < capacity; i++) {
      if (slots[i] == null) {
        slots[i] = stack.copy();
        _changed();
        return true;
      }
    }
    return false;
  }

  /// Takes [count] of [id], from the last slots first; false (and nothing
  /// taken) when there are fewer.
  bool remove(String id, int count) {
    if (countOf(id) < count) return false;
    for (var i = capacity - 1; i >= 0; i--) {
      if (count <= 0) break;
      final s = slots[i];
      if (s != null && s.id == id) {
        final take = s.count < count ? s.count : count;
        s.count -= take;
        count -= take;
        if (s.count <= 0) slots[i] = null;
      }
    }
    _changed();
    return true;
  }

  /// Takes up to [count] from slot [i] as a new stack; null when empty.
  ItemStack? takeFromSlot(int i, int count) {
    final s = slots[i];
    if (s == null) return null;
    final take = count < s.count ? count : s.count;
    final out = ItemStack(s.id, take, bonus: s.bonus, dur: s.dur);
    s.count -= take;
    if (s.count <= 0) slots[i] = null;
    _changed();
    return out;
  }

  /// Sets slot [i] to a copy of [stack] (null empties it).
  void setSlot(int i, ItemStack? stack) {
    slots[i] = stack?.copy();
    _changed();
  }

  /// Swaps slots [a] and [b].
  void swap(int a, int b) {
    final t = slots[a];
    slots[a] = slots[b];
    slots[b] = t;
    _changed();
  }

  /// The first slot holding [id], or -1.
  int find(String id) {
    for (var i = 0; i < capacity; i++) {
      if (slots[i]?.id == id) return i;
    }
    return -1;
  }

  /// Every slot, an empty map for an empty one.
  List<Object> toJson() => [for (final s in slots) s?.toJson() ?? <String, Object>{}];

  /// Reads [data] back; a slot naming an item [known] rejects stays empty.
  void fromJson(List<Object?> data, {bool Function(String id)? known}) {
    for (var i = 0; i < capacity; i++) {
      final s = i < data.length ? data[i] : null;
      slots[i] = null;
      if (s is Map<String, Object?> && s['id'] != null && (known == null || known(s['id'].toString()))) {
        slots[i] = ItemStack.fromJson(s);
      }
    }
    _changed();
  }
}
