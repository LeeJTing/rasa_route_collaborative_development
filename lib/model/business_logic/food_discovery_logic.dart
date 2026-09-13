import 'dart:math' as math;

import 'package:meta/meta.dart' show protected;

import '../../domain_model/dietary_restriction.dart';
import '../../domain_model/food_distribution.dart';
import '../../domain_model/food_preference.dart';
import '../../domain_model/local_food.dart';
import '../../domain_model/opening_hour.dart';
import '../../domain_model/region.dart';
import '../../domain_model/swipe_mode.dart';
import '../../domain_model/swipe_session.dart';
import '../../domain_model/tourist_location.dart';
import '../repositories/discovery_repository_facade.dart';
import 'opening_hours_logic.dart';

/// REQ103 business rules for the state-localised Swipe Mode queue.
///
/// This class deliberately knows one repository facade only. It ranks domain
/// models and persists the device-local Swipe session; Supabase rows and local
/// JSON stay below the repository boundary.
class FoodDiscoveryLogic {
  FoodDiscoveryLogic();

  @protected
  DiscoveryRepositoryFacade createRepository() => DiscoveryRepositoryFacade();

  @protected
  DateTime currentTime() => DateTime.now();

  late final DiscoveryRepositoryFacade _repository = createRepository();

  /// Builds the real queue for the Malaysian state under the map centre.
  Future<SwipeModePreparation> prepareSwipeMode({
    required double latitude,
    required double longitude,
    TouristLocation distanceOrigin = TouristLocation.unknown,
    double? south,
    double? west,
    double? north,
    double? east,
  }) async {
    final String touristId = await _repository.currentTouristId() ?? '';
    if (touristId.isEmpty) {
      throw Exception('Sign in to use Swipe Mode.');
    }

    final List<Region> regions = await _repository.malaysiaRegions();
    final Region? activeRegion = _regionAt(regions, latitude, longitude);
    if (activeRegion == null) {
      throw Exception('Move the map to a Malaysian state to use Swipe Mode.');
    }

    final List<LocalFood> foods = await _repository.getLocalFoods();
    final Map<int, LocalFood> foodsById = <int, LocalFood>{
      for (final LocalFood food in foods) food.id: food,
    };
    final List<FoodOccurrence> occurrences =
        (await _repository.foodOccurrences())
            .map((FoodOccurrence occurrence) => _resolveFood(occurrence, foods))
            .where((FoodOccurrence occurrence) => occurrence.localFoodId != 0)
            .where(
              (FoodOccurrence occurrence) => _insideViewport(
                occurrence,
                south: south,
                west: west,
                north: north,
                east: east,
              ),
            )
            .where(
              (FoodOccurrence occurrence) => _contains(
                activeRegion.boundary,
                occurrence.latitude,
                occurrence.longitude,
              ),
            )
            .toList(growable: false);

    // Swipe Mode recommends foods backed by at least one real restaurant in
    // the active state. Submitted landmarks are additional Matches results;
    // they do not make a food eligible for the swipe queue by themselves.
    final Set<String> restaurantKeys = occurrences
        .where(
          (FoodOccurrence occurrence) =>
              occurrence.source == FoodOccurrenceSource.restaurant,
        )
        .map((FoodOccurrence occurrence) => 'restaurant:${occurrence.sourceId}')
        .toSet();
    final Map<String, List<OpeningHour>> hoursByPlace = await _repository
        .openingHoursByPlace(placeKeys: restaurantKeys);
    final DateTime malaysiaNow = currentTime().toUtc().add(
      const Duration(hours: 8),
    );
    final List<FoodOccurrence> restaurantOccurrences = occurrences
        .where(
          (FoodOccurrence occurrence) =>
              occurrence.source == FoodOccurrenceSource.restaurant &&
              !OpeningHoursLogic.isConfidentlyClosedAt(
                hoursByPlace['restaurant:${occurrence.sourceId}'],
                malaysiaNow,
              ),
        )
        .toList(growable: false);
    final Set<int> availableIds = restaurantOccurrences
        .map((FoodOccurrence occurrence) => occurrence.localFoodId)
        .where(foodsById.containsKey)
        .toSet();
    // A food backed by an open restaurant outranks one we only know about
    // through places whose hours are unknown (see the sort below).
    final Set<int> foodsWithOpenRestaurant = restaurantOccurrences
        .where(
          (FoodOccurrence occurrence) => OpeningHoursLogic.isConfidentlyOpenAt(
            hoursByPlace['restaurant:${occurrence.sourceId}'],
            malaysiaNow,
          ),
        )
        .map((FoodOccurrence occurrence) => occurrence.localFoodId)
        .toSet();
    final Map<int, double> nearestDistance = <int, double>{};
    for (final FoodOccurrence occurrence in restaurantOccurrences) {
      if (!distanceOrigin.isKnown) continue;
      final double distance = _distanceKm(
        distanceOrigin.latitude,
        distanceOrigin.longitude,
        occurrence.latitude,
        occurrence.longitude,
      );
      nearestDistance.update(
        occurrence.localFoodId,
        (double current) => math.min(current, distance),
        ifAbsent: () => distance,
      );
    }

    final List<FoodPreference> preferences = await _safePreferences(touristId);
    final Set<String> preferredTastes = preferences
        .where(
          (FoodPreference preference) =>
              preference.kind == FoodPreferenceKind.taste,
        )
        .map((FoodPreference preference) => _normalise(preference.name))
        .where((String value) => value.isNotEmpty)
        .toSet();
    final Set<String> preferredCategories = preferences
        .where(
          (FoodPreference preference) =>
              preference.kind == FoodPreferenceKind.category,
        )
        .map((FoodPreference preference) => _normalise(preference.name))
        .where((String value) => value.isNotEmpty)
        .toSet();
    final Set<int> favouriteFoodIds = await _safeFavouriteFoodIds(touristId);
    final Map<String, int> favouriteMainTasteCounts = <String, int>{};
    final Map<String, int> favouriteCategoryCounts = <String, int>{};
    for (final int foodId in favouriteFoodIds) {
      final LocalFood? favourite = foodsById[foodId];
      if (favourite == null) continue;
      final String mainTaste = _normalise(favourite.mainTaste);
      final String category = _normalise(favourite.category);
      if (mainTaste.isNotEmpty) {
        favouriteMainTasteCounts.update(
          mainTaste,
          (int count) => count + 1,
          ifAbsent: () => 1,
        );
      }
      if (category.isNotEmpty) {
        favouriteCategoryCounts.update(
          category,
          (int count) => count + 1,
          ifAbsent: () => 1,
        );
      }
    }

    final Set<int> touristRestrictionIds = (await _safeRestrictions(
      touristId,
    )).map((DietaryRestriction restriction) => restriction.id).toSet();
    final Map<int, Set<int>> restrictionsByFood =
        await _safeRestrictionIdsByFood();
    final Set<int> restrictedFoodIds = availableIds.where((int foodId) {
      final Set<int> foodRestrictions =
          restrictionsByFood[foodId] ?? const <int>{};
      return foodRestrictions.any(touristRestrictionIds.contains);
    }).toSet();

    final List<LocalFood> queue = availableIds
        .map((int id) => foodsById[id])
        .whereType<LocalFood>()
        .toList();
    queue.sort((LocalFood left, LocalFood right) {
      final int restrictionOrder = (restrictedFoodIds.contains(left.id) ? 1 : 0)
          .compareTo(restrictedFoodIds.contains(right.id) ? 1 : 0);
      if (restrictionOrder != 0) return restrictionOrder;

      // Lowest priority: a food whose only restaurants have UNKNOWN opening
      // hours sits under every food with a confirmed open restaurant, so a
      // card we cannot vouch for is only reached after the ones we can.
      final int hoursOrder = (foodsWithOpenRestaurant.contains(left.id) ? 0 : 1)
          .compareTo(foodsWithOpenRestaurant.contains(right.id) ? 0 : 1);
      if (hoursOrder != 0) return hoursOrder;

      final int mainTasteOrder =
          (_hasPreferredMainTaste(right, preferredTastes) ? 1 : 0).compareTo(
            _hasPreferredMainTaste(left, preferredTastes) ? 1 : 0,
          );
      if (mainTasteOrder != 0) return mainTasteOrder;

      final int affinityOrder =
          _foodAffinityScore(
            right,
            favouriteFoodIds: favouriteFoodIds,
            preferredTastes: preferredTastes,
            preferredCategories: preferredCategories,
            favouriteMainTasteCounts: favouriteMainTasteCounts,
            favouriteCategoryCounts: favouriteCategoryCounts,
          ).compareTo(
            _foodAffinityScore(
              left,
              favouriteFoodIds: favouriteFoodIds,
              preferredTastes: preferredTastes,
              preferredCategories: preferredCategories,
              favouriteMainTasteCounts: favouriteMainTasteCounts,
              favouriteCategoryCounts: favouriteCategoryCounts,
            ),
          );
      if (affinityOrder != 0) return affinityOrder;

      final int distanceOrder = (nearestDistance[left.id] ?? double.infinity)
          .compareTo(nearestDistance[right.id] ?? double.infinity);
      if (distanceOrder != 0) return distanceOrder;
      return left.name.toLowerCase().compareTo(right.name.toLowerCase());
    });

    final SwipeSession? savedSession = await _repository.getSwipeSession(
      touristId: touristId,
      stateCode: activeRegion.code,
    );
    final Set<int> savedLikes = savedSession?.likedFoodIds.toSet() ?? <int>{};
    final int savedRestaurantCount = occurrences
        .where(
          (FoodOccurrence occurrence) =>
              occurrence.source == FoodOccurrenceSource.restaurant &&
              savedLikes.contains(occurrence.localFoodId),
        )
        .map((FoodOccurrence occurrence) => occurrence.sourceId)
        .toSet()
        .length;

    return SwipeModePreparation(
      stateCode: activeRegion.code,
      stateName: activeRegion.name,
      touristId: touristId,
      queue: List<LocalFood>.unmodifiable(queue),
      restrictedFoodIds: Set<int>.unmodifiable(restrictedFoodIds),
      savedSession: savedSession,
      savedRestaurantCount: savedRestaurantCount,
    );
  }

  Future<SwipeSession> startNewSession(SwipeModePreparation preparation) async {
    await _repository.deleteSwipeSession(
      touristId: preparation.touristId,
      stateCode: preparation.stateCode,
    );
    final DateTime now = DateTime.now().toUtc();
    final SwipeSession session = SwipeSession(
      sessionId:
          '${preparation.touristId}:${preparation.stateCode}:${now.microsecondsSinceEpoch}',
      touristId: preparation.touristId,
      stateCode: preparation.stateCode,
      startedAt: now,
      candidateFoodIds: preparation.queue
          .map((LocalFood food) => food.id)
          .toList(growable: false),
      likedFoodIds: const <int>[],
      dislikedFoodIds: const <int>[],
    );
    await _repository.saveSwipeSession(session);
    return session;
  }

  /// Reconciles a persisted queue with the latest catalogue without changing
  /// the order the tourist previously saw.
  Future<SwipeSession> continueSession(SwipeModePreparation preparation) async {
    final SwipeSession? saved = preparation.savedSession;
    if (saved == null) return startNewSession(preparation);

    final Set<int> availableIds = preparation.queue
        .map((LocalFood food) => food.id)
        .toSet();
    final List<int> candidates = saved.candidateFoodIds
        .where(availableIds.contains)
        .toList(growable: false);
    if (candidates.isEmpty) return startNewSession(preparation);

    final SwipeSession reconciled = saved.copyWith(
      candidateFoodIds: candidates,
      likedFoodIds: saved.likedFoodIds
          .where(availableIds.contains)
          .toList(growable: false),
      dislikedFoodIds: saved.dislikedFoodIds
          .where(availableIds.contains)
          .toList(growable: false),
      currentIndex: saved.currentIndex.clamp(0, candidates.length - 1),
    );
    await _repository.saveSwipeSession(reconciled);
    return reconciled;
  }

  /// Re-ranks an existing device-local session after the tourist changes
  /// profile preferences or dietary restrictions.
  ///
  /// The card currently in the Target Frame and every card already visited
  /// stay in place. Only the unvisited tail adopts the newly prepared order,
  /// so a restriction warning can update immediately without making the
  /// visible card jump. Likes and dislikes remain part of the same session.
  Future<SwipeModePreparation> refreshAfterProfileChange({
    required double latitude,
    required double longitude,
    TouristLocation distanceOrigin = TouristLocation.unknown,
    bool rebuildWholeQueue = false,
    double? south,
    double? west,
    double? north,
    double? east,
  }) async {
    final SwipeModePreparation preparation = await prepareSwipeMode(
      latitude: latitude,
      longitude: longitude,
      distanceOrigin: distanceOrigin,
      south: south,
      west: west,
      north: north,
      east: east,
    );
    final SwipeSession? saved = preparation.savedSession;
    if (saved == null) return preparation;

    final List<int> rankedIds = preparation.queue
        .map((LocalFood food) => food.id)
        .toList(growable: false);
    final Set<int> availableIds = rankedIds.toSet();

    if (rebuildWholeQueue) {
      final SwipeSession rebuilt = saved.copyWith(
        candidateFoodIds: List<int>.unmodifiable(rankedIds),
        likedFoodIds: saved.likedFoodIds,
        dislikedFoodIds: saved.dislikedFoodIds,
        currentIndex: 0,
      );
      await _repository.saveSwipeSession(rebuilt);
      return SwipeModePreparation(
        stateCode: preparation.stateCode,
        stateName: preparation.stateName,
        touristId: preparation.touristId,
        queue: preparation.queue,
        restrictedFoodIds: preparation.restrictedFoodIds,
        savedSession: rebuilt,
        savedRestaurantCount: preparation.savedRestaurantCount,
      );
    }

    final int oldIndex = saved.candidateFoodIds.isEmpty
        ? 0
        : saved.currentIndex.clamp(0, saved.candidateFoodIds.length - 1);
    final int? currentFoodId = saved.candidateFoodIds.isEmpty
        ? null
        : saved.candidateFoodIds[oldIndex];

    final List<int> retainedPrefix = saved.candidateFoodIds
        .take(oldIndex)
        .where(availableIds.contains)
        .toList(growable: true);
    if (currentFoodId != null && availableIds.contains(currentFoodId)) {
      retainedPrefix.add(currentFoodId);
    }
    final Set<int> retainedIds = retainedPrefix.toSet();
    final List<int> candidates = <int>[
      ...retainedPrefix,
      ...rankedIds.where((int id) => !retainedIds.contains(id)),
    ];

    final int currentIndex = candidates.isEmpty
        ? 0
        : currentFoodId != null && availableIds.contains(currentFoodId)
        ? retainedPrefix.length - 1
        : oldIndex.clamp(0, candidates.length - 1);
    final SwipeSession reconciled = saved.copyWith(
      candidateFoodIds: List<int>.unmodifiable(candidates),
      likedFoodIds: saved.likedFoodIds,
      dislikedFoodIds: saved.dislikedFoodIds,
      currentIndex: currentIndex,
    );
    await _repository.saveSwipeSession(reconciled);

    return SwipeModePreparation(
      stateCode: preparation.stateCode,
      stateName: preparation.stateName,
      touristId: preparation.touristId,
      queue: preparation.queue,
      restrictedFoodIds: preparation.restrictedFoodIds,
      savedSession: reconciled,
      savedRestaurantCount: preparation.savedRestaurantCount,
    );
  }

  /// Re-reads the device-local session after another screen edits it. This is
  /// intentionally different from [continueSession], which resumes the saved
  /// snapshot presented in the Continue/New prompt.
  Future<SwipeSession?> reloadSession(SwipeModePreparation preparation) =>
      _repository.getSwipeSession(
        touristId: preparation.touristId,
        stateCode: preparation.stateCode,
      );

  Future<SwipeSession> moveToIndex(
    SwipeSession session,
    int requestedIndex,
  ) async {
    if (session.candidateFoodIds.isEmpty) return session;
    final SwipeSession moved = session.copyWith(
      currentIndex: requestedIndex.clamp(
        0,
        session.candidateFoodIds.length - 1,
      ),
    );
    await _repository.saveSwipeSession(moved);
    return moved;
  }

  /// Adds a food to this device's state-scoped match list.
  Future<SwipeSession> likeFood(SwipeSession session, int foodId) async {
    if (session.likedFoodIds.contains(foodId)) return session;
    final SwipeSession liked = session.copyWith(
      likedFoodIds: List<int>.unmodifiable(<int>[
        ...session.likedFoodIds,
        foodId,
      ]),
      dislikedFoodIds: session.dislikedFoodIds
          .where((int id) => id != foodId)
          .toList(growable: false),
    );
    await _repository.saveSwipeSession(liked);
    return liked;
  }

  /// Removes a match without treating the action as a dislike.
  Future<SwipeSession> removeLike(SwipeSession session, int foodId) async {
    if (!session.likedFoodIds.contains(foodId)) return session;
    final SwipeSession updated = session.copyWith(
      likedFoodIds: session.likedFoodIds
          .where((int id) => id != foodId)
          .toList(growable: false),
    );
    await _repository.saveSwipeSession(updated);
    return updated;
  }

  Future<List<FoodPreference>> _safePreferences(String touristId) async {
    try {
      return await _repository.foodPreferencesForTourist(touristId);
    } catch (_) {
      return const <FoodPreference>[];
    }
  }

  Future<List<DietaryRestriction>> _safeRestrictions(String touristId) async {
    try {
      return await _repository.dietaryRestrictionsForTourist(touristId);
    } catch (_) {
      return const <DietaryRestriction>[];
    }
  }

  Future<Set<int>> _safeFavouriteFoodIds(String touristId) async {
    try {
      return await _repository.favouriteFoodIdsForTourist(touristId);
    } catch (_) {
      return const <int>{};
    }
  }

  Future<Map<int, Set<int>>> _safeRestrictionIdsByFood() async {
    try {
      return await _repository.dietaryRestrictionIdsByFood();
    } catch (_) {
      return const <int, Set<int>>{};
    }
  }

  static bool _hasPreferredMainTaste(
    LocalFood food,
    Set<String> preferredTastes,
  ) => preferredTastes.contains(_normalise(food.mainTaste));

  static int _foodAffinityScore(
    LocalFood food, {
    required Set<int> favouriteFoodIds,
    required Set<String> preferredTastes,
    required Set<String> preferredCategories,
    required Map<String, int> favouriteMainTasteCounts,
    required Map<String, int> favouriteCategoryCounts,
  }) {
    final String category = _normalise(food.category);
    final String mainTaste = _normalise(food.mainTaste);
    final bool secondaryTasteMatch = food.tastes
        .map(_normalise)
        .where((String taste) => taste != mainTaste)
        .any(preferredTastes.contains);
    final int favouriteTasteBonus = math.min(
      (favouriteMainTasteCounts[mainTaste] ?? 0) * 15,
      45,
    );
    final int favouriteCategoryBonus = math.min(
      (favouriteCategoryCounts[category] ?? 0) * 10,
      30,
    );

    return (favouriteFoodIds.contains(food.id) ? 100 : 0) +
        favouriteTasteBonus +
        (preferredCategories.contains(category) ? 40 : 0) +
        favouriteCategoryBonus +
        (secondaryTasteMatch ? 25 : 0);
  }

  static FoodOccurrence _resolveFood(
    FoodOccurrence occurrence,
    List<LocalFood> foods,
  ) {
    if (occurrence.localFoodId != 0) return occurrence;
    final String dish = _normalise(occurrence.foodName);
    for (final LocalFood food in foods) {
      final bool matches =
          _normalise(food.name) == dish ||
          food.synonyms.any((String synonym) => _normalise(synonym) == dish);
      if (!matches) continue;
      return FoodOccurrence(
        sourceId: occurrence.sourceId,
        source: occurrence.source,
        placeName: occurrence.placeName,
        localFoodId: food.id,
        foodName: occurrence.foodName,
        foodType: food.foodType,
        latitude: occurrence.latitude,
        longitude: occurrence.longitude,
        placeImageUrl: occurrence.placeImageUrl,
        placeCategory: occurrence.placeCategory,
        placeRating: occurrence.placeRating,
        itemPrice: occurrence.itemPrice,
      );
    }
    return occurrence;
  }

  static Region? _regionAt(
    List<Region> regions,
    double latitude,
    double longitude,
  ) {
    for (final Region region in regions) {
      if (_contains(region.boundary, latitude, longitude)) return region;
    }
    return null;
  }

  static bool _insideViewport(
    FoodOccurrence occurrence, {
    required double? south,
    required double? west,
    required double? north,
    required double? east,
  }) {
    if (south == null || west == null || north == null || east == null) {
      return true;
    }
    return occurrence.latitude >= south &&
        occurrence.latitude <= north &&
        occurrence.longitude >= west &&
        occurrence.longitude <= east;
  }

  static bool _contains(
    List<GeoPoint> polygon,
    double latitude,
    double longitude,
  ) {
    if (polygon.length < 3) return false;
    bool inside = false;
    for (
      int current = 0, previous = polygon.length - 1;
      current < polygon.length;
      previous = current++
    ) {
      final GeoPoint a = polygon[current];
      final GeoPoint b = polygon[previous];
      final bool crosses = (a.latitude > latitude) != (b.latitude > latitude);
      if (!crosses) continue;
      final double intersection =
          (b.longitude - a.longitude) *
              (latitude - a.latitude) /
              (b.latitude - a.latitude) +
          a.longitude;
      if (longitude < intersection) inside = !inside;
    }
    return inside;
  }

  static double _distanceKm(
    double fromLatitude,
    double fromLongitude,
    double toLatitude,
    double toLongitude,
  ) {
    const double earthRadiusKm = 6371;
    final double latitudeDelta = _radians(toLatitude - fromLatitude);
    final double longitudeDelta = _radians(toLongitude - fromLongitude);
    final double haversine =
        math.pow(math.sin(latitudeDelta / 2), 2).toDouble() +
        math.cos(_radians(fromLatitude)) *
            math.cos(_radians(toLatitude)) *
            math.pow(math.sin(longitudeDelta / 2), 2).toDouble();
    return earthRadiusKm *
        2 *
        math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine));
  }

  static double _radians(double degrees) => degrees * math.pi / 180;

  static String _normalise(String value) => value.trim().toLowerCase();
}
