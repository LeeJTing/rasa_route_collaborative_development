import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/core/view_state.dart';
import 'package:rasa_route_collaborative_development/domain_model/local_food.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/food_logic_facade.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/tourist_information_logic_facade.dart';
import 'package:rasa_route_collaborative_development/view_models/favourite_collection_view_model.dart';

void main() {
  group('FavouriteCollectionViewModel', () {
    test('load joins the saved ids against the catalogue', () async {
      final _FakeFoodLogicFacade foodLogic = _FakeFoodLogicFacade(
        foods: <LocalFood>[
          _food(1, 'Roti Canai'),
          _food(2, 'Nasi Lemak'),
          _food(3, 'Maggie Goreng'),
        ],
      );
      final _FakeTouristInformationLogicFacade touristLogic =
          _FakeTouristInformationLogicFacade(savedIds: <int>{1, 3});
      final FavouriteCollectionViewModel viewModel =
          FavouriteCollectionViewModel(
            foodLogic: foodLogic,
            touristLogic: touristLogic,
          );

      await viewModel.load();

      expect(viewModel.favourites.map((LocalFood f) => f.id), <int>[1, 3]);
      expect(viewModel.state, ViewState.ready);
    });

    test(
      'removeFavourite removes locally and delegates the deletion',
      () async {
        final _FakeFoodLogicFacade foodLogic = _FakeFoodLogicFacade(
          foods: <LocalFood>[_food(1, 'Roti Canai'), _food(2, 'Nasi Lemak')],
        );
        final _FakeTouristInformationLogicFacade touristLogic =
            _FakeTouristInformationLogicFacade(savedIds: <int>{1, 2});
        final FavouriteCollectionViewModel viewModel =
            FavouriteCollectionViewModel(
              foodLogic: foodLogic,
              touristLogic: touristLogic,
            );
        await viewModel.load();

        await viewModel.removeFavourite(_food(1, 'Roti Canai'));

        expect(touristLogic.removedFoodIds, <int>[1]);
        expect(viewModel.favourites.map((LocalFood f) => f.id), <int>[2]);
        expect(viewModel.hasError, isFalse);
      },
    );

    test('removeFavourite reloads when the deletion fails', () async {
      final _FakeFoodLogicFacade foodLogic = _FakeFoodLogicFacade(
        foods: <LocalFood>[_food(1, 'Roti Canai')],
      );
      final _FakeTouristInformationLogicFacade touristLogic =
          _FakeTouristInformationLogicFacade(
            savedIds: <int>{1},
            throwOnRemove: true,
          );
      final FavouriteCollectionViewModel viewModel =
          FavouriteCollectionViewModel(
            foodLogic: foodLogic,
            touristLogic: touristLogic,
          );
      await viewModel.load();

      await viewModel.removeFavourite(_food(1, 'Roti Canai'));

      // The delete failed, so the reload restored the card from the truth.
      expect(viewModel.favourites.map((LocalFood f) => f.id), <int>[1]);
      expect(viewModel.hasError, isFalse);
    });
  });
}

LocalFood _food(int id, String name) => LocalFood(
  id: id,
  name: name,
  description: '',
  origin: '',
  culturalBackground: '',
  ingredients: '',
  category: 'Malay',
  cookingStyle: '',
  mealType: 'Breakfast',
  foodType: 'Food',
);

/// Fakes the food facade - provides the catalogue.
class _FakeFoodLogicFacade extends FoodLogicFacade {
  _FakeFoodLogicFacade({required this.foods});

  final List<LocalFood> foods;

  @override
  Future<List<LocalFood>> getLocalFoods() async => foods;
}

/// Fakes the tourist facade - provides the saved ids / deletion.
class _FakeTouristInformationLogicFacade extends TouristInformationLogicFacade {
  _FakeTouristInformationLogicFacade({
    this.savedIds = const <int>{},
    this.throwOnRemove = false,
  });

  final Set<int> savedIds;
  final bool throwOnRemove;
  final List<int> removedFoodIds = <int>[];

  @override
  Future<Set<int>> favouriteFoodIds() async => savedIds;

  @override
  Future<void> removeFavourite(int localFoodId) async {
    if (throwOnRemove) throw StateError('delete failed');
    removedFoodIds.add(localFoodId);
  }
}
