/// What a bucket does with a liquid. An empty one scoops a liquid's source,
/// leaving air, and becomes the full item [fills] names for that liquid; a
/// full one pours its [liquid] where it is aimed and becomes its [empties].
class Bucket {
  /// An empty bucket: each liquid kind it scoops, to the full item it becomes.
  const Bucket.empty(this.fills) : liquid = null, empties = null;

  /// A full bucket: the source block of the [liquid] it pours, and the item it
  /// becomes once poured.
  const Bucket.full(String this.liquid, {required String this.empties}) : fills = const {};

  /// Liquid kind to the full item; empty on a full bucket.
  final Map<String, String> fills;

  /// The liquid source block it pours; null on an empty bucket.
  final String? liquid;

  /// The item it becomes once poured; null on an empty bucket.
  final String? empties;

  /// Whether it holds a liquid.
  bool get isFull => liquid != null;
}
