import '../../core/json_model.dart';

import '../../domain_model/local_food.dart';

/// Wire shape of `public.local_food`, joined with `local_food_image`.
///
/// Supabase schema:
///   local_food table: local_food_id, food_name, description, origin,
///   cultural_background, ingredients, food_category, cooking_style, meal_type
///   local_food_image table: local_food_image_id, img_name, local_food_id
///
/// `toJson`/`fromJson` live here and only here - [LocalFood] (the domain
/// model) carries no JSON, per the developer guideline.
class LocalFoodDataModel implements JsonModel {
  const LocalFoodDataModel({
    required this.localFoodId,
    required this.foodName,
    this.description,
    this.origin,
    this.culturalBackground,
    this.ingredients,
    this.foodCategory,
    this.cookingStyle,
    this.mealType,
    this.foodType,
    this.tastes = const <String>[],
    this.mainTaste,
    this.pronunciationText,
    this.audioGuideUrl,
    this.synonyms,
    this.imageUrls = const <String>[],
  });

  final int localFoodId;
  final String foodName;
  final String? description;
  final String? origin;
  final String? culturalBackground;
  final String? ingredients;
  final String? foodCategory;
  final String? cookingStyle;
  final String? mealType;
  final String? foodType;
  final List<String> tastes;
  final String? mainTaste;
  final String? pronunciationText;
  final String? audioGuideUrl;
  final String? synonyms;
  final List<String> imageUrls;

  String? get imageUrl => imageUrls.isEmpty ? null : imageUrls.first;

  /// Parse a raw Supabase row, e.g.:
  /// ```
  /// {
  ///   local_food_id: 1,
  ///   food_name: "Prawn Noodle",
  ///   description: "...",
  ///   food_category: "All-Day Dining",
  ///   local_food_image: [{ img_name: "https://..." }]
  /// }
  /// ```
  factory LocalFoodDataModel.fromJson(Map<String, dynamic> json) {
    return LocalFoodDataModel(
      localFoodId: JsonReader.asInt(json['local_food_id']),
      foodName: JsonReader.asString(json['food_name']),
      description: JsonReader.asStringOrNull(json['description']),
      origin: JsonReader.asStringOrNull(json['origin']),
      culturalBackground: JsonReader.asStringOrNull(
        json['cultural_background'],
      ),
      ingredients: JsonReader.asStringOrNull(json['ingredients']),
      foodCategory: JsonReader.asStringOrNull(json['food_category']),
      cookingStyle: JsonReader.asStringOrNull(json['cooking_style']),
      mealType: JsonReader.asStringOrNull(json['meal_type']),
      foodType: JsonReader.asStringOrNull(json['food_type']),
      tastes: _extractTastes(json),
      mainTaste:
          _extractMainTaste(json) ??
          JsonReader.asStringOrNull(json['main_taste']),
      pronunciationText: JsonReader.asStringOrNull(json['pronunciation_text']),
      audioGuideUrl: JsonReader.asStringOrNull(json['audio_guide_url']),
      synonyms: JsonReader.asStringOrNull(json['synonyms']),
      imageUrls: _extractImageUrls(json),
    );
  }

  static List<String> _extractTastes(Map<String, dynamic> json) {
    final Set<String> values = JsonReader.asStringList(json['tastes']).toSet();
    final Object? links = json['local_food_preference'];
    if (links is List) {
      for (final Object? link in links) {
        if (link is! Map) continue;
        final Object? preference = link['food_preference'];
        if (preference is! Map) continue;
        final String? raw = JsonReader.asStringOrNull(
          preference['preferred_taste'],
        );
        if (raw == null) continue;
        values.addAll(_splitValues(raw));
      }
    }
    return values.toList(growable: false);
  }

  static String? _extractMainTaste(Map<String, dynamic> json) {
    final Object? links = json['local_food_preference'];
    if (links is! List) return null;
    for (final Object? link in links) {
      if (link is! Map || !JsonReader.asBool(link['is_main'])) continue;
      final Object? preference = link['food_preference'];
      if (preference is! Map) continue;
      return JsonReader.asStringOrNull(preference['preferred_taste']);
    }
    return null;
  }

  static Iterable<String> _splitValues(String raw) => raw
      .split(RegExp(r'[,;/|]'))
      .map((String value) => value.trim())
      .where((String value) => value.isNotEmpty);

  /// Handles either a direct `img_name` field or the joined
  /// `local_food_image` array shape. The catalogue currently stores three
  /// ordered images per dish; keeping all of them lets Food Detail present
  /// the real gallery while list cards continue to use the first image.
  static List<String> _extractImageUrls(Map<String, dynamic> json) {
    final String? direct = JsonReader.asStringOrNull(json['img_name']);
    if (direct != null) return <String>[direct];

    final Object? images = json['local_food_image'];
    if (images is List) {
      final List<String> values = <String>[];
      for (final Object? image in images) {
        if (image is Map) {
          final String? name = JsonReader.asStringOrNull(image['img_name']);
          if (name != null && !values.contains(name)) values.add(name);
        }
      }
      values.sort();
      return List<String>.unmodifiable(values);
    }
    return const <String>[];
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'local_food_id': localFoodId,
    'food_name': foodName,
    'description': description,
    'origin': origin,
    'cultural_background': culturalBackground,
    'ingredients': ingredients,
    'food_category': foodCategory,
    'cooking_style': cookingStyle,
    'meal_type': mealType,
    'food_type': foodType,
    'tastes': tastes,
    'main_taste': mainTaste,
    'pronunciation_text': pronunciationText,
    'audio_guide_url': audioGuideUrl,
    'synonyms': synonyms,
    'local_food_image': imageUrls
        .map((String imageUrl) => <String, dynamic>{'img_name': imageUrl})
        .toList(growable: false),
  };

  /// Converts to the domain model. [isFavourite] is looked up separately
  /// against `favourite_food` - the wire row itself carries no such column.
  LocalFood toDomain({bool isFavourite = false}) => LocalFood(
    id: localFoodId,
    name: foodName,
    description: description ?? '',
    origin: origin ?? '',
    culturalBackground: culturalBackground ?? '',
    ingredients: ingredients ?? '',
    category: foodCategory ?? '',
    cookingStyle: cookingStyle ?? '',
    mealType: mealType ?? '',
    foodType: foodType ?? '',
    tastes: tastes,
    mainTaste: mainTaste ?? '',
    pronunciationText: pronunciationText ?? '',
    audioGuideUrl: audioGuideUrl,
    synonyms: JsonReader.asStringList(synonyms),
    imageUrls: imageUrls,
    isFavourite: isFavourite,
  );

  @override
  String toString() =>
      'LocalFoodDataModel(id: $localFoodId, name: $foodName, imageCount: ${imageUrls.length})';
}
