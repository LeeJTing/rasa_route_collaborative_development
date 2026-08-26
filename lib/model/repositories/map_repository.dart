import '../../domain_model/food_distribution.dart';
import '../../domain_model/opening_hour.dart';
import '../../domain_model/region.dart';
import '../../shared_client/api_manager/api_manager.dart';
import '../../shared_client/local_storage_manager/local_storage_manager.dart';
import '../data_models/malaysia_outline_data_model.dart';
import '../data_models/malaysia_region_data_model.dart';
import '../data_models/map_data_model.dart';
import '../data_models/opening_hours_data_model.dart';

/// The exploration map: the Malaysian regions it is drawn from, the food
/// occurrences plotted on it, and the viewport the tourist left it at.
///
/// A repository is the only layer that talks to the shared clients. It asks
/// `APIManager` for raw rows, hands them to a **data model** (`fromJson`), then
/// converts that data model into a **domain model** for everything above.
///
/// Two sources feed the REQ102 heatmap, kept separate all the way up per C21:
///   * `restaurant` + `restaurant_item` - the Google-sourced catalogue, joined
///     to `local_food` by `local_food_id`;
///   * `submitted_landmark` + `landmark_item` - tourist contributions, which
///     carry only a free-text `dish`, resolved against the catalogue by name
///     one layer up.
///
/// Both joins are done here in Dart rather than as a PostgREST embed:
/// `landmark_item` has two foreign keys pointing at `submitted_landmark`, so an
/// embed would have to be disambiguated by constraint name, and a schema tidy-
/// up would silently break the query.
class MapRepository {
  MapRepository();

  final APIManager api = APIManager();
  final LocalStorageManager storage = LocalStorageManager();

  /// Cached for the process lifetime - the catalogue is compile-time constant,
  /// so there is nothing to invalidate.
  List<Region>? _regions;

  /// The 13 states + 3 federal territories the map covers (REQ102_1).
  Future<List<Region>> malaysiaRegions() async {
    return _regions ??= MalaysiaRegionDataModel.catalogue
        .map((MalaysiaRegionDataModel data) => data.toDomain())
        .toList(growable: false);
  }

  List<CountryOutline>? _outlines;

  /// REQ102_1 - the coastline of each Malaysian landmass, used to mask
  /// everything that is not Malaysia out of the detailed map view.
  Future<List<CountryOutline>> malaysiaOutlines() async {
    return _outlines ??= MalaysiaOutlineDataModel.catalogue
        .map((MalaysiaOutlineDataModel data) => data.toDomain())
        .toList(growable: false);
  }

  List<CountryOutline>? _maskOutlines;

  /// REQ102_1 - the rings the detailed map cuts out of its mask. Deliberately
  /// more generous than [malaysiaOutlines]; see `MalaysiaOutlineDataModel`.
  Future<List<CountryOutline>> malaysiaMaskOutlines() async {
    return _maskOutlines ??= MalaysiaOutlineDataModel.maskCatalogue
        .map((MalaysiaOutlineDataModel data) => data.toDomain())
        .toList(growable: false);
  }

  /// Every place a local food is served, from both sources.
  ///
  /// Returns an empty list when the backend holds no restaurants or landmarks
  /// yet - that is a real, honest answer (every state scores zero and the
  /// heatmap is grey), not an error. A failed *query* does throw, so the
  /// ViewModel can offer a retry rather than showing a blank map as if it were
  /// the truth.
  Future<List<FoodOccurrence>> foodOccurrences() async {
    final List<FoodOccurrence> occurrences = <FoodOccurrence>[];
    occurrences.addAll(await _restaurantOccurrences());
    occurrences.addAll(await _landmarkOccurrences());
    return List<FoodOccurrence>.unmodifiable(occurrences);
  }

  Future<List<FoodOccurrence>> _restaurantOccurrences() async {
    final List<Map<String, dynamic>> restaurants;
    final List<Map<String, dynamic>> items;
    try {
      restaurants = await api.selectAll(
        APIManager.tableRestaurant,
        columns:
            'restaurant_id, restaurant_name, latitude, longitude, '
            'category, rating, restaurant_image_url',
      );
      items = await api.selectAll(
        APIManager.tableRestaurantItem,
        columns:
            'restaurant_id, local_food_id, restaurant_item_name, '
            'restaurant_item_price',
      );
    } catch (_) {
      throw Exception(
        'Unable to load the local food distribution. '
        'Check your connection and try again.',
      );
    }

    final Map<int, Map<String, dynamic>> byId = <int, Map<String, dynamic>>{
      for (final Map<String, dynamic> row in restaurants)
        if (_asInt(row['restaurant_id']) != 0)
          _asInt(row['restaurant_id']): row,
    };

    final List<FoodOccurrence> out = <FoodOccurrence>[];
    for (final Map<String, dynamic> item in items) {
      final Map<String, dynamic>? place = byId[_asInt(item['restaurant_id'])];
      if (place == null) continue;

      final double? latitude = _asDoubleOrNull(place['latitude']);
      final double? longitude = _asDoubleOrNull(place['longitude']);
      if (latitude == null || longitude == null) continue;

      out.add(
        FoodOccurrence(
          sourceId: '${_asInt(place['restaurant_id'])}',
          source: FoodOccurrenceSource.restaurant,
          placeName: _asString(place['restaurant_name']),
          localFoodId: _asInt(item['local_food_id']),
          foodName: _asString(item['restaurant_item_name']),
          latitude: latitude,
          longitude: longitude,
          placeImageUrl: _asStringOrNull(place['restaurant_image_url']),
          placeCategory: _asStringOrNull(place['category']),
          placeRating: _asDoubleOrNull(place['rating']),
          itemPrice: _asDoubleOrNull(item['restaurant_item_price']),
        ),
      );
    }
    return out;
  }

  Future<List<FoodOccurrence>> _landmarkOccurrences() async {
    final List<Map<String, dynamic>> landmarks;
    final List<Map<String, dynamic>> items;
    try {
      landmarks = await api.selectAll(
        APIManager.tableSubmittedLandmark,
        columns: 'landmark_id, landmark_name, latitude, longitude, status',
      );
      items = await api.selectAll(
        APIManager.tableLandmarkItem,
        columns: 'landmark_id, dish, image_url, item_price, food_category',
      );
    } catch (_) {
      throw Exception(
        'Unable to load submitted landmarks. '
        'Check your connection and try again.',
      );
    }

    // C26: a landmark that reached the report threshold is excluded from map
    // pins, search results and recommendations.
    final Map<int, Map<String, dynamic>> byId = <int, Map<String, dynamic>>{
      for (final Map<String, dynamic> row in landmarks)
        if (_asInt(row['landmark_id']) != 0 &&
            _asString(row['status']).toLowerCase() != 'hidden')
          _asInt(row['landmark_id']): row,
    };

    final List<FoodOccurrence> out = <FoodOccurrence>[];
    for (final Map<String, dynamic> item in items) {
      final Map<String, dynamic>? place = byId[_asInt(item['landmark_id'])];
      if (place == null) continue;

      final double? latitude = _asDoubleOrNull(place['latitude']);
      final double? longitude = _asDoubleOrNull(place['longitude']);
      if (latitude == null || longitude == null) continue;

      out.add(
        FoodOccurrence(
          // No local_food_id on landmark_item - the dish text is resolved
          // against the catalogue by MapExplorationLogic.
          sourceId: '${_asInt(place['landmark_id'])}',
          source: FoodOccurrenceSource.submittedLandmark,
          placeName: _asString(place['landmark_name']),
          localFoodId: 0,
          foodName: _asString(item['dish']),
          latitude: latitude,
          longitude: longitude,
          placeImageUrl: _asStringOrNull(item['image_url']),
          placeCategory: _asStringOrNull(place['category']),
          itemPrice: _asDoubleOrNull(item['item_price']),
        ),
      );
    }
    return out;
  }

  /// Opening hours for every restaurant and submitted landmark, keyed the same
  /// way pins are - `"restaurant:12"`, `"submittedLandmark:3"` - so the logic
  /// layer can decide whether a place is open right now (UC300 A11, C12).
  ///
  /// A place with no rows simply has no entry, which is how "hours unknown"
  /// reaches the sheet instead of being guessed as closed.
  Future<Map<String, List<OpeningHour>>> openingHours() async {
    final List<Map<String, dynamic>> rows;
    try {
      rows = await api.selectAll(
        APIManager.tableOpeningHours,
        columns:
            'opening_hours_id, day, opening_time, closing_time, '
            'landmark_id, restaurant_id',
      );
    } catch (_) {
      // Hours are a nice-to-have on a map pin; losing them must not take the
      // whole detailed view down.
      return const <String, List<OpeningHour>>{};
    }

    final Map<String, List<OpeningHour>> byPlace =
        <String, List<OpeningHour>>{};
    for (final Map<String, dynamic> row in rows) {
      final OpeningHoursDataModel data = OpeningHoursDataModel.fromJson(row);
      final int? restaurantId = data.restaurantId;
      final int? landmarkId = data.landmarkId;
      final String key = restaurantId != null && restaurantId != 0
          ? 'restaurant:$restaurantId'
          : landmarkId != null && landmarkId != 0
          ? 'submittedLandmark:$landmarkId'
          : '';
      if (key.isEmpty) continue;

      final Weekday? day = _weekday(data.day);
      if (day == null) continue;

      final int? opensAt = _minutesOfDay(data.openingTime);
      final int? closesAt = _minutesOfDay(data.closingTime);

      byPlace.putIfAbsent(key, () => <OpeningHour>[]).add(
        OpeningHour(
          id: data.openingHoursId,
          day: day,
          status: opensAt == null || closesAt == null
              ? DayStatus.closed
              : DayStatus.open,
          opensAt: opensAt,
          closesAt: closesAt,
        ),
      );
    }
    return byPlace;
  }

  static Weekday? _weekday(String value) {
    final String name = value.trim().toLowerCase();
    for (final Weekday day in Weekday.values) {
      if (day.name == name) return day;
    }
    return null;
  }

  /// `"HH:MM:SS"` -> minutes since midnight.
  static int? _minutesOfDay(String? value) {
    if (value == null || value.isEmpty) return null;
    final List<String> parts = value.split(':');
    if (parts.length < 2) return null;
    final int? hour = int.tryParse(parts[0]);
    final int? minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return hour * 60 + minute;
  }

  // ---------------------------------------------------------------------------
  // Viewport - so the dashboard reopens where the tourist left it.
  // ---------------------------------------------------------------------------

  /// The last viewport this device was looking at, or null on a first run.
  Future<MapDataModel?> lastViewport() async {
    final Map<String, dynamic>? cached = storage.readJson(
      LocalStorageManager.keyLastMapViewport,
    );
    if (cached == null) return null;
    try {
      return MapDataModel.fromJson(cached);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveViewport(MapDataModel viewport) =>
      storage.writeJson(LocalStorageManager.keyLastMapViewport,
          viewport.toJson());

  // ---------------------------------------------------------------------------
  // Row readers. Supabase returns numerics as String on some drivers, so every
  // read goes through one of these rather than a raw cast.
  // ---------------------------------------------------------------------------

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  static double? _asDoubleOrNull(Object? value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }

  static String _asString(Object? value) => value == null ? '' : '$value';

  static String? _asStringOrNull(Object? value) {
    if (value == null) return null;
    final String text = '$value';
    return text.isEmpty ? null : text;
  }
}
