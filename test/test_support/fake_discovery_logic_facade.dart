import 'package:rasa_route_collaborative_development/domain_model/local_food.dart';
import 'package:rasa_route_collaborative_development/domain_model/matches_recommendation.dart';
import 'package:rasa_route_collaborative_development/domain_model/restaurant.dart';
import 'package:rasa_route_collaborative_development/domain_model/restaurant_item.dart';
import 'package:rasa_route_collaborative_development/domain_model/swipe_session.dart';
import 'package:rasa_route_collaborative_development/domain_model/tourist_location.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/discovery_logic_facade.dart';

const Restaurant testRestaurant = Restaurant(
  id: 1,
  name: 'OldTown Heritage Kitchen',
  category: 'Malaysian',
  address: '1 Jalan Heritage, Kuala Lumpur',
  rating: 4.6,
  latitude: 3.1478,
  longitude: 101.6953,
  phone: '+60 3-1234 5678',
  website: 'https://example.test/oldtown',
  openingHours: [],
  distanceMetres: 280,
  reviewCount: 3200,
  items: <RestaurantItem>[
    RestaurantItem(
      id: 11,
      restaurantId: 1,
      localFoodId: 1,
      foodName: 'Prawn Noodle',
      description: 'A comforting local noodle dish in a rich prawn broth.',
      ingredients: 'Prawn, noodle and broth',
      price: 18,
      currency: 'RM',
      foodCategory: 'Noodles',
    ),
  ],
);

const List<Restaurant> testRestaurants = <Restaurant>[
  testRestaurant,
  Restaurant(
    id: 2,
    name: 'Kopitiam Corner',
    category: 'Malaysian',
    address: '2 Jalan Market, Kuala Lumpur',
    rating: 4.2,
    phone: '',
    website: '',
    openingHours: [],
    distanceMetres: 620,
    items: <RestaurantItem>[
      RestaurantItem(
        id: 21,
        restaurantId: 2,
        localFoodId: 1,
        foodName: 'Prawn Noodle',
        price: 15,
        currency: 'RM',
        foodCategory: 'Noodles',
      ),
    ],
  ),
  Restaurant(
    id: 3,
    name: 'Heritage Noodle House',
    category: 'Noodles',
    address: '3 Jalan Sultan, Kuala Lumpur',
    rating: 4.8,
    phone: '',
    website: '',
    openingHours: [],
    distanceMetres: 940,
    items: <RestaurantItem>[
      RestaurantItem(
        id: 31,
        restaurantId: 3,
        localFoodId: 1,
        foodName: 'Prawn Noodle',
        price: 21,
        currency: 'RM',
        foodCategory: 'Noodles',
      ),
    ],
  ),
];

const LocalFood testMatchedFood = LocalFood(
  id: 1,
  name: 'Prawn Noodle',
  description: 'Prawn noodles in a rich broth.',
  origin: 'Penang',
  culturalBackground: 'Local hawker food.',
  ingredients: 'Prawn, noodles, broth',
  category: 'Noodles',
  cookingStyle: 'Boiled',
  mealType: 'All Day',
  foodType: 'Food',
);

const SubmittedLandmarkRecommendation testLandmarkRecommendation =
    SubmittedLandmarkRecommendation(
      id: 901,
      name: 'Uncle Lim Prawn Noodle Stall',
      category: 'Hawker Stall',
      distanceMetres: 620,
      dishes: <SubmittedLandmarkDish>[
        SubmittedLandmarkDish(name: 'Prawn Noodle', price: 12),
      ],
      price: 12,
    );

const SwipeSession testSwipeSession = SwipeSession(
  sessionId: 'session-1',
  touristId: 'tourist-1',
  stateCode: 'KUL',
  candidateFoodIds: <int>[1, 2],
  likedFoodIds: <int>[1],
  dislikedFoodIds: <int>[],
);

const MatchesRecommendationResult testMatchesResult =
    MatchesRecommendationResult(
      stateCode: 'KUL',
      stateName: 'Kuala Lumpur',
      session: testSwipeSession,
      groups: <MatchedFoodRecommendations>[
        MatchedFoodRecommendations(
          food: testMatchedFood,
          restaurants: testRestaurants,
          restaurantStartingPrices: <int, double>{1: 18, 2: 15, 3: 21},
          submittedLandmarks: <SubmittedLandmarkRecommendation>[
            testLandmarkRecommendation,
          ],
        ),
      ],
    );

class FakeDiscoveryLogicFacade extends DiscoveryLogicFacade {
  FakeDiscoveryLogicFacade({
    this.restaurants = testRestaurants,
    this.restaurant = testRestaurant,
    this.matchesResult = testMatchesResult,
  });

  final List<Restaurant> restaurants;
  final Restaurant? restaurant;
  final MatchesRecommendationResult matchesResult;

  @override
  Future<List<Restaurant>> getNearbyRestaurants({
    required TouristLocation location,
    required double radiusKm,
    required int limit,
  }) async => restaurants.take(limit).toList(growable: false);

  @override
  Future<Restaurant?> getRestaurantById(
    int restaurantId, {
    TouristLocation origin = TouristLocation.unknown,
  }) async => restaurant?.id == restaurantId ? restaurant : null;

  @override
  Future<MatchesRecommendationResult> getMatchesRecommendations(
    MatchesRecommendationRequest request,
  ) async => matchesResult;

  @override
  Future<SwipeSession> removeMatchedFood(
    SwipeSession session,
    int foodId,
  ) async => session.copyWith(
    likedFoodIds: session.likedFoodIds
        .where((int id) => id != foodId)
        .toList(growable: false),
  );

  @override
  Future<SwipeSession> removeSwipeFoodLike(SwipeSession session, int foodId) =>
      removeMatchedFood(session, foodId);
}
