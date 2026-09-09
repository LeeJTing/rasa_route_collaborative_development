import '../../domain_model/food_distribution.dart';
import '../../domain_model/opening_hour.dart';
import '../../domain_model/place_closure_rules.dart';
import '../../domain_model/region.dart';
import '../../shared_client/api_manager/api_manager.dart';
import '../../shared_client/local_storage_manager/local_storage_manager.dart';
import '../../domain_model/map.dart';
import '../../domain_model/map_data_stamp.dart';
import '../../domain_model/map_place.dart';
import '../data_models/malaysia_outline_data_model.dart';
import '../data_models/malaysia_region_data_model.dart';
import '../data_models/map_data_model.dart';
import '../data_models/map_marker_row_data_model.dart';
import '../data_models/opening_hours_data_model.dart';
import '../data_models/place_data_model.dart';
import '../data_models/region_tally_data_model.dart';

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

  /// One entry per level+parent+filter the heatmap has already asked for.
  ///
  /// Keyed rather than single-valued because the tourist moves between levels -
  /// Malaysia, into Selangor, back out - and going back should not cost a round
  /// trip. Cleared by [clearMapCache] along with everything else.
  static final Map<String, List<RegionTallyDataModel>> _tallyCache =
      <String, List<RegionTallyDataModel>>{};

  /// REQ102_15 - the counts behind one level of the heatmap, worked out by
  /// Postgres against the real administrative boundaries in `region_boundary`.
  ///
  /// [level] 1 with a null [parentCode] is the whole country; [level] 2 with a
  /// state's code is that state's districts. [foodIds] narrows the tally to
  /// those catalogue entries; null counts every food.
  ///
  /// Returns an empty list rather than throwing when the function is missing,
  /// so a database that has not had the migration applied yet degrades to an
  /// empty heatmap instead of a broken dashboard.
  Future<List<RegionTally>> regionDistribution({
    int level = Region.stateLevel,
    String? parentCode,
    List<int>? foodIds,
  }) async {
    final List<Region> areas =
        level == Region.districtLevel && parentCode != null
        ? await districtsOf(parentCode)
        : await malaysiaRegions();

    // An empty id list means "no catalogue food survived the filter", which is
    // a real answer - every area scores zero - not a reason to query.
    if (foodIds != null && foodIds.isEmpty) {
      return areas
          .map(
            (Region region) => RegionTally(
              region: region,
              placeCount: 0,
              foodCount: 0,
              restaurantCount: 0,
              landmarkCount: 0,
            ),
          )
          .toList(growable: false);
    }

    final String key = _tallyKey(level, parentCode, foodIds);
    List<RegionTallyDataModel>? rows = _tallyCache[key];
    if (rows == null) {
      final List<Map<String, dynamic>> raw = await api.callFunction(
        APIManager.functionRegionDistribution,
        params: <String, Object?>{
          'p_level': level,
          'p_parent_code': parentCode,
          'p_food_ids': foodIds,
        },
      );
      rows = raw.map(RegionTallyDataModel.fromJson).toList(growable: false);
      if (_tallyCache.length >= tallyCacheEntries) _tallyCache.clear();
      _tallyCache[key] = rows;
    }

    final Map<String, RegionTallyDataModel> byCode =
        <String, RegionTallyDataModel>{
          for (final RegionTallyDataModel row in rows) row.code: row,
        };

    // Driven by the outlines rather than by the rows: an area with nothing in
    // it is still drawn, in grey (REQ102_16), and a row for an area the app has
    // no outline for is not something it can paint.
    return areas.map((Region region) {
      final RegionTallyDataModel? row = byCode[region.code];
      return RegionTally(
        region: region,
        placeCount: row?.placeCount ?? 0,
        foodCount: row?.foodCount ?? 0,
        restaurantCount: row?.restaurantCount ?? 0,
        landmarkCount: row?.landmarkCount ?? 0,
      );
    }).toList(growable: false);
  }

  /// Levels x parents x filter selections worth keeping. Small: the tourist
  /// moves between a handful of states with a handful of filter sets.
  static const int tallyCacheEntries = 64;

  /// Answers to [regionAt], keyed to about a kilometre.
  static final Map<String, Region?> _regionAtCache = <String, Region?>{};

  /// REQ102_12 - the state containing one point, decided by the real boundary
  /// rather than by a hand-drawn outline.
  ///
  /// Rounded to two decimal places - roughly a kilometre - before it is asked
  /// or cached, so panning across a city is one request, not one per frame.
  ///
  /// Throws nothing: an unreachable database returns null and the caller falls
  /// back to the offline outlines.
  Future<Region?> regionAt(double latitude, double longitude) async {
    final String key =
        '${latitude.toStringAsFixed(2)},${longitude.toStringAsFixed(2)}';
    if (_regionAtCache.containsKey(key)) return _regionAtCache[key];

    final List<Map<String, dynamic>> rows = await api.callFunction(
      APIManager.functionRegionAt,
      params: <String, Object?>{
        'p_latitude': latitude,
        'p_longitude': longitude,
        'p_level': Region.stateLevel,
      },
    );
    if (rows.isEmpty) {
      if (_regionAtCache.length >= regionAtCacheEntries) {
        _regionAtCache.clear();
      }
      _regionAtCache[key] = null;
      return null;
    }

    final String code = '${rows.first['code'] ?? ''}';
    final List<Region> catalogue = await malaysiaRegions();
    Region? match;
    for (final Region region in catalogue) {
      if (region.code == code) {
        match = region;
        break;
      }
    }

    if (_regionAtCache.length >= regionAtCacheEntries) _regionAtCache.clear();
    _regionAtCache[key] = match;
    return match;
  }

  static const int regionAtCacheEntries = 256;

  static String _tallyKey(int level, String? parentCode, List<int>? foodIds) {
    final String foods = foodIds == null
        ? 'all'
        : (List<int>.of(foodIds)..sort()).join(',');
    return '$level|${parentCode ?? ''}|$foods';
  }

  /// Cached per state - a district outline never changes, and the tourist
  /// drills into the same few states repeatedly.
  static final Map<String, List<Region>> _districtCache =
      <String, List<Region>>{};

  /// REQ102_12 - the districts of one state, with the outlines they are
  /// painted from.
  ///
  /// The rings are simplified server-side to about 300 m, which is well under
  /// one screen pixel at the scale the heatmap paints them: 17 kB for
  /// Selangor's nine districts, 92 kB for Sarawak's forty. The **full**
  /// boundaries never leave Postgres - they are what assigns a restaurant to an
  /// area, and simplifying those would move places across state lines.
  Future<List<Region>> districtsOf(String stateCode) async {
    final List<Region>? cached = _districtCache[stateCode];
    if (cached != null) return cached;

    final List<Map<String, dynamic>> rows = await api.callFunction(
      APIManager.functionRegionRings,
      params: <String, Object?>{
        'p_level': Region.districtLevel,
        'p_parent_code': stateCode,
      },
    );

    final List<Region> districts = rows
        .map(RegionRingDataModel.fromJson)
        .map(_toDistrict)
        .whereType<Region>()
        .toList(growable: false);
    _districtCache[stateCode] = districts;
    return districts;
  }

  /// Builds the painted outline of one district.
  ///
  /// The centre is the centroid of the largest part rather than of all of them:
  /// for a district with offshore islands, the average of every part lands in
  /// the sea, and that is where the label would be drawn.
  static Region? _toDistrict(RegionRingDataModel row) {
    if (row.parts.isEmpty) return null;

    final List<List<GeoPoint>> rings = row.parts
        .map(
          (List<List<double>> part) => part
              .map((List<double> pair) => GeoPoint(pair[1], pair[0]))
              .toList(growable: false),
        )
        .toList(growable: false);

    List<GeoPoint> largest = rings.first;
    for (final List<GeoPoint> ring in rings) {
      if (ring.length > largest.length) largest = ring;
    }

    double minLatitude = double.infinity;
    double minLongitude = double.infinity;
    double maxLatitude = -double.infinity;
    double maxLongitude = -double.infinity;
    for (final List<GeoPoint> ring in rings) {
      for (final GeoPoint point in ring) {
        if (point.latitude < minLatitude) minLatitude = point.latitude;
        if (point.latitude > maxLatitude) maxLatitude = point.latitude;
        if (point.longitude < minLongitude) minLongitude = point.longitude;
        if (point.longitude > maxLongitude) maxLongitude = point.longitude;
      }
    }

    double latitudeSum = 0;
    double longitudeSum = 0;
    for (final GeoPoint point in largest) {
      latitudeSum += point.latitude;
      longitudeSum += point.longitude;
    }

    return Region(
      code: row.code,
      name: row.name,
      centreLatitude: latitudeSum / largest.length,
      centreLongitude: longitudeSum / largest.length,
      // A district fills the screen at roughly a city's zoom; the detailed map
      // opens there when one is picked.
      defaultZoom: 11,
      boundary: largest,
      places: const <RegionPlace>[],
      level: Region.districtLevel,
      parentCode: row.parentCode,
      rings: rings,
      minLatitude: minLatitude,
      minLongitude: minLongitude,
      maxLatitude: maxLatitude,
      maxLongitude: maxLongitude,
    );
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

  // Viewport marker answers, keyed by the request that produced them. Panning
  // back to somewhere already visited - or swiping Nasi Lemak -> Laksa -> Nasi
  // Lemak - is then free. Short-lived and small: the map is a live view, not an
  // archive.
  static const Duration markerCacheTtl = Duration(minutes: 2);
  static const int markerCacheEntries = 48;

  static final Map<String, _CachedMarkers> _markerCache =
      <String, _CachedMarkers>{};

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
    _markerCache.clear();
    _tallyCache.clear();
    _regionAtCache.clear();
    // District outlines are not invalidated: they are administrative
    // boundaries, not data a tourist can change. Their *counts* live in
    // _tallyCache, which is.
  }

  /// Drops the cached map data from an instance. Same as [invalidate]; exists
  /// because a business-logic class holds a repository, not the class itself,
  /// and Dart will not let it reach a static through the instance.
  void clearCache() => invalidate();

  // ---------------------------------------------------------------------------
  // Viewport markers (REQ102_41)
  // ---------------------------------------------------------------------------

  /// The markers for one viewport, filtered and grouped **in Postgres**.
  ///
  /// This is the read that replaced downloading the country. `map_food_markers`
  /// takes the bounding box, the zoom and an optional set of `local_food_id`s,
  /// and answers with one row per grid cell - about a screenful, whatever the
  /// zoom. A GiST index on `restaurant.geom` makes the box test an index scan.
  ///
  /// A cell holding one place comes back as that place, with its real id; a cell
  /// holding several comes back as a count. So the answer normally contains both
  /// pins and clusters, and zooming in turns clusters into pins as the cells
  /// shrink past the point where markers would overlap.
  ///
  /// Only marker fields are selected - id, name, position, rating, photo. A
  /// menu, opening hours and a description are fetched by id when a pin is
  /// tapped, never for everything on screen.
  ///
  /// [foodIds] null means no food filter at all, and Postgres skips the menu
  /// lookup entirely. An **empty** list means "a filter is active and nothing
  /// matches it", which is a legitimate empty map rather than a reason to query.
  Future<MapMarkerSet> mapMarkers({
    required double southLatitude,
    required double westLongitude,
    required double northLatitude,
    required double eastLongitude,
    required double zoom,
    List<int>? foodIds,
    int limit = 400,
  }) async {
    if (foodIds != null && foodIds.isEmpty) return MapMarkerSet.empty;

    final String key = _markerKey(
      south: southLatitude,
      west: westLongitude,
      north: northLatitude,
      east: eastLongitude,
      zoom: zoom,
      foodIds: foodIds,
      limit: limit,
    );
    final _CachedMarkers? cached = _markerCache[key];
    if (cached != null &&
        DateTime.now().difference(cached.at) < markerCacheTtl) {
      return cached.markers;
    }

    final List<Map<String, dynamic>> rows;
    try {
      rows = await api.callFunction(
        APIManager.functionMapMarkers,
        params: <String, Object?>{
          'p_min_lat': southLatitude,
          'p_min_lng': westLongitude,
          'p_max_lat': northLatitude,
          'p_max_lng': eastLongitude,
          'p_zoom': zoom,
          'p_food_ids': foodIds,
          'p_limit': limit,
        },
      );
    } catch (_) {
      throw Exception(
        'Unable to load the map for this area. '
        'Check your connection and try again.',
      );
    }

    final List<MapCluster> clusters = <MapCluster>[];
    final List<MapPin> pins = <MapPin>[];
    for (final Map<String, dynamic> row in rows) {
      final MapMarkerRowDataModel data = MapMarkerRowDataModel.fromJson(
        row,
      );
      if (data.isCluster) {
        clusters.add(
          MapCluster(
            latitude: data.latitude,
            longitude: data.longitude,
            count: data.pointCount,
          ),
        );
        continue;
      }
      // Deliberately bare. Everything the "Click Map Pin" sheet shows beyond
      // this arrives from [MapExplorationLogic.pinDetail] when the pin is
      // tapped - carrying it on every marker is what made the old read enormous.
      final MapPin? pin = _toPin(row);
      if (pin != null) pins.add(pin);
    }

    final MapMarkerSet markers = MapMarkerSet(
      clusters: List<MapCluster>.unmodifiable(clusters),
      pins: List<MapPin>.unmodifiable(pins),
    );

    // Cheapest possible eviction: the whole map is a two-minute view anyway, so
    // dropping it wholesale beats tracking access order.
    if (_markerCache.length >= markerCacheEntries) _markerCache.clear();
    _markerCache[key] = _CachedMarkers(markers, DateTime.now());
    return markers;
  }

  /// REQ102_41 - where a tap on the cluster at [latitude]/[longitude] should
  /// zoom to, and how many places it holds.
  ///
  /// The cell arithmetic lives in `map_cluster_split_zoom` and is the same as
  /// `map_food_markers`, so the cluster probed is exactly the cluster drawn.
  /// A null zoom back means it never separates: its members share coordinates.
  Future<({double? splitZoom, int memberCount})> clusterSplitZoom({
    required double latitude,
    required double longitude,
    required double zoom,
    required double maximumZoom,
    List<int>? foodIds,
  }) async {
    if (foodIds != null && foodIds.isEmpty) {
      return (splitZoom: null, memberCount: 0);
    }
    final List<Map<String, dynamic>> rows;
    try {
      rows = await api.callFunction(
        APIManager.functionClusterSplitZoom,
        params: <String, Object?>{
          'p_lat': latitude,
          'p_lng': longitude,
          'p_zoom': zoom,
          'p_food_ids': foodIds,
          'p_max_zoom': maximumZoom,
        },
      );
    } catch (_) {
      // A failed probe must not swallow the tap - the caller falls back to a
      // plain zoom step.
      return (splitZoom: null, memberCount: 0);
    }
    if (rows.isEmpty) return (splitZoom: null, memberCount: 0);
    final Map<String, dynamic> row = rows.first;
    return (
      splitZoom: _asDoubleOrNull(row['split_zoom']),
      memberCount: _asInt(row['member_count']),
    );
  }

  /// Every place inside one cluster, individually.
  ///
  /// Only asked for when [clusterSplitZoom] says the cluster never separates,
  /// so the map can draw its members rather than a badge that cannot be opened.
  Future<List<MapPin>> clusterMembers({
    required double latitude,
    required double longitude,
    required double zoom,
    List<int>? foodIds,
    int limit = 200,
  }) async {
    if (foodIds != null && foodIds.isEmpty) return const <MapPin>[];
    final List<Map<String, dynamic>> rows;
    try {
      rows = await api.callFunction(
        APIManager.functionClusterMembers,
        params: <String, Object?>{
          'p_lat': latitude,
          'p_lng': longitude,
          'p_zoom': zoom,
          'p_food_ids': foodIds,
          'p_limit': limit,
        },
      );
    } catch (_) {
      return const <MapPin>[];
    }
    return List<MapPin>.unmodifiable(rows.map(_toPin).whereType<MapPin>());
  }

  /// One marker row from any of the three map functions.
  static MapPin? _toPin(Map<String, dynamic> row) {
    final MapMarkerRowDataModel data = MapMarkerRowDataModel.fromJson(row);
    final int? id = data.referenceId;
    if (data.isCluster || id == null) return null;
    final bool isRestaurant = data.source == 'restaurant';
    return MapPin(
      referenceId: '$id',
      kind: isRestaurant ? MapPinKind.restaurant : MapPinKind.landmark,
      latitude: data.latitude,
      longitude: data.longitude,
      label: data.name,
      weight: 1,
      imageUrl: isRestaurant
          ? data.imageUrl
          : _normalizeLandmarkImageUrl(data.imageUrl),
      rating: data.rating,
    );
  }

  /// The cache key: the request, rounded.
  ///
  /// Bounds are rounded to about 100 m so that the pixel-level jitter a finger
  /// leaves on the map does not miss the cache. The zoom is **not** rounded into
  /// buckets: it sets the grid cell size, so half a level really is a different
  /// answer.
  static String _markerKey({
    required double south,
    required double west,
    required double north,
    required double east,
    required double zoom,
    required List<int>? foodIds,
    required int limit,
  }) {
    final String box =
        '${south.toStringAsFixed(3)},${west.toStringAsFixed(3)},'
        '${north.toStringAsFixed(3)},${east.toStringAsFixed(3)}';
    final String foods = foodIds == null
        ? 'all'
        : (List<int>.of(foodIds)..sort()).join('.');
    return '$box|${zoom.toStringAsFixed(1)}|$foods|$limit';
  }

  /// How much map data exists right now - polled by `RestaurantMonitor` to
  /// notice that another tourist has added a landmark.
  ///
  /// Deliberately **not cached**: its whole job is to see past the cache.
  ///
  /// Counted server-side (a `HEAD` request answered by `Content-Range`) rather
  /// than by downloading an id column and measuring the list. Downloading was
  /// both wasteful and *wrong*: PostgREST caps an unpaged select at 1000 rows,
  /// so past a thousand restaurants every poll reported exactly 1000 and the
  /// stamp could never change again.
  Future<MapDataStamp> mapDataStamp() async {
    try {
      final List<int> counts = await Future.wait(<Future<int>>[
        api.countRows(APIManager.tableSubmittedLandmark),
        api.countRows(APIManager.tableRestaurant),
      ]);
      return MapDataStamp(landmarkCount: counts[0], restaurantCount: counts[1]);
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
      final List<Map<String, dynamic>> rows = await api.selectEvery(
        APIManager.tablePlace,
        orderBy: 'place_id',
        columns:
            'place_id, name, kind, state_name, latitude, longitude, '
            'zoom, aliases',
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
      final List<List<Map<String, dynamic>>> rows = await Future.wait(
        <Future<List<Map<String, dynamic>>>>[
          // Paged, not `selectAll`: both tables are far past PostgREST's
          // 1000-row ceiling, and a truncated read here is what makes a
          // fully seeded database look like an almost empty map.
          api.selectEvery(
            APIManager.tableRestaurant,
            orderBy: 'restaurant_id',
            columns:
                'restaurant_id, restaurant_name, latitude, longitude, '
                'category, rating, restaurant_image_url, status, closed_until',
          ),
          api.selectEvery(
            APIManager.tableRestaurantItem,
            orderBy: 'restaurant_item_id',
            columns:
                'restaurant_id, local_food_id, restaurant_item_name, '
                'restaurant_item_price',
          ),
        ],
      );
      restaurants = rows[0];
      items = rows[1];
    } catch (_) {
      throw Exception(
        'Unable to load the local food distribution. '
        'Check your connection and try again.',
      );
    }

    // A restaurant is on the map unless it is explicitly marked otherwise.
    //
    // This used to require `status == 'available'`, which silently dropped
    // every row where the column was never set - 3,368 of 12,584 in the seeded
    // data, including 2,177 in Selangor and 579 in Johor. A scraped row with no
    // status is not evidence that the place is shut; it is a column nobody
    // filled in. Anything genuinely withdrawn carries a different value and is
    // still excluded.
    //
    // A place frozen by a TEMPORARY closure (status 'frozen' with a
    // `closed_until` in the past) is available again - it stays on the map
    // (see `PlaceClosureRules`) and is auto-reactivated on read so the DB
    // catches up (status -> 'available', closed_until cleared).
    final Map<int, Map<String, dynamic>> byId = <int, Map<String, dynamic>>{};
    final List<int> reactivateIds = <int>[];
    final DateTime now = DateTime.now();
    for (final Map<String, dynamic> row in restaurants) {
      final int restaurantId = _asInt(row['restaurant_id']);
      if (restaurantId == 0) continue;
      if (_isVisible(row['status']) ||
          PlaceClosureRules.isEffectivelyAvailable(
            status: _asStringOrNull(row['status']),
            closedUntil: _asDateTimeOrNull(row['closed_until']),
            now: now,
          )) {
        byId[restaurantId] = row;
      }
      if (PlaceClosureRules.needsReactivation(
        status: _asStringOrNull(row['status']),
        closedUntil: _asDateTimeOrNull(row['closed_until']),
        now: now,
      )) {
        reactivateIds.add(restaurantId);
      }
    }
    await _reactivateExpiredRestaurants(reactivateIds);

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
            api.selectEvery(
              APIManager.tableSubmittedLandmark,
              orderBy: 'landmark_id',
              columns:
                  'landmark_id, landmark_name, latitude, longitude, status, '
                  'image_url, category, closed_until',
            ),
            api.selectEvery(
              APIManager.tableLandmarkItem,
              orderBy: 'landmark_item_id',
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

    // A landmark that reached the report threshold is frozen (`status`
    // 'frozen') and excluded from map pins, search results and
    // recommendations - only 'available' landmarks are shown. A landmark
    // frozen by a TEMPORARY closure whose `closed_until` has passed is
    // available again (see `PlaceClosureRules`) - it comes back on the map
    // and is auto-reactivated on read so the DB catches up.
    final Map<int, Map<String, dynamic>> byId = <int, Map<String, dynamic>>{};
    final List<int> reactivateIds = <int>[];
    final DateTime now = DateTime.now();
    for (final Map<String, dynamic> row in landmarks) {
      final int landmarkId = _asInt(row['landmark_id']);
      if (landmarkId == 0) continue;
      if (PlaceClosureRules.isEffectivelyAvailable(
        status: _asStringOrNull(row['status']),
        closedUntil: _asDateTimeOrNull(row['closed_until']),
        now: now,
      )) {
        byId[landmarkId] = row;
      }
      if (PlaceClosureRules.needsReactivation(
        status: _asStringOrNull(row['status']),
        closedUntil: _asDateTimeOrNull(row['closed_until']),
        now: now,
      )) {
        reactivateIds.add(landmarkId);
      }
    }
    await _reactivateExpiredLandmarks(reactivateIds);

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
  ///
  /// Pass [placeKeys] to fetch only the places actually being drawn. The table
  /// carries a row per place per weekday, so it is roughly seven times the size
  /// of the restaurant table - reading all of it to decorate at most a couple
  /// of hundred pins is the single most expensive thing the map used to do.
  /// Omitting [placeKeys] reads and caches the whole table, which is what the
  /// recommendation modules want.
  Future<Map<String, List<OpeningHour>>> openingHours({
    Set<String>? placeKeys,
  }) {
    final Map<String, List<OpeningHour>>? cached = _cachedHours;

    if (placeKeys != null) {
      if (placeKeys.isEmpty) {
        return Future<Map<String, List<OpeningHour>>>.value(
          const <String, List<OpeningHour>>{},
        );
      }
      // The whole table is already in hand - no reason to ask again for a
      // subset of it.
      if (cached != null && _isFresh(_cachedHoursAt)) {
        return Future<Map<String, List<OpeningHour>>>.value(
          <String, List<OpeningHour>>{
            for (final String key in placeKeys)
              if (cached[key] != null) key: cached[key]!,
          },
        );
      }
      // Deliberately uncached: a viewport-sized answer is not the truth about
      // the table, and caching it would poison the full read.
      return _fetchOpeningHours(placeKeys: placeKeys);
    }

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

  /// How many ids go into one `in.(...)` filter. Kept well clear of the URL
  /// length a proxy will accept, and each chunk is itself paged, so a chunk
  /// spanning more than 1000 rows is not truncated.
  static const int _idsPerRequest = 150;

  static const String _openingHoursColumns =
      'opening_hours_id, day, status, opening_time, closing_time, '
      'landmark_id, restaurant_id';

  Future<Map<String, List<OpeningHour>>> _fetchOpeningHours({
    Set<String>? placeKeys,
  }) async {
    final List<Map<String, dynamic>> rows;
    try {
      rows = placeKeys == null
          ? await api.selectEvery(
              APIManager.tableOpeningHours,
              orderBy: 'opening_hours_id',
              columns: _openingHoursColumns,
            )
          : await _openingHoursFor(placeKeys);
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

  /// Opening hours for a bounded set of place keys, one request per column per
  /// chunk of ids, all in flight together.
  Future<List<Map<String, dynamic>>> _openingHoursFor(
    Set<String> placeKeys,
  ) async {
    final List<Object?> restaurantIds = <Object?>[];
    final List<Object?> landmarkIds = <Object?>[];
    for (final String key in placeKeys) {
      final int separator = key.indexOf(':');
      if (separator < 0) continue;
      final int? id = int.tryParse(key.substring(separator + 1));
      if (id == null || id == 0) continue;
      if (key.startsWith('restaurant:')) {
        restaurantIds.add(id);
      } else {
        landmarkIds.add(id);
      }
    }

    final List<Future<List<Map<String, dynamic>>>> requests =
        <Future<List<Map<String, dynamic>>>>[
          ..._chunkedRequests('restaurant_id', restaurantIds),
          ..._chunkedRequests('landmark_id', landmarkIds),
        ];
    if (requests.isEmpty) return const <Map<String, dynamic>>[];

    final List<List<Map<String, dynamic>>> pages = await Future.wait(requests);
    return pages
        .expand((List<Map<String, dynamic>> page) => page)
        .toList(growable: false);
  }

  List<Future<List<Map<String, dynamic>>>> _chunkedRequests(
    String column,
    List<Object?> ids,
  ) {
    final List<Future<List<Map<String, dynamic>>>> out =
        <Future<List<Map<String, dynamic>>>>[];
    for (int start = 0; start < ids.length; start += _idsPerRequest) {
      final int end = start + _idsPerRequest > ids.length
          ? ids.length
          : start + _idsPerRequest;
      out.add(
        api.selectEvery(
          APIManager.tableOpeningHours,
          orderBy: 'opening_hours_id',
          columns: _openingHoursColumns,
          inFilter: <String, List<Object?>>{column: ids.sublist(start, end)},
        ),
      );
    }
    return out;
  }

  /// Whether a `restaurant.status` value means the place should be shown.
  /// Null or blank counts as visible - see [_restaurantOccurrences].
  static bool _isVisible(Object? status) {
    final String value = _asString(status).trim().toLowerCase();
    return value.isEmpty || value == 'available';
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

  /// Parses a `closed_until` timestamptz value (may arrive as ISO-8601 text
  /// or already a [DateTime]).
  static DateTime? _asDateTimeOrNull(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse('$value');
  }

  /// Read-time auto-reactivation: a restaurant frozen by a temporary closure
  /// whose `closed_until` has passed is written back to 'available' with
  /// `closed_until` cleared, so the DB catches up with what the read just
  /// decided. Best-effort - a failed write must never take the map read down
  /// (the place is already treated as available for this read regardless).
  Future<void> _reactivateExpiredRestaurants(List<int> restaurantIds) async {
    for (final int restaurantId in restaurantIds) {
      try {
        await api.updateRow(
          APIManager.tableRestaurant,
          <String, Object?>{'status': 'available', 'closed_until': null},
          eq: <String, Object?>{'restaurant_id': restaurantId},
        );
      } catch (_) {
        // Best-effort - see method doc.
      }
    }
  }

  /// Landmark half of [_reactivateExpiredRestaurants] - see that method.
  Future<void> _reactivateExpiredLandmarks(List<int> landmarkIds) async {
    for (final int landmarkId in landmarkIds) {
      try {
        await api.updateRow(
          APIManager.tableSubmittedLandmark,
          <String, Object?>{'status': 'available', 'closed_until': null},
          eq: <String, Object?>{'landmark_id': landmarkId},
        );
      } catch (_) {
        // Best-effort - see _reactivateExpiredRestaurants.
      }
    }
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

/// One cached viewport answer and when it arrived.
class _CachedMarkers {
  const _CachedMarkers(this.markers, this.at);

  final MapMarkerSet markers;
  final DateTime at;
}
