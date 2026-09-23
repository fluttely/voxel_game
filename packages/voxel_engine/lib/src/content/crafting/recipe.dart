import '../inventory/inventory.dart';

/// One recipe: [ingredients] (item id to count) make [count] of [result] at
/// [station] (`''` by hand). Shapeless: only the counts matter.
class Recipe {
  /// A recipe.
  const Recipe(this.result, this.count, this.ingredients, {this.station = ''});

  /// The item made.
  final String result;

  /// How many are made.
  final int count;

  /// What is used up.
  final Map<String, int> ingredients;

  /// Where it is made; `''` in the hand.
  final String station;
}

/// A game's recipes.
class RecipeBook {
  /// [recipes], in the order a crafting screen lists them.
  RecipeBook(List<Recipe> recipes) : recipes = List<Recipe>.unmodifiable(recipes);

  /// Every recipe.
  final List<Recipe> recipes;

  /// What can be made at [station]: its recipes and the hand's.
  List<Recipe> available(String station) => [for (final r in recipes) if (r.station == '' || r.station == station) r];

  /// Whether [inventory] holds every ingredient of [recipe].
  bool canCraft(Recipe recipe, Inventory inventory) {
    for (final e in recipe.ingredients.entries) {
      if (inventory.countOf(e.key) < e.value) return false;
    }
    return true;
  }

  /// Uses up the ingredients and adds the result; false (and nothing
  /// changed) when something is missing.
  bool craft(Recipe recipe, Inventory inventory) {
    if (!canCraft(recipe, inventory)) return false;
    for (final e in recipe.ingredients.entries) {
      inventory.remove(e.key, e.value);
    }
    inventory.add(recipe.result, recipe.count);
    return true;
  }
}
