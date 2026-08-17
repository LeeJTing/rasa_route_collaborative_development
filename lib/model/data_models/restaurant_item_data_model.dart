import '../../core/json_model.dart';

/// Wire shape of `public.restaurant_item` - one dish on one restaurant's menu.
class RestaurantItemDataModel implements JsonModel {
  const RestaurantItemDataModel({
    required this.restaurantItemId,
    required this.restaurantId,
    required this.localFoodId,
    this.seasonal,
    this.foodCategory,
    this.restaurantItemPrice,
  });

  /// `restaurant_item.restaurant_item_id` (bigint identity, PK).
  final int restaurantItemId;

  /// FK -> `restaurant.restaurant_id`.
  final int restaurantId;

  /// FK -> `local_food.local_food_id`.
  final int localFoodId;

  final String? seasonal;
  final String? foodCategory;
  final double? restaurantItemPrice;

  factory RestaurantItemDataModel.fromJson(Map<String, dynamic> json) {
    return RestaurantItemDataModel(
      restaurantItemId: JsonReader.asInt(json['restaurant_item_id']),
      restaurantId: JsonReader.asInt(json['restaurant_id']),
      localFoodId: JsonReader.asInt(json['local_food_id']),
      seasonal: JsonReader.asStringOrNull(json['seasonal']),
      foodCategory: JsonReader.asStringOrNull(json['food_category']),
      restaurantItemPrice:
          JsonReader.asDoubleOrNull(json['restaurant_item_price']),
    );
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'restaurant_item_id': restaurantItemId,
    'restaurant_id': restaurantId,
    'local_food_id': localFoodId,
    'seasonal': seasonal,
    'food_category': foodCategory,
    'restaurant_item_price': restaurantItemPrice,
  };
}
