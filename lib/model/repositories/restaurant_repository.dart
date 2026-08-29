import 'dart:developer' as developer;

import '../../core/json_model.dart';
import '../../domain_model/restaurant.dart';
import '../../domain_model/restaurant_item.dart';
import '../../shared_client/api_manager/api_manager.dart';
import '../data_models/restaurant_data_model.dart';
import '../data_models/restaurant_item_data_model.dart';
import '../data_models/local_food_data_model.dart';
import '../data_models/local_food_image_data_model.dart';

/// Supabase-backed restaurant catalogue used by Quick Mode.
///
/// Errors and empty results are intentionally not replaced with sample cards:
/// the ViewModel must be able to show an honest retry/empty state in the final
/// product. Restaurant-specific item photos are preferred; when absent, the
/// linked local-food catalogue image is used.
class RestaurantRepository {
  final APIManager api = APIManager();

  static const String _selectColumns = '''
    restaurant_id,
    restaurant_name,
    category,
    address,
    rating,
    longitude,
    latitude,
    phone,
    website,
    opening_hours,
    restaurant_image_id,
    restaurant_image_url,
    restaurant_item(
      restaurant_item_id,
      restaurant_id,
      local_food_id,
      restaurant_item_name,
      ingredients,
      food_img_url,
      food_category,
      restaurant_item_price,
      local_food(
        local_food_id,
        food_name,
        description,
        local_food_image(local_food_image_id, img_name, local_food_id)
      )
    )
  ''';

  Future<Restaurant?> getRestaurantById(int restaurantId) async {
    try {
      final Map<String, dynamic>? row = await api.selectOne(
        APIManager.tableRestaurant,
        columns: _selectColumns,
        eq: <String, Object?>{'restaurant_id': restaurantId},
      );
      return row == null ? null : _toDomain(row);
    } catch (error, stackTrace) {
      developer.log(
        'Restaurant detail query failed for restaurant $restaurantId.',
        name: 'RestaurantRepository',
        error: error,
        stackTrace: stackTrace,
      );
      throw Exception(
        'Unable to load restaurant details. Check your connection and try again.',
      );
    }
  }

  Future<List<Restaurant>> getRestaurants() async {
    try {
      final List<Map<String, dynamic>> rows = await api.selectAll(
        APIManager.tableRestaurant,
        columns: _selectColumns,
        orderBy: 'rating',
        ascending: false,
        limit: 200,
      );
      return rows.map(_toDomain).toList(growable: false);
    } catch (error, stackTrace) {
      developer.log(
        'Restaurant catalogue query failed.',
        name: 'RestaurantRepository',
        error: error,
        stackTrace: stackTrace,
      );
      throw Exception(
        'Unable to load nearby restaurants. Check your connection and try again.',
      );
    }
  }

  /// UC500's "Restaurant Already Exists" check.
  Future<Restaurant?> findByName(String name) async {
    final String normalized = name.trim().toLowerCase();
    final List<Restaurant> restaurants = await getRestaurants();
    for (final Restaurant restaurant in restaurants) {
      if (restaurant.name.toLowerCase() == normalized) return restaurant;
    }
    return null;
  }

  Restaurant _toDomain(Map<String, dynamic> row) {
    final RestaurantDataModel data = RestaurantDataModel.fromJson(row);
    final Object? rawItems = row['restaurant_item'];
    final List<RestaurantItem> items = rawItems is List
        ? rawItems
              .whereType<Map>()
              .map((Map raw) => _itemToDomain(Map<String, dynamic>.from(raw)))
              .toList(growable: false)
        : const <RestaurantItem>[];

    return Restaurant(
      id: data.restaurantId,
      name: data.restaurantName,
      category: data.category ?? '',
      address: data.address ?? '',
      rating: data.rating,
      latitude: data.latitude,
      longitude: data.longitude,
      phone: data.phone ?? '',
      website: data.website ?? '',
      imageUrl: data.restaurantImageUrl,
      openingHours: const [],
      items: items,
    );
  }

  RestaurantItem _itemToDomain(Map<String, dynamic> row) {
    final RestaurantItemDataModel data = RestaurantItemDataModel.fromJson(row);
    final Map<String, dynamic>? localFoodRow = JsonReader.asMapOrNull(
      row['local_food'],
    );
    final LocalFoodDataModel? localFood = localFoodRow == null
        ? null
        : LocalFoodDataModel.fromJson(localFoodRow);
    final List<LocalFoodImageDataModel> localFoodImages =
        localFoodRow == null
              ? const <LocalFoodImageDataModel>[]
              : JsonReader.asModelList(
                  localFoodRow['local_food_image'],
                  LocalFoodImageDataModel.fromJson,
                )
          ..sort(
            (LocalFoodImageDataModel a, LocalFoodImageDataModel b) =>
                a.localFoodImageId.compareTo(b.localFoodImageId),
          );
    final String? imageName =
        data.foodImgUrl ??
        (localFoodImages.isEmpty ? null : localFoodImages.first.imageName);
    return RestaurantItem(
      id: data.restaurantItemId,
      restaurantId: data.restaurantId,
      localFoodId: data.localFoodId,
      foodName: data.restaurantItemName.isEmpty
          ? localFood?.foodName ?? 'Local food'
          : data.restaurantItemName,
      ingredients: data.ingredients ?? localFood?.description,
      imageUrl: api.resolveImageUrl(
        imageName,
        bucket: APIManager.storageBucketFoodImages,
      ),
      price: data.restaurantItemPrice,
      currency: 'RM',
      foodCategory: data.foodCategory ?? '',
    );
  }
}
