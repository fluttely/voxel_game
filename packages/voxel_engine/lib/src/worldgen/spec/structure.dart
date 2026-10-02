import 'structure_site.dart';

/// Draws one structure into one chunk.
typedef StructureBuild = void Function(StructureSite site);

/// What a structure is: how far it reaches, how deep it sits, the blocks it
/// uses, and how it is drawn around a [StructureSite]. A [StructureSpec]
/// places one in the world; the stock ones (`Dungeon`, `Tower`, `Well`,
/// `Camp`, `Ruins`, `Mine`, `Village`) take their blocks by name, and a
/// game's own is a [CustomStructure] or a subclass.
///
/// [build] is called once for every chunk the structure may reach, and must
/// draw the same thing every time: roll with [StructureSite.roll] and
/// [StructureSite.hashAt], never anything else.
abstract class Structure {
  /// A structure.
  const Structure();

  /// How far it reaches from its site, in blocks, sideways: the site stays
  /// that far inside its region, and other structures' sites that far away.
  int get radius;

  /// How far under the surface its site sits (a dungeon), 0 on the surface.
  int get depth => 0;

  /// How far around its site no tree roots, in blocks (the generator adds a
  /// tree's own reach); by default its [radius] on the surface and nothing
  /// under it, which is dug under the trees, never through them.
  int get clearing => depth == 0 ? radius : 0;

  /// Every block it draws, so a world fails to compile, naming the block,
  /// when a game's table lacks one.
  Set<String> get blockNames;

  /// Draws it around [site].
  void build(StructureSite site);
}

/// A game's own structure, drawn by a function.
///
/// ```dart
/// void hut(StructureSite s) {
///   s.level(-2, -2, 2, 2, 'cobblestone');
///   s.fill(-2, 0, -2, 2, 3, 2, 'cobblestone', hollow: true);
///   s.put(0, 1, 2, 'air'); // the door
/// }
///
/// StructureSpec('hut', CustomStructure(hut, radius: 3, blocks: {'cobblestone'}))
/// ```
class CustomStructure extends Structure {
  /// A structure [draw] draws, reaching [radius] from its site, [depth] under
  /// the surface; [blocks] are the names it uses, checked when the world
  /// compiles (a name left out still fails, later, when it is drawn).
  const CustomStructure(this.draw, {this.radius = 8, this.depth = 0, this.blocks = const {}});

  /// The function that draws it.
  final StructureBuild draw;

  @override
  final int radius;

  @override
  final int depth;

  /// The block names it uses.
  final Set<String> blocks;

  @override
  Set<String> get blockNames => blocks;

  @override
  void build(StructureSite site) => draw(site);
}
