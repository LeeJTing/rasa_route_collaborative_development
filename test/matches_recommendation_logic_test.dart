import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/food_distribution.dart';
import 'package:rasa_route_collaborative_development/domain_model/local_food.dart';
import 'package:rasa_route_collaborative_development/domain_model/opening_hour.dart';
import 'package:rasa_route_collaborative_development/domain_model/matches_recommendation.dart';
import 'package:rasa_route_collaborative_development/domain_model/region.dart';
import 'package:rasa_route_collaborative_development/domain_model/restaurant.dart';
import 'package:rasa_route_collaborative_development/domain_model/restaurant_item.dart';
import 'package:rasa_route_collaborative_development/domain_model/swipe_session.dart';
import 'package:rasa_route_collaborative_development/domain_model/tourist_location.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/matches_recommendation_logic.dart';
import 'package:rasa_route_collaborative_development/model/repositories/discovery_repository_facade.dart';

void main() {
  group('MatchesRecommendationLogic', () {
    late _MatchesRepository repository;
    late MatchesRecommendationLogic logic;

    setUp(() {
      repository = _MatchesRepository();
      logic = _TestMatchesRecommendationLogic(repository);
    });

    test(
      'groups real restaurants and landmarks under liked foods only',
      () async {
        final MatchesRecommendationResult result = await logic.recommendations(
          const MatchesRecommendationRequest(
            stateCode: 'TST',
            origin: TouristLocation(latitude: 1, longitude: 1),
          ),
        );

        expect(result.groups, hasLength(1));
        expect(result.groups.single.food.id, 1);
        expect(result.groups.single.restaurants.single.id, 10);
        expect(result.groups.single.restaurants.single.items, hasLength(1));
        // The headline price is restaurant-wide: the RM2.50 item belongs to a
        // different food, but it is still the restaurant's cheapest item.
        expect(result.groups.single.restaurantStartingPrices[10], 2.5);
        expect(
          result.groups.single.restaurants.single.items.single.localFoodId,
          1,
        );
        expect(result.groups.single.submittedLandmarks.single.id, 20);
        expect(
          result.groups.single.submittedLandmarks.single.foodNames,
          containsAll(<String>['Liked Food', 'Not Liked Food']),
        );
        // Each dish carries its OWN price, and the landmark's headline price
        // is the STARTING price - the LOWEST of them (8 and 12 -> 8) - so
        // the card can read "From RM 8.00" like a restaurant's.
        final SubmittedLandmarkRecommendation landmark =
            result.groups.single.submittedLandmarks.single;
        expect(
          landmark.dishes
              .map((SubmittedLandmarkDish dish) => dish.name)
              .toList(),
          orderedEquals(<String>['Liked Food', 'Not Liked Food']),
        );
        expect(landmark.dishes.first.price, 8);
        expect(landmark.dishes.last.price, 12);
        expect(landmark.price, 8);
        expect(landmark.dishes.first.ingredients, 'Rice, sambal');
        expect(landmark.dishes.last.ingredients, isNull);
        // The tourist-supplied address rides along for the card's address
        // row.
        expect(landmark.address, 'Jalan Ampang, Kuala Lumpur');
      },
    );

    test('removing a match persists only the updated local session', () async {
      final SwipeSession updated = await logic.removeLike(
        repository.session,
        1,
      );

      expect(updated.likedFoodIds, isEmpty);
      expect(repository.savedSession, same(updated));
    });

    test('keeps a real occurrence when the catalogue page omits it', () async {
      final MatchesRecommendationLogic fallbackLogic =
          _TestMatchesRecommendationLogic(
            _MissingCatalogueRestaurantRepository(),
          );

      final MatchesRecommendationResult result = await fallbackLogic
          .recommendations(
            const MatchesRecommendationRequest(
              stateCode: 'TST',
              origin: TouristLocation(latitude: 1, longitude: 1),
            ),
          );

      expect(result.groups.single.restaurants.single.id, 10);
      expect(result.groups.single.restaurants.single.name, 'Actual Restaurant');
    });

    test(
      'uses occurrence prices when catalogue summaries omit menu items',
      () async {
        final _MatchesRepository summaryRepository = _MatchesRepository()
          ..catalogueIncludesItems = false;
        final MatchesRecommendationLogic summaryLogic =
            _TestMatchesRecommendationLogic(summaryRepository);

        final MatchesRecommendationResult result = await summaryLogic
            .recommendations(
              const MatchesRecommendationRequest(
                stateCode: 'TST',
                origin: TouristLocation(latitude: 1, longitude: 1),
              ),
            );

        final List<RestaurantItem> items =
            result.groups.single.restaurants.single.items;
        expect(items, hasLength(1));
        expect(items.single.price, 9.5);
        expect(result.groups.single.restaurantStartingPrices[10], 2.5);
      },
    );

    test('excludes a recommendation confidently closed now', () async {
      repository.hoursByPlace = const <String, List<OpeningHour>>{
        'restaurant:10': <OpeningHour>[
          OpeningHour(id: 1, day: Weekday.monday, status: DayStatus.closed),
        ],
      };

      final MatchesRecommendationResult result = await logic.recommendations(
        const MatchesRecommendationRequest(
          stateCode: 'TST',
          origin: TouristLocation(latitude: 1, longitude: 1),
        ),
      );

      expect(result.groups.single.restaurants, isEmpty);
      expect(result.groups.single.submittedLandmarks, isNotEmpty);
    });

    test(
      'does not substitute the explored state centre for missing GPS',
      () async {
        final MatchesRecommendationResult result = await logic.recommendations(
          const MatchesRecommendationRequest(
            stateCode: 'TST',
            origin: TouristLocation.unknown,
          ),
        );

        expect(result.groups.single.restaurants.single.distanceMetres, isNull);
        expect(
          result.groups.single.submittedLandmarks.single.distanceMetres,
          double.infinity,
        );
      },
    );
  });
}

class _TestMatchesRecommendationLogic extends MatchesRecommendationLogic {
  _TestMatchesRecommendationLogic(this.repository);

  final DiscoveryRepositoryFacade repository;

  @override
  DiscoveryRepositoryFacade createRepository() => repository;

  @override
  DateTime currentTime() => DateTime(2026, 9, 7, 12);
}

class _MissingCatalogueRestaurantRepository extends _MatchesRepository {
  @override
  Future<List<Restaurant>> getRestaurants() async => const <Restaurant>[];
}

class _MatchesRepository extends DiscoveryRepositoryFacade {
  _MatchesRepository();

  final SwipeSession session = const SwipeSession(
    sessionId: 'session',
    touristId: 'tourist',
    stateCode: 'TST',
    candidateFoodIds: <int>[1, 2],
    likedFoodIds: <int>[1],
    dislikedFoodIds: <int>[],
  );
  SwipeSession? savedSession;
  Map<String, List<OpeningHour>> hoursByPlace =
      const <String, List<OpeningHour>>{};
  bool catalogueIncludesItems = true;

  @override
  Future<String?> currentTouristId() async => 'tourist';

  @override
  Future<List<Region>> malaysiaRegions() async => const <Region>[
    Region(
      code: 'TST',
      name: 'Test State',
      centreLatitude: 1,
      centreLongitude: 1,
      defaultZoom: 10,
      boundary: <GeoPoint>[
        GeoPoint(0, 0),
        GeoPoint(0, 2),
        GeoPoint(2, 2),
        GeoPoint(2, 0),
      ],
      places: <RegionPlace>[],
    ),
  ];

  @override
  Future<SwipeSession?> getSwipeSession({
    required String touristId,
    required String stateCode,
  }) async => session;

  @override
  Future<List<LocalFood>> getLocalFoods() async => const <LocalFood>[
    LocalFood(
      id: 1,
      name: 'Liked Food',
      description: '',
      origin: 'Malaysia',
      culturalBackground: '',
      ingredients: '',
      category: 'Local',
      cookingStyle: '',
      mealType: 'All Day',
      foodType: 'Food',
    ),
    LocalFood(
      id: 2,
      name: 'Not Liked Food',
      description: '',
      origin: 'Malaysia',
      culturalBackground: '',
      ingredients: '',
      category: 'Local',
      cookingStyle: '',
      mealType: 'All Day',
      foodType: 'Food',
    ),
  ];

  @override
  Future<List<Restaurant>> getRestaurants() async => <Restaurant>[
    Restaurant(
      id: 10,
      name: 'Actual Restaurant',
      category: 'Malaysian, Halal',
      address: 'Test Road',
      phone: '',
      website: '',
      openingHours: [],
      items: catalogueIncludesItems
          ? const <RestaurantItem>[
              RestaurantItem(
                id: 101,
                restaurantId: 10,
                localFoodId: 1,
                foodName: 'Liked Food',
                currency: 'RM',
                foodCategory: 'Local',
                price: 10,
              ),
              RestaurantItem(
                id: 102,
                restaurantId: 10,
                localFoodId: 2,
                foodName: 'Not Liked Food',
                currency: 'RM',
                foodCategory: 'Local',
                price: 12,
              ),
            ]
          : const <RestaurantItem>[],
    ),
  ];

  @override
  Future<Map<String, List<OpeningHour>>> openingHoursByPlace({
    Set<String>? placeKeys,
  }) async => hoursByPlace;

  @override
  Future<List<FoodOccurrence>> foodOccurrences() async =>
      const <FoodOccurrence>[
        FoodOccurrence(
          sourceId: '10',
          source: FoodOccurrenceSource.restaurant,
          placeName: 'Actual Restaurant',
          localFoodId: 1,
          foodName: 'Liked Food',
          foodType: 'Food',
          latitude: 1,
          longitude: 1.001,
          itemPrice: 9.5,
        ),
        FoodOccurrence(
          sourceId: '10',
          source: FoodOccurrenceSource.restaurant,
          placeName: 'Actual Restaurant',
          localFoodId: 2,
          foodName: 'Cheaper Unmatched Item',
          foodType: 'Food',
          latitude: 1,
          longitude: 1.001,
          itemPrice: 2.5,
        ),
        FoodOccurrence(
          sourceId: '20',
          source: FoodOccurrenceSource.submittedLandmark,
          placeName: 'Actual Landmark',
          localFoodId: 0,
          foodName: 'Liked Food',
          foodType: 'Food',
          latitude: 1,
          longitude: 1.002,
          placeAddress: 'Jalan Ampang, Kuala Lumpur',
          itemPrice: 8,
          itemIngredients: 'Rice, sambal',
        ),
        FoodOccurrence(
          sourceId: '20',
          source: FoodOccurrenceSource.submittedLandmark,
          placeName: 'Actual Landmark',
          localFoodId: 0,
          foodName: 'Not Liked Food',
          foodType: 'Food',
          latitude: 1,
          longitude: 1.002,
          itemPrice: 12,
        ),
      ];
  @override
  Future<void> saveSwipeSession(SwipeSession value) async {
    savedSession = value;
  }
}
