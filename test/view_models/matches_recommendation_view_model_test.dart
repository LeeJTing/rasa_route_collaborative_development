import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/matches_recommendation.dart';
import 'package:rasa_route_collaborative_development/view_models/presentation_models/matches_recommendation_state.dart';
import 'package:rasa_route_collaborative_development/domain_model/restaurant.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/discovery_logic_facade.dart';
import 'package:rasa_route_collaborative_development/view_models/matches_recommendation_view_model.dart';

import '../test_support/fake_discovery_logic_facade.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads restaurants with Restaurants as the default tab', () async {
    final MatchesRecommendationViewModel viewModel =
        _TestMatchesRecommendationViewModel(FakeDiscoveryLogicFacade());

    await viewModel.onInit();

    expect(viewModel.selectedTab, MatchesRecommendationTab.restaurants);
    expect(viewModel.groups.single.food.name, 'Prawn Noodle');
    expect(viewModel.groups.single.submittedLandmarks, hasLength(1));
    expect(
      viewModel.displayedGroups.single.restaurants.length,
      lessThanOrEqualTo(2),
    );
    expect(viewModel.hasError, isFalse);

    viewModel.dispose();
  });

  test('expands each food group to its nearest restaurant on load', () async {
    final MatchesRecommendationViewModel viewModel =
        _TestMatchesRecommendationViewModel(
          FakeDiscoveryLogicFacade(
            matchesResult: MatchesRecommendationResult(
              stateCode: testMatchesResult.stateCode,
              stateName: testMatchesResult.stateName,
              session: testMatchesResult.session,
              groups: <MatchedFoodRecommendations>[
                MatchedFoodRecommendations(
                  food: testMatchedFood,
                  restaurants: <Restaurant>[
                    _restaurantAtDistance(testRestaurant, 2500),
                  ],
                  submittedLandmarks: const <SubmittedLandmarkRecommendation>[],
                ),
              ],
            ),
          ),
        );

    await viewModel.onInit();

    expect(viewModel.radiusFor(testMatchedFood.id), 3);
    expect(viewModel.displayedGroups.single.restaurants, hasLength(1));
    viewModel.dispose();
  });

  test('changes tabs and exposes Show Less after See More', () async {
    final MatchesRecommendationViewModel viewModel =
        _TestMatchesRecommendationViewModel(FakeDiscoveryLogicFacade());
    await viewModel.onInit();

    viewModel.selectTab(MatchesRecommendationTab.submittedLandmarks);
    expect(viewModel.selectedTab, MatchesRecommendationTab.submittedLandmarks);

    viewModel.selectTab(MatchesRecommendationTab.restaurants);
    await viewModel.showMore(testMatchedFood.id);
    expect(viewModel.canShowLess(testMatchedFood.id), isTrue);

    viewModel.showLess(testMatchedFood.id);
    expect(viewModel.canShowLess(testMatchedFood.id), isFalse);

    viewModel.dispose();
  });

  test('preserves See More state when recommendations reload', () async {
    final MatchesRecommendationViewModel viewModel =
        _TestMatchesRecommendationViewModel(FakeDiscoveryLogicFacade());
    await viewModel.onInit();

    await viewModel.showMore(testMatchedFood.id);
    expect(viewModel.displayedGroups.single.restaurants, hasLength(3));
    expect(viewModel.canShowLess(testMatchedFood.id), isTrue);

    await viewModel.loadRecommendations();

    expect(viewModel.displayedGroups.single.restaurants, hasLength(3));
    expect(viewModel.canShowLess(testMatchedFood.id), isTrue);
    viewModel.dispose();
  });

  test('selects and toggles restaurant and landmark sorting', () async {
    final MatchesRecommendationViewModel viewModel =
        _TestMatchesRecommendationViewModel(FakeDiscoveryLogicFacade());
    await viewModel.onInit();

    viewModel.selectRestaurantSort(MatchesRestaurantSort.price);
    expect(viewModel.restaurantSort, MatchesRestaurantSort.price);
    expect(viewModel.restaurantSortDirection, MatchesSortDirection.ascending);

    viewModel.selectRestaurantSort(MatchesRestaurantSort.price);
    expect(viewModel.restaurantSortDirection, MatchesSortDirection.descending);

    viewModel.selectLandmarkSort(MatchesLandmarkSort.name);
    expect(viewModel.landmarkSort, MatchesLandmarkSort.name);
    expect(viewModel.landmarkSortDirection, MatchesSortDirection.ascending);
    expect(
      viewModel.displayedGroups.single.submittedLandmarks.first.name,
      'Uncle Lim Prawn Noodle Stall',
    );

    viewModel.selectLandmarkSort(MatchesLandmarkSort.name);
    expect(viewModel.landmarkSortDirection, MatchesSortDirection.descending);

    viewModel.dispose();
  });

  test('landmark Preference sort leads with the most dishes served', () async {
    final MatchesRecommendationViewModel viewModel =
        _TestMatchesRecommendationViewModel(
          FakeDiscoveryLogicFacade(
            matchesResult: MatchesRecommendationResult(
              stateCode: testMatchesResult.stateCode,
              stateName: testMatchesResult.stateName,
              session: testMatchesResult.session,
              groups: <MatchedFoodRecommendations>[
                MatchedFoodRecommendations(
                  food: testMatchedFood,
                  restaurants: const <Restaurant>[],
                  submittedLandmarks: <SubmittedLandmarkRecommendation>[
                    _landmarkWithDishes(id: 1, dishes: 1, distance: 500),
                    _landmarkWithDishes(id: 2, dishes: 3, distance: 800),
                  ],
                ),
              ],
            ),
          ),
        );
    await viewModel.onInit();
    viewModel.selectTab(MatchesRecommendationTab.submittedLandmarks);

    // Ascending = fewest dishes first; the direction toggle flips it, the
    // same rule the restaurant tab's Preference chip uses.
    viewModel.selectLandmarkSort(MatchesLandmarkSort.preference);
    expect(
      viewModel.displayedGroups.single.submittedLandmarks.map(
        (SubmittedLandmarkRecommendation landmark) => landmark.id,
      ),
      <int>[1, 2],
    );

    viewModel.selectLandmarkSort(MatchesLandmarkSort.preference);
    expect(
      viewModel.displayedGroups.single.submittedLandmarks.map(
        (SubmittedLandmarkRecommendation landmark) => landmark.id,
      ),
      <int>[2, 1],
    );

    viewModel.dispose();
  });

  test('restaurant price sort changes the displayed order', () async {
    final MatchesRecommendationViewModel viewModel =
        _TestMatchesRecommendationViewModel(FakeDiscoveryLogicFacade());
    await viewModel.onInit();

    viewModel.selectRestaurantSort(MatchesRestaurantSort.price);
    expect(
      viewModel.displayedGroups.single.restaurants.map(
        (Restaurant restaurant) => restaurant.id,
      ),
      <int>[2, 1],
    );

    viewModel.selectRestaurantSort(MatchesRestaurantSort.price);
    expect(
      viewModel.displayedGroups.single.restaurants.map(
        (Restaurant restaurant) => restaurant.id,
      ),
      <int>[3, 1],
    );
    viewModel.dispose();
  });

  test(
    'removing a liked food removes its entire recommendation group',
    () async {
      final MatchesRecommendationViewModel viewModel =
          _TestMatchesRecommendationViewModel(FakeDiscoveryLogicFacade());
      await viewModel.onInit();

      expect(viewModel.hasLikedFoods, isTrue);
      await viewModel.removeMatchedFood(testMatchedFood.id);
      expect(viewModel.hasLikedFoods, isFalse);

      viewModel.dispose();
    },
  );
}

class _TestMatchesRecommendationViewModel
    extends MatchesRecommendationViewModel {
  _TestMatchesRecommendationViewModel(this.logic);

  final DiscoveryLogicFacade logic;

  @override
  DiscoveryLogicFacade createDiscoveryLogic() => logic;
}

Restaurant _restaurantAtDistance(
  Restaurant restaurant,
  double distanceMetres,
) => Restaurant(
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
  distanceMetres: distanceMetres,
  reviewCount: restaurant.reviewCount,
  items: restaurant.items,
);

/// A Matches landmark serving [dishes] dishes - what the Preference sort
/// counts ([SubmittedLandmarkRecommendation.dishes] length).
SubmittedLandmarkRecommendation _landmarkWithDishes({
  required int id,
  required int dishes,
  required double distance,
}) => SubmittedLandmarkRecommendation(
  id: id,
  name: 'Stall $id',
  category: 'Hawker',
  distanceMetres: distance,
  dishes: List<SubmittedLandmarkDish>.generate(
    dishes,
    (int index) => SubmittedLandmarkDish(name: 'Dish $id-$index'),
  ),
);
