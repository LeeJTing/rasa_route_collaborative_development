import '../../domain_model/restaurant.dart';
import '../../domain_model/tourist_location.dart';
import '../repositories/discovery_repository_facade.dart';
import 'dart:math' as math;
import 'package:meta/meta.dart' show visibleForTesting;

/// Finding and filtering restaurants.
///
/// A business-logic class knows exactly one thing below it: a **repository
/// facade**. It never sees a repository, a shared client or Flutter.
class RestaurantDiscoveryLogic {
  RestaurantDiscoveryLogic({
    @visibleForTesting DiscoveryRepositoryFacade? discoveryRepository,
  }) : repository = discoveryRepository ?? DiscoveryRepositoryFacade();

  final DiscoveryRepositoryFacade repository;

  Future<List<Restaurant>> nearby({
    required TouristLocation location,
    required double radiusKm,
    required int limit,
  }) async {
    final List<Restaurant> restaurants = await repository.getRestaurants();
    return _withinRadius(
      _measure(restaurants, location),
      radiusKm: radiusKm,
      limit: limit,
    );
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
    items: restaurant.items,
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
    required int limit,
  }) {
    final List<Restaurant> matches = measured.where((Restaurant restaurant) {
      final double? distance = restaurant.distanceMetres;
      return distance == null || distance <= radiusKm * 1000;
    }).toList();
    matches.sort(
      (Restaurant a, Restaurant b) => (a.distanceMetres ?? double.infinity)
          .compareTo(b.distanceMetres ?? double.infinity),
    );
    return matches.take(limit).toList(growable: false);
  }

  /// Quick Mode starts at 1 km and expands silently until [limit] nearest
  /// restaurants are found or the 10 km Use Case boundary is reached.
  ///
  /// When the boundary contains fewer than [limit] restaurants, every
  /// available restaurant in that boundary is returned.
  Future<List<Restaurant>> nearbyWithAutomaticExpansion({
    required TouristLocation location,
    required int limit,
    double initialRadiusKm = 1,
    double radiusStepKm = 1,
    double maximumRadiusKm = 10,
  }) async {
    final List<Restaurant> measured = _measure(
      await repository.getRestaurants(),
      location,
    );
    double radiusKm = initialRadiusKm;
    List<Restaurant> available = const <Restaurant>[];
    while (radiusKm <= maximumRadiusKm) {
      final List<Restaurant> results = _withinRadius(
        measured,
        radiusKm: radiusKm,
        limit: limit,
      );
      available = results;
      if (results.length >= limit || !location.isKnown) return results;
      radiusKm += radiusStepKm;
    }
    return available;
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
