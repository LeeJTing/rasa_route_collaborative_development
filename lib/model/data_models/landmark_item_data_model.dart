import '../../core/json_model.dart';

/// Wire shape of `public.landmark_item` - a dish a tourist attached to a
/// landmark they submitted.
class LandmarkItemDataModel implements JsonModel {
  const LandmarkItemDataModel({
    required this.landmarkItemId,
    required this.landmarkId,
    required this.touristId,
    this.localFoodId,
    this.dish,
    this.variant,
    this.foodCategory,
    this.description,
    this.origin,
    this.culturalBackground,
    this.imageUrl,
    this.imageId,
    this.itemPrice,
    this.priceMin,
    this.priceMax,
    this.seasonal,
    this.cookingStyle,
    this.mealType,
    this.isRemoved = false,
  });

  /// `landmark_item.landmark_item_id` (bigint identity, PK).
  final int landmarkItemId;

  /// FK -> `submitted_landmark.landmark_id`.
  final int landmarkId;

  /// FK -> `tourist.tourist_id` (uuid).
  final String touristId;

  /// FK -> `local_food.local_food_id`, nullable. The curated dish this item
  /// resolves to - mirrors `restaurant_item.local_food_id`. Null when the
  /// submitted dish has no catalogue row yet (brand-new food, backfilled
  /// after the Option-C insert) or could not be matched.
  final int? localFoodId;

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

  /// `landmark_item.price_min` / `price_max` - Gemini's suggested selling
  /// range for this dish (MYR), carried on the submitted item (see
  /// `LandmarkItem.priceMin`). Null when Gemini supplied no range.
  final double? priceMin;
  final double? priceMax;

  final String? seasonal;
  final String? cookingStyle;
  final String? mealType;

  /// Soft-removal flag (`landmark_item.is_removed`) - set when enough
  /// tourists reported this dish does not exist.
  final bool isRemoved;

  factory LandmarkItemDataModel.fromJson(Map<String, dynamic> json) {
    return LandmarkItemDataModel(
      landmarkItemId: JsonReader.asInt(json['landmark_item_id']),
      landmarkId: JsonReader.asInt(json['landmark_id']),
      touristId: JsonReader.asString(json['tourist_id']),
      localFoodId: JsonReader.asIntOrNull(json['local_food_id']),
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
      priceMin: JsonReader.asDoubleOrNull(json['price_min']),
      priceMax: JsonReader.asDoubleOrNull(json['price_max']),
      seasonal: JsonReader.asStringOrNull(json['seasonal']),
      cookingStyle: JsonReader.asStringOrNull(json['cooking_style']),
      mealType: JsonReader.asStringOrNull(json['meal_type']),
      isRemoved: JsonReader.asBool(json['is_removed']),
    );
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'landmark_item_id': landmarkItemId,
    'landmark_id': landmarkId,
    'tourist_id': touristId,
    'local_food_id': localFoodId,
    'dish': dish,
    'variant': variant,
    'food_category': foodCategory,
    'description': description,
    'origin': origin,
    'cultural_background': culturalBackground,
    'image_url': imageUrl,
    'image_id': imageId,
    'item_price': itemPrice,
    'price_min': priceMin,
    'price_max': priceMax,
    'seasonal': seasonal,
    'cooking_style': cookingStyle,
    'meal_type': mealType,
    'is_removed': isRemoved,
  };
}
