import '../../domain_model/exploration_filter.dart';
import '../../domain_model/exploration_search.dart';
import '../../domain_model/food_distribution.dart';
import '../../domain_model/local_food.dart';
import '../../domain_model/map.dart';
import '../../domain_model/map_place.dart';
import '../../domain_model/opening_hour.dart';
import '../../domain_model/region.dart';
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
  // How many pins the detailed map draws
  // ===========================================================================
  //
  // A viewport at state zoom can contain several thousand restaurants. Drawing
  // them all is unreadable, and building them all costs a frame, so the map
  // draws the [pinLimitForZoom] places nearest the centre of the screen and
  // reports the rest as hidden rather than pretending they do not exist.
  //
  // The cap rises with zoom instead of staying fixed. Each zoom level quarters
  // the ground area on screen, so a larger cap deeper in is still *fewer*
  // markers per square kilometre - and a tourist who has zoomed to a street has
  // asked for that level of detail. The numbers are marker counts a phone can
  // still be read through, not a hardware limit.

  /// 7.5 - 9: a whole state fills the screen.
  static const int pinLimitState = 80;

  /// 9 - 11: a district or a conurbation.
  static const int pinLimitDistrict = 150;

  /// 11 - 13: a town or a city centre.
  static const int pinLimitCity = 250;

  /// 13 - 16: a neighbourhood.
  static const int pinLimitNeighbourhood = 400;

  /// 16 and in: individual streets, where every pin is separately tappable.
  static const int pinLimitStreet = 600;

  /// The zoom at which restaurant pins start being drawn at all.
  ///
  /// Below this the detailed map is tiles and the country mask only - the way a
  /// general-purpose map shows no business pins while a whole state is on
  /// screen. Measured rather than picked: a tile map covers
  /// `360 / (256 * 2^zoom)` degrees per pixel, so on a 390pt-wide phone zoom 11
  /// spans 0.27 degrees, about 30 km - a city and its outskirts. The same
  /// screen at zoom 9 spans 120 km, where a marker is a smear the size of a
  /// town and tapping the right one is guesswork.
  static const double pinMinimumZoom = 11;

  /// Pins already on screen survive down to here before being dropped.
  ///
  /// Without the gap, a pinch that comes to rest on the threshold strobes the
  /// whole marker layer. 0.3 is well under one press of the zoom buttons
  /// ([zoomStep] is 1), so "-" still hides them in a single tap.
  static const double pinHideZoom = pinMinimumZoom - 0.3;

  /// Whether pins belong on screen at [zoom].
  ///
  /// **A dish in the Target Frame or a searched food is exempt** - pass its
  /// [localFoodId] and the answer is always yes. Swipe Mode (REQ103_8) asks
  /// "where can I eat this", and the honest answer is every place that serves
  /// it, at whatever zoom the tourist is looking from. The threshold exists to
  /// declutter a general browse, not to hide an answer somebody asked for.
  ///
  /// [pinsAlreadyShown] applies the hysteresis: pins appear at
  /// [pinMinimumZoom] and are kept until [pinHideZoom].
  static bool pinsVisibleAtZoom(
    double zoom, {
    int? localFoodId,
    bool pinsAlreadyShown = false,
  }) {
    if (localFoodId != null) return true;
    return zoom >= (pinsAlreadyShown ? pinHideZoom : pinMinimumZoom);
  }

  /// How many pins the detailed map may draw at [zoom].
  ///
  /// The thresholds reuse the zoom levels the rest of the module already names:
  /// [cityZoom] is where a city search settles, [addressZoom] where a street
  /// address does.
  ///
  /// The two rungs below [pinMinimumZoom] are not dead: a Target Frame dish
  /// skips the threshold but still needs a cap, and at country zoom that is
  /// exactly the rung it lands on.
  static int pinLimitForZoom(double zoom) {
    if (zoom < 9) return pinLimitState;
    if (zoom < 11) return pinLimitDistrict;
    if (zoom < cityZoom) return pinLimitCity;
    if (zoom < addressZoom) return pinLimitNeighbourhood;
    return pinLimitStreet;
  }

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

  /// REQ102_32 - the restaurant and submitted-landmark pins drawn on the
  /// detailed map view.
  ///
  /// With [localFoodId] set, only the places serving that dish are pinned;
  /// otherwise every place serving anything that survives [filter] is.
  ///
  /// Two things bound the answer, and they are different:
  ///
  ///  * the **viewport box** ([south] / [west] / [north] / [east]) decides what
  ///    is even a candidate - a place off screen is not on the map;
  ///  * the **zoom** decides how many of those candidates are drawn, through
  ///    [pinLimitForZoom]. Pass [limit] to override it.
  ///
  /// When more places match than the cap allows, the ones kept are those
  /// nearest the centre of the viewport - what the tourist is looking at -
  /// rather than whichever the occurrence list happened to reach first. The
  /// number left out travels back in [MapPinPage.hiddenCount] so the map can
  /// say "zoom in for the rest" instead of quietly losing them.
  ///
  /// **This is where REQ103_8 lands.** The food resting in the Target Frame
  /// becomes [localFoodId], and the pins it produces are the ones that appear
  /// on the detailed map.
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
    // The zoom gate, before anything is fetched or counted: below it there are
    // no pins to draw, so there is no reason to read a row. A Target Frame dish
    // is exempt - see [pinsVisibleAtZoom].
    //
    // The floor here is [pinHideZoom], the permissive end of the hysteresis.
    // Deciding when pins first *appear* belongs to whoever is driving the
    // camera; refusing to answer below the point where they would be dropped
    // anyway is the hard rule, and it holds for every caller.
    if (localFoodId == null && zoom < pinHideZoom) {
      return MapPinPage.hiddenByZoom;
    }

    final int cap = limit ?? pinLimitForZoom(zoom);
    // Catalogue and occurrences are independent reads, so they go together;
    // cached, they cost nothing at all on a pan. Opening hours deliberately do
    // *not* join them - which places need hours is not known until the viewport
    // and the filter have been applied, and asking for all of them is a read
    // seven times the size of the restaurant table.
    final List<Object> gathered = await Future.wait(<Future<Object>>[
      repository.getLocalFoods(),
      repository.map.foodOccurrences(),
    ]);
    final List<LocalFood> catalogue = gathered[0] as List<LocalFood>;
    final List<FoodOccurrence> rawOccurrences =
        gathered[1] as List<FoodOccurrence>;

    final Map<int, String> nameById = <int, String>{
      for (final LocalFood food in catalogue) food.id: food.name,
    };
    final Set<int> matchingIds = catalogue
        .where(
          (LocalFood food) =>
              (localFoodId == null || food.id == localFoodId) &&
              matchesFilter(food, filter),
        )
        .map((LocalFood food) => food.id)
        .toSet();

    final List<FoodOccurrence> occurrences = _resolve(
      rawOccurrences,
      catalogue,
    );

    // A dish only has to match the catalogue when the tourist is actually
    // looking for one - a filter is active or a specific dish search is set.
    // An unresolved submitted landmark (free-text dish, `localFoodId` 0) still
    // has valid coordinates, so with nothing filtering the map it deserves a
    // pin; it just cannot honestly be matched against a criterion it was never
    // checked against, so it is excluded the moment a criterion exists. This
    // is deliberately different from `distribution()`, where an unmatched dish
    // counting by no state is the honest outcome for a diversity score.
    final bool requiresCatalogueMatch =
        localFoodId != null || filter.selectionCount > 0;

    // One pin per place, gathering every matching dish served there.
    final Map<String, _PinBuilder> byPlace = <String, _PinBuilder>{};
    for (final FoodOccurrence occurrence in occurrences) {
      if (requiresCatalogueMatch &&
          !matchingIds.contains(occurrence.localFoodId)) {
        continue;
      }
      if (south != null && occurrence.latitude < south) continue;
      if (north != null && occurrence.latitude > north) continue;
      if (west != null && occurrence.longitude < west) continue;
      if (east != null && occurrence.longitude > east) continue;

      final String key = '${occurrence.source.name}:${occurrence.sourceId}';
      // Deliberately *not* capped here. The cap is applied after every
      // candidate is known, because a count that stopped at the cap could only
      // ever report the cap - which is how a map ends up lying about how much
      // it is not showing.
      byPlace
          .putIfAbsent(key, () => _PinBuilder(occurrence))
          .add(occurrence, nameById[occurrence.localFoodId]);
    }

    final List<_PinCandidate> candidates = <_PinCandidate>[];
    // The middle of the viewport when there is one, the tourist otherwise.
    final double? centreLatitude = south != null && north != null
        ? (south + north) / 2
        : fromLatitude;
    final double? centreLongitude = west != null && east != null
        ? (west + east) / 2
        : fromLongitude;
    for (final MapEntry<String, _PinBuilder> entry in byPlace.entries) {
      candidates.add(
        _PinCandidate(
          entry.key,
          entry.value,
          centreLatitude == null || centreLongitude == null
              ? 0
              : _distanceMetres(
                  centreLatitude,
                  centreLongitude,
                  entry.value.first.latitude,
                  entry.value.first.longitude,
                ),
        ),
      );
    }

    final int totalInView = candidates.length;
    if (totalInView > cap) {
      // Distance was measured once per place above, so this is a plain sort on
      // a number rather than tens of thousands of repeated haversines.
      candidates.sort(
        (_PinCandidate a, _PinCandidate b) =>
            a.fromCentre.compareTo(b.fromCentre),
      );
    }
    final List<_PinCandidate> drawn = totalInView > cap
        ? candidates.sublist(0, cap)
        : candidates;

    // Now that the drawn pins are known, and only now, fetch the hours for
    // them - at most [cap] places rather than every place in the country.
    final Map<String, List<OpeningHour>> hours = await repository.map
        .openingHours(
          placeKeys: drawn
              .map((_PinCandidate candidate) => candidate.key)
              .toSet(),
        );

    return MapPinPage(
      pins: List<MapPin>.unmodifiable(
        drawn.map(
          (_PinCandidate candidate) => candidate.builder.build(
            openNow: _openNow(hours[candidate.key]),
            distanceMetres: fromLatitude == null || fromLongitude == null
                ? null
                : _distanceMetres(
                    fromLatitude,
                    fromLongitude,
                    candidate.builder.first.latitude,
                    candidate.builder.first.longitude,
                  ),
          ),
        ),
      ),
      totalInView: totalInView,
      limit: cap,
    );
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
    final Set<String> seenAddresses = <String>{};
    for (final FoodOccurrence occurrence in occurrences) {
      final int score = _score(needle, <String>[occurrence.placeName]);
      if (score == 0) continue;
      final String key = '${occurrence.source.name}:${occurrence.sourceId}';
      if (!seenAddresses.add(key)) continue;
      scored.add(
        _ScoredPlace(
          // One step below a named place: a restaurant called "Penang Village"
          // must not outrank Penang.
          score - 1,
          PlaceSuggestion(
            name: occurrence.placeName,
            subtitle: occurrence.source == FoodOccurrenceSource.restaurant
                ? 'Restaurant'
                : 'Submitted landmark',
            kind: PlaceKind.address,
            latitude: occurrence.latitude,
            longitude: occurrence.longitude,
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

/// A place that qualified for a pin, with how far it sits from the middle of
/// the viewport - the key the zoom cap sorts on.
class _PinCandidate {
  _PinCandidate(this.key, this.builder, this.fromCentre);

  final String key;
  final _PinBuilder builder;
  final double fromCentre;
}

/// Gathers every matching dish at one place while the pins are being built.
class _PinBuilder {
  _PinBuilder(this.first);

  final FoodOccurrence first;
  final List<String> foods = <String>[];
  final List<double> prices = <double>[];

  void add(FoodOccurrence occurrence, String? foodName) {
    final String name = (foodName ?? occurrence.foodName).trim();
    if (name.isNotEmpty && !foods.contains(name)) foods.add(name);
    final double? price = occurrence.itemPrice;
    if (price != null && price > 0) prices.add(price);
  }

  MapPin build({required bool? openNow, required double? distanceMetres}) =>
      MapPin(
        referenceId: first.sourceId,
        kind: first.source == FoodOccurrenceSource.restaurant
            ? MapPinKind.restaurant
            : MapPinKind.landmark,
        latitude: first.latitude,
        longitude: first.longitude,
        label: first.placeName,
        weight: foods.length,
        imageUrl: first.placeImageUrl,
        category: first.placeCategory,
        rating: first.placeRating,
        servedFoods: List<String>.unmodifiable(foods),
        priceRange: _priceRange(),
        openNow: openNow,
        distanceMetres: distanceMetres,
      );

  /// "RM20-40", or "RM20" when everything costs the same. Null when no dish
  /// here carries a price - better an absent line than an invented one.
  String? _priceRange() {
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
}

/// One search hit with the score that ordered it.
class _ScoredPlace {
  const _ScoredPlace(this.score, this.suggestion);

  final int score;
  final PlaceSuggestion suggestion;
}
