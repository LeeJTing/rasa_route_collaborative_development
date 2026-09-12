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
import 'package:string_similarity/string_similarity.dart';

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

  /// The same, for the "Local Food" half - and the same ids the search layer
  /// asks the map about, so a keyword can never turn into an open-ended query.
  static const int maximumFoodResults = 12;

  /// How close a dish's name has to be before the keyword is taken to mean it.
  ///
  /// **Measured, not guessed.** Every name in the live catalogue was scored
  /// against a set of real typos and the number chosen from what it did to
  /// them:
  ///
  /// | keyword | intended dish | score |
  /// |---|---|---|
  /// | `teh tarikk` | Teh Tarik | 0.93 |
  /// | `rendag daging` | Rendang Daging | 0.87 |
  /// | `murtabk` | Murtabak | 0.77 |
  /// | `nasi lemka` | Nasi Lemak | 0.75 |
  /// | `cendl` | Cendol | 0.67 |
  /// | `chiken rice` | Hainanese Chicken Rice | 0.57 |
  ///
  /// Each of those ranks first for its keyword, or first among equals -
  /// `chiken rice` puts Chicken Rice Ball and Claypot Chicken Rice above the
  /// Hainanese one, which is three right answers rather than a wrong one.
  ///
  /// 0.55 sits just under the weakest of them and just over what has to go.
  /// Raising it to 0.6 loses that Hainanese Chicken Rice at 0.57. Lowering it
  /// to 0.5 admits the band between - Kuih Talam and Kuih Lopes for a search
  /// for `kuih lapis`, Gulai Kambing for `gulai ayam` - which are other dishes,
  /// not other spellings.
  ///
  /// Pure nonsense needs no threshold at all: `asdfghjkl` and `qwerty` score 0
  /// against every name, because two strings with no bigram in common share
  /// nothing for Dice to count.
  static const double foodMatchThreshold = 0.55;

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
    /// The dishes to constrain to, when the caller has already worked them out.
    ///
    /// Overrides [filter] and [localFoodId] rather than narrowing them - the
    /// search layer asks for "places serving any of these dishes" and must not
    /// inherit the filter chips, because a keyword is a different question from
    /// the one the chips are asking.
    List<int>? foodIds,
    double? south,
    double? west,
    double? north,
    double? east,
    double? fromLatitude,
    double? fromLongitude,
    double zoom = detailedViewZoom,
    int? limit,
    /// What a keyword is asking about, grouped into the same grid as the
    /// filter's answer rather than queried separately.
    MapSearchSelection search = MapSearchSelection.none,
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
    final List<int>? resolvedFoodIds =
        foodIds ??
        await _foodIdsFor(filter: filter, localFoodId: localFoodId);

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
      foodIds: resolvedFoodIds,
      limit: cap,
      search: search,
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

  /// The search half of a marker query, built from what a keyword matched.
  ///
  /// **There is no second query any more.** The search layer used to be its own
  /// call to `map_food_markers`, which meant two grids over overlapping sets of
  /// places and two badges landing on top of each other - 100 here, 5 there,
  /// for places standing in the same street. Postgres now groups the filtered
  /// map and the search results together, once, and this is what tells it which
  /// places the keyword is asking about.
  ///
  /// Two ways in, because a keyword can name two different things:
  ///
  ///  * a **place**, by name - `map_place_search` has already answered, so the
  ///    ids cost nothing to collect;
  ///  * a **dish**, by name - Restaurant/Landmark -> Local Food, the same
  ///    relationship the filters use, which is why "nasi lemak" reaches the
  ///    stalls that sell it.
  ///
  /// Empty when the keyword matched nothing, and then the marker query behaves
  /// exactly as it did before search existed.
  static MapSearchSelection searchSelectionFor(
    ExplorationSearchResults results,
  ) {
    final List<int> foodIds = <int>[
      for (final LocalFood food in results.foods) food.id,
    ];
    final List<int> restaurantIds = <int>[];
    final List<int> landmarkIds = <int>[];

    for (final PlaceSuggestion place in results.places) {
      if (!place.isPlaceOnTheMap) continue;
      final int? id = int.tryParse(place.referenceId!);
      if (id == null) continue;
      if (place.isRestaurant) {
        restaurantIds.add(id);
      } else {
        landmarkIds.add(id);
      }
    }

    if (foodIds.isEmpty && restaurantIds.isEmpty && landmarkIds.isEmpty) {
      return MapSearchSelection.none;
    }
    return MapSearchSelection(
      foodIds: List<int>.unmodifiable(foodIds),
      restaurantIds: List<int>.unmodifiable(restaurantIds),
      landmarkIds: List<int>.unmodifiable(landmarkIds),
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
  /// [foodIds] overrides [filter] and [localFoodId], for a cluster that belongs
  /// to the search layer: it was drawn from the dishes a keyword matched, and
  /// it has to be opened by asking about those same dishes. Opening it against
  /// the filter chips instead would probe a different set of places and hand
  /// back a split zoom that does not split *this* badge.
  Future<ClusterExpansion> expandCluster(
    MapCluster cluster, {
    required double zoom,
    ExplorationFilter filter = ExplorationFilter.none,
    int? localFoodId,
    List<int>? foodIds,
    MapSearchSelection search = MapSearchSelection.none,
  }) async {
    final List<int>? resolvedFoodIds =
        foodIds ??
        await _foodIdsFor(filter: filter, localFoodId: localFoodId);

    final ({double? splitZoom, int memberCount}) probe = await repository.map
        .clusterSplitZoom(
          latitude: cluster.latitude,
          longitude: cluster.longitude,
          zoom: zoom,
          maximumZoom: maximumZoom,
          foodIds: resolvedFoodIds,
          search: search,
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
      foodIds: resolvedFoodIds,
      search: search,
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
        thumbnailUrl: pin.thumbnailUrl,
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

    // The same chips produce the same ids every time, and this is asked on
    // every pan. Resolve once per filter selection rather than walking the
    // catalogue again for each load.
    //
    // Sorted, because a group is now a set: ticking Lunch then Breakfast and
    // ticking Breakfast then Lunch are the same filter and must not be cached
    // twice under two different keys.
    final String key = ExplorationFilterGroup.values
        .map((ExplorationFilterGroup group) {
          final List<String> chosen = filter.selectionFor(group).toList()
            ..sort();
          return chosen.join(',');
        })
        .join('|');
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
    thumbnailUrl: pin.thumbnailUrl,
    category: pin.category,
    rating: pin.rating,
    servedFoods: pin.servedFoods,
    priceRange: pin.priceRange,
    openNow: pin.openNow,
    distanceMetres: distanceMetres,
    // Carried, or every search result would lose its colour the moment the
    // tourist's position is known and distances are filled in.
    isSearchResult: pin.isSearchResult,
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

  /// Does [food] survive the four filter groups? An empty group is no
  /// constraint. A dish marked `All-Day Dining` satisfies every meal filter -
  /// it is, by definition, served at all of them.
  ///
  /// **Options within a group are OR; the groups are AND.** Breakfast *or*
  /// Lunch, *and* Malay - which is the only reading that makes ticking two
  /// chips in one row useful, since no dish is two meals at once and an AND
  /// there would answer nothing every time.
  ///
  /// Note what is being asked the question: a [LocalFood], never a restaurant.
  /// Meal, category, taste and type are the dish's attributes, and a place
  /// reaches the map by serving a dish that survives this - restaurants and
  /// landmarks carry no meal of their own (C2 - C5).
  bool matchesFilter(LocalFood food, ExplorationFilter filter) {
    final Set<String> meals = filter.meals;
    if (meals.isNotEmpty) {
      final String dishMeal = food.mealType.toLowerCase().trim();
      final bool matches =
          dishMeal.contains('all-day') ||
          meals.any(
            (String meal) => meal.toLowerCase().trim() == dishMeal,
          );
      if (!matches) return false;
    }

    final Set<String> categories = filter.categories;
    if (categories.isNotEmpty) {
      final String dishCategory = food.category.toLowerCase().trim();
      final bool matches = categories.any(
        (String category) => category.toLowerCase().trim() == dishCategory,
      );
      if (!matches) return false;
    }

    final Set<String> types = filter.types;
    if (types.isNotEmpty) {
      final String dishType = food.foodType.toLowerCase().trim();
      final bool matches = types.any(
        (String type) => type.toLowerCase().trim() == dishType,
      );
      if (!matches) return false;
    }

    final Set<String> tastes = filter.tastes;
    if (tastes.isNotEmpty) {
      // OR on both sides: any chosen taste, against any taste the dish has.
      final bool matches = food.tastes.any((String value) {
        final String dishTaste = value.toLowerCase().trim();
        return tastes.any(
          (String taste) => taste.toLowerCase().trim() == dishTaste,
        );
      });
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
  /// Search answers with what is on the map, and nothing else narrows it:
  /// the active filter is deliberately not a parameter. Filters drive the
  /// heatmap and the pin list; a keyword is the other way in, and a tourist who
  /// types a restaurant's name expects to find it whether or not it serves
  /// something the filter chips happen to be asking for.
  Future<ExplorationSearchResults> search(String keyword) async {
    // Normalised, not merely lowercased: "nasi-lemak", "char_kway_teow" and
    // "cHarKwayteOW" are all somebody asking for a dish, and the punctuation
    // they reached for is not part of the question.
    final String needle = searchNormalise(keyword);
    if (needle.isEmpty) return ExplorationSearchResults.empty;

    // What the *database* is asked. An abbreviation is the one case where the
    // text as typed can match nothing at all - no restaurant is called "ckt" -
    // so a whole-name synonym is spent before the request goes out. Anything
    // else is sent as typed: one request per keyword either way, which is the
    // point of resolving this here rather than asking twice.
    final String? alias = foodSynonyms[needle];
    final String placeNeedle = alias == null ? needle : searchNormalise(alias);

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
      repository.getLocalFoods(),
      repository.map.searchPlaceNames(placeNeedle, limit: maximumPlaceResults),
    ]);
    final List<Region> allRegions = gathered[0] as List<Region>;
    final List<MapPlace> catalogue = gathered[1] as List<MapPlace>;
    final List<LocalFood> allFoods = gathered[2] as List<LocalFood>;
    final List<MapPlaceHit> hits = gathered[3] as List<MapPlaceHit>;

    // REQ102_30 - the "Local Food" group, scored here rather than read back
    // from the repository's plain `contains`.
    //
    // Deciding that "ckt" and "Char Kuey Teow" are the same dish is a rule,
    // and rules live in this layer. The catalogue itself is the same cached
    // 368 rows either way, so this costs nothing extra to read - and 368 names
    // is small enough that fuzzy matching them on the phone is cheaper than
    // asking Postgres would be.
    //
    // Threshold, then sort, then cap: a keyword that means a dish produces a
    // handful of ids, best first, and those are the ids the map is asked about.
    final List<_ScoredFood> scoredFoods = <_ScoredFood>[];
    for (final LocalFood food in allFoods) {
      final double score = foodMatchScore(needle, food.name);
      if (score < foodMatchThreshold) continue;
      scoredFoods.add(_ScoredFood(score, food));
    }
    scoredFoods.sort((_ScoredFood a, _ScoredFood b) {
      final int byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      // Same closeness: the shorter name is the more direct answer, then
      // alphabetically so the order never depends on catalogue order.
      final int byLength = a.food.name.length.compareTo(b.food.name.length);
      if (byLength != 0) return byLength;
      return a.food.name.compareTo(b.food.name);
    });
    final List<LocalFood> foods = List<LocalFood>.unmodifiable(
      scoredFoods.take(maximumFoodResults).map((_ScoredFood e) => e.food),
    );

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
  ///
  /// **They are out of step right now, and knowingly so.** The squashed rungs
  /// and the synonym expansion below are client-side only until the pending
  /// migration lands, because the Supabase connector dropped out before the SQL
  /// could be applied. Regions, the place table and the food catalogue are
  /// matched here and get the smarter reading immediately; restaurant and
  /// landmark names are matched in Postgres and keep the plain one until then.
  /// The rungs a name can reach are unchanged either way, so nothing that
  /// matched before stops matching - the two halves simply admit different
  /// spellings until the SQL catches up.
  ///
  /// [needle] arrives normalised; the candidates are normalised here. Both
  /// sides are then expanded through [searchVariants], which is what lets a
  /// tourist's spelling meet the catalogue's: one map of synonyms applied to
  /// whichever side happens to be holding the odd spelling.
  static int _score(String needle, List<String> candidates) {
    if (needle.isEmpty) return 0;
    final List<String> typedForms = searchVariants(needle);
    int best = 0;
    for (final String candidate in candidates) {
      for (final String value in searchVariants(candidate)) {
        if (value.isEmpty) continue;
        final String squashedValue = searchSquash(value);
        for (final String typed in typedForms) {
          if (typed.isEmpty) continue;
          // The squashed forms are the same two strings with the spaces gone,
          // so "charkwayteow" reaches "Char Kway Teow". They are only ever
          // consulted alongside the spaced comparison, never instead of it,
          // so a match that respected the words still wins.
          final String squashedTyped = searchSquash(typed);
          if (value == typed || squashedValue == squashedTyped) {
            best = _scoreExact;
          } else if (value.startsWith(typed) ||
              squashedValue.startsWith(squashedTyped)) {
            if (best < _scorePrefix) best = _scorePrefix;
          } else if (_startsAWord(value, typed)) {
            // "alor" finding "Jalan Alor" - a word boundary is a much better
            // signal than a substring landing mid-word.
            if (best < _scoreWord) best = _scoreWord;
          } else if (value.contains(typed) ||
              squashedValue.contains(squashedTyped)) {
            if (best < _scoreContains) best = _scoreContains;
          }
          if (best == _scoreExact) break;
        }
        if (best == _scoreExact) break;
      }
      if (best == _scoreExact) break;
    }
    return best;
  }

  // ---------------------------------------------------------------------------
  // Text normalisation and local-food synonyms (REQ102_30, REQ102_31)
  // ---------------------------------------------------------------------------

  /// What "the same text" means for search.
  ///
  /// Case folded, every run of punctuation - hyphens, underscores, apostrophes,
  /// dots, brackets - reduced to a single space, and the ends trimmed. So
  /// `nasi-lemak`, `NASI LEMAK` and `nasi_lemak  ` are one keyword, and a
  /// keyword of nothing but punctuation is empty rather than unanswerable.
  ///
  /// Letters and digits are kept by category rather than by an `a-z0-9` range,
  /// so an accented name is folded, not gutted.
  static String searchNormalise(String value) => value
      .toLowerCase()
      .replaceAll(_punctuation, ' ')
      .trim();

  /// [searchNormalise] with the spaces taken out too.
  ///
  /// The last resort of the ladder: it is what makes `cHarKwayteOW` findable,
  /// and it is deliberately blind to word boundaries, which is why a match
  /// found this way never scores above one found with them.
  static String searchSquash(String value) =>
      searchNormalise(value).replaceAll(' ', '');

  static final RegExp _punctuation = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

  /// Whole-name local-food synonyms: what tourists type, against what the
  /// catalogue calls the dish (REQ102_30).
  ///
  /// Applied to **both** sides of a comparison, so the direction of an entry
  /// does not matter - `ckt` and `Char Kuey Teow` both arrive at
  /// `char kway teow` and meet there. Keys are normalised form.
  static const Map<String, String> foodSynonyms = <String, String>{
    'ckt': 'char kway teow',
    'bkt': 'bak kut teh',
    'ytf': 'yong tau foo',
    'abc': 'ais kacang',
    'ice kacang': 'ais kacang',
    'poh piah': 'popiah',
    'coconut rice': 'nasi lemak',
    'chicken rice': 'nasi ayam',
    'fried rice': 'nasi goreng',
    'fried noodles': 'mee goreng',
    'pulled tea': 'teh tarik',
    'shaved ice': 'ais kacang',
  };

  /// Word-level spelling variants, applied word by word to both sides.
  ///
  /// Malaysian dish names are transliterations and have no single spelling -
  /// `kuey`, `koay` and `kway` are the same syllable, and the catalogue can
  /// only pick one of them. Each entry folds a variant onto the spelling the
  /// catalogue uses; because it is applied to both sides, an entry read the
  /// wrong way round still brings the two together.
  static const Map<String, String> foodWordSynonyms = <String, String>{
    'kuey': 'kway',
    'koay': 'kway',
    'kueh': 'kuih',
    'kue': 'kuih',
    'chendol': 'cendol',
    'chanai': 'canai',
    'prata': 'canai',
    'mie': 'mee',
    'mi': 'mee',
    'sate': 'satay',
    'satey': 'satay',
    'wonton': 'wantan',
    'wanton': 'wantan',
    'maggie': 'maggi',
    'bihun': 'bee hoon',
    'mihun': 'bee hoon',
    'kwetiau': 'kway teow',
    'kuetiau': 'kway teow',
    'kari': 'curry',
  };

  /// [value] as every spelling the synonym tables can reach from it.
  ///
  /// Always contains the normalised original first, so nothing a plain reading
  /// would have matched is lost by expanding it.
  static List<String> searchVariants(String value) {
    // The same catalogue names are normalised against every keyword, and the
    // normalisation is regex work. Cached, each name is folded once for the
    // life of the app rather than once per name per search - measured at a
    // little under half the cost of a full-catalogue sweep.
    final List<String>? cached = _variantCache[value];
    if (cached != null) return cached;

    final String base = searchNormalise(value);
    if (base.isEmpty) {
      _remember(value, const <String>[]);
      return const <String>[];
    }

    final List<String> variants = <String>[base];

    void add(String candidate) {
      if (candidate.isNotEmpty && !variants.contains(candidate)) {
        variants.add(candidate);
      }
    }

    final String? whole = foodSynonyms[base];
    if (whole != null) add(searchNormalise(whole));

    final List<String> words = base.split(' ');
    final List<String> folded = <String>[
      for (final String word in words) foodWordSynonyms[word] ?? word,
    ];
    add(folded.join(' '));

    // A phrase whose words were folded may itself be a whole-name synonym -
    // "char kuey teow" folds to "char kway teow" and stops there, but "fried
    // noodle" spellings reach their entry only after folding.
    final String? foldedWhole = foodSynonyms[folded.join(' ')];
    if (foldedWhole != null) add(searchNormalise(foldedWhole));

    final List<String> result = List<String>.unmodifiable(variants);
    _remember(value, result);
    return result;
  }

  static void _remember(String value, List<String> variants) {
    // Room for the whole food catalogue plus a long session's keywords. Past
    // that the keywords are the growth, so the whole thing goes and the
    // catalogue pays to be folded once more.
    if (_variantCache.length > 512) _variantCache.clear();
    _variantCache[value] = variants;
  }

  static final Map<String, List<String>> _variantCache = <String, List<String>>{};

  /// How alike two dish names are, 0..1, over every spelling of both.
  ///
  /// Dice coefficient on bigrams, from `string_similarity`. Two characters
  /// swapped costs a couple of bigrams rather than everything, which is what a
  /// typo actually is - `nasi lemka` keeps six of Nasi Lemak's eight.
  ///
  /// **Both sides go through [searchVariants] first**, and that is not
  /// optional: `compareTwoStrings` strips whitespace but does **not** fold case
  /// or punctuation, so `Nasi Lemak` against `nasi-lemak` would score short of
  /// 1 on nothing but capital letters. Normalising first also means the synonym
  /// tables reach the fuzzy stage - `ckt` is compared as `char kway teow`.
  ///
  /// Asked of the **368-row cached catalogue only**. Restaurant and landmark
  /// names are matched in Postgres, by a trigram index over 15,018 rows, and
  /// are never downloaded to do it.
  /// Two readings of "alike", and the better one wins.
  ///
  /// **Whole name against whole name** is the plain comparison, and it is the
  /// right one for a keyword that names the dish. It has one failure, and it is
  /// systematic: a short keyword is punished for the length of the name it is
  /// looking for. `maggie` against `Maggi Goreng` scores 0.53 - under the
  /// threshold - purely because `goreng` is in the name and not in the keyword.
  /// That is not a weak match, it is a match against the wrong unit.
  ///
  /// **Word against word** is the second reading, and it fixes exactly that:
  /// `maggie` against `maggi` is 0.89. See [_wordAlignedSimilarity] for what
  /// keeps it honest.
  static double foodSimilarity(String needle, String name) {
    double best = 0;
    for (final String typed in searchVariants(needle)) {
      for (final String candidate in searchVariants(name)) {
        final double whole = StringSimilarity.compareTwoStrings(
          typed,
          candidate,
        );
        if (whole > best) best = whole;

        final double aligned =
            _wordAlignedSimilarity(typed, candidate) * _wordAlignedWeight;
        if (aligned > best) best = aligned;
      }
    }
    return best;
  }

  /// Every word of the keyword against its best word in the name, scored by the
  /// **worst** of those matches.
  ///
  /// The worst, not the average, because an average lets one strong word carry
  /// a weak one: `nasi lemak` against `Gulai Lemak Itik` averages 0.65 on the
  /// strength of `lemak` alone, and that is not a dish anybody searching for
  /// nasi lemak wants to be shown. The worst match asks "did every word of the
  /// keyword find a home in this name", which is the question.
  ///
  /// Returns 0 unless every word cleared [foodWordMatchFloor]. A word that only
  /// half-matches is not an alignment, and reading it as one is how `nasilemak`
  /// starts finding `Gulai Lemak Itik` through `lemak` at 0.67.
  ///
  /// One word against one word returns 0 as well: that *is* the whole-name
  /// comparison, [foodSimilarity] has already counted it, and counting it again
  /// here would only apply the discount below to it.
  static double _wordAlignedSimilarity(String typed, String candidate) {
    final List<String> typedWords = typed.split(' ')
      ..removeWhere((String word) => word.isEmpty);
    final List<String> nameWords = candidate.split(' ')
      ..removeWhere((String word) => word.isEmpty);
    if (typedWords.isEmpty || nameWords.isEmpty) return 0;
    if (typedWords.length == 1 && nameWords.length == 1) return 0;

    double worst = 1;
    for (final String word in typedWords) {
      double best = 0;
      for (final String other in nameWords) {
        // `compareTwoStrings` answers 0 for anything under two characters
        // unless the two are equal, and the catalogue has words that short -
        // `Kopi O`, `Teh C Peng Special`. Equality is checked first so those
        // still count as the perfect matches they are.
        final double score = word == other
            ? 1
            : StringSimilarity.compareTwoStrings(word, other);
        if (score > best) best = score;
      }
      if (best < worst) worst = best;
      if (worst < foodWordMatchFloor) return 0;
    }
    return worst;
  }

  /// How well a single word has to match before word-by-word alignment counts
  /// as an alignment at all.
  ///
  /// Measured on the live catalogue. Without it, `nasilemak` reaches
  /// `Gulai Lemak Itik`, `Udang Masak Lemak Nenas` and four more: the word
  /// `lemak` matches at 0.67, and nothing else in those names has to match at
  /// all. 0.75 sits above that and below every genuine word-level match in the
  /// test set - `maggie`/`maggi` 0.89, `canaii`/`canai` 0.89,
  /// `hokien`/`hokkien` 0.91.
  static const double foodWordMatchFloor = 0.75;

  /// A word-by-word match is worth a little less than the same closeness across
  /// the whole name, so a dish that answers the keyword outright always sorts
  /// above one that only answers it a word at a time.
  static const double _wordAlignedWeight = 0.95;

  /// How well [name] answers [needle], 0..1. Below [foodMatchThreshold] the
  /// keyword is taken not to mean this dish at all.
  ///
  /// **Exact and synonym matching first, similarity second.** The ladder runs
  /// before the fuzzy stage and sets a floor under whatever it found, so a
  /// dish the tourist spelled correctly can never be beaten by one they did
  /// not: an exact name is 1.0, a prefix 0.90, a word 0.80, a substring 0.70.
  /// Everything the ladder scored 0 falls through to [foodSimilarity].
  ///
  /// A ladder hit still takes the *higher* of its floor and its own similarity,
  /// so two dishes that both contain the keyword order by how close they are
  /// rather than tying forever - `Cendol` beats `Durian Cendol` for `cendol`.
  ///
  /// The floors sit above the threshold by construction, so filtering never
  /// removes a literal match. It only ever removes a guess.
  static double foodMatchScore(String needle, String name) {
    final double floor = switch (_score(needle, <String>[name])) {
      _scoreExact => 1.0,
      _scorePrefix => 0.90,
      _scoreWord => 0.80,
      _scoreContains => 0.70,
      _ => 0.0,
    };
    final double similarity = foodSimilarity(needle, name);
    return similarity > floor ? similarity : floor;
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

/// The "Local Food" half of a search result, carrying the score that ordered
/// it. The score is a search detail and stops here - the caller receives plain
/// [LocalFood]s, best answer first.
class _ScoredFood {
  const _ScoredFood(this.score, this.food);

  /// 0..1. Not the place ladder's 0/20/40/100 - see
  /// `MapExplorationLogic.foodMatchScore` for how the two relate.
  final double score;
  final LocalFood food;
}
