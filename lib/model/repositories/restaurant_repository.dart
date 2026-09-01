import 'dart:developer' as developer;

import 'package:meta/meta.dart' show visibleForTesting;

import '../../core/json_model.dart';
import '../../domain_model/opening_hour.dart';
import '../../domain_model/restaurant.dart';
import '../../domain_model/restaurant_item.dart';
import '../../shared_client/api_manager/api_manager.dart';
import '../data_models/restaurant_data_model.dart';
import '../data_models/restaurant_item_data_model.dart';
import '../data_models/local_food_data_model.dart';
import '../data_models/local_food_image_data_model.dart';
import '../data_models/opening_hours_data_model.dart';

/// Supabase-backed restaurant catalogue used by Quick Mode.
///
/// Errors and empty results are intentionally not replaced with sample cards:
/// the ViewModel must be able to show an honest retry/empty state in the final
/// product. Restaurant-specific item photos are preferred; when absent, the
/// linked local-food catalogue image is used.
class RestaurantRepository {
  final APIManager api = APIManager();

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
    restaurant_image_id,
    restaurant_image_url,
    status,
    restaurant_opening_hours:opening_hours!opening_hours_restaurant_id_fkey(
      opening_hours_id,
      day,
      status,
      opening_time,
      closing_time,
      landmark_id,
      restaurant_id
    )
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
        synonyms,
        description,
        local_food_image(local_food_image_id, img_name, local_food_id)
      )
    )
  ''';

  Future<Restaurant?> getRestaurantById(int restaurantId) async {
    try {
      final Map<String, dynamic>? row = await api.selectOne(
        APIManager.tableRestaurant,
        columns: _detailColumns,
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
      return List<RestaurantItem>.unmodifiable(
        _deduplicateRestaurantItems(items),
      );
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
    final List<OpeningHour> openingHours = openingHoursFromRows(
      JsonReader.asModelList<Map<String, dynamic>>(
        row['restaurant_opening_hours'],
        (Map<String, dynamic> json) => json,
      ),
    );
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
      openingHours: openingHours,
      status: data.status,
      items: _deduplicateRestaurantItems(items),
    );
  }

  /// Converts ERD `opening_hours` rows at the repository boundary.
  @visibleForTesting
  List<OpeningHour> openingHoursFromRows(List<Map<String, dynamic>> rows) {
    final List<OpeningHour> hours = <OpeningHour>[];
    for (final Map<String, dynamic> row in rows) {
      final OpeningHoursDataModel data = OpeningHoursDataModel.fromJson(row);
      final Weekday? day = _weekday(data.day);
      final DayStatus? status = _dayStatus(data.status);
      if (day == null || status == null) continue;
      int? opensAt = _minutesOfDay(data.openingTime);
      int? closesAt = _minutesOfDay(data.closingTime);
      if (status == DayStatus.open && opensAt == null && closesAt == null) {
        opensAt = 0;
        closesAt = 1440;
      } else if (status == DayStatus.open &&
          opensAt == 0 &&
          data.closingTime?.startsWith('23:59') == true) {
        closesAt = 1440;
      }
      hours.add(
        OpeningHour(
          id: data.openingHoursId,
          day: day,
          status: status,
          opensAt: status == DayStatus.open ? opensAt : null,
          closesAt: status == DayStatus.open ? closesAt : null,
        ),
      );
    }
    hours.sort((OpeningHour a, OpeningHour b) {
      final int dayOrder = a.day.index.compareTo(b.day.index);
      if (dayOrder != 0) return dayOrder;
      return (a.opensAt ?? -1).compareTo(b.opensAt ?? -1);
    });
    return List<OpeningHour>.unmodifiable(hours);
  }

  Weekday? _weekday(String value) {
    final String name = value.trim().toLowerCase();
    for (final Weekday day in Weekday.values) {
      if (day.name == name) return day;
    }
    return null;
  }

  DayStatus? _dayStatus(String value) {
    final String name = value.trim().toLowerCase();
    for (final DayStatus status in DayStatus.values) {
      if (status.name == name) return status;
    }
    return null;
  }

  int? _minutesOfDay(String? value) {
    if (value == null || value.isEmpty) return null;
    final List<String> parts = value.split(':');
    if (parts.length < 2) return null;
    final int? hour = int.tryParse(parts[0]);
    final int? minute = int.tryParse(parts[1]);
    if (hour == null || minute == null || hour > 23 || minute > 59) {
      return null;
    }
    return hour * 60 + minute;
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
    final String? imageName = preferredRestaurantItemImageName(
      restaurantImageName: data.foodImgUrl,
      linkedFoodImageNames: localFoodImages
          .map((LocalFoodImageDataModel image) => image.imageName)
          .toList(growable: false),
    );
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

  /// Resolves an item's image according to the ERD relationship.
  ///
  /// A restaurant-specific photo wins. Otherwise the first image belonging to
  /// the `local_food_id` foreign-key target is used. Missing data remains null
  /// so the View can render its neutral fallback.
  @visibleForTesting
  String? preferredRestaurantItemImageName({
    required String? restaurantImageName,
    required List<String> linkedFoodImageNames,
  }) {
    final String? restaurantImage = _nonEmpty(restaurantImageName);
    if (restaurantImage != null) return restaurantImage;
    for (final String linkedImage in linkedFoodImageNames) {
      final String? value = _nonEmpty(linkedImage);
      if (value != null) return value;
    }
    return null;
  }

  String? _nonEmpty(String? value) {
    final String? trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  String _normaliseMenuEntryName(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  /// Imported menu datasets can contain the same dish more than once under
  /// different row ids. A restaurant menu is unique by its visible dish name
  /// and price; when duplicates exist, retain the row with the richer photo
  /// and ingredient data.
  @visibleForTesting
  List<RestaurantItem> deduplicateRestaurantItems(List<RestaurantItem> items) =>
      _deduplicateRestaurantItems(items);

  List<RestaurantItem> _deduplicateRestaurantItems(List<RestaurantItem> items) {
    final Map<String, RestaurantItem> byMenuEntry = <String, RestaurantItem>{};
    for (final RestaurantItem item in items) {
      final String key = <String>[
        item.restaurantId.toString(),
        _normaliseMenuEntryName(item.foodName),
        item.price?.toStringAsFixed(2) ?? 'no-price',
      ].join('|');
      final RestaurantItem? existing = byMenuEntry[key];
      if (existing == null || _itemQuality(item) > _itemQuality(existing)) {
        byMenuEntry[key] = item;
      }
    }
    return List<RestaurantItem>.unmodifiable(byMenuEntry.values);
  }

  int _itemQuality(RestaurantItem item) {
    int quality = 0;
    if (item.imageUrl?.trim().isNotEmpty == true) quality += 2;
    if (item.ingredients?.trim().isNotEmpty == true) quality += 1;
    return quality;
  }
}
