import '../../core/json_model.dart';

/// Wire shape of `public.restaurant_item` - one dish on one restaurant's menu.
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
    this.localFoodName,
    this.localFoodDescription,
    this.localFoodImageName,
  });

  /// `restaurant_item.restaurant_item_id` (bigint identity, PK).
  final int restaurantItemId;

  /// FK -> `restaurant.restaurant_id`.
  final int restaurantId;

  /// FK -> `local_food.local_food_id`.
  final int localFoodId;

  /// Restaurant-specific label shown on the menu.
  final String restaurantItemName;

  /// Restaurant-specific ingredients, when the source states them.
  final String? ingredients;

  /// Image associated with this restaurant-specific menu item.
  final String? foodImgUrl;

  final String? foodCategory;
  final double? restaurantItemPrice;
  final String? localFoodName;
  final String? localFoodDescription;
  final String? localFoodImageName;

  factory RestaurantItemDataModel.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> localFood = JsonReader.asMap(json['local_food']);
    return RestaurantItemDataModel(
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
      localFoodName: JsonReader.asStringOrNull(localFood['food_name']),
      localFoodDescription: JsonReader.asStringOrNull(localFood['description']),
      localFoodImageName: _firstImageName(localFood),
    );
  }

  static String? _firstImageName(Map<String, dynamic> localFood) {
    final Object? images = localFood['local_food_image'];
    if (images is! List) return null;
    final List<String> names =
        images
            .whereType<Map>()
            .map((Map image) => JsonReader.asStringOrNull(image['img_name']))
            .whereType<String>()
            .toList()
          ..sort();
    return names.isEmpty ? null : names.first;
  }

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
    'local_food': <String, dynamic>{
      'food_name': localFoodName,
      'description': localFoodDescription,
      'local_food_image': <Map<String, dynamic>>[
        if (localFoodImageName != null)
          <String, dynamic>{'img_name': localFoodImageName},
      ],
    },
  };
}
