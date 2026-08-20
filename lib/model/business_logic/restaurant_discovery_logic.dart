import '../repositories/discovery_repository_facade.dart';
import '../../domain_model/restaurant.dart';
import '../data_models/location_data_model.dart';
import 'dart:math' as math;

/// Finding and filtering restaurants.
///
/// A business-logic class knows exactly one thing below it: a **repository
/// facade**. It never sees a repository, a shared client or Flutter.
class RestaurantDiscoveryLogic {
  RestaurantDiscoveryLogic();

  final DiscoveryRepositoryFacade repository = DiscoveryRepositoryFacade();

  Future<List<Restaurant>> nearby({
    required LocationDataModel location,
    required double radiusKm,
    required int limit,
  }) async {
    final List<Restaurant> restaurants = await repository.getRestaurants();
    final List<Restaurant> measured = restaurants
        .map((Restaurant restaurant) {
          if (!location.isKnown ||
              restaurant.latitude == null ||
              restaurant.longitude == null) {
            return restaurant;
          }
          return restaurant.copyWith(
            distanceMetres: _distanceMetres(
              location.latitude,
              location.longitude,
              restaurant.latitude!,
              restaurant.longitude!,
            ),
          );
        })
        .where((Restaurant restaurant) {
          final double? distance = restaurant.distanceMetres;
          return distance == null || distance <= radiusKm * 1000;
        })
        .toList();
    measured.sort(
      (Restaurant a, Restaurant b) => (a.distanceMetres ?? double.infinity)
          .compareTo(b.distanceMetres ?? double.infinity),
    );
    return measured.take(limit).toList(growable: false);
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
