import '../../core/json_model.dart';

/// Wire shape of `public.landmark_item` - a dish a tourist attached to a
/// landmark they submitted.
class LandmarkItemDataModel implements JsonModel {
  const LandmarkItemDataModel({
    required this.landmarkItemId,
    required this.landmarkId,
    required this.touristId,
    this.dish,
    this.variant,
    this.foodCategory,
    this.description,
    this.origin,
    this.culturalBackground,
    this.imageUrl,
    this.imageId,
    this.itemPrice,
    this.seasonal,
    this.cookingStyle,
    this.mealType,
  });

  /// `landmark_item.landmark_item_id` (bigint identity, PK).
  final int landmarkItemId;

  /// FK -> `submitted_landmark.landmark_id`.
  final int landmarkId;

  /// FK -> `tourist.tourist_id` (uuid).
  final String touristId;

  final String? dish;
  final String? variant;
  final String? foodCategory;
  final String? description;
  final String? origin;
  final String? culturalBackground;

  /// Public URL of the image in Supabase Storage.
  final String? imageUrl;

  /// Storage object id, kept so the image can be replaced or deleted.
  final String? imageId;

  final double? itemPrice;
  final String? seasonal;
  final String? cookingStyle;
  final String? mealType;

  factory LandmarkItemDataModel.fromJson(Map<String, dynamic> json) {
    return LandmarkItemDataModel(
      landmarkItemId: JsonReader.asInt(json['landmark_item_id']),
      landmarkId: JsonReader.asInt(json['landmark_id']),
      touristId: JsonReader.asString(json['tourist_id']),
      dish: JsonReader.asStringOrNull(json['dish']),
      variant: JsonReader.asStringOrNull(json['variant']),
      foodCategory: JsonReader.asStringOrNull(json['food_category']),
      description: JsonReader.asStringOrNull(json['description']),
      origin: JsonReader.asStringOrNull(json['origin']),
      culturalBackground: JsonReader.asStringOrNull(
        json['cultural_background'],
      ),
      imageUrl: JsonReader.asStringOrNull(json['image_url']),
      imageId: JsonReader.asStringOrNull(json['image_id']),
      itemPrice: JsonReader.asDoubleOrNull(json['item_price']),
      seasonal: JsonReader.asStringOrNull(json['seasonal']),
      cookingStyle: JsonReader.asStringOrNull(json['cooking_style']),
      mealType: JsonReader.asStringOrNull(json['meal_type']),
    );
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'landmark_item_id': landmarkItemId,
    'landmark_id': landmarkId,
    'tourist_id': touristId,
    'dish': dish,
    'variant': variant,
    'food_category': foodCategory,
    'description': description,
    'origin': origin,
    'cultural_background': culturalBackground,
    'image_url': imageUrl,
    'image_id': imageId,
    'item_price': itemPrice,
    'seasonal': seasonal,
    'cooking_style': cookingStyle,
    'meal_type': mealType,
  };
}
