import 'dart:math' as math;

import 'package:meta/meta.dart' show protected;

import '../../domain_model/dietary_restriction.dart';
import '../../domain_model/food_distribution.dart';
import '../../domain_model/matches_recommendation.dart';
import '../../domain_model/opening_hour.dart';
import '../../domain_model/place_closure_rules.dart';
import '../../domain_model/restaurant.dart';
import '../../domain_model/restaurant_item.dart';
import '../../domain_model/tourist_location.dart';
import '../repositories/discovery_repository_facade.dart';
import 'opening_hours_logic.dart';

/// Finding and filtering restaurants.
///
/// A business-logic class knows exactly one thing below it: a repository
/// facade. It never sees a repository, a shared client or Flutter.
class RestaurantDiscoveryLogic {
  RestaurantDiscoveryLogic();

  static const int _quickModeResultTarget = 20;
  static const double _quickModeInitialRadiusKm = 1;
  static const double _quickModeRadiusStepKm = 1;
  static const double _quickModeMaximumRadiusKm = 10;

  @protected
  DiscoveryRepositoryFacade createRepository() => DiscoveryRepositoryFacade();

  @protected
  DateTime currentTime() => DateTime.now();

  late final DiscoveryRepositoryFacade repository = createRepository();

  Future<Restaurant?> findById(
    int restaurantId, {
    TouristLocation origin = TouristLocation.unknown,
  }) async {
    final Restaurant? restaurant = await repository.getRestaurantById(
      restaurantId,
    );
    if (restaurant == null) return null;
    return _measure(<Restaurant>[restaurant], origin).single;
  }

  Future<List<Restaurant>> nearby({
    required TouristLocation location,
    required double radiusKm,
    required int limit,
  }) async {
    if (!location.isKnown || radiusKm <= 0 || limit <= 0) {
      return const <Restaurant>[];
    }
    final List<Restaurant> allMeasured = _measure(
      await repository.getRestaurantsNear(
        latitude: location.latitude,
        longitude: location.longitude,
        maximumDistanceKm: radiusKm,
      ),
      location,
    );
    await _reactivateExpiredClosures(allMeasured);
    final List<Restaurant> candidates = _withinRadius(
      _availableSummaries(allMeasured),
      radiusKm: radiusKm,
    );
    final List<Restaurant> eligible = await _eligibleRestaurants(candidates);
    return _hydrateSelected(eligible.take(limit).toList(growable: false));
  }

  List<Restaurant> _measure(
    List<Restaurant> restaurants,
    TouristLocation location,
  ) => restaurants
      .map((Restaurant restaurant) {
        final String visibleCategory = _visibleCategory(restaurant.category);
        if (!location.isKnown ||
            restaurant.latitude == null ||
            restaurant.longitude == null) {
          return _withDiscoveryValues(restaurant, category: visibleCategory);
        }
        return _withDiscoveryValues(
          restaurant,
          category: visibleCategory,
          distanceMetres: _distanceMetres(
            location.latitude,
            location.longitude,
            restaurant.latitude!,
            restaurant.longitude!,
          ),
        );
      })
      .toList(growable: false);

  Restaurant _withDiscoveryValues(
    Restaurant restaurant, {
    required String category,
    double? distanceMetres,
    List<RestaurantItem>? items,
  }) => Restaurant(
    id: restaurant.id,
    name: restaurant.name,
    category: category,
    address: restaurant.address,
    rating: restaurant.rating,
    latitude: restaurant.latitude,
    longitude: restaurant.longitude,
    phone: restaurant.phone,
    website: restaurant.website,
    imageUrl: restaurant.imageUrl,
    openingHours: restaurant.openingHours,
    distanceMetres: distanceMetres ?? restaurant.distanceMetres,
    reviewCount: restaurant.reviewCount,
    status: restaurant.status,
    closedUntil: restaurant.closedUntil,
    items: items ?? restaurant.items,
  );

  /// Halal classification was retired from the product. Imported restaurant
  /// source categories can still contain the old word, so remove that whole
  /// category segment before anything reaches a View.
  String _visibleCategory(String raw) => raw
      .split(RegExp(r'[,·|/]'))
      .map((String value) => value.trim())
      .where(
        (String value) => !value.toLowerCase().contains(RegExp(r'\bhalal\b')),
      )
      .where((String value) => value.isNotEmpty)
      .join(', ');

  List<Restaurant> _withinRadius(
    List<Restaurant> measured, {
    required double radiusKm,
  }) {
    final List<Restaurant> matches = measured.where((Restaurant restaurant) {
      final double? distance = restaurant.distanceMetres;
      // A place without coordinates cannot be "within" a GPS radius and must
      // not consume one of the twenty nearest-result slots.
      return distance != null && distance <= radiusKm * 1000;
    }).toList();
    matches.sort(
      (Restaurant a, Restaurant b) => (a.distanceMetres ?? double.infinity)
          .compareTo(b.distanceMetres ?? double.infinity),
    );
    return matches;
  }

  /// Quick Mode starts at 1 km and expands silently until 20 nearest
  /// eligible restaurants are found or the 10 km Use Case boundary is reached.
  Future<List<Restaurant>> nearbyWithAutomaticExpansion({
    required TouristLocation location,
  }) async {
    if (!location.isKnown) return const <Restaurant>[];
    final List<Restaurant> allMeasured = _measure(
      await repository.getRestaurantsNear(
        latitude: location.latitude,
        longitude: location.longitude,
        maximumDistanceKm: _quickModeMaximumRadiusKm,
      ),
      location,
    );
    await _reactivateExpiredClosures(allMeasured);
    final List<Restaurant> measured = _availableSummaries(allMeasured);
    final List<Restaurant> eligible = await _eligibleRestaurants(
      _withinRadius(measured, radiusKm: _quickModeMaximumRadiusKm),
    );
    double radiusKm = _quickModeInitialRadiusKm;
    List<Restaurant> available = const <Restaurant>[];
    while (radiusKm <= _quickModeMaximumRadiusKm) {
      final List<Restaurant> results = _withinRadius(
        eligible,
        radiusKm: radiusKm,
      ).take(_quickModeResultTarget).toList(growable: false);
      available = results;
      if (results.length >= _quickModeResultTarget || !location.isKnown) {
        return _hydrateSelected(results);
      }
      radiusKm += _quickModeRadiusStepKm;
    }
    return _hydrateSelected(available);
  }

  /// Submitted-landmark half of Quick Mode, using the same map occurrences
  /// that feed dashboard pins. C21 keeps it separate from Google-sourced
  /// restaurants while the radius, closed-place and dietary rules stay equal.
  Future<List<SubmittedLandmarkRecommendation>>
  nearbyLandmarksWithAutomaticExpansion({
    required TouristLocation location,
  }) async {
    if (!location.isKnown) return const <SubmittedLandmarkRecommendation>[];

    final List<Object> gathered = await Future.wait(<Future<Object>>[
      repository.foodOccurrences(),
      repository.openingHoursByPlace(),
      repository.getCurrentDietaryRestrictions(),
      repository.getRestrictionIdsByFood(),
    ]);
    final List<FoodOccurrence> occurrences =
        gathered[0] as List<FoodOccurrence>;
    final Map<String, List<OpeningHour>> hoursByPlace =
        gathered[1] as Map<String, List<OpeningHour>>;
    final Set<int> activeRestrictionIds =
        (gathered[2] as List<DietaryRestriction>)
            .map((DietaryRestriction restriction) => restriction.id)
            .toSet();
    final Map<int, List<int>> restrictionIdsByFood =
        gathered[3] as Map<int, List<int>>;

    final Map<String, List<FoodOccurrence>> byLandmark =
        <String, List<FoodOccurrence>>{};
    for (final FoodOccurrence occurrence in occurrences) {
      if (occurrence.source != FoodOccurrenceSource.submittedLandmark) {
        continue;
      }
      if (!_occurrenceIsSafe(
        occurrence,
        activeRestrictionIds: activeRestrictionIds,
        restrictionIdsByFood: restrictionIdsByFood,
      )) {
        continue;
      }
      byLandmark
          .putIfAbsent(occurrence.sourceId, () => <FoodOccurrence>[])
          .add(occurrence);
    }

    final DateTime now = currentTime();
    final List<SubmittedLandmarkRecommendation> measured =
        <SubmittedLandmarkRecommendation>[];
    for (final MapEntry<String, List<FoodOccurrence>> entry
        in byLandmark.entries) {
      if (entry.value.isEmpty ||
          _isConfidentlyClosedHours(
            hoursByPlace['submittedLandmark:${entry.key}'] ??
                const <OpeningHour>[],
            now,
          )) {
        continue;
      }
      final FoodOccurrence place = entry.value.first;
      measured.add(
        SubmittedLandmarkRecommendation(
          id: int.tryParse(entry.key) ?? 0,
          name: place.placeName,
          category: place.placeCategory?.trim().isNotEmpty == true
              ? place.placeCategory!.trim()
              : 'Submitted Landmark',
          distanceMetres: _distanceMetres(
            location.latitude,
            location.longitude,
            place.latitude,
            place.longitude,
          ),
          foodNames: entry.value
              .map((FoodOccurrence item) => item.foodName.trim())
              .where((String name) => name.isNotEmpty)
              .toSet()
              .toList(growable: false),
          imageUrl: place.placeImageUrl,
          price: entry.value
              .map((FoodOccurrence item) => item.itemPrice)
              .whereType<double>()
              .fold<double?>(null, (double? lowest, double price) {
                return lowest == null || price < lowest ? price : lowest;
              }),
        ),
      );
    }
    measured.sort(
      (SubmittedLandmarkRecommendation a, SubmittedLandmarkRecommendation b) =>
          a.distanceMetres.compareTo(b.distanceMetres),
    );

    double radiusKm = _quickModeInitialRadiusKm;
    List<SubmittedLandmarkRecommendation> available =
        const <SubmittedLandmarkRecommendation>[];
    while (radiusKm <= _quickModeMaximumRadiusKm) {
      available = measured
          .where(
            (SubmittedLandmarkRecommendation landmark) =>
                landmark.distanceMetres <= radiusKm * 1000,
          )
          .take(_quickModeResultTarget)
          .toList(growable: false);
      if (available.length >= _quickModeResultTarget) return available;
      radiusKm += _quickModeRadiusStepKm;
    }
    return available;
  }

  Future<List<Restaurant>> _hydrateSelected(List<Restaurant> selected) async {
    if (selected.isEmpty) return const <Restaurant>[];
    final List<Restaurant> detailed = await repository.getRestaurantsByIds(
      selected.map((Restaurant restaurant) => restaurant.id).toList(),
    );
    final Map<int, Restaurant> detailById = <int, Restaurant>{
      for (final Restaurant restaurant in detailed) restaurant.id: restaurant,
    };
    return selected
        .map((Restaurant measured) {
          final Restaurant detail = detailById[measured.id] ?? measured;
          final Set<int> allowedItemIds = measured.items
              .map((RestaurantItem item) => item.id)
              .toSet();
          final List<RestaurantItem> safeDetailedItems = detail.items
              .where((RestaurantItem item) => allowedItemIds.contains(item.id))
              .toList(growable: false);
          return _withDiscoveryValues(
            detail,
            category: measured.category,
            distanceMetres: measured.distanceMetres,
            items: safeDetailedItems.isEmpty
                ? measured.items
                : safeDetailedItems,
          );
        })
        .toList(growable: false);
  }

  List<Restaurant> _availableSummaries(List<Restaurant> restaurants) {
    final DateTime now = currentTime();
    return restaurants
        .where(
          (Restaurant restaurant) =>
              // Only 'available' places are discovered - a place frozen by a
              // report (or by a still-running temporary closure) is hidden.
              // A frozen place whose TEMPORARY closure has passed is available
              // again (see PlaceClosureRules) and is included on this read.
              PlaceClosureRules.isEffectivelyAvailable(
                status: restaurant.status,
                closedUntil: restaurant.closedUntil,
                now: currentTime(),
              ) &&
              !_isConfidentlyClosed(restaurant, now),
        )
        .toList(growable: false);
  }

  /// Read-time auto-reactivation: any restaurant in [allMeasured] that is
  /// frozen by a temporary closure whose `closed_until` has passed is written
  /// back to 'available' with `closed_until` cleared, so the DB catches up
  /// with what this read just decided. Best-effort (a failed write must not
  /// take discovery down - the restaurant is treated as available this read
  /// regardless).
  Future<void> _reactivateExpiredClosures(List<Restaurant> allMeasured) async {
    for (final Restaurant restaurant in allMeasured) {
      if (!PlaceClosureRules.needsReactivation(
        status: restaurant.status,
        closedUntil: restaurant.closedUntil,
        now: currentTime(),
      )) {
        continue;
      }
      try {
        await repository.reactivateRestaurantFromClosure(restaurant.id);
      } catch (_) {
        // Best-effort - see method doc.
      }
    }
  }

  bool _isConfidentlyClosed(Restaurant restaurant, DateTime malaysiaNow) {
    return _isConfidentlyClosedHours(restaurant.openingHours, malaysiaNow);
  }

  bool _isConfidentlyClosedHours(
    List<OpeningHour> hours,
    DateTime malaysiaNow,
  ) => OpeningHoursLogic.isConfidentlyClosedAt(hours, malaysiaNow);

  Future<List<Restaurant>> _eligibleRestaurants(
    List<Restaurant> candidates,
  ) async {
    if (candidates.isEmpty) return const <Restaurant>[];
    final List<RestaurantItem> menuItems = await repository
        .getRestaurantItemsByRestaurantIds(
          candidates.map((Restaurant restaurant) => restaurant.id).toList(),
        );
    final Map<int, List<RestaurantItem>> itemsByRestaurant =
        <int, List<RestaurantItem>>{};
    for (final RestaurantItem item in menuItems) {
      itemsByRestaurant
          .putIfAbsent(item.restaurantId, () => <RestaurantItem>[])
          .add(item);
    }

    final List<DietaryRestriction> restrictions = await repository
        .getCurrentDietaryRestrictions();
    final Set<int> activeRestrictionIds = restrictions
        .map((DietaryRestriction restriction) => restriction.id)
        .toSet();
    final Map<int, List<int>> restrictionIdsByFood =
        activeRestrictionIds.isEmpty
        ? const <int, List<int>>{}
        : await repository.getRestrictionIdsByFood();

    final List<Restaurant> eligible = <Restaurant>[];
    for (final Restaurant restaurant in candidates) {
      final List<RestaurantItem> items =
          itemsByRestaurant[restaurant.id] ?? const <RestaurantItem>[];
      if (items.isEmpty) continue;
      final List<RestaurantItem> safeItems = activeRestrictionIds.isEmpty
          ? items
          : items
                .where(
                  (RestaurantItem item) =>
                      item.localFoodId > 0 &&
                      !_conflictsWithRestrictions(
                        item,
                        activeRestrictionIds: activeRestrictionIds,
                        restrictionIdsByFood: restrictionIdsByFood,
                      ),
                )
                .toList(growable: false);
      if (safeItems.isEmpty) continue;
      eligible.add(
        _withDiscoveryValues(
          restaurant,
          category: restaurant.category,
          items: safeItems,
        ),
      );
    }
    return eligible;
  }

  bool _conflictsWithRestrictions(
    RestaurantItem item, {
    required Set<int> activeRestrictionIds,
    required Map<int, List<int>> restrictionIdsByFood,
  }) => (restrictionIdsByFood[item.localFoodId] ?? const <int>[]).any(
    activeRestrictionIds.contains,
  );

  bool _occurrenceIsSafe(
    FoodOccurrence occurrence, {
    required Set<int> activeRestrictionIds,
    required Map<int, List<int>> restrictionIdsByFood,
  }) {
    if (activeRestrictionIds.isEmpty) return true;
    if (occurrence.localFoodId <= 0) return false;
    return !(restrictionIdsByFood[occurrence.localFoodId] ?? const <int>[]).any(
      activeRestrictionIds.contains,
    );
  }

  double _distanceMetres(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000;
    final double dLat = _radians(lat2 - lat1);
    final double dLon = _radians(lon2 - lon1);
    final double a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_radians(lat1)) *
            math.cos(_radians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  double _radians(double degrees) => degrees * math.pi / 180;
}
