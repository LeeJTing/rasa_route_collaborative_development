import '../../core/json_model.dart';

/// Wire shape of one row in `public.restaurant_item`.
class RestaurantItemDataModel implements JsonModel {
  const RestaurantItemDataModel({
    required this.restaurantItemId,
    required this.restaurantId,
    required this.localFoodId,
    required this.restaurantItemName,
    this.ingredients,
    this.foodImgUrl,
    this.foodCategory,
    this.restaurantItemPrice,
  });

  final int restaurantItemId;
  final int restaurantId;
  final int localFoodId;
  final String restaurantItemName;
  final String? ingredients;
  final String? foodImgUrl;
  final String? foodCategory;
  final double? restaurantItemPrice;

  factory RestaurantItemDataModel.fromJson(Map<String, dynamic> json) =>
      RestaurantItemDataModel(
        restaurantItemId: JsonReader.asInt(json['restaurant_item_id']),
        restaurantId: JsonReader.asInt(json['restaurant_id']),
        localFoodId: JsonReader.asInt(json['local_food_id']),
        restaurantItemName: JsonReader.asString(json['restaurant_item_name']),
        ingredients: JsonReader.asStringOrNull(json['ingredients']),
        foodImgUrl: JsonReader.asStringOrNull(json['food_img_url']),
        foodCategory: JsonReader.asStringOrNull(json['food_category']),
        restaurantItemPrice: JsonReader.asDoubleOrNull(
          json['restaurant_item_price'],
        ),
      );

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'restaurant_item_id': restaurantItemId,
    'restaurant_id': restaurantId,
    'local_food_id': localFoodId,
    'restaurant_item_name': restaurantItemName,
    'ingredients': ingredients,
    'food_img_url': foodImgUrl,
    'food_category': foodCategory,
    'restaurant_item_price': restaurantItemPrice,
  };
}
