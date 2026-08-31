import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/matches_recommendation.dart';
import 'package:rasa_route_collaborative_development/domain_model/matches_recommendation_tab.dart';
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
                    testRestaurant.copyWith(distanceMetres: 2500),
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
