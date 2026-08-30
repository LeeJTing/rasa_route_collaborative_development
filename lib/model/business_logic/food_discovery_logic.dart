import 'dart:math' as math;

import 'package:meta/meta.dart' show visibleForTesting;

import '../../domain_model/dietary_restriction.dart';
import '../../domain_model/food_distribution.dart';
import '../../domain_model/local_food.dart';
import '../../domain_model/region.dart';
import '../../domain_model/swipe_mode.dart';
import '../../domain_model/swipe_session.dart';
import '../repositories/discovery_repository_facade.dart';

/// REQ103 business rules for the state-localised Swipe Mode queue.
///
/// This class deliberately knows one repository facade only. It ranks domain
/// models and persists the device-local Swipe session; Supabase rows and local
/// JSON stay below the repository boundary.
class FoodDiscoveryLogic {
  FoodDiscoveryLogic({@visibleForTesting DiscoveryRepositoryFacade? repository})
    : _repository = repository ?? DiscoveryRepositoryFacade();

  final DiscoveryRepositoryFacade _repository;

  /// Builds the real queue for the Malaysian state under the map centre.
  Future<SwipeModePreparation> prepareSwipeMode({
    required double latitude,
    required double longitude,
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
    final List<FoodOccurrence> restaurantOccurrences = occurrences
        .where(
          (FoodOccurrence occurrence) =>
              occurrence.source == FoodOccurrenceSource.restaurant,
        )
        .toList(growable: false);
    final Set<int> availableIds = restaurantOccurrences
        .map((FoodOccurrence occurrence) => occurrence.localFoodId)
        .where(foodsById.containsKey)
        .toSet();
    final Map<int, double> nearestDistance = <int, double>{};
    for (final FoodOccurrence occurrence in restaurantOccurrences) {
      final double distance = _distanceKm(
        latitude,
        longitude,
        occurrence.latitude,
        occurrence.longitude,
      );
      nearestDistance.update(
        occurrence.localFoodId,
        (double current) => math.min(current, distance),
        ifAbsent: () => distance,
      );
    }

    final Set<int> favouriteIds = await _safeFavouriteIds(touristId);
    final Set<String> preferredTastes = foods
        .where((LocalFood food) => favouriteIds.contains(food.id))
        .expand((LocalFood food) => <String>[food.mainTaste, ...food.tastes])
        .map(_normalise)
        .where((String value) => value.isNotEmpty)
        .toSet();

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

      final int tasteOrder = _preferenceScore(
        right,
        preferredTastes,
      ).compareTo(_preferenceScore(left, preferredTastes));
      if (tasteOrder != 0) return tasteOrder;

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

  Future<Set<int>> _safeFavouriteIds(String touristId) async {
    try {
      return await _repository.favouriteFoodIdsForTourist(touristId);
    } catch (_) {
      return <int>{};
    }
  }

  Future<List<DietaryRestriction>> _safeRestrictions(String touristId) async {
    try {
      return await _repository.dietaryRestrictionsForTourist(touristId);
    } catch (_) {
      return const <DietaryRestriction>[];
    }
  }

  Future<Map<int, Set<int>>> _safeRestrictionIdsByFood() async {
    try {
      return await _repository.dietaryRestrictionIdsByFood();
    } catch (_) {
      return const <int, Set<int>>{};
    }
  }

  static int _preferenceScore(LocalFood food, Set<String> preferredTastes) {
    if (preferredTastes.isEmpty) return 0;
    return <String>[
      food.mainTaste,
      ...food.tastes,
    ].map(_normalise).where(preferredTastes.contains).toSet().length;
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
