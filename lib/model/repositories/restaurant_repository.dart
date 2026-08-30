import 'dart:developer' as developer;

import 'package:meta/meta.dart' show visibleForTesting;

import '../../core/json_model.dart';
import '../../domain_model/restaurant.dart';
import '../../domain_model/restaurant_item.dart';
import '../../shared_client/api_manager/api_manager.dart';
import '../data_models/restaurant_data_model.dart';
import '../data_models/restaurant_item_data_model.dart';
import '../data_models/local_food_data_model.dart';
import '../data_models/local_food_image_data_model.dart';
import 'restaurant_opening_hours_parser.dart';

/// Supabase-backed restaurant catalogue used by Quick Mode.
///
/// Errors and empty results are intentionally not replaced with sample cards:
/// the ViewModel must be able to show an honest retry/empty state in the final
/// product. Restaurant-specific item photos are preferred; when absent, the
/// linked local-food catalogue image is used.
class RestaurantRepository {
  final APIManager api = APIManager();
  final RestaurantOpeningHoursParser openingHoursParser =
      const RestaurantOpeningHoursParser();

  static const int _cataloguePageSize = 1000;
  static const int _restaurantIdBatchSize = 200;

  static const String _summaryColumns = '''
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
    status
  ''';

  static const String _itemSummaryColumns = '''
    restaurant_item_id,
    restaurant_id,
    local_food_id,
    restaurant_item_name,
    ingredients,
    food_img_url,
    food_category,
    restaurant_item_price
  ''';

  static const String _detailColumns =
      '''
    $_summaryColumns,
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

  Future<List<Restaurant>> getRestaurants() async {
    try {
      final List<Restaurant> restaurants = <Restaurant>[];
      int rangeStart = 0;
      while (true) {
        final List<Map<String, dynamic>> rows = await api.selectAll(
          APIManager.tableRestaurant,
          columns: _summaryColumns,
          orderBy: 'restaurant_id',
          rangeStart: rangeStart,
          rangeEnd: rangeStart + _cataloguePageSize - 1,
        );
        restaurants.addAll(rows.map(_toDomain));
        if (rows.length < _cataloguePageSize) break;
        rangeStart += _cataloguePageSize;
      }
      return List<Restaurant>.unmodifiable(restaurants);
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

  /// Loads menu details only for the restaurants Quick Mode will display.
  ///
  /// Distance selection must consider the full catalogue, but downloading
  /// every nested menu would make that first query unnecessarily large.
  Future<List<Restaurant>> getRestaurantsByIds(List<int> restaurantIds) async {
    if (restaurantIds.isEmpty) return const <Restaurant>[];
    try {
      final List<Map<String, dynamic>> rows = await api.selectAll(
        APIManager.tableRestaurant,
        columns: _detailColumns,
        inFilter: <String, List<Object?>>{
          'restaurant_id': restaurantIds.cast<Object?>(),
        },
        orderBy: 'restaurant_id',
      );
      return rows.map(_toDomain).toList(growable: false);
    } catch (error, stackTrace) {
      developer.log(
        'Restaurant menu query failed.',
        name: 'RestaurantRepository',
        error: error,
        stackTrace: stackTrace,
      );
      throw Exception(
        'Unable to load restaurant menus. Check your connection and try again.',
      );
    }
  }

  /// Loads the menu facts needed to decide Quick Mode eligibility without
  /// downloading nested catalogue images for every restaurant in 10 km.
  Future<List<RestaurantItem>> getRestaurantItemsByRestaurantIds(
    List<int> restaurantIds,
  ) async {
    if (restaurantIds.isEmpty) return const <RestaurantItem>[];
    try {
      final List<RestaurantItem> items = <RestaurantItem>[];
      for (
        int start = 0;
        start < restaurantIds.length;
        start += _restaurantIdBatchSize
      ) {
        final int end = (start + _restaurantIdBatchSize < restaurantIds.length)
            ? start + _restaurantIdBatchSize
            : restaurantIds.length;
        final List<int> batch = restaurantIds.sublist(start, end);
        int rangeStart = 0;
        while (true) {
          final List<Map<String, dynamic>> rows = await api.selectAll(
            APIManager.tableRestaurantItem,
            columns: _itemSummaryColumns,
            inFilter: <String, List<Object?>>{
              'restaurant_id': batch.cast<Object?>(),
            },
            orderBy: 'restaurant_item_id',
            rangeStart: rangeStart,
            rangeEnd: rangeStart + _cataloguePageSize - 1,
          );
          items.addAll(
            rows.map(
              (Map<String, dynamic> row) =>
                  _itemDataToDomain(RestaurantItemDataModel.fromJson(row)),
            ),
          );
          if (rows.length < _cataloguePageSize) break;
          rangeStart += _cataloguePageSize;
        }
      }
      return List<RestaurantItem>.unmodifiable(items);
    } catch (error, stackTrace) {
      developer.log(
        'Restaurant item eligibility query failed.',
        name: 'RestaurantRepository',
        error: error,
        stackTrace: stackTrace,
      );
      throw Exception(
        'Unable to verify restaurant menus. Check your connection and try again.',
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
      openingHours: openingHoursParser.parse(data.openingHours),
      status: data.status,
      items: items,
    );
  }

  RestaurantItem _itemDataToDomain(RestaurantItemDataModel data) =>
      RestaurantItem(
        id: data.restaurantItemId,
        restaurantId: data.restaurantId,
        localFoodId: data.localFoodId,
        foodName: data.restaurantItemName,
        ingredients: data.ingredients,
        imageUrl: data.foodImgUrl,
        price: data.restaurantItemPrice,
        currency: 'RM',
        foodCategory: data.foodCategory ?? '',
      );

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
    final bool canUseCatalogueImage = catalogueImageMatchesItem(
      restaurantItemName: data.restaurantItemName,
      localFoodName: localFood?.foodName,
    );
    final String? imageName =
        data.foodImgUrl ??
        (canUseCatalogueImage && localFoodImages.isNotEmpty
            ? localFoodImages.first.imageName
            : null);
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

  /// A catalogue image is a generic food reference, not proof that the
  /// restaurant serves the pictured plate. Imported restaurant items can also
  /// carry an incorrect local_food_id. Only reuse the catalogue image when the
  /// linked food name is visibly part of the restaurant's item name; otherwise
  /// the View shows its neutral food-image fallback.
  @visibleForTesting
  bool catalogueImageMatchesItem({
    required String restaurantItemName,
    required String? localFoodName,
  }) {
    final String item = _normaliseFoodName(restaurantItemName);
    final String linkedFood = _normaliseFoodName(localFoodName ?? '');
    return item.isNotEmpty &&
        linkedFood.isNotEmpty &&
        item.contains(linkedFood);
  }

  String _normaliseFoodName(String value) => value
      .toLowerCase()
      .replaceAll('chilli', 'chili')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
}
