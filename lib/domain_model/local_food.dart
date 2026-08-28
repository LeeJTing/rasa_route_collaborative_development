/// Domain model: LocalFood.
///
/// This is what Views and ViewModels reason about - clean, immutable, shaped
/// exactly for what the UI needs. Repository converts Supabase rows into this.
class LocalFood {
  const LocalFood({
    required this.id,
    required this.name,
    required this.description,
    required this.origin,
    required this.culturalBackground,
    required this.ingredients,
    required this.category,
    required this.cookingStyle,
    required this.mealType,
    required this.foodType,
    this.tastes = const <String>[],
    this.mainTaste = '',
    this.pronunciationText = '',
    this.audioGuideUrl,
    this.synonyms = const <String>[],
    this.imageUrls = const <String>[],
    this.isFavourite = false,
  });

  /// Primary key: local_food_id (bigint)
  final int id;

  /// food_name
  final String name;

  /// description
  final String description;

  /// origin
  final String origin;

  /// cultural_background
  final String culturalBackground;

  /// ingredients (comma-separated or JSON - repo parses)
  final String ingredients;

  /// food_category (All-Day Dining, Chinese, Indian, etc.)
  final String category;

  /// cooking_style
  final String cookingStyle;

  /// meal_type
  final String mealType;

  /// food_type (Food, Beverage, Fruit, Dessert or Kuih)
  final String foodType;

  /// Normalised taste preferences associated through local_food_preference.
  final List<String> tastes;

  /// The taste marked `is_main` in `local_food_preference`.
  final String mainTaste;

  /// Human-readable pronunciation from `pronunciation_text`.
  final String pronunciationText;

  /// Optional remote audio guide from `audio_guide_url`.
  final String? audioGuideUrl;

  /// Alternate names parsed from the `synonyms` text column.
  final List<String> synonyms;

  /// Ordered gallery from `local_food_image`.
  final List<String> imageUrls;

  /// Whether current user has favourited this. Set by repo from favourite_food table.
  final bool isFavourite;
}
