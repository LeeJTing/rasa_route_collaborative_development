import '../../domain_model/food_distribution.dart';
import '../../domain_model/opening_hour.dart';
import '../../domain_model/region.dart';
import '../../shared_client/api_manager/api_manager.dart';
import '../../shared_client/local_storage_manager/local_storage_manager.dart';
import '../../domain_model/map_data_stamp.dart';
import '../../domain_model/map_place.dart';
import '../data_models/malaysia_outline_data_model.dart';
import '../data_models/malaysia_region_data_model.dart';
import '../data_models/map_data_model.dart';
import '../data_models/opening_hours_data_model.dart';
import '../data_models/place_data_model.dart';

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

  // ---------------------------------------------------------------------------
  // Caching
  // ---------------------------------------------------------------------------
  //
  // Occurrences and opening hours are read on every pin refresh, and a pin
  // refresh happens on every pan and every zoom. Uncached that was four
  // full-table selects per camera move; cached, panning costs nothing at all
  // and the work becomes pure in-memory filtering one layer up.
  //
  // Static, so the heatmap and the pins share one copy even though each facade
  // builds its own `MapRepository`, and so the cache survives a ViewModel being
  // rebuilt. Restaurants and submitted landmarks change on the scale of days,
  // not seconds; [cacheTtl] is the ceiling on how stale the map can be, and
  // [invalidate] is there for anything that writes.

  static const Duration cacheTtl = Duration(minutes: 5);

  static List<FoodOccurrence>? _cachedOccurrences;
  static DateTime? _cachedOccurrencesAt;
  static Future<List<FoodOccurrence>>? _occurrencesRequest;

  static List<MapPlace>? _cachedPlaces;
  static DateTime? _cachedPlacesAt;
  static Future<List<MapPlace>>? _placesRequest;

  static Map<String, List<OpeningHour>>? _cachedHours;
  static DateTime? _cachedHoursAt;
  static Future<Map<String, List<OpeningHour>>>? _hoursRequest;

  static bool _isFresh(DateTime? at) =>
      at != null && DateTime.now().difference(at) < cacheTtl;

  /// Drops the cached map data. Call after anything that adds or edits a
  /// restaurant or a submitted landmark, or the map will keep showing the old
  /// answer for up to [cacheTtl].
  static void invalidate() {
    _cachedOccurrences = null;
    _cachedOccurrencesAt = null;
    _cachedHours = null;
    _cachedHoursAt = null;
    _cachedPlaces = null;
    _cachedPlacesAt = null;
  }

  /// Drops the cached map data from an instance. Same as [invalidate]; exists
  /// because a business-logic class holds a repository, not the class itself,
  /// and Dart will not let it reach a static through the instance.
  void clearCache() => invalidate();

  /// How much map data exists right now - polled by `RestaurantMonitor` to
  /// notice that another tourist has added a landmark.
  ///
  /// Deliberately **not cached**: its whole job is to see past the cache. Reads
  /// one id column from each table, so the payload stays small even as the
  /// tables grow.
  Future<MapDataStamp> mapDataStamp() async {
    try {
      final List<List<Map<String, dynamic>>> rows =
          await Future.wait(<Future<List<Map<String, dynamic>>>>[
            api.selectAll(
              APIManager.tableSubmittedLandmark,
              columns: 'landmark_id',
            ),
            api.selectAll(APIManager.tableRestaurant, columns: 'restaurant_id'),
          ]);
      return MapDataStamp(
        landmarkCount: rows[0].length,
        restaurantCount: rows[1].length,
      );
    } catch (_) {
      // A failed poll must not look like "everything vanished" - that would
      // prompt the tourist to refresh into an empty map.
      return MapDataStamp.empty;
    }
  }

  /// REQ102_19 / REQ102_20 - every searchable city, town, area and landmark.
  ///
  /// Read whole and cached: the table is small reference data and the search
  /// runs on every keystroke, so filtering in memory beats a query per letter.
  /// `APIManager` only offers equality filters anyway - there is no `ilike` to
  /// push the match down to Postgres with.
  ///
  /// An empty or unreachable table is not fatal. The region catalogue still
  /// carries the 16 states and a city each, so search degrades to what it did
  /// before this table existed rather than returning nothing.
  Future<List<MapPlace>> places() {
    final List<MapPlace>? cached = _cachedPlaces;
    if (cached != null && _isFresh(_cachedPlacesAt)) {
      return Future<List<MapPlace>>.value(cached);
    }
    return _placesRequest ??= _fetchPlaces()
        .then((List<MapPlace> value) {
          _cachedPlaces = value;
          _cachedPlacesAt = DateTime.now();
          return value;
        })
        .whenComplete(() => _placesRequest = null);
  }

  Future<List<MapPlace>> _fetchPlaces() async {
    try {
      final List<Map<String, dynamic>> rows = await api.selectAll(
        APIManager.tablePlace,
        columns:
            'place_id, name, kind, state_name, latitude, longitude, '
            'zoom, aliases',
        orderBy: 'name',
      );
      return rows
          .map(PlaceDataModel.fromJson)
          .map((PlaceDataModel data) => data.toDomain())
          .toList(growable: false);
    } catch (_) {
      // Reference data - losing it degrades search, it does not break it.
      return const <MapPlace>[];
    }
  }

  /// Every place a local food is served, from both sources.
  ///
  /// Returns an empty list when the backend holds no restaurants or landmarks
  /// yet - that is a real, honest answer (every state scores zero and the
  /// heatmap is grey), not an error. A failed *query* does throw, so the
  /// ViewModel can offer a retry rather than showing a blank map as if it were
  /// the truth.
  ///
  /// Cached for [cacheTtl]. Concurrent callers share one request rather than
  /// each firing their own - the heatmap and the pins routinely ask at the
  /// same moment.
  Future<List<FoodOccurrence>> foodOccurrences() {
    final List<FoodOccurrence>? cached = _cachedOccurrences;
    if (cached != null && _isFresh(_cachedOccurrencesAt)) {
      return Future<List<FoodOccurrence>>.value(cached);
    }
    return _occurrencesRequest ??= _fetchOccurrences()
        .then((List<FoodOccurrence> value) {
          _cachedOccurrences = value;
          _cachedOccurrencesAt = DateTime.now();
          return value;
        })
        .whenComplete(() => _occurrencesRequest = null);
  }

  Future<List<FoodOccurrence>> _fetchOccurrences() async {
    // The two sources are independent, so they go together rather than one
    // after the other.
    final List<List<FoodOccurrence>> both = await Future.wait(
      <Future<List<FoodOccurrence>>>[
        _restaurantOccurrences(),
        _landmarkOccurrences(),
      ],
    );
    return List<FoodOccurrence>.unmodifiable(
      both.expand((List<FoodOccurrence> group) => group),
    );
  }

  Future<List<FoodOccurrence>> _restaurantOccurrences() async {
    final List<Map<String, dynamic>> restaurants;
    final List<Map<String, dynamic>> items;
    try {
      // Neither select depends on the other.
      final List<List<Map<String, dynamic>>> rows =
          await Future.wait(<Future<List<Map<String, dynamic>>>>[
            api.selectAll(
              APIManager.tableRestaurant,
              columns:
                  'restaurant_id, restaurant_name, latitude, longitude, '
                  'category, rating, restaurant_image_url',
            ),
            api.selectAll(
              APIManager.tableRestaurantItem,
              columns:
                  'restaurant_id, local_food_id, restaurant_item_name, '
                  'restaurant_item_price',
            ),
          ]);
      restaurants = rows[0];
      items = rows[1];
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
      final List<List<Map<String, dynamic>>> rows =
          await Future.wait(<Future<List<Map<String, dynamic>>>>[
            api.selectAll(
              APIManager.tableSubmittedLandmark,
              columns:
                  'landmark_id, landmark_name, latitude, longitude, status, '
                  'image_url, category',
            ),
            api.selectAll(
              APIManager.tableLandmarkItem,
              columns:
                  'landmark_id, local_food_id, dish, image_url, item_price, '
                  'food_category',
            ),
          ]);
      landmarks = rows[0];
      items = rows[1];
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
          // The item's local_food_id (mirrors restaurant_item); a 0/absent
          // id falls back to name matching in MapExplorationLogic._resolve.
          sourceId: '${_asInt(place['landmark_id'])}',
          source: FoodOccurrenceSource.submittedLandmark,
          placeName: _asString(place['landmark_name']),
          localFoodId: _asInt(item['local_food_id']),
          foodName: _asString(item['dish']),
          latitude: latitude,
          longitude: longitude,
          // The tourist's own signboard/stall photo is the landmark's "place
          // photo" (like a restaurant's own photo); fall back to the food
          // photo when it is missing. URLs are normalized so legacy rows that
          // doubled the bucket segment still display.
          placeImageUrl:
              _normalizeLandmarkImageUrl(place['image_url']) ??
              _normalizeLandmarkImageUrl(item['image_url']),
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
  Future<Map<String, List<OpeningHour>>> openingHours() {
    final Map<String, List<OpeningHour>>? cached = _cachedHours;
    if (cached != null && _isFresh(_cachedHoursAt)) {
      return Future<Map<String, List<OpeningHour>>>.value(cached);
    }
    return _hoursRequest ??= _fetchOpeningHours()
        .then((Map<String, List<OpeningHour>> value) {
          _cachedHours = value;
          _cachedHoursAt = DateTime.now();
          return value;
        })
        .whenComplete(() => _hoursRequest = null);
  }

  Future<Map<String, List<OpeningHour>>> _fetchOpeningHours() async {
    final List<Map<String, dynamic>> rows;
    try {
      rows = await api.selectAll(
        APIManager.tableOpeningHours,
        columns:
            'opening_hours_id, day, status, opening_time, closing_time, '
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

      byPlace
          .putIfAbsent(key, () => <OpeningHour>[])
          .add(
            OpeningHour(
              id: data.openingHoursId,
              day: day,
              status: status,
              opensAt: status == DayStatus.open ? opensAt : null,
              closesAt: status == DayStatus.open ? closesAt : null,
            ),
          );
    }
    return byPlace;
  }

  DayStatus? _dayStatus(String value) {
    final String name = value.trim().toLowerCase();
    for (final DayStatus status in DayStatus.values) {
      if (status.name == name) return status;
    }
    return null;
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

  Future<void> saveViewport(MapDataModel viewport) => storage.writeJson(
    LocalStorageManager.keyLastMapViewport,
    viewport.toJson(),
  );

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

  /// Legacy landmark image URLs (written before the bucket-prefix guard in
  /// `SubmittedLandmarkRepository.uploadImage` existed) double the bucket
  /// segment: ".../object/public/landmark-images/landmark-images/photo/...".
  /// Supabase answers that with 404 NoSuchKey, which is the blank-card
  /// symptom. Collapse the doubled segment so those rows display; correct
  /// URLs pass through unchanged. Null/empty becomes null.
  static String? _normalizeLandmarkImageUrl(Object? value) {
    final String? trimmed = _asStringOrNull(value)?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed.replaceAll(RegExp(r'(/object/public/[^/]+/)\1'), r'$1');
  }
}
