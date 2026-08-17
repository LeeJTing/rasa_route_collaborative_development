import '../../core/json_model.dart';

/// Wire shape of `public.local_food`.
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
    this.imageNames = const <String>[],
  });

  /// `local_food.local_food_id` (bigint identity, PK).
  final int localFoodId;

  /// `local_food.food_name` (text, not null).
  final String foodName;

  final String? description;
  final String? origin;
  final String? culturalBackground;

  /// Comma-separated in Postgres.
  final String? ingredients;

  final String? foodCategory;
  final String? cookingStyle;
  final String? mealType;
  final String? pronunciationText;
  final String? audioGuideUrl;

  /// Comma-separated in Postgres.
  final String? synonyms;

  /// Joined from `public.local_food_image.img_name`. Empty when not selected.
  final List<String> imageNames;

  factory LocalFoodDataModel.fromJson(Map<String, dynamic> json) {
    return LocalFoodDataModel(
      localFoodId: JsonReader.asInt(json['local_food_id']),
      foodName: JsonReader.asString(json['food_name']),
      description: JsonReader.asStringOrNull(json['description']),
      origin: JsonReader.asStringOrNull(json['origin']),
      culturalBackground:
          JsonReader.asStringOrNull(json['cultural_background']),
      ingredients: JsonReader.asStringOrNull(json['ingredients']),
      foodCategory: JsonReader.asStringOrNull(json['food_category']),
      cookingStyle: JsonReader.asStringOrNull(json['cooking_style']),
      mealType: JsonReader.asStringOrNull(json['meal_type']),
      pronunciationText:
          JsonReader.asStringOrNull(json['pronunciation_text']),
      audioGuideUrl: JsonReader.asStringOrNull(json['audio_guide_url']),
      synonyms: JsonReader.asStringOrNull(json['synonyms']),
      imageNames: _readImageNames(json['local_food_image']),
    );
  }

  /// Supabase returns the embedded relation as
  /// `[{"img_name": "..."} , ...]` when the select uses `local_food_image(*)`.
  static List<String> _readImageNames(Object? value) {
    if (value is! List) return const <String>[];
    return value
        .whereType<Map<Object?, Object?>>()
        .map((Map<Object?, Object?> e) =>
            JsonReader.asString(Map<String, dynamic>.from(e)['img_name']))
        .where((String name) => name.isNotEmpty)
        .toList(growable: false);
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
  };
}
