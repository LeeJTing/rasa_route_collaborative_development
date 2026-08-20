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
    this.pronunciationText,
    this.audioGuideUrl,
    this.synonyms,
    this.imageUrl,
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
  final String? pronunciationText;
  final String? audioGuideUrl;
  final String? synonyms;
  final String? imageUrl;

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
      pronunciationText: JsonReader.asStringOrNull(json['pronunciation_text']),
      audioGuideUrl: JsonReader.asStringOrNull(json['audio_guide_url']),
      synonyms: JsonReader.asStringOrNull(json['synonyms']),
      imageUrl: _extractImageUrl(json),
    );
  }

  /// Handles either a direct `img_name` field or the joined
  /// `local_food_image` array shape.
  static String? _extractImageUrl(Map<String, dynamic> json) {
    final String? direct = JsonReader.asStringOrNull(json['img_name']);
    if (direct != null) return direct;

    final dynamic images = json['local_food_image'];
    if (images is List && images.isNotEmpty) {
      final Object? first = images.first;
      if (first is Map) {
        return JsonReader.asStringOrNull(
          Map<String, dynamic>.from(first)['img_name'],
        );
      }
    }
    return null;
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
    'pronunciation_text': pronunciationText,
    'audio_guide_url': audioGuideUrl,
    'synonyms': synonyms,
    'img_name': imageUrl,
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
    pronunciationText: pronunciationText ?? '',
    audioGuideUrl: audioGuideUrl,
    synonyms: JsonReader.asStringList(synonyms),
    imageUrl: imageUrl,
    isFavourite: isFavourite,
  );

  @override
  String toString() =>
      'LocalFoodDataModel(id: $localFoodId, name: $foodName, imageUrl: $imageUrl)';
}
