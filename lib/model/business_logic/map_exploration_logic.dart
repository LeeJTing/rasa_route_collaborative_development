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
import '../../domain_model/submitted_landmark.dart';
import '../../domain_model/tourist_location.dart';
import '../repositories/discovery_repository_facade.dart';
import 'opening_hours_logic.dart';
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

  DateTime currentTime() => DateTime.now();

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

  /// Neighbourhood-level camera used when a Swipe card becomes active. It is
  /// close enough to make individual places useful without dropping directly
  /// onto a building-level view.
  static const double swipeFoodFocusZoom = 13;

  /// A food filter should be a focused answer, not hundreds of markers across
  /// a state. Normal Dashboard browsing keeps [maximumMarkers].
  static const int swipeFoodMarkerLimit = 10;

  /// REQ102_12, for the heatmap illustration rather than the slippy map.
  ///
  /// The overview is a painted, stylised Malaysia (see `RegionHeatmapCanvas`),
  /// so "the predefined zoom level" is a canvas scale factor there, not a
  /// slippy-map zoom.
  ///
  /// Raised from 3x: the overview handed over so early that it could never be
  /// zoomed in far enough to read, and the canvas allows 12x.
  ///
  /// Crossing it opens the real OpenStreetMap view, centred on the state under
  /// the middle of the screen.
  static const double heatmapDetailScale = 6;

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
  /// **Strict**: the point must be inside a boundary. This answers "where is
  /// the tourist" and "which state is the map centred on", where being generous
  /// would mean claiming somebody standing in Singapore is in Johor.
  ///
  /// Decided by Postgres against the real administrative boundary. Answering it
  /// from the hand-drawn outlines is what reported every point in Kuala Lumpur
  /// as Selangor: the two outlines overlap and Selangor came first in the
  /// catalogue. The repository rounds and caches, so panning is at most one
  /// request per kilometre travelled.
  ///
  /// Falls back to the offline outlines when the database cannot be reached, so
  /// a lost connection degrades to the old, coarser answer rather than to no
  /// answer at all.
  Future<Region?> regionAt(double latitude, double longitude) async {
    try {
      return await repository.map.regionAt(latitude, longitude);
    } catch (_) {
      return _regionOf(await regions(), latitude, longitude);
    }
  }

  /// REQ102_8 / REQ102_14 - is the tourist somewhere the dashboard can centre
  /// on?
  ///
  /// **Checked against the country outlines, not the state ones, and never
  /// against the network.** This used to ask [regionAt], which meant a tourist
  /// on Pulau Redang was told they were not in Malaysia: the hand-drawn state
  /// polygons contain no island except Labuan - not Redang, Perhentian,
  /// Langkawi, Tioman, Kapas, Pangkor or Ketam - so the offline answer was
  /// always "outside", and the online one depended on a round trip that an
  /// island is the worst place to rely on. Every one of those islands is inside
  /// the mask rings, which is why they are the right dataset for a question
  /// about the country rather than about a state.
  ///
  /// It stays strict where it matters: Singapore, Jakarta, Hat Yai and Sumatra
  /// are all outside these rings. Brunei is *inside* the Borneo ring, because
  /// the mask deliberately leaves it visible - a tourist there sees their dot
  /// on ground the map is actually drawing, which is a far smaller error than
  /// hiding the dot from everyone on an island.
  ///
  /// Being local, it cannot fail, so a lost connection can no longer be
  /// mistaken for being abroad.
  Future<bool> isWithinMalaysia(double latitude, double longitude) async {
    for (final CountryOutline outline in await maskOutlines()) {
      if (_contains(outline.ring, latitude, longitude)) return true;
    }
    return false;
  }

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
    // REQ102_12 - the counting happens in Postgres now, against the real
    // administrative boundaries in `region_boundary`.
    //
    // What this replaced: every restaurant in the country (12,660 rows) and
    // every menu entry (78,355) downloaded to the phone, then a ray-cast
    // point-in-polygon test per place against hand-drawn state outlines, on
    // every redraw of the heatmap. Those outlines were coarse enough that
    // Selangor's polygon swallowed Kuala Lumpur - 1,900 restaurants counted
    // under the wrong state and Kuala Lumpur reported as empty - and 699 places
    // fell in the gaps between two outlines and were counted by nobody.
    //
    // The same tally now arrives as sixteen rows.
    final List<int>? foodIds = await _foodIdsFor(
      filter: filter,
      localFoodId: localFoodId,
    );

    final List<Object> gathered = await Future.wait(<Future<Object>>[
      repository.map.regionDistribution(foodIds: foodIds),
      repository.getLocalFoods(),
    ]);
    final List<RegionTally> tallies = gathered[0] as List<RegionTally>;
    final List<LocalFood> catalogue = gathered[1] as List<LocalFood>;

    // C1's denominator is the largest count *in the set on screen*. At state
    // level that is the national maximum; drilled into one state it is that
    // state's busiest district, so the colour ramp re-spreads across the
    // districts actually being shown rather than leaving them all one shade of
    // Johor's 3,155.
    int maximum = 0;
    for (final RegionTally tally in tallies) {
      if (tally.placeCount > maximum) maximum = tally.placeCount;
    }

    final List<RegionAvailability> availability = tallies
        .map(
          (RegionTally tally) => RegionAvailability(
            region: tally.region,
            placeCount: tally.placeCount,
            maximumPlaceCount: maximum,
            // REQ102_17 - the gradient between green and grey is generated
            // from this, never picked per area.
            score: maximum == 0 ? 0 : tally.placeCount / maximum,
            foodCount: tally.foodCount,
            restaurantCount: tally.restaurantCount,
            landmarkCount: tally.landmarkCount,
          ),
        )
        .toList(growable: false);

    return FoodDistribution(
      regions: availability,
      maximumPlaceCount: maximum,
      matchingFoodCount: catalogue
          .where(
            (LocalFood food) =>
                (localFoodId == null || food.id == localFoodId) &&
                matchesFilter(food, filter),
          )
          .length,
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
    // Swipe Mode must not recommend a place the stored schedule confidently
    // says is closed now. Missing/malformed scraped hours remain visible as
    // unknown rather than being silently treated as closed.
    List<MapPin> eligiblePins = markers.pins;
    if (localFoodId != null && eligiblePins.isNotEmpty) {
      final Set<String> placeKeys = eligiblePins.map(_placeKeyForPin).toSet();
      final Map<String, List<OpeningHour>> hoursByPlace = await repository
          .openingHoursByPlace(placeKeys: placeKeys);
      final DateTime malaysiaNow = _malaysiaNow;
      eligiblePins = eligiblePins
          .where(
            (MapPin pin) => !OpeningHoursLogic.isConfidentlyClosedAt(
              hoursByPlace[_placeKeyForPin(pin)],
              malaysiaNow,
            ),
          )
          .toList(growable: false);
    }

    final List<MapPin> withDistance =
        fromLatitude == null || fromLongitude == null
        ? eligiblePins
        : eligiblePins
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

  /// The closest visible place serving [localFoodId] to the map's current
  /// exploration anchor. Swipe Mode uses this before loading its focused
  /// viewport; GPS is deliberately not used because tourists may be exploring
  /// a different state.
  Future<GeoPoint?> nearestFoodLocation({
    required int localFoodId,
    required double fromLatitude,
    required double fromLongitude,
  }) async {
    final List<Object> gathered = await Future.wait(<Future<Object>>[
      repository.foodOccurrences(),
      repository.openingHoursByPlace(),
    ]);
    final List<FoodOccurrence> occurrences =
        gathered[0] as List<FoodOccurrence>;
    final Map<String, List<OpeningHour>> hoursByPlace =
        gathered[1] as Map<String, List<OpeningHour>>;
    final DateTime malaysiaNow = _malaysiaNow;
    FoodOccurrence? nearest;
    double nearestDistance = double.infinity;
    for (final FoodOccurrence occurrence in occurrences) {
      if (occurrence.localFoodId != localFoodId) continue;
      final String key = occurrence.source == FoodOccurrenceSource.restaurant
          ? 'restaurant:${occurrence.sourceId}'
          : 'submittedLandmark:${occurrence.sourceId}';
      if (OpeningHoursLogic.isConfidentlyClosedAt(
        hoursByPlace[key],
        malaysiaNow,
      )) {
        continue;
      }
      final double distance = _distanceMetres(
        fromLatitude,
        fromLongitude,
        occurrence.latitude,
        occurrence.longitude,
      );
      if (distance >= nearestDistance) continue;
      nearest = occurrence;
      nearestDistance = distance;
    }
    return nearest == null
        ? null
        : GeoPoint(nearest.latitude, nearest.longitude);
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

    List<MapPin> members = await repository.map.clusterMembers(
      latitude: cluster.latitude,
      longitude: cluster.longitude,
      zoom: zoom,
      foodIds: foodIds,
    );
    if (localFoodId != null && members.isNotEmpty) {
      final Set<String> placeKeys = members.map(_placeKeyForPin).toSet();
      final Map<String, List<OpeningHour>> hoursByPlace = await repository
          .openingHoursByPlace(placeKeys: placeKeys);
      final DateTime malaysiaNow = _malaysiaNow;
      members = members
          .where(
            (MapPin pin) => !OpeningHoursLogic.isConfidentlyClosedAt(
              hoursByPlace[_placeKeyForPin(pin)],
              malaysiaNow,
            ),
          )
          .toList(growable: false);
    }
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
        thumbnailUrl: pin.thumbnailUrl,
        category: pin.category,
        rating: pin.rating,
        servedFoods: pin.servedFoods,
        priceRange: pin.priceRange,
        openNow: pin.openNow,
        distanceMetres: pin.distanceMetres,
      );

  DateTime get _malaysiaNow =>
      currentTime().toUtc().add(const Duration(hours: 8));

  static String _placeKeyForPin(MapPin pin) => pin.kind == MapPinKind.restaurant
      ? 'restaurant:${pin.referenceId}'
      : 'submittedLandmark:${pin.referenceId}';

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

    if (pin.kind == MapPinKind.restaurant) {
      return _restaurantPinDetail(pin, id, filter: filter, localFoodId: localFoodId);
    } else if (pin.kind == MapPinKind.landmark) {
      return _landmarkPinDetail(pin, id, filter: filter, localFoodId: localFoodId);
    }

    return pin;
  }

  Future<MapPin> _restaurantPinDetail(
    MapPin pin,
    int id, {
    ExplorationFilter filter = ExplorationFilter.none,
    int? localFoodId,
  }) async {
    final Restaurant? restaurant;
    final List<RestaurantItem> items;
    final Map<String, List<OpeningHour>> hours;
    try {
      final List<Object?> gathered = await Future.wait(<Future<Object?>>[
        repository.getRestaurantById(id),
        repository.getRestaurantItemsByRestaurantIds(<int>[id]),
        repository.openingHoursByPlace(placeKeys: <String>{'restaurant:$id'}),
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
      // The marker's small variant, kept: it is the same place, the card behind
      // the open sheet still wants it, and the sheet's own photo uses the
      // full-size URL above.
      thumbnailUrl: pin.thumbnailUrl,
      category: restaurant.category.isEmpty ? null : restaurant.category,
      rating: restaurant.rating ?? pin.rating,
      servedFoods: List<String>.unmodifiable(
        served.length > maximumServedFoods
            ? served.sublist(0, maximumServedFoods)
            : served,
      ),
      priceRange: _priceRangeOf(prices),
      openNow: openNow(hours['restaurant:$id']),
      distanceMetres: pin.distanceMetres,
    );
  }

  Future<MapPin> _landmarkPinDetail(
    MapPin pin,
    int id, {
    ExplorationFilter filter = ExplorationFilter.none,
    int? localFoodId,
  }) async {
    final SubmittedLandmark? landmark;
    try {
      landmark = await repository.getSubmittedLandmarkById(id);
    } catch (_) {
      return pin;
    }
    if (landmark == null) return pin;

    // A landmark's items are already in its items list. Filter them the same
    // way restaurant items are filtered.
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
    for (final LandmarkItem item in landmark.items) {
      final bool matches = wanted.contains(item.localFoodId);
      if (narrowed && !matches) continue;
      final String name = (nameById[item.localFoodId] ?? item.dish).trim();
      if (name.isNotEmpty && !served.contains(name)) served.add(name);
      final double? price = item.price;
      if (price != null && price > 0) prices.add(price);
    }

    return MapPin(
      referenceId: pin.referenceId,
      kind: pin.kind,
      latitude: pin.latitude,
      longitude: pin.longitude,
      label: landmark.name.isEmpty ? pin.label : landmark.name,
      weight: served.isEmpty ? pin.weight : served.length,
      imageUrl: landmark.imageUrl ?? pin.imageUrl,
      thumbnailUrl: pin.thumbnailUrl,
      category: landmark.category.isEmpty ? null : landmark.category,
      rating: pin.rating, // Landmarks don't have star ratings yet.
      servedFoods: List<String>.unmodifiable(
        served.length > maximumServedFoods
            ? served.sublist(0, maximumServedFoods)
            : served,
      ),
      priceRange: _priceRangeOf(prices),
      openNow: openNow(landmark.openingHours),
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
    thumbnailUrl: pin.thumbnailUrl,
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
  /// Returns:
  /// * null - **Unknown** (no records today, or any record is `DayStatus.unknown`)
  /// * true - **Opening** (at least one Open record covers the current local time)
  /// * false - **Closed** (all Open records are outside current time, or status is `closed`)
  static bool? openNow(List<OpeningHour>? hours) {
    if (hours == null || hours.isEmpty) return null;

    final DateTime now = DateTime.now();
    final Weekday today = Weekday.values[now.weekday - 1];
    final int minutes = now.hour * 60 + now.minute;

    // Check if a shift from yesterday is still running (past midnight).
    final Weekday yesterday = Weekday.values[(now.weekday + 5) % 7];
    final bool stillOpenFromYesterday = hours.any((OpeningHour h) {
      return h.day == yesterday &&
          h.status == DayStatus.open &&
          h.opensAt != null &&
          h.closesAt != null &&
          h.closesAt! < h.opensAt! &&
          minutes < h.closesAt!;
    });
    if (stillOpenFromYesterday) return true;

    final List<OpeningHour> todayRows = hours
        .where((OpeningHour hour) => hour.day == today)
        .toList(growable: false);

    // UNKNOWN: no usable records for today, or any record explicitly set to Unknown.
    if (todayRows.isEmpty ||
        todayRows.any((OpeningHour h) => h.status == DayStatus.unknown)) {
      return null;
    }

    for (final OpeningHour hour in todayRows) {
      if (hour.status == DayStatus.open) {
        final int? opensAt = hour.opensAt;
        final int? closesAt = hour.closesAt;
        if (opensAt == null || closesAt == null) continue;

        // OPENING: inside ANY valid operating period.
        // Also handles "starts today ends tomorrow" (closes < opens)
        final bool open = closesAt >= opensAt
            ? minutes >= opensAt && minutes < closesAt
            : minutes >= opensAt || minutes < closesAt;
        if (open) return true;
      }
    }

    // CLOSED: has records but none are currently Open.
    return false;
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

    // States, the place table, the food catalogue and the place-name search are
    // independent reads.
    //
    // The last of those used to be `repository.map.foodOccurrences()` - every
    // restaurant in Malaysia, every menu row, every landmark and every landmark
    // item, pulled down so that a keyword could be scored against some names.
    // It is now `map_place_search`, which applies the same ladder in Postgres
    // and answers with the twelve rows the list can show.
    final List<Object> gathered = await Future.wait(<Future<Object>>[
      regions(),
      repository.map.places(),
      repository.searchLocalFoods(keyword),
      repository.map.searchPlaceNames(needle, limit: maximumPlaceResults),
    ]);
    final List<Region> allRegions = gathered[0] as List<Region>;
    final List<MapPlace> catalogue = gathered[1] as List<MapPlace>;
    final List<LocalFood> foods = gathered[2] as List<LocalFood>;
    final List<MapPlaceHit> hits = gathered[3] as List<MapPlaceHit>;

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
    // Already scored, already ordered and already capped by Postgres. The
    // scores are the same numbers the Dart produced - 100 exact, 60 the name
    // starts with the keyword, 40 a word in it does, 20 it contains it - and
    // the same "one step below a named place" adjustment is applied here, so a
    // restaurant called "Penang Village" still cannot outrank Penang.
    for (final MapPlaceHit hit in hits) {
      scored.add(
        _ScoredPlace(
          hit.score - 1,
          PlaceSuggestion(
            name: hit.name,
            subtitle: hit.isRestaurant ? 'Restaurant' : 'Submitted landmark',
            kind: PlaceKind.address,
            latitude: hit.latitude,
            longitude: hit.longitude,
            zoom: addressZoom,
            referenceId: hit.referenceId,
            isRestaurant: hit.isRestaurant,
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
  /// The ladder [_score] applies is also the one `map_place_search` applies -
  /// `_scoreExact` / `_scorePrefix` / `_scoreWord` / `_scoreContains` are the
  /// 100 / 60 / 40 / 20 the function returns. If either changes, both have to.
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

/// One search hit with the score that ordered it.
class _ScoredPlace {
  const _ScoredPlace(this.score, this.suggestion);

  final int score;
  final PlaceSuggestion suggestion;
}
