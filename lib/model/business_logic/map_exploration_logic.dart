import '../../domain_model/exploration_filter.dart';
import '../../domain_model/exploration_search.dart';
import '../../domain_model/food_distribution.dart';
import '../../domain_model/local_food.dart';
import '../../domain_model/map.dart';
import '../../domain_model/map_place.dart';
import '../../domain_model/opening_hour.dart';
import '../../domain_model/region.dart';
import '../../domain_model/restaurant.dart';
import '../../domain_model/restaurant_item.dart';
import '../../domain_model/tourist_location.dart';
import '../repositories/discovery_repository_facade.dart';
import 'dart:math' as math;

/// REQ102 - the Local Food Dashboard.
///
/// Everything the dashboard map reasons about lives here: which state a
/// coordinate falls in, the C1 availability score behind the heatmap gradient,
/// the Smart Filtering rules, the location search, and the zoom level at which
/// the heatmap becomes a detailed map.
///
/// Reached from `DiscoveryLogicFacade`, which is the one facade the dashboard
/// talks to.
///
/// A business-logic class knows exactly one thing below it: a repository
/// facade. Map facts and the local-food catalogue are both exposed through
/// [DiscoveryRepositoryFacade], so this class stays within that boundary.
///
/// It never sees a repository, a shared client or Flutter.
class MapExplorationLogic {
  MapExplorationLogic();

  final DiscoveryRepositoryFacade repository = DiscoveryRepositoryFacade();

  // ===========================================================================
  // Dev GPS mock (Android-only presenter tool)
  // ===========================================================================
  //
  // Teleports the OS-level GPS so a demo can be "at" a preset spot without
  // moving the device. The state lives in `MockLocationService`, behind
  // `LocationRepository`, so `LocationMonitor` can hold the mocked fix and
  // ignore the real GPS for exactly as long as the mock is active.

  /// Whether this build can mock the OS GPS (Android, non-web). Views hide
  /// the dev control when false.
  bool get mockGpsSupported => repository.location.mockSupported;

  /// Whether a mock is live right now.
  bool get mockGpsActive => repository.location.mockActive;

  /// Teleports the OS GPS to [latitude]/[longitude]. Returns an error
  /// message, or null on success.
  Future<String?> setMockGps({
    required double latitude,
    required double longitude,
  }) => repository.location.setMockLocation(latitude, longitude);

  /// Stops mocking and resumes real GPS fixes.
  Future<void> stopMockGps() => repository.location.stopMockLocation();

  // ===========================================================================
  // Map geometry constants
  // ===========================================================================

  /// REQ102_1 - the camera is clamped to this box, so the tourist can never
  /// pan off Malaysia.
  static const double malaysiaSouth = 0.70;
  static const double malaysiaWest = 99.30;
  static const double malaysiaNorth = 7.60;
  static const double malaysiaEast = 119.60;

  /// REQ102_14 - the whole-country overview, used when the tourist's location
  /// is unavailable or outside Malaysia.
  static const double malaysiaCentreLatitude = 4.10;
  static const double malaysiaCentreLongitude = 109.50;

  ///
  /// 4.7, not 5.3: Malaysia's bounding box is 20.3 degrees of longitude wide,
  /// and at 5.3 that does not fit a 390pt phone - Sabah fell off the right
  /// edge. Measured, not guessed: 360 / (256 * 2^4.7) degrees per pixel puts
  /// 21.1 degrees across 390pt.
  static const double malaysiaOverviewZoom = 4.7;

  /// REQ102_12 / REQ102_13 - "the predefined zoom level". At or above this the
  /// dashboard is a detailed map view; below it, the heatmap.
  static const double detailedViewZoom = 7.5;

  /// REQ102_12, for the heatmap illustration rather than the slippy map.
  ///
  /// The overview is a painted, stylised Malaysia (see `RegionHeatmapCanvas`),
  /// so "the predefined zoom level" is a canvas scale factor there, not a
  /// slippy-map zoom. Pinching or pressing "+" past 3x hands over to the real
  /// OpenStreetMap detailed view, centred on the state under the middle of the
  /// screen.
  static const double heatmapDetailScale = 3;

  /// Where a city search result settles the map (REQ102_22).
  static const double cityZoom = 13;

  /// Where a restaurant or landmark search result settles - street level.
  static const double addressZoom = 16;

  /// What people type instead of a state's official name.
  ///
  /// Without these, searching "Penang" surfaces George Town and Penang Hill
  /// but never the state itself, because the catalogue calls it Pulau Pinang.
  /// Keyed by region code.
  static const Map<String, List<String>> stateAliases = <String, List<String>>{
    'PNG': <String>['Penang'],
    'MLK': <String>['Malacca'],
    'NSN': <String>['N. Sembilan', 'Negri Sembilan'],
    'KUL': <String>['KL', 'WP Kuala Lumpur'],
    'PJY': <String>['WP Putrajaya'],
    'LBN': <String>['WP Labuan'],
    'TRG': <String>['Trengganu'],
    'PLS': <String>['Perlis Indera Kayangan'],
  };

  /// How many location results the list shows. Enough to find what you meant,
  /// short enough to scan.
  static const int maximumPlaceResults = 12;

  /// Where Find Me and the initial GPS centring settle the map
  /// (REQ102_8, REQ102_9).
  static const double currentLocationZoom = 14;

  /// Below the overview zoom, so the country can always be framed whole.
  /// Above this the country mask comes off.
  ///
  /// It used to be 11, because the tight coastline was coarse enough to start
  /// shaving real Malaysian roads at street level. The mask now uses the
  /// buffered rings, which sit ~13 km out to sea, so its edge is off screen
  /// long before that matters - and REQ102_1 holds at every zoom the tourist
  /// can reach.
  static const double countryMaskMaxZoom = 18;

  static const double minimumZoom = 4.2;
  static const double maximumZoom = 18;

  /// One press of "+" or "-" (REQ102_3, REQ102_5).
  static const double zoomStep = 1;

  // ===========================================================================
  // How many markers the detailed map draws
  // ===========================================================================

  /// There is **no zoom at which clustering stops.**
  ///
  /// It used to stop at 11, and that was the bug: past the threshold every place
  /// in view was drawn, so a dense city became a mat of overlapping markers. The
  /// grouping is now decided per grid cell in `map_food_markers` - a cell with
  /// one place is that place, a cell with several is a count - and the cell is
  /// about 56 screen pixels at whatever the current zoom is.
  ///
  /// Two consequences worth knowing:
  ///
  ///  * markers can never be denser than the grid, so the map cannot become
  ///    unreadable however many restaurants are underneath it;
  ///  * zooming in splits cells, and places drop out of their clusters as pins
  ///    exactly when there is room to draw them.

  /// How far outside the visible box to query, as a fraction of its size.
  ///
  /// REQ102_41 - panning a short way should find its markers already loaded
  /// rather than flashing an empty edge. 25% each way roughly doubles the area
  /// queried, which at these row counts is free.
  static const double viewportBuffer = 0.25;

  /// How many dish names the pin sheet lists before it stops.
  static const int maximumServedFoods = 8;

  /// How many pins the detailed map may draw at [zoom].
  ///
  /// The thresholds reuse the zoom levels the rest of the module already names:
  /// [cityZoom] is where a city search settles, [addressZoom] where a street
  /// address does.
  ///
  /// A safety net, not a working limit: the cell grid already bounds the answer
  /// to roughly a screenful (measured: 12 markers for the whole of Malaysia,
  /// 66 for Kuala Lumpur at zoom 11, 10 at street level). This only bites if a
  /// caller asks for a box far larger than a screen.
  static int pinLimitForZoom(double zoom) => maximumMarkers;

  /// Ceiling on marker rows from one viewport query.
  static const int maximumMarkers = 400;

  // ===========================================================================
  // Smart Filtering options (REQ102_23 - REQ102_27)
  // ===========================================================================

  /// C2 / REQ102_24. "All" is not an option here - the UI renders it as the
  /// chip that clears the group, and an empty group already means "all".
  static const List<String> mealOptions = <String>[
    'All-Day Dining',
    'Breakfast',
    'Brunch',
    'Lunch',
    'High Tea',
    'Dinner',
    'Supper',
    'Street Food',
  ];

  /// C3 / REQ102_25.
  ///
  /// Four cuisines, per JT's updated requirement. **`Sabah` and `Sarawak` were
  /// dropped from the filter but still exist in `local_food.food_category`** -
  /// 23 of the 102 catalogue rows carry one of them. Those dishes are still
  /// searchable and still counted when no category filter is set; they simply
  /// cannot be filtered *to*, and picking any category now excludes them.
  static const List<String> categoryOptions = <String>[
    'Malay',
    'Chinese',
    'Indian',
    'Nyonya',
  ];

  /// C4 / REQ102_26. Order follows the requirement, not the alphabet, so the
  /// row reads the way the spec does.
  static const List<String> tasteOptions = <String>[
    'Sweet',
    'Salty',
    'Sour',
    'Bitter',
    'Umami',
    'Spicy',
    'Mild',
    'Buttery',
    'Peppery',
    'Savoury',
    'Rich',
    'Light',
    'Creamy',
    'Smoky',
    'Roasted',
    'Fresh',
    'Herbal',
    'Nutty',
    'Earthy',
    'Fermented',
    'Tangy',
    'Fragrant',
    'Refreshing',
  ];

  /// C5 / REQ102_27.
  static const List<String> typeOptions = <String>[
    'Food',
    'Beverage',
    'Fruit',
    'Dessert',
    'Kuih',
  ];

  /// The options belonging to one filter group. Kept here rather than in the
  /// ViewModel so the four C2 - C5 lists have exactly one owner.
  List<String> optionsFor(ExplorationFilterGroup group) => switch (group) {
    ExplorationFilterGroup.meal => mealOptions,
    ExplorationFilterGroup.category => categoryOptions,
    ExplorationFilterGroup.taste => tasteOptions,
    ExplorationFilterGroup.type => typeOptions,
  };

  /// The label on the pill that opens a filter row.
  String labelFor(ExplorationFilterGroup group) => switch (group) {
    ExplorationFilterGroup.meal => 'Meal',
    ExplorationFilterGroup.category => 'Category',
    ExplorationFilterGroup.taste => 'Taste',
    ExplorationFilterGroup.type => 'Type',
  };

  // ===========================================================================
  // Regions
  // ===========================================================================

  Future<List<Region>> regions() => repository.map.malaysiaRegions();

  /// Throws away the cached map data so the next read goes to Supabase.
  ///
  /// Called when the tourist accepts the "map has been updated" prompt, and
  /// worth calling after this app submits a landmark of its own - otherwise the
  /// tourist's own contribution takes up to `MapRepository.cacheTtl` to appear.
  void clearMapCache() => repository.map.clearCache();

  /// REQ102_1 - the tight coastline, which the painted overview clips to.
  Future<List<CountryOutline>> outlines() => repository.map.malaysiaOutlines();

  /// REQ102_1 - the generous rings the detailed map masks with.
  Future<List<CountryOutline>> maskOutlines() =>
      repository.map.malaysiaMaskOutlines();

  /// The state containing [latitude] / [longitude], or null when the point is
  /// outside every Malaysian state (A3).
  ///
  /// **Strict**: the point must be inside an outline. This answers "where is
  /// the tourist" and "which state did they tap", where being generous would
  /// mean claiming somebody standing in Singapore is in Johor. The heatmap
  /// tally uses [_regionOf] with `snap: true` instead - see there.
  Future<Region?> regionAt(double latitude, double longitude) async =>
      _regionOf(await regions(), latitude, longitude);

  /// REQ102_8 / REQ102_14 - is the tourist somewhere the dashboard can centre
  /// on? Checked against the state outlines rather than the bounding box, so a
  /// fix in the South China Sea is correctly "not in Malaysia".
  Future<bool> isWithinMalaysia(double latitude, double longitude) async =>
      await regionAt(latitude, longitude) != null;

  // ===========================================================================
  // The heatmap (REQ102_15 - REQ102_17, REQ102_28, REQ102_29, REQ102_33)
  // ===========================================================================

  /// Recomputes the whole heatmap for the current [filter].
  ///
  /// C1: a state's score is the number of **places** (restaurants and
  /// submitted landmarks) in it divided by the maximum any state reached,
  /// so the best-served state is 1.0 (green, REQ102_16) and a state with
  /// nothing is 0.0 (grey). Passing [localFoodId] narrows the calculation
  /// to one dish, which is REQ102_33 - the map redrawn around a searched food.
  ///
  /// @param localFoodId (swipe mode) - `LocalFood.id` of the dish in the
  ///        Target Frame, or null to score every food. Reaches here from
  ///        `DashboardViewModel.showFoodInTargetFrame`.
  Future<FoodDistribution> distribution({
    ExplorationFilter filter = ExplorationFilter.none,
    int? localFoodId,
  }) async {
    final List<Object> gathered = await Future.wait(<Future<Object>>[
      regions(),
      repository.getLocalFoods(),
      repository.map.foodOccurrences(),
    ]);
    final List<Region> allRegions = gathered[0] as List<Region>;
    final List<LocalFood> catalogue = gathered[1] as List<LocalFood>;
    final List<FoodOccurrence> rawOccurrences =
        gathered[2] as List<FoodOccurrence>;

    final List<LocalFood> matching = catalogue
        .where(
          (LocalFood food) =>
              (localFoodId == null || food.id == localFoodId) &&
              matchesFilter(food, filter),
        )
        .toList(growable: false);

    final Set<int> matchingIds = matching
        .map((LocalFood food) => food.id)
        .toSet();

    final List<FoodOccurrence> occurrences = _resolve(
      rawOccurrences,
      catalogue,
    );

    // When viewing "All local food" (no filter, no specific dish), include
    // EVERY landmark even if its dish text hasn't been matched to a catalogue
    // row yet - matching the logic used for map pins.
    final bool includesAllLandmarks =
        localFoodId == null && filter.selectionCount == 0;

    // Collapse the occurrence list to one entry per place first. A place
    // with ten matching dishes still counts once (C1), and - the reason this is
    // a separate pass - the point-in-polygon test then runs once per place
    // rather than once per dish, which is the difference between ~12k tests and
    // ~78k on every heatmap redraw.
    final Map<String, _PlaceTally> tallies = <String, _PlaceTally>{};
    for (final FoodOccurrence occurrence in occurrences) {
      final bool isMatchingFood = matchingIds.contains(occurrence.localFoodId);
      final bool isUnresolvedLandmark =
          includesAllLandmarks &&
          occurrence.source == FoodOccurrenceSource.submittedLandmark &&
          occurrence.localFoodId == 0;

      if (!isMatchingFood && !isUnresolvedLandmark) continue;

      tallies
          .putIfAbsent(
            '${occurrence.source.name}:${occurrence.sourceId}',
            () => _PlaceTally(occurrence.latitude, occurrence.longitude),
          )
          .foods
          .add(occurrence.localFoodId);
    }

    // Two tallies per state: the places (what the gradient measures) and the
    // distinct dishes (context on the state card).
    final Map<String, int> placesByRegion = <String, int>{
      for (final Region region in allRegions) region.code: 0,
    };
    final Map<String, Set<int>> foodsByRegion = <String, Set<int>>{
      for (final Region region in allRegions) region.code: <int>{},
    };

    for (final _PlaceTally tally in tallies.values) {
      final Region? region = _regionOf(
        allRegions,
        tally.latitude,
        tally.longitude,
        // The heatmap is a count of every place in the country, so a place
        // that fell in a gap between two coarse outlines must still land
        // somewhere. See [regionSnapMetres].
        snap: true,
      );
      if (region == null) continue;
      placesByRegion[region.code] = placesByRegion[region.code]! + 1;
      foodsByRegion[region.code]!.addAll(tally.foods);
    }

    int maximum = 0;
    for (final int places in placesByRegion.values) {
      if (places > maximum) maximum = places;
    }

    final List<RegionAvailability> availability = allRegions
        .map((Region region) {
          final int places = placesByRegion[region.code]!;
          return RegionAvailability(
            region: region,
            placeCount: places,
            maximumPlaceCount: maximum,
            // REQ102_17 - the gradient between green and grey is generated
            // from this, never picked per state.
            score: maximum == 0 ? 0 : places / maximum,
            foodCount: foodsByRegion[region.code]!.length,
          );
        })
        .toList(growable: false);

    return FoodDistribution(
      regions: availability,
      maximumPlaceCount: maximum,
      matchingFoodCount: matching.length,
    );
  }

  /// REQ102_41 - the markers drawn on the detailed map view.
  ///
  /// **Nothing is downloaded and filtered here.** The viewport, the food
  /// selection and the zoom go to Postgres, which answers with the markers
  /// actually drawn: seven cluster rows for the whole of Malaysia, a couple of
  /// hundred pins for a city. Before this the app read every restaurant and
  /// every menu row in the country on the first pan.
  ///
  /// Three things decide the answer, and they are independent:
  ///
  ///  * the **viewport box** ([south] / [west] / [north] / [east]), widened by
  ///    [viewportBuffer] so a place just off the edge is already loaded;
  ///  * the **zoom**, which sets the size of the grid cell each marker stands
  ///    for - so it decides how much is grouped, not whether grouping happens;
  ///  * the **food**, either one dish ([localFoodId]) or every dish surviving
  ///    [filter]. Null means no food constraint, and Postgres skips the menu
  ///    lookup entirely.
  ///
  /// A pin comes back bare - id, name, position, rating, photo. Its menu,
  /// opening hours and category arrive from [pinDetail] when it is tapped.
  ///
  /// **This is where REQ103_8 lands.** The food resting in the Target Frame
  /// becomes [localFoodId], and the query returns only places serving it. The
  /// camera is untouched, so swiping from one dish to the next re-draws the
  /// markers where the tourist is already looking.
  ///
  /// @param localFoodId (swipe mode) - `LocalFood.id` of the dish in the
  ///        Target Frame, or null for every matching food.
  Future<MapPinPage> pins({
    ExplorationFilter filter = ExplorationFilter.none,
    int? localFoodId,
    double? south,
    double? west,
    double? north,
    double? east,
    double? fromLatitude,
    double? fromLongitude,
    double zoom = detailedViewZoom,
    int? limit,
  }) async {
    // Without a box there is nothing to ask about. The detailed map always has
    // one; this is the guard for anyone calling before the first camera event.
    if (south == null || west == null || north == null || east == null) {
      return MapPinPage.empty;
    }

    final int cap = limit ?? maximumMarkers;

    // Which foods count. `null` is "no constraint" and is not the same as an
    // empty list, which is "a filter is on and nothing matches it" - the first
    // skips the menu lookup, the second is an empty map.
    final List<int>? foodIds = await _foodIdsFor(
      filter: filter,
      localFoodId: localFoodId,
    );

    // REQ102_41 - a little wider than the screen, so panning a short way finds
    // its markers already loaded instead of flashing an empty edge.
    final double latitudeSpan = (north - south).abs();
    final double longitudeSpan = (east - west).abs();
    final double latitudePad = latitudeSpan * viewportBuffer;
    final double longitudePad = longitudeSpan * viewportBuffer;

    final MapMarkerSet markers = await repository.map.mapMarkers(
      southLatitude: south - latitudePad,
      westLongitude: west - longitudePad,
      northLatitude: north + latitudePad,
      eastLongitude: east + longitudePad,
      zoom: zoom,
      foodIds: foodIds,
      limit: cap,
    );

    // Distance to the tourist is the one thing Postgres was not asked for: it
    // changes with every GPS fix, and recomputing it here costs nothing.
    final List<MapPin> withDistance = fromLatitude == null ||
            fromLongitude == null
        ? markers.pins
        : markers.pins
              .map(
                (MapPin pin) => _withDistance(
                  pin,
                  _distanceMetres(
                    fromLatitude,
                    fromLongitude,
                    pin.latitude,
                    pin.longitude,
                  ),
                ),
              )
              .toList(growable: false);

    return MapPinPage(
      pins: List<MapPin>.unmodifiable(withDistance),
      clusters: markers.clusters,
      // Markers produced, not places found - `placesRepresented` is the second
      // number, and it counts what is inside the clusters too.
      totalInView: withDistance.length + markers.clusters.length,
      limit: cap,
    );
  }

  /// REQ102_41 - what a tap on [cluster] should do.
  ///
  /// Returns the zoom that visibly breaks the cluster up, so one tap does what
  /// three used to fail to do. When no zoom separates the members - places at
  /// the same coordinates - the answer instead carries every member, so the map
  /// can draw them individually rather than a badge that can never be opened.
  ///
  /// Members that would land on top of each other are spread onto a small
  /// circle so each is separately tappable. That moves the **drawn** position by
  /// a few metres at maximum zoom; `referenceId` is untouched, so tapping still
  /// opens the right restaurant.
  Future<ClusterExpansion> expandCluster(
    MapCluster cluster, {
    required double zoom,
    ExplorationFilter filter = ExplorationFilter.none,
    int? localFoodId,
  }) async {
    final List<int>? foodIds = await _foodIdsFor(
      filter: filter,
      localFoodId: localFoodId,
    );

    final ({double? splitZoom, int memberCount}) probe = await repository.map
        .clusterSplitZoom(
          latitude: cluster.latitude,
          longitude: cluster.longitude,
          zoom: zoom,
          maximumZoom: maximumZoom,
          foodIds: foodIds,
        );

    if (probe.splitZoom != null) {
      return ClusterExpansion(
        splitZoom: probe.splitZoom,
        memberCount: probe.memberCount,
      );
    }

    final List<MapPin> members = await repository.map.clusterMembers(
      latitude: cluster.latitude,
      longitude: cluster.longitude,
      zoom: zoom,
      foodIds: foodIds,
    );
    return ClusterExpansion(
      splitZoom: null,
      memberCount: probe.memberCount == 0 ? members.length : probe.memberCount,
      members: _spreadColliding(members, maximumZoom),
    );
  }

  /// Pushes markers that share a position onto a small circle around it.
  ///
  /// Without this, "show them individually" draws six pins on top of each other
  /// and only the last is tappable. The radius is [collisionSpreadPixels]
  /// converted to degrees at [zoom] - about four metres at maximum zoom, which
  /// is below the accuracy of the coordinates themselves.
  static List<MapPin> _spreadColliding(List<MapPin> members, double zoom) {
    if (members.length < 2) return members;

    // Places within a marker's width of each other, grouped by rounded position.
    final Map<String, List<MapPin>> byPosition = <String, List<MapPin>>{};
    for (final MapPin member in members) {
      final String key =
          '${member.latitude.toStringAsFixed(5)}:'
          '${member.longitude.toStringAsFixed(5)}';
      byPosition.putIfAbsent(key, () => <MapPin>[]).add(member);
    }

    final double degreesPerPixel = 360 / (256 * math.pow(2, zoom));
    final double radius = collisionSpreadPixels * degreesPerPixel;

    final List<MapPin> out = <MapPin>[];
    for (final List<MapPin> group in byPosition.values) {
      if (group.length == 1) {
        out.add(group.first);
        continue;
      }
      for (int i = 0; i < group.length; i++) {
        final double angle = 2 * math.pi * i / group.length;
        final MapPin member = group[i];
        out.add(
          _movedTo(
            member,
            member.latitude + radius * math.sin(angle),
            member.longitude +
                radius * math.cos(angle) / math.cos(_radians(member.latitude)),
          ),
        );
      }
    }
    return List<MapPin>.unmodifiable(out);
  }

  static MapPin _movedTo(MapPin pin, double latitude, double longitude) =>
      MapPin(
        referenceId: pin.referenceId,
        kind: pin.kind,
        latitude: latitude,
        longitude: longitude,
        label: pin.label,
        weight: pin.weight,
        imageUrl: pin.imageUrl,
        category: pin.category,
        rating: pin.rating,
        servedFoods: pin.servedFoods,
        priceRange: pin.priceRange,
        openNow: pin.openNow,
        distanceMetres: pin.distanceMetres,
      );

  /// How far apart to push markers that share a position, in screen pixels.
  static const double collisionSpreadPixels = 18;

  /// The `local_food_id`s a viewport query should be constrained to.
  ///
  /// Null when nothing is constraining the map, so the query skips the menu
  /// lookup. A single id when a dish is in the Target Frame or has been
  /// searched. Otherwise every catalogue food surviving the filter chips -
  /// resolved here rather than in SQL, so the filter rules stay in one place
  /// and the 368-row catalogue is read from cache.
  Future<List<int>?> _foodIdsFor({
    required ExplorationFilter filter,
    required int? localFoodId,
  }) async {
    if (localFoodId != null) return <int>[localFoodId];
    if (filter.selectionCount == 0) return null;

    // The same four chips produce the same ids every time, and this is asked on
    // every pan. Resolve once per filter selection rather than walking the
    // catalogue again for each load.
    final String key =
        '${filter.meal}|${filter.category}|${filter.taste}|${filter.type}';
    final List<int>? cached = _foodIdCache[key];
    if (cached != null) return cached;

    final List<LocalFood> catalogue = await repository.getLocalFoods();
    final List<int> ids = catalogue
        .where((LocalFood food) => matchesFilter(food, filter))
        .map((LocalFood food) => food.id)
        .toList(growable: false);
    if (_foodIdCache.length > 32) _foodIdCache.clear();
    _foodIdCache[key] = ids;
    return ids;
  }

  static final Map<String, List<int>> _foodIdCache = <String, List<int>>{};

  /// REQ102_47 - everything the "Click Map Pin" sheet shows, fetched by id the
  /// moment a pin is tapped.
  ///
  /// The map markers carry only what they draw. This is the other half of that
  /// bargain: one row by primary key, its menu, and its opening hours - three
  /// small reads for one place, instead of those three columns on every place
  /// in the country.
  ///
  /// Returns [pin] unchanged when the detail cannot be read, so a tap always
  /// opens a sheet with at least the name and photo already on the marker.
  Future<MapPin> pinDetail(
    MapPin pin, {
    ExplorationFilter filter = ExplorationFilter.none,
    int? localFoodId,
  }) async {
    final int? id = int.tryParse(pin.referenceId);
    if (id == null || id <= 0) return pin;
    if (pin.kind != MapPinKind.restaurant) return pin;

    final Restaurant? restaurant;
    final List<RestaurantItem> items;
    final Map<String, List<OpeningHour>> hours;
    try {
      final List<Object?> gathered = await Future.wait(<Future<Object?>>[
        repository.getRestaurantById(id),
        repository.getRestaurantItemsByRestaurantIds(<int>[id]),
        repository.openingHoursByPlace(
          placeKeys: <String>{'restaurant:$id'},
        ),
      ]);
      restaurant = gathered[0] as Restaurant?;
      items = gathered[1] as List<RestaurantItem>;
      hours = gathered[2] as Map<String, List<OpeningHour>>;
    } catch (_) {
      return pin;
    }
    if (restaurant == null) return pin;

    // "Serves: ..." lists what the tourist is looking for first. With nothing
    // selected that is simply the menu, catalogue names preferred over the
    // restaurant's own spelling so the sheet matches the rest of the app.
    final List<LocalFood> catalogue = await repository.getLocalFoods();
    final Map<int, String> nameById = <int, String>{
      for (final LocalFood food in catalogue) food.id: food.name,
    };
    final Set<int> wanted = <int>{
      for (final LocalFood food in catalogue)
        if ((localFoodId == null || food.id == localFoodId) &&
            matchesFilter(food, filter))
          food.id,
    };
    final bool narrowed = localFoodId != null || filter.selectionCount > 0;

    final List<String> served = <String>[];
    final List<double> prices = <double>[];
    for (final RestaurantItem item in items) {
      final bool matches = wanted.contains(item.localFoodId);
      if (narrowed && !matches) continue;
      final String name = (nameById[item.localFoodId] ?? item.foodName).trim();
      if (name.isNotEmpty && !served.contains(name)) served.add(name);
      final double? price = item.price;
      if (price != null && price > 0) prices.add(price);
    }

    return MapPin(
      referenceId: pin.referenceId,
      kind: pin.kind,
      latitude: pin.latitude,
      longitude: pin.longitude,
      label: restaurant.name.isEmpty ? pin.label : restaurant.name,
      weight: served.isEmpty ? pin.weight : served.length,
      imageUrl: restaurant.imageUrl ?? pin.imageUrl,
      category: restaurant.category.isEmpty ? null : restaurant.category,
      rating: restaurant.rating ?? pin.rating,
      servedFoods: List<String>.unmodifiable(
        served.length > maximumServedFoods
            ? served.sublist(0, maximumServedFoods)
            : served,
      ),
      priceRange: _priceRangeOf(prices),
      openNow: _openNow(hours['restaurant:$id']),
      distanceMetres: pin.distanceMetres,
    );
  }

  static MapPin _withDistance(MapPin pin, double distanceMetres) => MapPin(
    referenceId: pin.referenceId,
    kind: pin.kind,
    latitude: pin.latitude,
    longitude: pin.longitude,
    label: pin.label,
    weight: pin.weight,
    imageUrl: pin.imageUrl,
    category: pin.category,
    rating: pin.rating,
    servedFoods: pin.servedFoods,
    priceRange: pin.priceRange,
    openNow: pin.openNow,
    distanceMetres: distanceMetres,
  );

  /// "RM20-40", or "RM20" when everything costs the same. Null when no dish
  /// here carries a price - better an absent line than an invented one.
  static String? _priceRangeOf(List<double> prices) {
    if (prices.isEmpty) return null;
    double low = prices.first;
    double high = prices.first;
    for (final double price in prices) {
      if (price < low) low = price;
      if (price > high) high = price;
    }
    final int from = low.round();
    final int to = high.round();
    return from == to ? 'RM$from' : 'RM$from-$to';
  }

  /// Is the place open at this moment (UC300 C12)?
  ///
  /// Returns **null when there is nothing on record** - the sheet says "Hours
  /// unknown" rather than claiming the place is shut. A row whose times are
  /// missing is a closed day; a range that ends before it starts has run past
  /// midnight.
  static bool? _openNow(List<OpeningHour>? hours) {
    if (hours == null || hours.isEmpty) return null;

    final DateTime now = DateTime.now();
    final Weekday today = Weekday.values[now.weekday - 1];
    final List<OpeningHour> rows = hours
        .where((OpeningHour hour) => hour.day == today)
        .toList(growable: false);
    if (rows.isEmpty) return null;

    final int minutes = now.hour * 60 + now.minute;
    for (final OpeningHour hour in rows) {
      if (hour.status != DayStatus.open) continue;
      final int? opensAt = hour.opensAt;
      final int? closesAt = hour.closesAt;
      if (opensAt == null || closesAt == null) continue;
      final bool open = closesAt >= opensAt
          ? minutes >= opensAt && minutes < closesAt
          : minutes >= opensAt || minutes < closesAt;
      if (open) return true;
    }
    return rows.any((OpeningHour hour) => hour.status == DayStatus.unknown)
        ? null
        : false;
  }

  /// Great-circle distance in metres. Straight-line, not walking distance -
  /// the sheet labels it as such.
  static double _distanceMetres(
    double fromLatitude,
    double fromLongitude,
    double toLatitude,
    double toLongitude,
  ) {
    const double earthRadius = 6371000;
    final double dLat = _radians(toLatitude - fromLatitude);
    final double dLng = _radians(toLongitude - fromLongitude);
    final double a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_radians(fromLatitude)) *
            math.cos(_radians(toLatitude)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _radians(double degrees) => degrees * math.pi / 180;

  /// Does [food] survive the four filter groups? A group left unset is no
  /// constraint. A dish marked `All-Day Dining` satisfies every meal filter -
  /// it is, by definition, served at all of them.
  bool matchesFilter(LocalFood food, ExplorationFilter filter) {
    final String? meal = filter.meal;
    if (meal != null) {
      final String dishMeal = food.mealType.toLowerCase().trim();
      if (!dishMeal.contains('all-day') && dishMeal != meal.toLowerCase()) {
        return false;
      }
    }

    final String? category = filter.category;
    if (category != null &&
        food.category.toLowerCase().trim() != category.toLowerCase()) {
      return false;
    }

    final String? type = filter.type;
    if (type != null &&
        food.foodType.toLowerCase().trim() != type.toLowerCase()) {
      return false;
    }

    final String? taste = filter.taste;
    if (taste != null) {
      final bool matches = food.tastes.any(
        (String value) => value.toLowerCase().trim() == taste.toLowerCase(),
      );
      if (!matches) return false;
    }

    return true;
  }

  // ===========================================================================
  // Search (A8, REQ102_18 - REQ102_22, REQ102_30, REQ102_31)
  // ===========================================================================

  /// One keyword, matched against both location records and the local-food
  /// catalogue, returned as the single grouped result list of A8 step 3.
  ///
  /// Both lists coming back empty is A8.2 - the caller turns that into M2.
  Future<ExplorationSearchResults> search(String keyword) async {
    final String needle = keyword.trim().toLowerCase();
    if (needle.isEmpty) return ExplorationSearchResults.empty;

    // States, the place table and the food catalogue are independent reads.
    final List<Object> gathered = await Future.wait(<Future<Object>>[
      regions(),
      repository.map.places(),
      repository.searchLocalFoods(keyword),
      repository.map.foodOccurrences(),
    ]);
    final List<Region> allRegions = gathered[0] as List<Region>;
    final List<MapPlace> catalogue = gathered[1] as List<MapPlace>;
    final List<LocalFood> foods = gathered[2] as List<LocalFood>;
    final List<FoodOccurrence> occurrences =
        gathered[3] as List<FoodOccurrence>;

    final List<_ScoredPlace> scored = <_ScoredPlace>[];

    // REQ102_18 - states.
    for (final Region region in allRegions) {
      final int score = _score(needle, <String>[
        region.name,
        ...?stateAliases[region.code],
      ]);
      if (score == 0) continue;
      scored.add(
        _ScoredPlace(
          score,
          PlaceSuggestion(
            name: region.name,
            subtitle: 'State',
            kind: PlaceKind.state,
            latitude: region.centreLatitude,
            longitude: region.centreLongitude,
            zoom: region.defaultZoom,
          ),
        ),
      );
    }

    // REQ102_19 / REQ102_20 - cities, towns, areas and notable locations, each
    // matched on its name and on the alternates people actually type.
    for (final MapPlace place in catalogue) {
      final int score = _score(needle, <String>[place.name, ...place.aliases]);
      if (score == 0) continue;
      scored.add(
        _ScoredPlace(
          score,
          PlaceSuggestion(
            name: place.name,
            subtitle: '${_label(place.kind)} - ${place.stateName}',
            kind: _suggestionKind(place.kind),
            latitude: place.latitude,
            longitude: place.longitude,
            zoom: place.zoom,
          ),
        ),
      );
    }

    // The fallback that keeps search working when the place table is empty or
    // unreachable: the region catalogue's own handful of cities.
    if (catalogue.isEmpty) {
      for (final Region region in allRegions) {
        for (final RegionPlace place in region.places) {
          final int score = _score(needle, <String>[place.name]);
          if (score == 0) continue;
          scored.add(
            _ScoredPlace(
              score,
              PlaceSuggestion(
                name: place.name,
                subtitle: place.regionName,
                kind: PlaceKind.city,
                latitude: place.latitude,
                longitude: place.longitude,
                zoom: cityZoom,
              ),
            ),
          );
        }
      }
    }

    // Addresses: the places already on the map answer "where is X" too, and a
    // tourist searching a restaurant name expects to find it.
    //
    // Scored against a prepared index rather than the raw occurrence list. The
    // occurrences are one row per dish - 78,355 of them for 12,666 places - and
    // the old loop scored every one, lower-casing and regex-splitting the same
    // restaurant name six times over, on every keystroke. Every occurrence of a
    // place carries the same name and position, so scoring the place once gives
    // **the same result** and does a sixth of the work.
    for (final _SearchablePlace place in _placeIndexFor(occurrences)) {
      final int score = _scorePrepared(needle, place);
      if (score == 0) continue;
      scored.add(
        _ScoredPlace(
          // One step below a named place: a restaurant called "Penang Village"
          // must not outrank Penang.
          score - 1,
          PlaceSuggestion(
            name: place.name,
            subtitle: place.source == FoodOccurrenceSource.restaurant
                ? 'Restaurant'
                : 'Submitted landmark',
            kind: PlaceKind.address,
            latitude: place.latitude,
            longitude: place.longitude,
            zoom: addressZoom,
          ),
        ),
      );
    }

    scored.sort((_ScoredPlace a, _ScoredPlace b) {
      final int byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      // Same score: broader things first, then alphabetically.
      final int byKind = a.suggestion.kind.index.compareTo(
        b.suggestion.kind.index,
      );
      if (byKind != 0) return byKind;
      return a.suggestion.name.compareTo(b.suggestion.name);
    });

    return ExplorationSearchResults(
      keyword: keyword.trim(),
      places: List<PlaceSuggestion>.unmodifiable(
        scored
            .take(maximumPlaceResults)
            .map((_ScoredPlace entry) => entry.suggestion),
      ),
      foods: foods,
    );
  }

  /// How well [candidates] answer what was typed. 0 means no match.
  ///
  /// Ranked rather than a flat `contains`, because with 148 places a bare
  /// substring match buries the obvious answer: typing "kl" should offer Kuala
  /// Lumpur and KLCC before Kluang and Kuala Selangor.
  /// One searchable place, with the per-keystroke work already done.
  ///
  /// Built once per occurrence list and reused for every keystroke.
  static List<_SearchablePlace> _placeIndexFor(
    List<FoodOccurrence> occurrences,
  ) {
    // Occurrences are cached and replaced wholesale, so identity is a sound and
    // very cheap staleness test.
    if (identical(_indexedOccurrences, occurrences) && _placeIndex != null) {
      return _placeIndex!;
    }
    final Set<String> seen = <String>{};
    final List<_SearchablePlace> index = <_SearchablePlace>[];
    for (final FoodOccurrence occurrence in occurrences) {
      final String key = '${occurrence.source.name}:${occurrence.sourceId}';
      if (!seen.add(key)) continue;
      index.add(_SearchablePlace(occurrence));
    }
    _indexedOccurrences = occurrences;
    _placeIndex = List<_SearchablePlace>.unmodifiable(index);
    return _placeIndex!;
  }

  static List<FoodOccurrence>? _indexedOccurrences;
  static List<_SearchablePlace>? _placeIndex;

  /// [_score] for a place whose lower-cased name and word list are already in
  /// hand. Same ladder, same numbers, same answer - just no re-work.
  static int _scorePrepared(String needle, _SearchablePlace place) {
    final String value = place.nameLower;
    if (value.isEmpty) return 0;
    if (value == needle) return _scoreExact;
    if (value.startsWith(needle)) return _scorePrefix;
    for (final String word in place.words) {
      if (word.startsWith(needle)) return _scoreWord;
    }
    if (value.contains(needle)) return _scoreContains;
    return 0;
  }

  static int _score(String needle, List<String> candidates) {
    int best = 0;
    for (final String candidate in candidates) {
      final String value = candidate.toLowerCase().trim();
      if (value.isEmpty) continue;
      if (value == needle) {
        best = _scoreExact;
      } else if (value.startsWith(needle)) {
        if (best < _scorePrefix) best = _scorePrefix;
      } else if (_startsAWord(value, needle)) {
        // "alor" finding "Jalan Alor" - a word boundary is a much better
        // signal than a substring landing mid-word.
        if (best < _scoreWord) best = _scoreWord;
      } else if (value.contains(needle)) {
        if (best < _scoreContains) best = _scoreContains;
      }
      if (best == _scoreExact) break;
    }
    return best;
  }

  static bool _startsAWord(String value, String needle) {
    for (final String word in value.split(RegExp(r'[\s,./-]+'))) {
      if (word.startsWith(needle)) return true;
    }
    return false;
  }

  static const int _scoreExact = 100;
  static const int _scorePrefix = 60;
  static const int _scoreWord = 40;
  static const int _scoreContains = 20;

  static PlaceKind _suggestionKind(MapPlaceKind kind) => switch (kind) {
    MapPlaceKind.city => PlaceKind.city,
    MapPlaceKind.town => PlaceKind.town,
    MapPlaceKind.area => PlaceKind.area,
    MapPlaceKind.landmark => PlaceKind.landmark,
  };

  static String _label(MapPlaceKind kind) => switch (kind) {
    MapPlaceKind.city => 'City',
    MapPlaceKind.town => 'Town',
    MapPlaceKind.area => 'Area',
    MapPlaceKind.landmark => 'Landmark',
  };

  // ===========================================================================
  // Location (REQ102_6 - REQ102_9)
  // ===========================================================================

  /// REQ102_6 - asks the OS for location permission, returning whether it was
  /// granted (A1 / A2).
  Future<bool> ensureLocationPermission() =>
      repository.location.ensureLocationPermission();

  /// REQ102_7 - one GPS fix. `TouristLocation.unknown` when there isn't one.
  Future<TouristLocation> currentLocation() =>
      repository.location.currentLocation();

  // ===========================================================================
  // Internals
  // ===========================================================================

  /// Restaurant occurrences already carry a `local_food_id`. Submitted
  /// landmarks carry only free text, so their `dish` is matched against the
  /// catalogue name and synonyms here; an unmatched dish keeps id 0 and is
  /// therefore counted by no state, which is the honest outcome - the app
  /// cannot claim a landmark serves a local food it cannot identify.
  /// Restaurant occurrences already carry a `local_food_id`. Submitted
  /// landmarks carry only free text, so their `dish` is matched against the
  /// catalogue name and synonyms here; an unmatched dish keeps id 0 and is
  /// therefore counted by no state, which is the honest outcome - the app
  /// cannot claim a landmark serves a local food it cannot identify.
  ///
  /// Pure and synchronous: both inputs are already in hand, so this no longer
  /// hides a repository call behind an await.
  List<FoodOccurrence> _resolve(
    List<FoodOccurrence> raw,
    List<LocalFood> catalogue,
  ) {
    // Nothing to match against, so nothing to rewrite.
    if (raw.every((FoodOccurrence o) => o.localFoodId != 0)) return raw;

    final Map<String, int> idByName = <String, int>{};
    for (final LocalFood food in catalogue) {
      idByName[food.name.toLowerCase().trim()] = food.id;
      for (final String synonym in food.synonyms) {
        final String key = synonym.toLowerCase().trim();
        if (key.isNotEmpty) idByName.putIfAbsent(key, () => food.id);
      }
    }

    return raw
        .map((FoodOccurrence occurrence) {
          if (occurrence.localFoodId != 0) return occurrence;
          final int resolved =
              idByName[occurrence.foodName.toLowerCase().trim()] ?? 0;
          if (resolved == 0) return occurrence;
          return FoodOccurrence(
            sourceId: occurrence.sourceId,
            source: occurrence.source,
            placeName: occurrence.placeName,
            localFoodId: resolved,
            foodName: occurrence.foodName,
            latitude: occurrence.latitude,
            longitude: occurrence.longitude,
            placeImageUrl: occurrence.placeImageUrl,
            placeCategory: occurrence.placeCategory,
            placeRating: occurrence.placeRating,
            itemPrice: occurrence.itemPrice,
          );
        })
        .toList(growable: false);
  }

  /// How far outside every outline a point may be and still be counted by the
  /// nearest state.
  ///
  /// The outlines are coarse - about 190 vertices for the whole country - so a
  /// genuinely Malaysian address can sit outside all of them. Langkawi is not
  /// inside Kedah's ring at all; Sepang, Banting, Kuala Terengganu, Chukai,
  /// Port Dickson, Tampin, Tawau and Semporna all fall in gaps. Measured
  /// against the seeded data, **1,554 of 12,584 restaurants - one in eight -
  /// were counted by no state and so appeared nowhere on the heatmap.**
  ///
  /// 50 km is enough for the island and coastline cases and does not reach
  /// another country: Singapore and Brunei sit inside the outlines already, so
  /// nothing is snapped across a border that was not already crossed.
  static const double regionSnapMetres = 50000;

  /// Which state owns [latitude] / [longitude].
  ///
  /// Two rules, both learned from the data:
  ///
  ///  * **The smallest containing outline wins**, not the first one found.
  ///    Kuala Lumpur and Putrajaya are enclaves drawn inside Selangor's ring,
  ///    and Selangor comes first in the catalogue - so first-match ordering
  ///    handed all 2,552 restaurants inside the KL outline to Selangor and left
  ///    the capital grey.
  ///  * With [snap], a point inside no outline is given to the nearest one
  ///    within [regionSnapMetres]. Without it the answer is strict.
  static Region? _regionOf(
    List<Region> regions,
    double latitude,
    double longitude, {
    bool snap = false,
  }) {
    Region? containing;
    double smallest = double.infinity;
    for (final Region region in regions) {
      if (!_contains(region.boundary, latitude, longitude)) continue;
      final double area = _boundaryArea(region);
      if (area < smallest) {
        smallest = area;
        containing = region;
      }
    }
    if (containing != null || !snap) return containing;

    Region? nearest;
    double nearestMetres = regionSnapMetres;
    for (final Region region in regions) {
      final double metres = _metresToBoundary(
        region.boundary,
        latitude,
        longitude,
      );
      if (metres < nearestMetres) {
        nearestMetres = metres;
        nearest = region;
      }
    }
    return nearest;
  }

  /// Cached because the catalogue is fixed and this is asked once per place on
  /// every heatmap redraw.
  static final Map<String, double> _areaByCode = <String, double>{};

  static double _boundaryArea(Region region) =>
      _areaByCode[region.code] ??= _shoelaceArea(region.boundary);

  /// Twice the polygon's area in square degrees. Only ever compared against
  /// another region's, so neither the units nor the factor of two matter.
  static double _shoelaceArea(List<GeoPoint> boundary) {
    if (boundary.length < 3) return 0;
    double sum = 0;
    for (int i = 0, j = boundary.length - 1; i < boundary.length; j = i++) {
      sum +=
          (boundary[j].longitude + boundary[i].longitude) *
          (boundary[j].latitude - boundary[i].latitude);
    }
    return sum.abs();
  }

  /// Shortest distance in metres from the point to the outline's edge.
  ///
  /// Equirectangular, centred on the point: over the tens of kilometres this
  /// is ever asked about, the projection error is far below the accuracy of
  /// the outlines themselves.
  static double _metresToBoundary(
    List<GeoPoint> boundary,
    double latitude,
    double longitude,
  ) {
    if (boundary.length < 2) return double.infinity;
    const double metresPerDegreeLatitude = 110540;
    final double metresPerDegreeLongitude =
        111320 * math.cos(_radians(latitude));
    double best = double.infinity;
    for (int i = 0, j = boundary.length - 1; i < boundary.length; j = i++) {
      final double distance = _segmentDistanceToOrigin(
        (boundary[j].longitude - longitude) * metresPerDegreeLongitude,
        (boundary[j].latitude - latitude) * metresPerDegreeLatitude,
        (boundary[i].longitude - longitude) * metresPerDegreeLongitude,
        (boundary[i].latitude - latitude) * metresPerDegreeLatitude,
      );
      if (distance < best) best = distance;
    }
    return best;
  }

  /// Distance from the origin to the segment a-b, all already in metres.
  static double _segmentDistanceToOrigin(
    double ax,
    double ay,
    double bx,
    double by,
  ) {
    final double dx = bx - ax;
    final double dy = by - ay;
    final double lengthSquared = dx * dx + dy * dy;
    double t = lengthSquared == 0 ? 0 : -(ax * dx + ay * dy) / lengthSquared;
    if (t < 0) {
      t = 0;
    } else if (t > 1) {
      t = 1;
    }
    final double x = ax + t * dx;
    final double y = ay + t * dy;
    return math.sqrt(x * x + y * y);
  }

  /// Ray-casting point-in-polygon. The outlines are coarse (see
  /// `MalaysiaRegionDataModel`), so a point within a few kilometres of a
  /// border can land in the neighbouring state - acceptable for a heatmap,
  /// not for anything that must be legally correct.
  static bool _contains(
    List<GeoPoint> boundary,
    double latitude,
    double longitude,
  ) {
    if (boundary.length < 3) return false;
    bool inside = false;
    for (int i = 0, j = boundary.length - 1; i < boundary.length; j = i++) {
      final GeoPoint a = boundary[i];
      final GeoPoint b = boundary[j];
      final bool straddles = (a.latitude > latitude) != (b.latitude > latitude);
      if (!straddles) continue;
      final double crossing =
          (b.longitude - a.longitude) *
              (latitude - a.latitude) /
              (b.latitude - a.latitude) +
          a.longitude;
      if (longitude < crossing) inside = !inside;
    }
    return inside;
  }
}

/// One place while the heatmap is being counted: where it is, and which
/// matching dishes it serves.
class _PlaceTally {
  _PlaceTally(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
  final Set<int> foods = <int>{};
}

/// A place as the search sees it: the name already lower-cased and split into
/// words, so a keystroke is a comparison rather than a string rebuild.
class _SearchablePlace {
  _SearchablePlace(FoodOccurrence occurrence)
    : name = occurrence.placeName,
      nameLower = occurrence.placeName.toLowerCase().trim(),
      words = occurrence.placeName
          .toLowerCase()
          .trim()
          .split(RegExp(r'[\s,./-]+')),
      latitude = occurrence.latitude,
      longitude = occurrence.longitude,
      source = occurrence.source;

  final String name;
  final String nameLower;
  final List<String> words;
  final double latitude;
  final double longitude;
  final FoodOccurrenceSource source;
}

/// One search hit with the score that ordered it.
class _ScoredPlace {
  const _ScoredPlace(this.score, this.suggestion);

  final int score;
  final PlaceSuggestion suggestion;
}
