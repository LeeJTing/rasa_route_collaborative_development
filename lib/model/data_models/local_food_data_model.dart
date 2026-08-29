import '../../core/json_model.dart';

/// Wire shape of one row in `public.local_food`.
///
/// Joined `local_food_image` and `local_food_preference` payloads are parsed
/// by their own data models inside `FoodKnowledgeRepository`. Keeping joined
/// data out of this class preserves the one-data-model-per-table rule.
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
    this.pronunciationText,
    this.audioGuideUrl,
    this.synonyms,
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
  final String? pronunciationText;
  final String? audioGuideUrl;
  final String? synonyms;

  factory LocalFoodDataModel.fromJson(
    Map<String, dynamic> json,
  ) => LocalFoodDataModel(
    localFoodId: JsonReader.asInt(json['local_food_id']),
    foodName: JsonReader.asString(json['food_name']),
    description: JsonReader.asStringOrNull(json['description']),
    origin: JsonReader.asStringOrNull(json['origin']),
    culturalBackground: JsonReader.asStringOrNull(json['cultural_background']),
    ingredients: JsonReader.asStringOrNull(json['ingredients']),
    foodCategory: JsonReader.asStringOrNull(json['food_category']),
    cookingStyle: JsonReader.asStringOrNull(json['cooking_style']),
    mealType: JsonReader.asStringOrNull(json['meal_type']),
    foodType: JsonReader.asStringOrNull(json['food_type']),
    pronunciationText: JsonReader.asStringOrNull(json['pronunciation_text']),
    audioGuideUrl: JsonReader.asStringOrNull(json['audio_guide_url']),
    synonyms: JsonReader.asStringOrNull(json['synonyms']),
  );

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
    'pronunciation_text': pronunciationText,
    'audio_guide_url': audioGuideUrl,
    'synonyms': synonyms,
  };
}
