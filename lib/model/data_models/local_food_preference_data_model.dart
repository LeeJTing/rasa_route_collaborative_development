import '../../core/json_model.dart';

/// Wire shape of one row in `public.local_food_preference`.
class LocalFoodPreferenceDataModel implements JsonModel {
  const LocalFoodPreferenceDataModel({
    required this.foodPreferenceId,
    required this.localFoodId,
    required this.isMain,
  });

  final int foodPreferenceId;
  final int localFoodId;
  final bool isMain;

  factory LocalFoodPreferenceDataModel.fromJson(Map<String, dynamic> json) =>
      LocalFoodPreferenceDataModel(
        foodPreferenceId: JsonReader.asInt(json['food_preference_id']),
        localFoodId: JsonReader.asInt(json['local_food_id']),
        isMain: JsonReader.asBool(json['is_main']),
      );

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'food_preference_id': foodPreferenceId,
    'local_food_id': localFoodId,
    'is_main': isMain,
  };
}
