import '../../core/json_model.dart';

/// Wire shape of `public.dietary_restriction`.
class DietaryRestrictionDataModel implements JsonModel {
  const DietaryRestrictionDataModel({
    required this.dietaryRestrictionId,
    required this.restrictionName,
  });

  /// `dietary_restriction.dietary_restriction_id` (bigint identity, PK).
  final int dietaryRestrictionId;

  /// `dietary_restriction.restriction_name` (text, unique).
  final String restrictionName;

  factory DietaryRestrictionDataModel.fromJson(Map<String, dynamic> json) {
    return DietaryRestrictionDataModel(
      dietaryRestrictionId: JsonReader.asInt(json['dietary_restriction_id']),
      restrictionName: JsonReader.asString(json['restriction_name']),
    );
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'dietary_restriction_id': dietaryRestrictionId,
    'restriction_name': restrictionName,
  };
}
