import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/dietary_restriction.dart';
import 'package:rasa_route_collaborative_development/domain_model/food_distribution.dart';
import 'package:rasa_route_collaborative_development/domain_model/food_preference.dart';
import 'package:rasa_route_collaborative_development/domain_model/local_food.dart';
import 'package:rasa_route_collaborative_development/domain_model/opening_hour.dart';
import 'package:rasa_route_collaborative_development/domain_model/region.dart';
import 'package:rasa_route_collaborative_development/domain_model/swipe_mode.dart';
import 'package:rasa_route_collaborative_development/domain_model/swipe_session.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/food_discovery_logic.dart';
import 'package:rasa_route_collaborative_development/model/repositories/discovery_repository_facade.dart';

void main() {
  group('FoodDiscoveryLogic', () {
    late _FakeDiscoveryRepository repository;
    late FoodDiscoveryLogic logic;

    setUp(() {
      repository = _FakeDiscoveryRepository();
      logic = _TestFoodDiscoveryLogic(repository);
    });

    test('localises, personalises, and places restricted food last', () async {
      final SwipeModePreparation result = await logic.prepareSwipeMode(
        latitude: 1,
        longitude: 1,
      );

      expect(result.stateCode, 'TST');
      expect(result.queue.map((LocalFood food) => food.id), <int>[1, 3, 2]);
      expect(result.restrictedFoodIds, <int>{2});
      expect(result.queue.map((LocalFood food) => food.id), isNot(contains(4)));
      expect(result.savedRestaurantCount, 1);
    });

    test('starts, moves, and saves a like locally', () async {
      final SwipeModePreparation preparation = await logic.prepareSwipeMode(
        latitude: 1,
        longitude: 1,
      );
      final SwipeSession started = await logic.startNewSession(preparation);
      final SwipeSession moved = await logic.moveToIndex(started, 1);
      final int foodId = moved.candidateFoodIds[moved.currentIndex];
      final SwipeSession liked = await logic.likeFood(moved, foodId);

      expect(started.candidateFoodIds, <int>[1, 3, 2]);
      expect(moved.currentIndex, 1);
      expect(liked.likedFoodIds, <int>[foodId]);
      expect(repository.savedSession, same(liked));
    });

    test('removing a like is not recorded as a dislike', () async {
      final SwipeSession session = SwipeSession(
        sessionId: 'session',
        touristId: 'tourist-1',
        stateCode: 'TST',
        candidateFoodIds: const <int>[1],
        likedFoodIds: const <int>[1],
        dislikedFoodIds: const <int>[3],
      );

      final SwipeSession updated = await logic.removeLike(session, 1);

      expect(updated.likedFoodIds, isEmpty);
      expect(updated.dislikedFoodIds, <int>[3]);
      expect(repository.savedSession, same(updated));
    });

    test('liking again removes the food from dislikes', () async {
      final SwipeSession session = SwipeSession(
        sessionId: 'session',
        touristId: 'tourist-1',
        stateCode: 'TST',
        candidateFoodIds: const <int>[1],
        likedFoodIds: const <int>[],
        dislikedFoodIds: const <int>[1],
      );

      final SwipeSession updated = await logic.likeFood(session, 1);

      expect(updated.likedFoodIds, <int>[1]);
      expect(updated.dislikedFoodIds, isEmpty);
    });

    test('reloads changes saved by the Matches screen', () async {
      final SwipeModePreparation preparation = await logic.prepareSwipeMode(
        latitude: 1,
        longitude: 1,
      );
      repository.savedSession = SwipeSession(
        sessionId: 'saved',
        touristId: preparation.touristId,
        stateCode: preparation.stateCode,
        candidateFoodIds: const <int>[1, 3, 2],
        likedFoodIds: const <int>[],
        dislikedFoodIds: const <int>[],
      );

      final SwipeSession? reloaded = await logic.reloadSession(preparation);

      expect(reloaded, isNotNull);
      expect(reloaded!.likedFoodIds, isEmpty);
    });

    test(
      'profile refresh re-ranks the unvisited tail and preserves interactions',
      () async {
        repository.savedSession = const SwipeSession(
          sessionId: 'saved',
          touristId: 'tourist-1',
          stateCode: 'TST',
          candidateFoodIds: <int>[1, 3, 2],
          likedFoodIds: <int>[1],
          dislikedFoodIds: <int>[2],
        );
        repository.restrictionIdsByFood = <int, Set<int>>{
          3: <int>{7},
        };

        final SwipeModePreparation refreshed = await logic
            .refreshAfterProfileChange(latitude: 1, longitude: 1);

        expect(refreshed.queue.map((LocalFood food) => food.id), <int>[1, 2, 3]);
        expect(refreshed.restrictedFoodIds, <int>{3});
        expect(refreshed.savedSession!.candidateFoodIds, <int>[1, 2, 3]);
        expect(refreshed.savedSession!.currentIndex, 0);
        expect(refreshed.savedSession!.likedFoodIds, <int>[1]);
        expect(refreshed.savedSession!.dislikedFoodIds, <int>[2]);
        expect(repository.savedSession, same(refreshed.savedSession));
      },
    );

    test('profile refresh keeps a newly restricted current card visible', () async {
      repository.savedSession = const SwipeSession(
        sessionId: 'saved',
        touristId: 'tourist-1',
        stateCode: 'TST',
        candidateFoodIds: <int>[1, 3, 2],
        likedFoodIds: <int>[3],
        dislikedFoodIds: <int>[],
        currentIndex: 1,
      );
      repository.restrictionIdsByFood = <int, Set<int>>{
        3: <int>{7},
      };

      final SwipeModePreparation refreshed = await logic
          .refreshAfterProfileChange(latitude: 1, longitude: 1);

      expect(refreshed.savedSession!.candidateFoodIds, <int>[1, 3, 2]);
      expect(refreshed.savedSession!.currentIndex, 1);
      expect(refreshed.savedSession!.likedFoodIds, <int>[3]);
      expect(refreshed.restrictedFoodIds, contains(3));
    });

    test('excludes food backed only by a restaurant closed now', () async {
      repository.hoursByPlace = const <String, List<OpeningHour>>{
        'restaurant:10': <OpeningHour>[
          OpeningHour(id: 1, day: Weekday.monday, status: DayStatus.closed),
        ],
      };

      final SwipeModePreparation result = await logic.prepareSwipeMode(
        latitude: 1,
        longitude: 1,
      );

      expect(result.queue.map((LocalFood food) => food.id), isNot(contains(1)));
    });
  });
}

class _TestFoodDiscoveryLogic extends FoodDiscoveryLogic {
  _TestFoodDiscoveryLogic(this.repository);

  final DiscoveryRepositoryFacade repository;

  @override
  DiscoveryRepositoryFacade createRepository() => repository;

  @override
  DateTime currentTime() => DateTime(2026, 9, 7, 12);
}

class _FakeDiscoveryRepository extends DiscoveryRepositoryFacade {
  _FakeDiscoveryRepository();

  final List<LocalFood> foods = <LocalFood>[
    _food(1, 'Nasi Lemak', category: 'Malay', tastes: <String>['Spicy']),
    _food(2, 'Curry Mee', tastes: <String>['Spicy']),
    _food(3, 'Cendol', tastes: <String>['Sweet']),
    _food(4, 'Outside Dish', tastes: <String>['Spicy']),
  ];

  SwipeSession? savedSession;
  Map<String, List<OpeningHour>> hoursByPlace =
      const <String, List<OpeningHour>>{};
  Map<int, Set<int>> restrictionIdsByFood = <int, Set<int>>{
    2: <int>{7},
  };

  @override
  Future<String?> currentTouristId() async => 'tourist-1';

  @override
  Future<List<Region>> malaysiaRegions() async => <Region>[
    const Region(
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
  Future<List<LocalFood>> getLocalFoods() async => foods;

  @override
  Future<List<FoodOccurrence>> foodOccurrences() async =>
      const <FoodOccurrence>[
        FoodOccurrence(
          sourceId: '10',
          source: FoodOccurrenceSource.restaurant,
          placeName: 'Near Restaurant',
          localFoodId: 1,
          foodName: 'Nasi Lemak',
          latitude: 1,
          longitude: 1.01,
        ),
        FoodOccurrence(
          sourceId: '20',
          source: FoodOccurrenceSource.restaurant,
          placeName: 'Restricted Restaurant',
          localFoodId: 2,
          foodName: 'Curry Mee',
          latitude: 1,
          longitude: 1.02,
        ),
        FoodOccurrence(
          sourceId: '30',
          source: FoodOccurrenceSource.restaurant,
          placeName: 'Dessert Stall',
          localFoodId: 3,
          foodName: 'Cendol',
          latitude: 1,
          longitude: 1.005,
        ),
        FoodOccurrence(
          sourceId: '40',
          source: FoodOccurrenceSource.restaurant,
          placeName: 'Outside Restaurant',
          localFoodId: 4,
          foodName: 'Outside Dish',
          latitude: 4,
          longitude: 4,
        ),
      ];

  @override
  Future<Map<String, List<OpeningHour>>> openingHoursByPlace({
    Set<String>? placeKeys,
  }) async => hoursByPlace;

  @override
  Future<List<FoodPreference>> foodPreferencesForTourist(
    String touristId,
  ) async => const <FoodPreference>[
    FoodPreference(id: 1, kind: FoodPreferenceKind.category, name: 'Malay'),
    FoodPreference(id: 2, kind: FoodPreferenceKind.taste, name: 'Spicy'),
  ];

  @override
  Future<List<DietaryRestriction>> dietaryRestrictionsForTourist(
    String touristId,
  ) async => const <DietaryRestriction>[
    DietaryRestriction(id: 7, name: 'Test restriction'),
  ];

  @override
  Future<Map<int, Set<int>>> dietaryRestrictionIdsByFood() async =>
      restrictionIdsByFood;

  @override
  Future<SwipeSession?> getSwipeSession({
    required String touristId,
    required String stateCode,
  }) async =>
      savedSession ??
      SwipeSession(
        sessionId: 'saved',
        touristId: touristId,
        stateCode: stateCode,
        candidateFoodIds: const <int>[1, 3, 2],
        likedFoodIds: const <int>[1],
        dislikedFoodIds: const <int>[],
      );

  @override
  Future<void> deleteSwipeSession({
    required String touristId,
    required String stateCode,
  }) async {
    savedSession = null;
  }

  @override
  Future<void> saveSwipeSession(SwipeSession session) async {
    savedSession = session;
  }
}

LocalFood _food(
  int id,
  String name, {
  List<String> tastes = const <String>[],
  String category = 'Local',
}) => LocalFood(
  id: id,
  name: name,
  description: '$name description',
  origin: 'Malaysia',
  culturalBackground: '',
  ingredients: '',
  category: category,
  cookingStyle: '',
  mealType: 'All Day',
  foodType: 'Food',
  tastes: tastes,
  mainTaste: tastes.isEmpty ? '' : tastes.first,
);
