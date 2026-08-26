import '../../domain_model/exploration_filter.dart';
import '../../domain_model/exploration_search.dart';
import '../../domain_model/food_distribution.dart';
import '../../domain_model/local_food.dart';
import '../../domain_model/map.dart';
import '../../domain_model/opening_hour.dart';
import '../../domain_model/region.dart';
import '../../domain_model/tourist_location.dart';
import '../repositories/discovery_repository_facade.dart';
import '../repositories/food_repository_facade.dart';
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
/// A business-logic class knows exactly one thing below it: a **repository
/// facade**. This is the second class in the project to hold two - the same
/// documented exception `FoodRecognitionLogic` uses, and for the same reason.
/// It needs [DiscoveryRepositoryFacade] for the map, the occurrences and the
/// GPS fix, and [FoodRepositoryFacade] for the local-food catalogue that both
/// the C1 denominator and the food keyword search are computed from. The
/// alternative would be a second copy of the catalogue query inside
/// `MapRepository`, which is worse.
///
/// It never sees a repository, a shared client or Flutter.
class MapExplorationLogic {
  MapExplorationLogic();

  final DiscoveryRepositoryFacade repository = DiscoveryRepositoryFacade();
  final FoodRepositoryFacade foodRepository = FoodRepositoryFacade();

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
  static const List<String> categoryOptions = <String>[
    'Malay',
    'Chinese',
    'Indian',
    'Nyonya',
    'Sabah',
    'Sarawak',
  ];

  /// C4 / REQ102_26.
  static const List<String> tasteOptions = <String>[
    'Sweet',
    'Salty',
    'Sour',
    'Bitter',
    'Umami',
    'Spicy',
    'Mild',
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
    'Buttery',
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

  /// REQ102_1 - the tight coastline, which the painted overview clips to.
  Future<List<CountryOutline>> outlines() => repository.map.malaysiaOutlines();

  /// REQ102_1 - the generous rings the detailed map masks with.
  Future<List<CountryOutline>> maskOutlines() =>
      repository.map.malaysiaMaskOutlines();

  /// The state containing [latitude] / [longitude], or null when the point is
  /// outside every Malaysian state (A3).
  Future<Region?> regionAt(double latitude, double longitude) async {
    for (final Region region in await regions()) {
      if (_contains(region.boundary, latitude, longitude)) return region;
    }
    return null;
  }

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
  /// C1: a state's score is the number of distinct local foods available in it
  /// divided by the maximum any state reached, so the best-served state is 1.0
  /// (green, REQ102_16) and a state with nothing is 0.0 (grey). Passing
  /// [localFoodId] narrows the calculation to one dish, which is REQ102_33 -
  /// the map redrawn around a searched food.
  ///
  /// @param localFoodId (swipe mode) - `LocalFood.id` of the dish in the
  ///        Target Frame, or null to score every food. Reaches here from
  ///        `DashboardViewModel.showFoodInTargetFrame`.
  Future<FoodDistribution> distribution({
    ExplorationFilter filter = ExplorationFilter.none,
    int? localFoodId,
  }) async {
    final List<Region> allRegions = await regions();
    final List<LocalFood> catalogue = await foodRepository.getFoods();

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

    final List<FoodOccurrence> occurrences = await _resolvedOccurrences(
      catalogue,
    );

    // state code -> the distinct local foods served in it
    final Map<String, Set<int>> foodsByRegion = <String, Set<int>>{
      for (final Region region in allRegions) region.code: <int>{},
    };
    final Map<String, int> occurrencesByRegion = <String, int>{
      for (final Region region in allRegions) region.code: 0,
    };

    for (final FoodOccurrence occurrence in occurrences) {
      if (!matchingIds.contains(occurrence.localFoodId)) continue;
      final Region? region = _regionOf(
        allRegions,
        occurrence.latitude,
        occurrence.longitude,
      );
      if (region == null) continue;
      foodsByRegion[region.code]!.add(occurrence.localFoodId);
      occurrencesByRegion[region.code] =
          occurrencesByRegion[region.code]! + 1;
    }

    int maximum = 0;
    for (final Set<int> foods in foodsByRegion.values) {
      if (foods.length > maximum) maximum = foods.length;
    }

    final List<RegionAvailability> availability = allRegions
        .map((Region region) {
          final int available = foodsByRegion[region.code]!.length;
          return RegionAvailability(
            region: region,
            availableFoodCount: available,
            maximumFoodCount: maximum,
            // REQ102_17 - the gradient between green and grey is generated
            // from this, never picked per state.
            score: maximum == 0 ? 0 : available / maximum,
            occurrenceCount: occurrencesByRegion[region.code]!,
          );
        })
        .toList(growable: false);

    return FoodDistribution(
      regions: availability,
      maximumFoodCount: maximum,
      matchingFoodCount: matching.length,
    );
  }

  /// REQ102_32 - the restaurant and submitted-landmark pins drawn on the
  /// detailed map view.
  ///
  /// With [localFoodId] set, only the places serving that dish are pinned;
  /// otherwise every place serving anything that survives [filter] is. Pins are
  /// limited to what is inside the viewport box so a country-wide zoom does not
  /// drop ten thousand markers on the map.
  ///
  /// **This is where REQ103_8 lands.** The food resting in the Target Frame
  /// becomes [localFoodId], and the pins it produces are the ones that appear
  /// on the detailed map.
  ///
  /// @param localFoodId (swipe mode) - `LocalFood.id` of the dish in the
  ///        Target Frame, or null for every matching food.
  Future<List<MapPin>> pins({
    ExplorationFilter filter = ExplorationFilter.none,
    int? localFoodId,
    double? south,
    double? west,
    double? north,
    double? east,
    double? fromLatitude,
    double? fromLongitude,
    int limit = 200,
  }) async {
    final List<LocalFood> catalogue = await foodRepository.getFoods();
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

    final List<FoodOccurrence> occurrences = await _resolvedOccurrences(
      catalogue,
    );
    final Map<String, List<OpeningHour>> hours = await repository.map
        .openingHours();

    // One pin per place, gathering every matching dish served there.
    final Map<String, _PinBuilder> byPlace = <String, _PinBuilder>{};
    for (final FoodOccurrence occurrence in occurrences) {
      if (!matchingIds.contains(occurrence.localFoodId)) continue;
      if (south != null && occurrence.latitude < south) continue;
      if (north != null && occurrence.latitude > north) continue;
      if (west != null && occurrence.longitude < west) continue;
      if (east != null && occurrence.longitude > east) continue;

      final String key = '${occurrence.source.name}:${occurrence.sourceId}';
      if (!byPlace.containsKey(key) && byPlace.length >= limit) continue;
      byPlace
          .putIfAbsent(key, () => _PinBuilder(occurrence))
          .add(occurrence, nameById[occurrence.localFoodId]);
    }

    return List<MapPin>.unmodifiable(
      byPlace.entries.map(
        (MapEntry<String, _PinBuilder> entry) => entry.value.build(
          openNow: _openNow(hours[entry.key]),
          distanceMetres: fromLatitude == null || fromLongitude == null
              ? null
              : _distanceMetres(
                  fromLatitude,
                  fromLongitude,
                  entry.value.first.latitude,
                  entry.value.first.longitude,
                ),
        ),
      ),
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

    final List<PlaceSuggestion> places = <PlaceSuggestion>[];

    // REQ102_18 - states first, so "Penang" lands on the state, not a suburb.
    for (final Region region in await regions()) {
      if (region.name.toLowerCase().contains(needle)) {
        places.add(
          PlaceSuggestion(
            name: region.name,
            subtitle: 'State',
            kind: PlaceKind.state,
            latitude: region.centreLatitude,
            longitude: region.centreLongitude,
            zoom: region.defaultZoom,
          ),
        );
      }
    }

    // REQ102_19 - then cities and notable locations.
    for (final Region region in await regions()) {
      for (final RegionPlace place in region.places) {
        if (place.name.toLowerCase().contains(needle)) {
          places.add(
            PlaceSuggestion(
              name: place.name,
              subtitle: place.regionName,
              kind: PlaceKind.city,
              latitude: place.latitude,
              longitude: place.longitude,
              zoom: cityZoom,
            ),
          );
        }
      }
    }

    // REQ102_30 / REQ102_31 - the same keyword against the food catalogue.
    final List<LocalFood> foods = await foodRepository.searchFoods(keyword);

    return ExplorationSearchResults(
      keyword: keyword.trim(),
      places: List<PlaceSuggestion>.unmodifiable(places),
      foods: foods,
    );
  }

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
  Future<List<FoodOccurrence>> _resolvedOccurrences(
    List<LocalFood> catalogue,
  ) async {
    final List<FoodOccurrence> raw = await repository.map.foodOccurrences();

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
          );
        })
        .toList(growable: false);
  }

  static Region? _regionOf(
    List<Region> regions,
    double latitude,
    double longitude,
  ) {
    for (final Region region in regions) {
      if (_contains(region.boundary, latitude, longitude)) return region;
    }
    return null;
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
      final bool straddles =
          (a.latitude > latitude) != (b.latitude > latitude);
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
