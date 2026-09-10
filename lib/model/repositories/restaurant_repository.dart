import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:meta/meta.dart' show protected, visibleForTesting;

import '../../core/json_model.dart';
import '../../core/name_normalization.dart';
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

  // ---------------------------------------------------------------------------
  // Catalogue cache
  // ---------------------------------------------------------------------------
  //
  // `getRestaurants()` downloads the WHOLE restaurant table (12k+ rows, each
  // with its nested `opening_hours`), paged 1000 at a time. Quick Mode ran it
  // on every GPS fix and Matches on every open - the single biggest source of
  // Supabase egress in the app. The catalogue is effectively static at
  // runtime (writes are rare: moderation, closures, merges), so it is cached
  // like `MapRepository`/`FoodKnowledgeRepository`, with a static copy shared
  // by every facade instance.
  //
  // Static, and every write below calls [invalidate] so the cache never
  // outlives its own edits.

  static const Duration cacheTtl = Duration(minutes: 5);

  static List<Restaurant>? _cachedRestaurants;
  static DateTime? _cachedRestaurantsAt;
  static Future<List<Restaurant>>? _restaurantsRequest;

  /// Bumped by [invalidate] so an in-flight download that started BEFORE the
  /// write can never repopulate the cache with pre-write rows (and stamp them
  /// fresh) once it finally lands.
  static int _cacheGeneration = 0;

  /// Drops the cached restaurant catalogue. Call after anything that writes a
  /// restaurant, a restaurant item or a restaurant's opening hours, or the
  /// next read keeps showing the old answer for up to [cacheTtl].
  ///
  /// Also abandons any download already in flight: the write happened, so a
  /// read that returns the pre-write request (or lets it fill the cache) is
  /// wrong, and the very next read must start from Supabase again.
  static void invalidate() {
    _cacheGeneration++;
    _cachedRestaurants = null;
    _cachedRestaurantsAt = null;
    _restaurantsRequest = null;
  }

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
    closed_until,
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
    restaurant_item_price,
    is_removed
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
      is_removed,
      local_food(
        local_food_id,
        food_name,
        synonyms,
        description,
        local_food_image(local_food_image_id, img_name, local_food_id)
      )
    )
  ''';

  /// range (see [restaurantPriceRangeByFood]).
  static final RegExp _bulkPackPattern = RegExp(
    r'(?:'
    r'(\d+)\s*\b(botol|biji|pek|paket|pak|kotak|tin|karton|dozen|lusin|bungkus|set)\b'
    r'|\b(botol|biji|pek|paket|pak|kotak|tin|karton|dozen|lusin|bungkus|set)\b\s*(\d+)'
    r')',
    caseSensitive: false,
  );

  static bool _isBulkPack(String itemName) {
    final RegExpMatch? match = _bulkPackPattern.firstMatch(itemName);
    if (match == null) return false;
    // The count is captured in group 1 ("30 botol") or group 4 ("BOTOL 30").
    final String? count = match.group(1) ?? match.group(4);
    final int? parsed = count == null ? null : int.tryParse(count);
    // A single unit (e.g. "BOTOL 1") is a normal single-serve price.
    return parsed != null && parsed > 1;
  }

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

  Future<List<Restaurant>> getRestaurants() {
    final List<Restaurant>? cached = _cachedRestaurants;
    if (cached != null &&
        _cachedRestaurantsAt != null &&
        currentTime().difference(_cachedRestaurantsAt!) < cacheTtl) {
      return Future<List<Restaurant>>.value(cached);
    }
    // Concurrent callers (Quick Mode + Matches load together) share one
    // request instead of each downloading the whole catalogue.
    final Future<List<Restaurant>>? inFlight = _restaurantsRequest;
    if (inFlight != null) return inFlight;
    final int generation = _cacheGeneration;
    late final Future<List<Restaurant>> request;
    request = fetchCatalogueRows()
        .then((List<Restaurant> value) {
          // A write may have invalidated the cache while this download was
          // out. If so, drop the result: it predates the write and would
          // otherwise resurrect stale rows under a fresh timestamp.
          if (generation == _cacheGeneration) {
            _cachedRestaurants = value;
            _cachedRestaurantsAt = currentTime();
          }
          return value;
        })
        .whenComplete(() {
          // Only clear the slot if it still holds THIS request - an
          // invalidate (or a newer download) may have replaced it.
          if (identical(_restaurantsRequest, request)) {
            _restaurantsRequest = null;
          }
        });
    _restaurantsRequest = request;
    return request;
  }

  /// Test seam: lets a cache test advance the clock so the [cacheTtl] branch
  /// can be exercised without waiting five real minutes. Production always
  /// returns `DateTime.now()` (the same contract as the logic layer's
  /// `currentTime()` seams).
  @protected
  DateTime currentTime() => DateTime.now();

  /// Test seam: lets a cache test feed canned rows through the REAL cache
  /// logic in [getRestaurants] (freshness check, single-flight request,
  /// [invalidate]) without a network. Production pages the whole table down
  /// through [_fetchRestaurants].
  @protected
  Future<List<Restaurant>> fetchCatalogueRows() => _fetchRestaurants();

  Future<List<Restaurant>> _fetchRestaurants() async {
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

  /// Loads only restaurant summaries inside a server-filtered coordinate box.
  ///
  /// The repository deliberately uses a bounding box rather than pretending
  /// latitude/longitude degrees are an exact distance. Business logic applies
  /// the precise Haversine radius after this inexpensive Supabase pre-filter.
  Future<List<Restaurant>> getRestaurantsNear({
    required double latitude,
    required double longitude,
    required double maximumDistanceKm,
  }) async {
    if (maximumDistanceKm <= 0) return const <Restaurant>[];
    const double kilometresPerLatitudeDegree = 110.574;
    const double kilometresPerLongitudeDegreeAtEquator = 111.320;
    final double latitudeDelta =
        maximumDistanceKm / kilometresPerLatitudeDegree;
    final double longitudeScale = math.cos(latitude * math.pi / 180).abs();
    final double longitudeDelta =
        maximumDistanceKm /
        (kilometresPerLongitudeDegreeAtEquator *
            math.max(longitudeScale, 0.01));

    try {
      final List<Restaurant> restaurants = <Restaurant>[];
      int rangeStart = 0;
      while (true) {
        final List<Map<String, dynamic>> rows = await api.selectAll(
          APIManager.tableRestaurant,
          columns: _summaryColumns,
          gte: <String, num>{
            'latitude': latitude - latitudeDelta,
            'longitude': longitude - longitudeDelta,
          },
          lte: <String, num>{
            'latitude': latitude + latitudeDelta,
            'longitude': longitude + longitudeDelta,
          },
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
        'Nearby restaurant summary query failed.',
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
  /// Distance selection uses nearby summaries, but downloading every nested
  /// menu for those candidates would still make the first query too large.
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

  /// The restaurant's CURRENT menu items for the report page's item picker -
  /// lightweight rows (id + name + price), excluding items already
  /// soft-removed by earlier reports. A tourist can only report a price /
  /// existence of a dish the place is still showing.
  Future<List<RestaurantItem>> getReportableItems(int restaurantId) async {
    final List<Map<String, dynamic>> rows = await api.selectAll(
      APIManager.tableRestaurantItem,
      columns:
          'restaurant_item_id, restaurant_id, local_food_id, '
          'restaurant_item_name, restaurant_item_price',
      eq: <String, Object?>{'restaurant_id': restaurantId, 'is_removed': false},
      orderBy: 'restaurant_item_id',
    );
    return List<RestaurantItem>.unmodifiable(
      rows.map(
        (Map<String, dynamic> row) =>
            _itemDataToDomain(RestaurantItemDataModel.fromJson(row)),
      ),
    );
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

  Future<Map<int, ({double min, double max})>> restaurantPriceRangeByFood(
    Set<int> localFoodIds,
  ) async {
    if (localFoodIds.isEmpty) {
      return const <int, ({double min, double max})>{};
    }
    try {
      final List<Map<String, dynamic>> rows = await api.selectAll(
        APIManager.tableRestaurantItem,
        columns: 'local_food_id, restaurant_item_name, restaurant_item_price',
        inFilter: <String, List<Object?>>{
          'local_food_id': localFoodIds.cast<Object?>().toList(),
        },
      );
      final Map<int, double> minByFood = <int, double>{};
      final Map<int, double> maxByFood = <int, double>{};
      for (final Map<String, dynamic> row in rows) {
        final int? foodId = JsonReader.asIntOrNull(row['local_food_id']);
        final double? price = JsonReader.asDoubleOrNull(
          row['restaurant_item_price'],
        );
        // A bulk/wholesale line (e.g. "Air Katira (30 botol) RM540") prices a
        // multi-unit pack, not a single serve - it would inflate the range the
        // comparison shows, so it is excluded from the min/max aggregation.
        final String itemName = JsonReader.asString(row['restaurant_item_name']);
        if (foodId == null ||
            price == null ||
            price <= 0 ||
            _isBulkPack(itemName)) {
          continue;
        }
        final double currentMin = minByFood[foodId] ?? price;
        final double currentMax = maxByFood[foodId] ?? price;
        minByFood[foodId] = price < currentMin ? price : currentMin;
        maxByFood[foodId] = price > currentMax ? price : currentMax;
      }
      return <int, ({double min, double max})>{
        for (final MapEntry<int, double> entry in minByFood.entries)
          entry.key: (
            min: entry.value,
            max: maxByFood[entry.key] ?? entry.value,
          ),
      };
    } catch (error, stackTrace) {
      developer.log(
        'Restaurant price range query failed.',
        name: 'RestaurantRepository',
        error: error,
        stackTrace: stackTrace,
      );
      throw Exception(
        'Unable to load restaurant prices. Check your connection and try again.',
      );
    }
  }

  /// Every real menu line (name + price) per dish, unfiltered - the source for
  /// the comparison's "Time and Price" list. Kept verbatim (no min/max, no
  /// bulk filtering) so a pack line like "BOTOL 30" keeps its unit text and
  /// is shown to the tourist as-is.
  Future<Map<int, List<({String name, double price})>>> restaurantMenuItemsByFood(
    Set<int> localFoodIds,
  ) async {
    if (localFoodIds.isEmpty) {
      return const <int, List<({String name, double price})>>{};
    }
    try {
      final List<Map<String, dynamic>> rows = await api.selectAll(
        APIManager.tableRestaurantItem,
        columns: 'local_food_id, restaurant_item_name, restaurant_item_price',
        inFilter: <String, List<Object?>>{
          'local_food_id': localFoodIds.cast<Object?>().toList(),
        },
      );
      final Map<int, List<({String name, double price})>> byFood =
          <int, List<({String name, double price})>>{};
      for (final Map<String, dynamic> row in rows) {
        final int? foodId = JsonReader.asIntOrNull(row['local_food_id']);
        final double? price = JsonReader.asDoubleOrNull(
          row['restaurant_item_price'],
        );
        final String name = JsonReader.asString(
          row['restaurant_item_name'],
        ).trim();
        if (foodId == null || price == null || price <= 0 || name.isEmpty) {
          continue;
        }
        byFood.putIfAbsent(
          foodId,
          () => <({String name, double price})>[],
        ).add((name: name, price: price));
      }
      for (final List<({String name, double price})> entries in byFood.values) {
        entries.sort(
          (a, b) => a.price.compareTo(b.price),
        );
      }
      return byFood;
    } catch (error, stackTrace) {
      developer.log(
        'Restaurant menu listing query failed.',
        name: 'RestaurantRepository',
        error: error,
        stackTrace: stackTrace,
      );
      throw Exception(
        'Unable to load restaurant prices. Check your connection and try again.',
      );
    }
  }

  /// UC500's "Restaurant Already Exists" check.
  Future<Restaurant?> findByName(String name) async {
    final List<Restaurant> matches = await findByNameList(name);
    return matches.isEmpty ? null : matches.first;
  }

  /// Every catalogue restaurant whose name equals [name] (trimmed,
  /// case-insensitive). Unlike [findByName] this returns ALL matches - the
  /// submit flow then picks the one within ~100m of the landmark's location
  /// (see `LandmarkSubmissionLogic`), so two same-named restaurants in
  /// different towns are not confused with each other.
  ///
  /// This is the merge/exists check a submission runs - it must be FRESH (a
  /// restaurant another device just added must be found so the submission
  /// merges instead of duplicating), so the shared catalogue cache is dropped
  /// first. Submissions are rare user actions; one fresh read is the right
  /// price for a correct merge decision.
  Future<List<Restaurant>> findByNameList(String name) async {
    final String normalized = placeNameKey(name);
    if (normalized.isEmpty) return const <Restaurant>[];
    invalidate();
    final List<Restaurant> restaurants = await getRestaurants();
    return <Restaurant>[
      for (final Restaurant restaurant in restaurants)
        if (placeNameKey(restaurant.name) == normalized) restaurant,
    ];
  }

  /// Attaches one submitted dish to [restaurantId] as a new `restaurant_item`
  /// row (the merge path of the Add-Landmark flow - "this is the same place,
  /// so add the dish to the existing restaurant instead of creating a new
  /// landmark"). `restaurant_item_id` is left for the DB to assign (identity).
  /// [localFoodId] is required by the table - the caller resolves it first
  /// (a genuinely-new dish is registered to `local_food` before this is
  /// called, Option-C style).
  Future<void> addRestaurantItem({
    required int restaurantId,
    required int localFoodId,
    required String name,
    String? ingredients,
    String? foodImgUrl,
    String? foodCategory,
    double? price,
  }) async {
    await api.insertRow(APIManager.tableRestaurantItem, <String, dynamic>{
      'restaurant_id': restaurantId,
      'local_food_id': localFoodId,
      'restaurant_item_name': name,
      'ingredients': ingredients,
      'food_img_url': foodImgUrl,
      'food_category': foodCategory,
      'restaurant_item_price': price,
    });
  }

  /// Clears a catalogue restaurant's moderation state - a tourist just
  /// confirmed (by re-submitting it in person, within ~100m) that the place
  /// exists, so any accumulated reports are dropped and its status returns to
  /// 'available' (A20-style reactivation on the restaurant side).
  Future<void> resetRestaurantModeration(int restaurantId) async {
    await api.updateRow(
      APIManager.tableRestaurant,
      <String, Object?>{'report_count': 0, 'status': 'available'},
      eq: <String, Object?>{'restaurant_id': restaurantId},
    );
    invalidate();
  }

  /// Increments `restaurant.report_count` by one after a report is recorded
  /// and returns the new value (read-modify-write - fine at the current dev
  /// scale; a later authenticated RPC can make it atomic).
  Future<int> incrementReportCount(int restaurantId) async {
    final Map<String, dynamic>? row = await api.selectOne(
      APIManager.tableRestaurant,
      columns: 'report_count',
      eq: <String, Object?>{'restaurant_id': restaurantId},
    );
    final int next = ((row?['report_count'] as num?)?.toInt() ?? 0) + 1;
    await api.updateRow(
      APIManager.tableRestaurant,
      <String, Object?>{'report_count': next},
      eq: <String, Object?>{'restaurant_id': restaurantId},
    );
    return next;
  }

  /// Freezes a restaurant (`status` -> 'frozen') once its report count passes
  /// the threshold - discovery/list filters only show 'available' places, so
  /// a frozen restaurant disappears until it is reset to 'available'.
  Future<void> freeze(int restaurantId) async {
    await api.updateRow(
      APIManager.tableRestaurant,
      <String, Object?>{'status': 'frozen'},
      eq: <String, Object?>{'restaurant_id': restaurantId},
    );
    invalidate();
  }

  // ===========================================================================
  // Report auto-apply writes (REPORT_REDESIGN_PLAN.md) - called when a claim
  // reaches its threshold. Each is a single targeted UPDATE.
  // ===========================================================================

  /// 2a item_price: rewrites one menu item's price to the reported value.
  Future<void> updateRestaurantItemPrice(int itemId, double price) async {
    await api.updateRow(
      APIManager.tableRestaurantItem,
      <String, Object?>{'restaurant_item_price': price},
      eq: <String, Object?>{'restaurant_item_id': itemId},
    );
  }

  /// 2b item_not_exist: soft-removes one menu item (`is_removed`), hiding it
  /// from the place's menu/discovery without deleting the row.
  Future<void> softRemoveRestaurantItem(int itemId) async {
    await api.updateRow(
      APIManager.tableRestaurantItem,
      <String, Object?>{'is_removed': true},
      eq: <String, Object?>{'restaurant_item_id': itemId},
    );
  }

  /// 2b: how many of [restaurantId]'s items are still shown (not removed) -
  /// used to decide whether the whole place should be hidden when every item
  /// was reported not-exist.
  Future<int> countVisibleRestaurantItems(int restaurantId) async {
    final List<Map<String, dynamic>> rows = await api.selectAll(
      APIManager.tableRestaurantItem,
      columns: 'restaurant_item_id',
      eq: <String, Object?>{'restaurant_id': restaurantId, 'is_removed': false},
    );
    return rows.length;
  }

  /// 2b: hides a restaurant whose every item was reported not-exist
  /// (`status` -> 'removed' - distinct from report-freeze 'frozen').
  Future<void> removeRestaurant(int restaurantId) async {
    await api.updateRow(
      APIManager.tableRestaurant,
      <String, Object?>{'status': 'removed'},
      eq: <String, Object?>{'restaurant_id': restaurantId},
    );
    invalidate();
  }

  /// 3 address: rewrites the restaurant's address to the reported value.
  Future<void> updateRestaurantAddress(int restaurantId, String address) async {
    await api.updateRow(
      APIManager.tableRestaurant,
      <String, Object?>{'address': address},
      eq: <String, Object?>{'restaurant_id': restaurantId},
    );
    invalidate();
  }

  /// 4a closed permanently / 4b closed temporarily: freezes the restaurant.
  /// For a TEMPORARY closure the caller sets [closedUntil] so the place can
  /// auto-reactivate once that time passes (see [reactivateFromClosure]).
  Future<void> freezeRestaurant(
    int restaurantId, {
    DateTime? closedUntil,
  }) async {
    await api.updateRow(
      APIManager.tableRestaurant,
      <String, Object?>{
        'status': 'frozen',
        if (closedUntil != null) 'closed_until': closedUntil.toUtc(),
      },
      eq: <String, Object?>{'restaurant_id': restaurantId},
    );
    invalidate();
  }

  /// 4b resume: clears a temporary closure that has expired - back to
  /// 'available' with no `closed_until`.
  Future<void> reactivateRestaurantFromClosure(int restaurantId) async {
    await api.updateRow(
      APIManager.tableRestaurant,
      <String, Object?>{'status': 'available', 'closed_until': null},
      eq: <String, Object?>{'restaurant_id': restaurantId},
    );
    invalidate();
  }

  /// 1 operating hours: replaces ONE weekday's stored rows with the reported
  /// proposal (delete that day's rows, insert the proposed rows). Used when a
  /// day's hours claim reaches its threshold - only that day is touched.
  Future<void> replaceRestaurantOpeningHourDay(
    int restaurantId,
    Weekday day,
    List<OpeningHour> rows,
  ) async {
    await api.deleteRows(
      APIManager.tableOpeningHours,
      eq: <String, Object?>{
        'restaurant_id': restaurantId,
        'day': _dayName(day),
      },
    );
    if (rows.isNotEmpty) {
      await _insertOpeningHours(restaurantId, rows);
    }
    invalidate();
  }

  Future<void> _insertOpeningHours(
    int restaurantId,
    List<OpeningHour> hours,
  ) async {
    int nextId = await _nextOpeningHoursId();
    for (final OpeningHour hour in hours) {
      final bool isOpen = hour.status == DayStatus.open;
      await api.insertRow(APIManager.tableOpeningHours, <String, dynamic>{
        'opening_hours_id': nextId++,
        'day': _dayName(hour.day),
        'status': hour.status.name,
        'opening_time': isOpen && hour.opensAt != null
            ? _formatTime(hour.opensAt!)
            : null,
        'closing_time': isOpen && hour.closesAt != null
            ? _formatTime(hour.closesAt!)
            : null,
        'landmark_id': null,
        'restaurant_id': restaurantId,
      });
    }
  }

  Future<int> _nextOpeningHoursId() async {
    final List<Map<String, dynamic>> rows = await api.selectAll(
      APIManager.tableOpeningHours,
      columns: 'opening_hours_id',
      orderBy: 'opening_hours_id',
      ascending: false,
      limit: 1,
    );
    if (rows.isEmpty) return 1;
    return ((rows.first['opening_hours_id'] as num?)?.toInt() ?? 0) + 1;
  }

  static String _dayName(Weekday day) => switch (day) {
    Weekday.monday => 'Monday',
    Weekday.tuesday => 'Tuesday',
    Weekday.wednesday => 'Wednesday',
    Weekday.thursday => 'Thursday',
    Weekday.friday => 'Friday',
    Weekday.saturday => 'Saturday',
    Weekday.sunday => 'Sunday',
  };

  static String _formatTime(int minutes) {
    final int h = minutes ~/ 60;
    final int m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:00';
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
      closedUntil: data.closedUntil,
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
        isRemoved: data.isRemoved,
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
      isRemoved: data.isRemoved,
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
