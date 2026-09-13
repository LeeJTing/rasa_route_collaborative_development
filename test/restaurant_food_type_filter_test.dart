import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/matches_recommendation.dart';
import 'package:rasa_route_collaborative_development/domain_model/restaurant.dart';
import 'package:rasa_route_collaborative_development/domain_model/restaurant_item.dart';
import 'package:rasa_route_collaborative_development/domain_model/tourist_location.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/discovery_logic_facade.dart';
import 'package:rasa_route_collaborative_development/view_models/restaurant_recommendation_view_model.dart';

void main() {
  test('Quick Mode defaults to Food and re-searches nearby on each filter '
      'change instead of filtering the previous 20', () async {
    final _FakeDiscoveryLogic logic = _FakeDiscoveryLogic();
    final RestaurantRecommendationViewModel viewModel = _TestViewModel(logic);
    addTearDown(viewModel.dispose);

    // No "All" option - 'Food' is selected before any load happens.
    expect(viewModel.selectedFoodType, 'Food');

    await viewModel.loadNearbyRestaurants();
    expect(logic.requestedFoodTypes, <String?>['Food']);
    expect(viewModel.restaurants, hasLength(1));
    expect(viewModel.restaurants.single.name, 'Nasi Lemak House');

    await viewModel.selectFoodType('Beverage');

    expect(viewModel.selectedFoodType, 'Beverage');
    expect(
      logic.requestedFoodTypes,
      <String?>['Food', 'Beverage'],
      reason:
          'selecting a chip must re-search nearby for that type, not '
          'just filter the restaurants already on screen',
    );
    expect(viewModel.restaurants, hasLength(1));
    expect(viewModel.restaurants.single.name, 'Beverage Corner');
    expect(
      viewModel.visibleRestaurants,
      viewModel.restaurants,
      reason: 'the list already comes back filtered by the repository',
    );
  });

  test('Quick Mode ignores unsupported food type values', () async {
    final _FakeDiscoveryLogic logic = _FakeDiscoveryLogic();
    final RestaurantRecommendationViewModel viewModel = _TestViewModel(logic);
    addTearDown(viewModel.dispose);

    await viewModel.loadNearbyRestaurants();
    expect(logic.requestedFoodTypes, <String?>['Food']);

    await viewModel.selectFoodType('Unknown');

    expect(viewModel.selectedFoodType, 'Food');
    expect(logic.requestedFoodTypes, <String?>[
      'Food',
    ], reason: 'an unsupported type must not trigger a re-search');
  });
}

class _TestViewModel extends RestaurantRecommendationViewModel {
  _TestViewModel(this.logic);

  final DiscoveryLogicFacade logic;

  @override
  DiscoveryLogicFacade createDiscoveryLogic() => logic;
}

class _FakeDiscoveryLogic extends DiscoveryLogicFacade {
  /// Every food type passed by the ViewModel, in call order - the test's
  /// evidence that a filter change re-searches nearby rather than filtering
  /// restaurants already fetched for a previous type.
  final List<String?> requestedFoodTypes = <String?>[];

  @override
  Future<List<Restaurant>> getQuickModeRestaurants({
    required TouristLocation location,
    String? foodType,
  }) async {
    requestedFoodTypes.add(foodType);
    if (foodType == 'Beverage') {
      return <Restaurant>[
        _restaurant(2, 'Beverage Corner', const <RestaurantItem>[
          RestaurantItem(
            id: 21,
            restaurantId: 2,
            localFoodId: 2,
            foodName: 'Teh Tarik',
            currency: 'RM',
            foodCategory: 'Malay',
            foodType: 'Beverage',
          ),
        ]),
      ];
    }
    return <Restaurant>[
      _restaurant(1, 'Nasi Lemak House', const <RestaurantItem>[
        RestaurantItem(
          id: 11,
          restaurantId: 1,
          localFoodId: 1,
          foodName: 'Nasi Lemak',
          currency: 'RM',
          foodCategory: 'Malay',
          foodType: 'Food',
        ),
      ]),
    ];
  }

  @override
  Future<List<SubmittedLandmarkRecommendation>> getQuickModeLandmarks({
    required TouristLocation location,
    String? foodType,
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
