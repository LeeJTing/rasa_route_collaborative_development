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

  /// First gallery image used by compact list and recommendation cards.
  String? get imageUrl => imageUrls.isEmpty ? null : imageUrls.first;

  /// Whether current user has favourited this. Set by repo from favourite_food table.
  final bool isFavourite;

  // NOTE: no toJson/fromJson here - domain models carry no JSON per the
  // developer guideline (§10). Serialisation lives on [LocalFoodDataModel]
  // in lib/model/data_models/. If a call site needs to reconstruct a
  // LocalFood from cache, it should read a data-model JSON blob and call
  // LocalFoodDataModel.fromJson(...).toDomain() instead.

  /// Immutable copy-with.
  LocalFood copyWith({
    int? id,
    String? name,
    String? description,
    String? origin,
    String? culturalBackground,
    String? ingredients,
    String? category,
    String? cookingStyle,
    String? mealType,
    String? foodType,
    List<String>? tastes,
    String? mainTaste,
    String? pronunciationText,
    String? audioGuideUrl,
    List<String>? synonyms,
    List<String>? imageUrls,
    bool? isFavourite,
  }) => LocalFood(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description ?? this.description,
    origin: origin ?? this.origin,
    culturalBackground: culturalBackground ?? this.culturalBackground,
    ingredients: ingredients ?? this.ingredients,
    category: category ?? this.category,
    cookingStyle: cookingStyle ?? this.cookingStyle,
    mealType: mealType ?? this.mealType,
    foodType: foodType ?? this.foodType,
    tastes: tastes ?? this.tastes,
    mainTaste: mainTaste ?? this.mainTaste,
    pronunciationText: pronunciationText ?? this.pronunciationText,
    audioGuideUrl: audioGuideUrl ?? this.audioGuideUrl,
    synonyms: synonyms ?? this.synonyms,
    imageUrls: imageUrls ?? this.imageUrls,
    isFavourite: isFavourite ?? this.isFavourite,
  );

  @override
  String toString() =>
      'LocalFood(id: $id, name: $name, category: $category, isFavourite: $isFavourite)';
}
