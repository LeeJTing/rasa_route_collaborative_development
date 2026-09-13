import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/opening_hour.dart';
import 'package:rasa_route_collaborative_development/domain_model/dietary_restriction.dart';
import 'package:rasa_route_collaborative_development/domain_model/food_distribution.dart';
import 'package:rasa_route_collaborative_development/domain_model/matches_recommendation.dart';
import 'package:rasa_route_collaborative_development/domain_model/restaurant.dart';
import 'package:rasa_route_collaborative_development/domain_model/restaurant_item.dart';
import 'package:rasa_route_collaborative_development/domain_model/tourist_location.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/restaurant_discovery_logic.dart';
import 'package:rasa_route_collaborative_development/model/repositories/discovery_repository_facade.dart';

void main() {
  group('Quick Mode automatic radius expansion', () {
    test(
      'restaurant details calculate distance from the supplied origin',
      () async {
        final Restaurant restaurant = _restaurant(1, distanceKm: 2);
        final RestaurantDiscoveryLogic logic = _TestRestaurantDiscoveryLogic(
          _FakeDiscoveryRepositoryFacade(<Restaurant>[restaurant]),
        );

        final Restaurant? result = await logic.findById(
          restaurant.id,
          origin: _testLocation,
        );

        expect(result, isNotNull);
        expect(result!.distanceMetres, closeTo(2000, 20));
      },
    );

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
        final _FakeDiscoveryRepositoryFacade repository =
            _FakeDiscoveryRepositoryFacade(restaurants);
        final RestaurantDiscoveryLogic logic = _TestRestaurantDiscoveryLogic(
          repository,
        );

        final List<Restaurant> results = await logic
            .nearbyWithAutomaticExpansion(location: _testLocation);

        expect(results, hasLength(20));
        expect(
          results.map((Restaurant item) => item.id),
          orderedEquals(<int>[for (int index = 0; index < 20; index++) index]),
        );
        expect(repository.allRestaurantQueryCount, 0);
        expect(repository.nearbyRestaurantQueryCount, 1);
        expect(repository.requestedMaximumDistanceKm, 10);
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
            .nearbyWithAutomaticExpansion(location: _testLocation);

        expect(
          results.map((Restaurant item) => item.id),
          orderedEquals(<int>[1, 2, 3]),
        );
      },
    );

    test(
      'excludes restaurants without coordinates from radius results',
      () async {
        final RestaurantDiscoveryLogic logic = _TestRestaurantDiscoveryLogic(
          _FakeDiscoveryRepositoryFacade(<Restaurant>[
            Restaurant(
              id: 99,
              name: 'Unknown location',
              category: 'Malaysian',
              address: '',
              phone: '',
              website: '',
              openingHours: const <OpeningHour>[],
            ),
            _restaurant(1, distanceKm: 0.5),
          ]),
        );

        final List<Restaurant> results = await logic
            .nearbyWithAutomaticExpansion(location: _testLocation);

        expect(
          results.map((Restaurant item) => item.id),
          orderedEquals(<int>[1]),
        );
      },
    );

    test(
      'filters submitted landmarks by radius, hours and dietary associations',
      () async {
        final _FakeDiscoveryRepositoryFacade repository =
            _FakeDiscoveryRepositoryFacade(
              const <Restaurant>[],
              restrictions: const <DietaryRestriction>[
                DietaryRestriction(id: 9, name: 'No Coconut'),
              ],
              restrictionIdsByFood: const <int, List<int>>{
                100: <int>[9],
              },
              occurrences: <FoodOccurrence>[
                _landmarkOccurrence(1, 101, 'Chicken Rice', distanceKm: 0.5),
                _landmarkOccurrence(2, 100, 'Nasi Lemak', distanceKm: 0.4),
                _landmarkOccurrence(3, 101, 'Far Chicken Rice', distanceKm: 11),
                _landmarkOccurrence(4, 101, 'Closed Food', distanceKm: 0.3),
              ],
              placeOpeningHours: const <String, List<OpeningHour>>{
                'submittedLandmark:4': <OpeningHour>[
                  OpeningHour(
                    id: 4,
                    day: Weekday.monday,
                    status: DayStatus.closed,
                  ),
                ],
              },
            );
        final RestaurantDiscoveryLogic logic = _TestRestaurantDiscoveryLogic(
          repository,
          now: () => DateTime.utc(2026, 8, 31, 2),
        );

        final results = await logic.nearbyLandmarksWithAutomaticExpansion(
          location: _testLocation,
        );

        expect(results.map((item) => item.id), orderedEquals(<int>[1]));
        expect(
          results.single.foodNames,
          orderedEquals(<String>['Chicken Rice']),
        );
      },
    );

    test(
      'shows the category most dishes carry, worded like a restaurant row',
      () async {
        final _FakeDiscoveryRepositoryFacade repository =
            _FakeDiscoveryRepositoryFacade(
              const <Restaurant>[],
              occurrences: <FoodOccurrence>[
                _landmarkOccurrence(
                  1,
                  101,
                  'Wan Tan Mee',
                  distanceKm: 0.5,
                  placeCategory: 'Malay',
                  itemFoodCategory: 'Chinese',
                ),
                _landmarkOccurrence(
                  1,
                  102,
                  'Char Kuey Teow',
                  distanceKm: 0.5,
                  placeCategory: 'Malay',
                  itemFoodCategory: 'Chinese',
                ),
                _landmarkOccurrence(
                  1,
                  103,
                  'Nasi Lemak',
                  distanceKm: 0.5,
                  placeCategory: 'Malay',
                  itemFoodCategory: 'Malay',
                ),
              ],
            );
        final RestaurantDiscoveryLogic logic = _TestRestaurantDiscoveryLogic(
          repository,
        );

        final results = await logic.nearbyLandmarksWithAutomaticExpansion(
          location: _testLocation,
        );

        // Stored as "Malay" (the first dish's category at submission), but
        // MOST of the dishes are Chinese - and the card words it exactly like
        // a restaurant row does.
        expect(results.single.category, 'Chinese');
        expect(results.single.categoryLabel, 'Chinese Restaurant');
      },
    );

    test('uses the lowest landmark dish price as the starting price', () async {
      final _FakeDiscoveryRepositoryFacade repository =
          _FakeDiscoveryRepositoryFacade(
            const <Restaurant>[],
            occurrences: <FoodOccurrence>[
              _landmarkOccurrence(
                1,
                101,
                'Chicken Rice',
                distanceKm: 0.5,
                itemPrice: 10,
                itemImageUrl: 'https://cdn.example.com/chicken-rice.jpg',
                itemIngredients: 'Rice, chicken, chili sauce',
              ),
              _landmarkOccurrence(
                1,
                102,
                'Nasi Lemak',
                distanceKm: 0.5,
                itemPrice: 20,
              ),
              // No price recorded - left out of the starting price.
              _landmarkOccurrence(1, 103, 'Cendol', distanceKm: 0.5),
            ],
          );
      final RestaurantDiscoveryLogic logic = _TestRestaurantDiscoveryLogic(
        repository,
      );

      final List<SubmittedLandmarkRecommendation> results = await logic
          .nearbyLandmarksWithAutomaticExpansion(location: _testLocation);

      // The headline price is the STARTING price - the LOWEST known dish
      // price - so the card can read "From RM 10.00" like a restaurant's.
      expect(results.single.price, 10);
      expect(
        results.single.dishes.map((SubmittedLandmarkDish dish) => dish.name),
        orderedEquals(<String>['Chicken Rice', 'Nasi Lemak', 'Cendol']),
      );
      expect(results.single.dishes.first.price, 10);
      expect(
        results.single.dishes.first.imageUrl,
        'https://cdn.example.com/chicken-rice.jpg',
      );
      expect(results.single.dishes.last.price, isNull);
      // The dish's ingredients ride along for the expanded row's gray line -
      // ingredients the record does not have stay null.
      expect(
        results.single.dishes.first.ingredients,
        'Rice, chicken, chili sauce',
      );
      expect(results.single.dishes[1].ingredients, isNull);
    });

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
            .nearbyWithAutomaticExpansion(location: _testLocation);

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

      final List<Restaurant> results = await logic.nearbyWithAutomaticExpansion(
        location: _testLocation,
      );

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
  String status = 'available',
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

FoodOccurrence _landmarkOccurrence(
  int landmarkId,
  int localFoodId,
  String foodName, {
  required double distanceKm,
  double? itemPrice,
  String? itemImageUrl,
  String? itemIngredients,
  String placeCategory = 'Food stall',
  String? itemFoodCategory,
}) => FoodOccurrence(
  sourceId: '$landmarkId',
  source: FoodOccurrenceSource.submittedLandmark,
  placeName: 'Landmark $landmarkId',
  localFoodId: localFoodId,
  foodName: foodName,
  foodType: 'Food',
  latitude: _testLocation.latitude + distanceKm / 111.2,
  longitude: _testLocation.longitude,
  placeCategory: placeCategory,
  itemPrice: itemPrice,
  itemImageUrl: itemImageUrl,
  itemIngredients: itemIngredients,
  itemFoodCategory: itemFoodCategory,
);

class _FakeDiscoveryRepositoryFacade extends DiscoveryRepositoryFacade {
  _FakeDiscoveryRepositoryFacade(
    this.restaurants, {
    this.menuItemsByRestaurant = const <int, List<RestaurantItem>>{},
    this.restrictions = const <DietaryRestriction>[],
    this.restrictionIdsByFood = const <int, List<int>>{},
    this.occurrences = const <FoodOccurrence>[],
    this.placeOpeningHours = const <String, List<OpeningHour>>{},
  });

  final List<Restaurant> restaurants;
  final Map<int, List<RestaurantItem>> menuItemsByRestaurant;
  final List<DietaryRestriction> restrictions;
  final Map<int, List<int>> restrictionIdsByFood;
  final List<FoodOccurrence> occurrences;
  final Map<String, List<OpeningHour>> placeOpeningHours;
  List<int> requestedRestaurantIds = const <int>[];
  int allRestaurantQueryCount = 0;
  int nearbyRestaurantQueryCount = 0;
  double? requestedMaximumDistanceKm;

  @override
  Future<List<Restaurant>> getRestaurants() async {
    allRestaurantQueryCount++;
    return restaurants;
  }

  @override
  Future<Restaurant?> getRestaurantById(int restaurantId) async {
    for (final Restaurant restaurant in restaurants) {
      if (restaurant.id == restaurantId) return restaurant;
    }
    return null;
  }

  @override
  Future<List<Restaurant>> getRestaurantsNear({
    required double latitude,
    required double longitude,
    required double maximumDistanceKm,
  }) async {
    nearbyRestaurantQueryCount++;
    requestedMaximumDistanceKm = maximumDistanceKm;
    return restaurants;
  }

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

  @override
  Future<List<FoodOccurrence>> foodOccurrences() async => occurrences;

  @override
  Future<Map<String, List<OpeningHour>>> openingHoursByPlace({
    Set<String>? placeKeys,
  }) async => placeOpeningHours;

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
