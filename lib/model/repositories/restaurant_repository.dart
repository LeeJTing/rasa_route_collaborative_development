import '../../core/json_model.dart';
import '../../domain_model/restaurant.dart';
import '../../domain_model/restaurant_item.dart';
import '../../shared_client/api_manager/api_manager.dart';

/// Supabase-backed restaurant catalogue with a local preview when it is empty.
class RestaurantRepository {
  final APIManager api = APIManager();

  Future<List<Restaurant>> getRestaurants() async {
    try {
      final List<Map<String, dynamic>> rows = await api.selectAll(
        APIManager.tableRestaurant,
        columns:
            '*, restaurant_item(*, local_food(food_name, local_food_image(img_name)))',
        orderBy: 'rating',
        ascending: false,
        limit: 30,
      );
      if (rows.isNotEmpty) {
        return rows.map(_fromRow).toList(growable: false);
      }
    } catch (_) {
      // Empty, unauthenticated and offline projects use the same useful UI.
    }
    return _demoRestaurants;
  }

  /// Looks up a restaurant by exact name match (case-insensitive) - UC500's
  /// A13 "Restaurant Already Exists" check. Returns null when nothing matches.
  Future<Restaurant?> findByName(String name) async {
    final String normalized = name.trim().toLowerCase();
    final List<Restaurant> restaurants = await getRestaurants();
    for (final Restaurant restaurant in restaurants) {
      if (restaurant.name.toLowerCase() == normalized) return restaurant;
    }
    return null;
  }

  Restaurant _fromRow(Map<String, dynamic> row) {
    final int id = JsonReader.asInt(row['restaurant_id']);
    final List<RestaurantItem> items = <RestaurantItem>[];
    final Object? rawItems = row['restaurant_item'];
    if (rawItems is List) {
      for (final Object? raw in rawItems) {
        if (raw is! Map) continue;
        final Map<String, dynamic> item = Map<String, dynamic>.from(raw);
        final Map<String, dynamic> food = JsonReader.asMap(item['local_food']);
        String? image = JsonReader.asStringOrNull(item['food_img_url']);
        final Object? images = food['local_food_image'];
        if (image == null &&
            images is List &&
            images.isNotEmpty &&
            images.first is Map) {
          image = JsonReader.asStringOrNull(
            Map<String, dynamic>.from(images.first as Map)['img_name'],
          );
        }
        items.add(
          RestaurantItem(
            id: JsonReader.asInt(item['restaurant_item_id']),
            restaurantId: id,
            localFoodId: JsonReader.asInt(item['local_food_id']),
            foodName: JsonReader.asString(
              item['restaurant_item_name'],
              fallback: JsonReader.asString(
                food['food_name'],
                fallback: 'Local food',
              ),
            ),
            ingredients: JsonReader.asStringOrNull(item['ingredients']),
            imageUrl: image,
            price: JsonReader.asDoubleOrNull(item['restaurant_item_price']),
            currency: 'RM',
            foodCategory: JsonReader.asString(item['food_category']),
            seasonal: JsonReader.asString(item['seasonal']),
          ),
        );
      }
    }
    return Restaurant(
      id: id,
      name: JsonReader.asString(row['restaurant_name']),
      category: JsonReader.asString(row['category']),
      address: JsonReader.asString(row['address']),
      rating: JsonReader.asDoubleOrNull(row['rating']),
      latitude: JsonReader.asDoubleOrNull(row['latitude']),
      longitude: JsonReader.asDoubleOrNull(row['longitude']),
      phone: JsonReader.asString(row['phone']),
      website: JsonReader.asString(row['website']),
      imageUrl: JsonReader.asStringOrNull(row['restaurant_image_url']),
      openingHours: const [],
      items: items,
    );
  }

  static const List<Restaurant> _demoRestaurants = <Restaurant>[
    Restaurant(
      id: 1,
      name: 'OldTown Heritage Kitchen',
      category: 'Malaysian · Chinese',
      address: 'Jalan Tun H S Lee, Kuala Lumpur',
      rating: 4.8,
      reviewCount: 1243,
      latitude: 3.1458,
      longitude: 101.6953,
      phone: '+60 3-2020 1888',
      website: '',
      imageUrl: 'assets/images/figma/restaurant_01.jpeg',
      openingHours: [],
      distanceMetres: 240,
      items: <RestaurantItem>[
        RestaurantItem(
          id: 1,
          restaurantId: 1,
          localFoodId: 1,
          foodName: 'Prawn Noodle',
          ingredients:
              'Yellow noodles and rice vermicelli in a rich prawn broth.',
          imageUrl: 'assets/images/figma/local_food_01.png',
          price: 14.9,
          currency: 'RM',
          foodCategory: 'Noodles',
          seasonal: 'All year',
        ),
        RestaurantItem(
          id: 2,
          restaurantId: 1,
          localFoodId: 2,
          foodName: 'Char Kway Teow',
          ingredients:
              'Flat rice noodles stir-fried with prawns, egg and bean sprouts.',
          imageUrl: 'assets/images/figma/restaurant_09.png',
          price: 13.5,
          currency: 'RM',
          foodCategory: 'Noodles',
          seasonal: 'All year',
        ),
        RestaurantItem(
          id: 3,
          restaurantId: 1,
          localFoodId: 6,
          foodName: 'Teh Tarik',
          ingredients: 'Pulled black tea with creamy condensed milk.',
          imageUrl: 'assets/images/figma/restaurant_04.png',
          price: 4.5,
          currency: 'RM',
          foodCategory: 'Beverage',
          seasonal: 'All year',
        ),
      ],
    ),
    Restaurant(
      id: 2,
      name: 'Kopitiam Sentral',
      category: 'Kopitiam · Local favourites',
      address: 'Brickfields, Kuala Lumpur',
      rating: 4.6,
      reviewCount: 842,
      latitude: 3.1348,
      longitude: 101.6867,
      phone: '+60 3-2276 2211',
      website: '',
      imageUrl: 'assets/images/figma/restaurant_08.jpeg',
      openingHours: [],
      distanceMetres: 480,
      items: <RestaurantItem>[
        RestaurantItem(
          id: 4,
          restaurantId: 2,
          localFoodId: 3,
          foodName: 'Roti Canai',
          ingredients: 'Crispy flatbread served with curry dhal.',
          imageUrl: 'assets/images/figma/restaurant_07.png',
          price: 3.2,
          currency: 'RM',
          foodCategory: 'Bread',
          seasonal: 'All year',
        ),
        RestaurantItem(
          id: 5,
          restaurantId: 2,
          localFoodId: 4,
          foodName: 'Curry Laksa',
          ingredients: 'Noodles served in a spicy coconut curry broth.',
          imageUrl: 'assets/images/figma/restaurant_13.png',
          price: 12.8,
          currency: 'RM',
          foodCategory: 'Noodles',
          seasonal: 'All year',
        ),
      ],
    ),
    Restaurant(
      id: 3,
      name: 'Nyonya Spice House',
      category: 'Peranakan · Malaysian',
      address: 'Bukit Bintang, Kuala Lumpur',
      rating: 4.5,
      reviewCount: 619,
      latitude: 3.1479,
      longitude: 101.7115,
      phone: '+60 3-2142 9088',
      website: '',
      imageUrl: 'assets/images/figma/restaurant_10.jpeg',
      openingHours: [],
      distanceMetres: 720,
      items: <RestaurantItem>[
        RestaurantItem(
          id: 6,
          restaurantId: 3,
          localFoodId: 8,
          foodName: 'Bubur Cha Cha',
          ingredients: 'Sweet potato, taro and sago in creamy coconut milk.',
          imageUrl: 'assets/images/figma/detail_07.png',
          price: 7.5,
          currency: 'RM',
          foodCategory: 'Dessert',
          seasonal: 'All year',
        ),
      ],
    ),
    Restaurant(
      id: 4,
      name: 'Mamak Corner 24/7',
      category: 'Indian Muslim · Street food',
      address: 'Chow Kit, Kuala Lumpur',
      rating: 4.4,
      reviewCount: 1108,
      latitude: 3.1643,
      longitude: 101.6977,
      phone: '+60 3-2698 7171',
      website: '',
      imageUrl: 'assets/images/figma/restaurant_12.jpeg',
      openingHours: [],
      distanceMetres: 910,
      items: <RestaurantItem>[
        RestaurantItem(
          id: 7,
          restaurantId: 4,
          localFoodId: 10,
          foodName: 'Satay',
          ingredients: 'Charcoal-grilled skewers served with peanut sauce.',
          imageUrl: 'assets/images/figma/detail_12.png',
          price: 12,
          currency: 'RM',
          foodCategory: 'Grilled',
          seasonal: 'All year',
        ),
        RestaurantItem(
          id: 8,
          restaurantId: 4,
          localFoodId: 6,
          foodName: 'Teh Tarik',
          ingredients: 'Pulled black tea with creamy condensed milk.',
          imageUrl: 'assets/images/figma/restaurant_04.png',
          price: 4,
          currency: 'RM',
          foodCategory: 'Beverage',
          seasonal: 'All year',
        ),
      ],
    ),
  ];
}
