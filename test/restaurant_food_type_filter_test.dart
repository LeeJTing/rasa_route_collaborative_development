import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/matches_recommendation.dart';
import 'package:rasa_route_collaborative_development/domain_model/restaurant.dart';
import 'package:rasa_route_collaborative_development/domain_model/restaurant_item.dart';
import 'package:rasa_route_collaborative_development/domain_model/tourist_location.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/discovery_logic_facade.dart';
import 'package:rasa_route_collaborative_development/view_models/restaurant_recommendation_view_model.dart';

void main() {
  test(
    'Quick Mode food type filters menus without changing source results',
    () async {
      final _FakeDiscoveryLogic logic = _FakeDiscoveryLogic();
      final RestaurantRecommendationViewModel viewModel = _TestViewModel(logic);
      addTearDown(viewModel.dispose);

      await viewModel.loadNearbyRestaurants();
      expect(viewModel.restaurants, hasLength(2));

      viewModel.selectFoodType('Beverage');

      expect(viewModel.visibleRestaurants, hasLength(1));
      expect(viewModel.visibleRestaurants.single.name, 'Mixed Menu');
      expect(viewModel.visibleRestaurants.single.items, hasLength(1));
      expect(
        viewModel.visibleRestaurants.single.items.single.foodName,
        'Teh Tarik',
      );
      expect(viewModel.restaurants.first.items, hasLength(2));

      viewModel.selectFoodType(null);
      expect(viewModel.visibleRestaurants, hasLength(2));
    },
  );

  test('Quick Mode ignores unsupported food type values', () async {
    final RestaurantRecommendationViewModel viewModel = _TestViewModel(
      _FakeDiscoveryLogic(),
    );
    addTearDown(viewModel.dispose);

    viewModel.selectFoodType('Unknown');

    expect(viewModel.selectedFoodType, isNull);
  });
}

class _TestViewModel extends RestaurantRecommendationViewModel {
  _TestViewModel(this.logic);

  final DiscoveryLogicFacade logic;

  @override
  DiscoveryLogicFacade createDiscoveryLogic() => logic;
}

class _FakeDiscoveryLogic extends DiscoveryLogicFacade {
  @override
  Future<List<Restaurant>> getQuickModeRestaurants({
    required TouristLocation location,
  }) async => <Restaurant>[
    _restaurant(1, 'Mixed Menu', const <RestaurantItem>[
      RestaurantItem(
        id: 11,
        restaurantId: 1,
        localFoodId: 1,
        foodName: 'Nasi Lemak',
        currency: 'RM',
        foodCategory: 'Malay',
        foodType: 'Food',
      ),
      RestaurantItem(
        id: 12,
        restaurantId: 1,
        localFoodId: 2,
        foodName: 'Teh Tarik',
        currency: 'RM',
        foodCategory: 'Malay',
        foodType: 'Beverage',
      ),
    ]),
    _restaurant(2, 'Food Only', const <RestaurantItem>[
      RestaurantItem(
        id: 21,
        restaurantId: 2,
        localFoodId: 3,
        foodName: 'Laksa',
        currency: 'RM',
        foodCategory: 'Nyonya',
        foodType: 'Food',
      ),
    ]),
  ];

  @override
  Future<List<SubmittedLandmarkRecommendation>> getQuickModeLandmarks({
    required TouristLocation location,
  }) async => const <SubmittedLandmarkRecommendation>[];
}

Restaurant _restaurant(int id, String name, List<RestaurantItem> items) =>
    Restaurant(
      id: id,
      name: name,
      category: 'Local',
      address: '',
      phone: '',
      website: '',
      openingHours: const [],
      distanceMetres: id * 100,
      items: items,
    );
