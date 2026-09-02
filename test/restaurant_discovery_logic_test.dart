import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/opening_hour.dart';
import 'package:rasa_route_collaborative_development/domain_model/dietary_restriction.dart';
import 'package:rasa_route_collaborative_development/domain_model/restaurant.dart';
import 'package:rasa_route_collaborative_development/domain_model/restaurant_item.dart';
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
        final RestaurantDiscoveryLogic logic = _TestRestaurantDiscoveryLogic(
          _FakeDiscoveryRepositoryFacade(restaurants),
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
        final RestaurantDiscoveryLogic logic = _TestRestaurantDiscoveryLogic(
          _FakeDiscoveryRepositoryFacade(restaurants),
        );

        final List<Restaurant> results = await logic
            .nearbyWithAutomaticExpansion(location: _testLocation, limit: 20);

        expect(
          results.map((Restaurant item) => item.id),
          orderedEquals(<int>[1, 2, 3]),
        );
      },
    );

    test(
      'hydrates only selected restaurants and preserves their menu',
      () async {
        final List<Restaurant> summaries = <Restaurant>[
          _restaurant(1, distanceKm: 3),
          _restaurant(2, distanceKm: 1),
          _restaurant(3, distanceKm: 2),
        ];
        final _FakeDiscoveryRepositoryFacade repository =
            _FakeDiscoveryRepositoryFacade(summaries);
        final RestaurantDiscoveryLogic logic = _TestRestaurantDiscoveryLogic(
          repository,
        );

        final List<Restaurant> results = await logic.nearby(
          location: _testLocation,
          radiusKm: 10,
          limit: 2,
        );

        expect(repository.requestedRestaurantIds, orderedEquals(<int>[2, 3]));
        expect(
          results.map((Restaurant restaurant) => restaurant.id),
          orderedEquals(<int>[2, 3]),
        );
        for (final Restaurant restaurant in results) {
          expect(restaurant.items, hasLength(1));
          expect(restaurant.items.single.restaurantId, restaurant.id);
        }
      },
    );

    test('excludes restaurants that are closed now or hidden', () async {
      final List<Restaurant> restaurants = <Restaurant>[
        _restaurant(
          1,
          distanceKm: 0.2,
          openingHours: const <OpeningHour>[
            OpeningHour(id: 0, day: Weekday.monday, status: DayStatus.closed),
          ],
        ),
        _restaurant(2, distanceKm: 0.3, status: 'hidden'),
        _restaurant(
          3,
          distanceKm: 0.4,
          openingHours: const <OpeningHour>[
            OpeningHour(
              id: 0,
              day: Weekday.monday,
              status: DayStatus.open,
              opensAt: 0,
              closesAt: 1440,
            ),
          ],
        ),
      ];
      final RestaurantDiscoveryLogic logic = _TestRestaurantDiscoveryLogic(
        _FakeDiscoveryRepositoryFacade(restaurants),
        now: () => DateTime.utc(2026, 8, 31, 2),
      );

      final List<Restaurant> results = await logic.nearbyWithAutomaticExpansion(
        location: _testLocation,
        limit: 20,
      );

      expect(
        results.map((Restaurant item) => item.id),
        orderedEquals(<int>[3]),
      );
    });

    test('keeps unknown hours instead of treating them as closed', () async {
      final Restaurant restaurant = _restaurant(
        1,
        distanceKm: 0.2,
        openingHours: const <OpeningHour>[
          OpeningHour(id: 0, day: Weekday.monday, status: DayStatus.unknown),
        ],
      );
      final RestaurantDiscoveryLogic logic = _TestRestaurantDiscoveryLogic(
        _FakeDiscoveryRepositoryFacade(<Restaurant>[restaurant]),
        now: () => DateTime.utc(2026, 8, 31, 2),
      );

      final List<Restaurant> results = await logic.nearbyWithAutomaticExpansion(
        location: _testLocation,
        limit: 20,
      );

      expect(results, hasLength(1));
    });

    test(
      'removes conflicting menu items and excludes restaurants with none left',
      () async {
        final List<Restaurant> restaurants = <Restaurant>[
          _restaurant(1, distanceKm: 0.2),
          _restaurant(2, distanceKm: 0.3),
        ];
        final _FakeDiscoveryRepositoryFacade repository =
            _FakeDiscoveryRepositoryFacade(
              restaurants,
              restrictions: const <DietaryRestriction>[
                DietaryRestriction(id: 9, name: 'No Shrimp/Prawn'),
              ],
              restrictionIdsByFood: const <int, List<int>>{
                100: <int>[9],
                102: <int>[9],
              },
              menuItemsByRestaurant: <int, List<RestaurantItem>>{
                1: const <RestaurantItem>[
                  RestaurantItem(
                    id: 10,
                    restaurantId: 1,
                    localFoodId: 100,
                    foodName: 'Prawn Noodle',
                    currency: 'RM',
                    foodCategory: 'Noodle',
                  ),
                  RestaurantItem(
                    id: 11,
                    restaurantId: 1,
                    localFoodId: 101,
                    foodName: 'Chicken Rice',
                    currency: 'RM',
                    foodCategory: 'Rice',
                  ),
                ],
                2: const <RestaurantItem>[
                  RestaurantItem(
                    id: 20,
                    restaurantId: 2,
                    localFoodId: 102,
                    foodName: 'Seafood Noodles',
                    ingredients: 'Fresh shrimp and stock',
                    currency: 'RM',
                    foodCategory: 'Noodle',
                  ),
                ],
              },
            );
        final RestaurantDiscoveryLogic logic = _TestRestaurantDiscoveryLogic(
          repository,
        );

        final List<Restaurant> results = await logic
            .nearbyWithAutomaticExpansion(location: _testLocation, limit: 20);

        expect(
          results.map((Restaurant item) => item.id),
          orderedEquals(<int>[1]),
        );
        expect(
          results.single.items.map((RestaurantItem item) => item.id),
          <int>[11],
        );
      },
    );

    test('does not infer dietary restrictions from ingredient text', () async {
      final Restaurant restaurant = _restaurant(1, distanceKm: 0.2);
      final _FakeDiscoveryRepositoryFacade repository =
          _FakeDiscoveryRepositoryFacade(
            <Restaurant>[restaurant],
            restrictions: const <DietaryRestriction>[
              DietaryRestriction(id: 9, name: 'No Shrimp/Prawn'),
            ],
            menuItemsByRestaurant: const <int, List<RestaurantItem>>{
              1: <RestaurantItem>[
                RestaurantItem(
                  id: 10,
                  restaurantId: 1,
                  localFoodId: 100,
                  foodName: 'Seafood Noodles',
                  ingredients: 'Fresh shrimp and stock',
                  currency: 'RM',
                  foodCategory: 'Noodle',
                ),
              ],
            },
          );
      final RestaurantDiscoveryLogic logic = _TestRestaurantDiscoveryLogic(
        repository,
      );

      final List<Restaurant> results = await logic
          .nearbyWithAutomaticExpansion(location: _testLocation, limit: 20);

      expect(results, hasLength(1));
      expect(results.single.items, hasLength(1));
    });
  });
}

const TouristLocation _testLocation = TouristLocation(
  latitude: 3,
  longitude: 101,
);

class _TestRestaurantDiscoveryLogic extends RestaurantDiscoveryLogic {
  _TestRestaurantDiscoveryLogic(this.fakeRepository, {DateTime Function()? now})
    : now = now ?? DateTime.now;

  final DiscoveryRepositoryFacade fakeRepository;
  final DateTime Function() now;

  @override
  DiscoveryRepositoryFacade createRepository() => fakeRepository;

  @override
  DateTime currentTime() => now();
}

Restaurant _restaurant(
  int id, {
  required double distanceKm,
  List<OpeningHour> openingHours = const <OpeningHour>[],
  String? status,
}) => Restaurant(
  id: id,
  name: 'Restaurant $id',
  category: 'Malaysian',
  address: 'Test address',
  latitude: _testLocation.latitude + distanceKm / 111.2,
  longitude: _testLocation.longitude,
  phone: '',
  website: '',
  openingHours: openingHours,
  status: status,
);

class _FakeDiscoveryRepositoryFacade extends DiscoveryRepositoryFacade {
  _FakeDiscoveryRepositoryFacade(
    this.restaurants, {
    this.menuItemsByRestaurant = const <int, List<RestaurantItem>>{},
    this.restrictions = const <DietaryRestriction>[],
    this.restrictionIdsByFood = const <int, List<int>>{},
  });

  final List<Restaurant> restaurants;
  final Map<int, List<RestaurantItem>> menuItemsByRestaurant;
  final List<DietaryRestriction> restrictions;
  final Map<int, List<int>> restrictionIdsByFood;
  List<int> requestedRestaurantIds = const <int>[];

  @override
  Future<List<Restaurant>> getRestaurants() async => restaurants;

  @override
  Future<List<Restaurant>> getRestaurantsByIds(List<int> restaurantIds) async {
    requestedRestaurantIds = List<int>.of(restaurantIds);
    return restaurants
        .where((Restaurant restaurant) => restaurantIds.contains(restaurant.id))
        .map(
          (Restaurant restaurant) => Restaurant(
            id: restaurant.id,
            name: restaurant.name,
            category: restaurant.category,
            address: restaurant.address,
            rating: restaurant.rating,
            latitude: restaurant.latitude,
            longitude: restaurant.longitude,
            phone: restaurant.phone,
            website: restaurant.website,
            imageUrl: restaurant.imageUrl,
            openingHours: restaurant.openingHours,
            status: restaurant.status,
            items: _itemsFor(restaurant.id),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<RestaurantItem>> getRestaurantItemsByRestaurantIds(
    List<int> restaurantIds,
  ) async => restaurantIds.expand(_itemsFor).toList(growable: false);

  @override
  Future<List<DietaryRestriction>> getCurrentDietaryRestrictions() async =>
      restrictions;

  @override
  Future<Map<int, List<int>>> getRestrictionIdsByFood() async =>
      restrictionIdsByFood;

  List<RestaurantItem> _itemsFor(int restaurantId) =>
      menuItemsByRestaurant[restaurantId] ??
      <RestaurantItem>[
        RestaurantItem(
          id: restaurantId * 10,
          restaurantId: restaurantId,
          localFoodId: restaurantId,
          foodName: 'Food $restaurantId',
          currency: 'RM',
          foodCategory: 'Local food',
        ),
      ];
}
