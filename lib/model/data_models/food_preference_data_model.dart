import '../../core/json_model.dart';

/// Wire shape of `public.food_preference`.
///
/// `preferred_categories` / `preferred_taste` are stored as comma-separated
/// text in Postgres; this model keeps that raw form and the domain layer is
/// what splits them into lists.
class FoodPreferenceDataModel implements JsonModel {
  const FoodPreferenceDataModel({
    required this.foodPreferenceId,
    this.preferredCategories,
    this.preferredTaste,
  });

  /// `food_preference.food_preference_id` (bigint identity, PK).
  final int foodPreferenceId;

  /// `food_preference.preferred_categories` (text, nullable).
  final String? preferredCategories;

  /// `food_preference.preferred_taste` (text, nullable).
  final String? preferredTaste;

  factory FoodPreferenceDataModel.fromJson(Map<String, dynamic> json) {
    return FoodPreferenceDataModel(
      foodPreferenceId: JsonReader.asInt(json['food_preference_id']),
      preferredCategories:
          JsonReader.asStringOrNull(json['preferred_categories']),
      preferredTaste: JsonReader.asStringOrNull(json['preferred_taste']),
    );
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'food_preference_id': foodPreferenceId,
    'preferred_categories': preferredCategories,
    'preferred_taste': preferredTaste,
  };
}
