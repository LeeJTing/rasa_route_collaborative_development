import 'dart:math' as math;

import 'package:meta/meta.dart' show protected, visibleForTesting;

import '../../domain_model/dietary_restriction.dart';
import '../../domain_model/opening_hour.dart';
import '../../domain_model/restaurant.dart';
import '../../domain_model/restaurant_item.dart';
import '../../domain_model/restaurant_report_reason.dart';
import '../../domain_model/tourist_location.dart';
import '../repositories/discovery_repository_facade.dart';

/// Finding and filtering restaurants.
///
/// A business-logic class knows exactly one thing below it: a repository
/// facade. It never sees a repository, a shared client or Flutter.
class RestaurantDiscoveryLogic {
  RestaurantDiscoveryLogic();

  @protected
  DiscoveryRepositoryFacade createRepository() => DiscoveryRepositoryFacade();

  @protected
  DateTime currentTime() => DateTime.now();

  late final DiscoveryRepositoryFacade repository = createRepository();

  Future<Restaurant?> findById(int restaurantId) =>
      repository.getRestaurantById(restaurantId);

  /// Records a tourist's report against a catalogue restaurant (the shared
  /// `report` table) and applies the moderation rule: `report_count` is
  /// incremented, and once it reaches [_reportFreezeAtReports] the
  /// restaurant is frozen (`status` 'frozen') so the discovery/list filters
  /// stop showing it. `frozePlace: true` tells the caller that THIS report
  /// was the one that froze it - the UI leaves the page and refreshes the
  /// map, dropping the now-hidden pin.
  ///
  /// Reporting is a signed-in feature: when no tourist is resolved (no auth
  /// session) nothing is written and `requiresSignIn: true` is returned so
  /// the UI can ask the user to sign in. When signed in, one tourist may
  /// report a place only once - a duplicate is detected first and
  /// `alreadyReported: true` is returned without touching the count.
  Future<({bool requiresSignIn, bool alreadyReported, bool frozePlace})>
  submitRestaurantReport({
    required int restaurantId,
    required RestaurantReportReason reason,
    String? touristId,
  }) async {
    final String? resolvedTouristId =
        touristId ?? await repository.currentTouristId();
    if (resolvedTouristId == null || resolvedTouristId.isEmpty) {
      return (requiresSignIn: true, alreadyReported: false, frozePlace: false);
    }
    final bool duplicate = await repository.report.alreadyReported(
      kind: 'restaurant',
      placeId: restaurantId,
      touristId: resolvedTouristId,
    );
    if (duplicate) {
      return (requiresSignIn: false, alreadyReported: true, frozePlace: false);
    }
    await repository.report.insertReport(
      kind: 'restaurant',
      placeId: restaurantId,
      reason: reason.name,
      touristId: resolvedTouristId,
    );
    final int count = await repository.restaurant.incrementReportCount(
      restaurantId,
    );
    final bool frozePlace = shouldFreezeAfterReport(count);
    if (frozePlace) {
      await repository.restaurant.freeze(restaurantId);
      // Frozen places are no longer 'available', so cached map pins must go:
      // the next read (right after the UI leaves the page) has no pin for it.
      repository.map.clearCache();
    }
    return (
      requiresSignIn: false,
      alreadyReported: false,
      frozePlace: frozePlace,
    );
  }

  /// Freeze once the reported count REACHES [_reportFreezeAtReports] (so the
  /// 5th report freezes). Pure so the boundary is unit-testable without a
  /// repository seam.
  @visibleForTesting
  static bool shouldFreezeAfterReport(int reportedCount) =>
      reportedCount >= _reportFreezeAtReports;

  /// A restaurant is frozen once its report count reaches this many reports.
  static const int _reportFreezeAtReports = 5;

  Future<List<Restaurant>> nearby({
    required TouristLocation location,
    required double radiusKm,
    required int limit,
  }) async {
    final List<Restaurant> candidates = _withinRadius(
      _availableSummaries(
        _measure(await repository.getRestaurants(), location),
      ),
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
      return distance == null || distance <= radiusKm * 1000;
    }).toList();
    matches.sort(
      (Restaurant a, Restaurant b) => (a.distanceMetres ?? double.infinity)
          .compareTo(b.distanceMetres ?? double.infinity),
    );
    return matches;
  }

  /// Quick Mode starts at 1 km and expands silently until [limit] nearest
  /// eligible restaurants are found or the 10 km Use Case boundary is reached.
  Future<List<Restaurant>> nearbyWithAutomaticExpansion({
    required TouristLocation location,
    required int limit,
    double initialRadiusKm = 1,
    double radiusStepKm = 1,
    double maximumRadiusKm = 10,
  }) async {
    final List<Restaurant> measured = _availableSummaries(
      _measure(await repository.getRestaurants(), location),
    );
    final List<Restaurant> eligible = await _eligibleRestaurants(
      _withinRadius(measured, radiusKm: maximumRadiusKm),
    );
    double radiusKm = initialRadiusKm;
    List<Restaurant> available = const <Restaurant>[];
    while (radiusKm <= maximumRadiusKm) {
      final List<Restaurant> results = _withinRadius(
        eligible,
        radiusKm: radiusKm,
      ).take(limit).toList(growable: false);
      available = results;
      if (results.length >= limit || !location.isKnown) {
        return _hydrateSelected(results);
      }
      radiusKm += radiusStepKm;
    }
    return _hydrateSelected(available);
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
    final DateTime malaysiaNow = currentTime().toUtc().add(
      const Duration(hours: 8),
    );
    return restaurants
        .where(
          (Restaurant restaurant) =>
              restaurant.status?.trim().toLowerCase() == 'available' &&
              !_isConfidentlyClosed(restaurant, malaysiaNow),
        )
        .toList(growable: false);
  }

  bool _isConfidentlyClosed(Restaurant restaurant, DateTime malaysiaNow) {
    final List<OpeningHour> hours = restaurant.openingHours;
    if (hours.isEmpty) return false;
    final Weekday today = Weekday.values[malaysiaNow.weekday - 1];
    final Weekday previous =
        Weekday.values[(malaysiaNow.weekday + Weekday.values.length - 2) %
            Weekday.values.length];
    final int minute = malaysiaNow.hour * 60 + malaysiaNow.minute;

    final bool previousDayStillOpen = hours.any((OpeningHour row) {
      final int? opens = row.opensAt;
      final int? closes = row.closesAt;
      return row.day == previous &&
          row.status == DayStatus.open &&
          opens != null &&
          closes != null &&
          closes < opens &&
          minute < closes;
    });
    if (previousDayStillOpen) return false;

    final List<OpeningHour> todayRows = hours
        .where((OpeningHour row) => row.day == today)
        .toList(growable: false);
    if (todayRows.isEmpty ||
        todayRows.any((OpeningHour row) => row.status == DayStatus.unknown)) {
      return false;
    }
    final bool openNow = todayRows.any((OpeningHour row) {
      final int? opens = row.opensAt;
      final int? closes = row.closesAt;
      if (row.status != DayStatus.open || opens == null || closes == null) {
        return false;
      }
      if (closes == 1440) return minute >= opens;
      if (closes < opens) return minute >= opens;
      return minute >= opens && minute < closes;
    });
    return !openNow;
  }

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
                  (RestaurantItem item) => !_conflictsWithRestrictions(
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
