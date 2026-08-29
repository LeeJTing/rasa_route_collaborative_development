import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/opening_hour.dart';
import 'package:rasa_route_collaborative_development/domain_model/restaurant.dart';
import 'package:rasa_route_collaborative_development/domain_model/tourist_location.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/restaurant_discovery_logic.dart';
import 'package:rasa_route_collaborative_development/model/repositories/discovery_repository_facade.dart';

void main() {
  group('Quick Mode automatic radius expansion', () {
    test(
      'continues past early results until 20 restaurants are found',
      () async {
        final List<Restaurant> restaurants = <Restaurant>[
          for (int index = 0; index < 5; index++)
            _restaurant(index, distanceKm: 0.5 + index * 0.05),
          for (int index = 5; index < 20; index++)
            _restaurant(index, distanceKm: 2 + (index - 5) * 0.04),
          _restaurant(20, distanceKm: 11),
        ];
        final RestaurantDiscoveryLogic logic = RestaurantDiscoveryLogic(
          discoveryRepository: _FakeDiscoveryRepositoryFacade(restaurants),
        );

        final List<Restaurant> results = await logic
            .nearbyWithAutomaticExpansion(location: _testLocation, limit: 20);

        expect(results, hasLength(20));
        expect(
          results.map((Restaurant item) => item.id),
          orderedEquals(<int>[for (int index = 0; index < 20; index++) index]),
        );
      },
    );

    test(
      'returns every available restaurant when 10 km has fewer than 20',
      () async {
        final List<Restaurant> restaurants = <Restaurant>[
          _restaurant(1, distanceKm: 0.5),
          _restaurant(2, distanceKm: 4),
          _restaurant(3, distanceKm: 9),
          _restaurant(4, distanceKm: 11),
        ];
        final RestaurantDiscoveryLogic logic = RestaurantDiscoveryLogic(
          discoveryRepository: _FakeDiscoveryRepositoryFacade(restaurants),
        );

        final List<Restaurant> results = await logic
            .nearbyWithAutomaticExpansion(location: _testLocation, limit: 20);

        expect(
          results.map((Restaurant item) => item.id),
          orderedEquals(<int>[1, 2, 3]),
        );
      },
    );
  });
}

const TouristLocation _testLocation = TouristLocation(
  latitude: 3,
  longitude: 101,
);

Restaurant _restaurant(int id, {required double distanceKm}) => Restaurant(
  id: id,
  name: 'Restaurant $id',
  category: 'Malaysian',
  address: 'Test address',
  latitude: _testLocation.latitude + distanceKm / 111.2,
  longitude: _testLocation.longitude,
  phone: '',
  website: '',
  openingHours: const <OpeningHour>[],
);

class _FakeDiscoveryRepositoryFacade extends DiscoveryRepositoryFacade {
  _FakeDiscoveryRepositoryFacade(this.restaurants);

  final List<Restaurant> restaurants;

  @override
  Future<List<Restaurant>> getRestaurants() async => restaurants;
}
