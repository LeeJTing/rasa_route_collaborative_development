import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/food_logic_facade.dart';
import 'package:rasa_route_collaborative_development/view_models/food_detail_view_model.dart';

void main() {
  group('FoodDetailViewModel favourites', () {
    test('uses the favourite state confirmed by the repository path', () async {
      final _FakeFoodLogicFacade foodLogic = _FakeFoodLogicFacade(
        nextFavouriteState: true,
      );
      final FoodDetailViewModel viewModel = _TestFoodDetailViewModel(foodLogic);

      expect(await viewModel.toggleLike(), isNull);

      expect(viewModel.isLiked, isTrue);
      expect(foodLogic.toggleCalls, 1);
    });

    test('returns a user-facing message without changing local state', () async {
      final _FakeFoodLogicFacade foodLogic = _FakeFoodLogicFacade(
        error: Exception('Unable to update favourites. Please try again.'),
      );
      final FoodDetailViewModel viewModel = _TestFoodDetailViewModel(foodLogic);

      final String? message = await viewModel.toggleLike();

      expect(message, 'Unable to update favourites. Please try again.');
      expect(viewModel.isLiked, isFalse);
    });

    test('ignores a second tap while an update is in progress', () async {
      final Completer<bool> result = Completer<bool>();
      final _FakeFoodLogicFacade foodLogic = _FakeFoodLogicFacade(
        result: result.future,
      );
      final FoodDetailViewModel viewModel = _TestFoodDetailViewModel(foodLogic);

      final Future<String?> first = viewModel.toggleLike();
      final Future<String?> second = viewModel.toggleLike();
      result.complete(true);
      await Future.wait(<Future<String?>>[first, second]);

      expect(foodLogic.toggleCalls, 1);
      expect(viewModel.isLiked, isTrue);
    });
  });
}

class _TestFoodDetailViewModel extends FoodDetailViewModel {
  _TestFoodDetailViewModel(this.fakeFoodLogic);

  final FoodLogicFacade fakeFoodLogic;

  @override
  FoodLogicFacade createFoodLogic() => fakeFoodLogic;
}

class _FakeFoodLogicFacade extends FoodLogicFacade {
  _FakeFoodLogicFacade({this.nextFavouriteState, this.error, this.result});

  final bool? nextFavouriteState;
  final Object? error;
  final Future<bool>? result;
  int toggleCalls = 0;

  @override
  Future<bool> toggleFavouriteFood(int foodId) {
    toggleCalls += 1;
    if (error != null) return Future<bool>.error(error!);
    return result ?? Future<bool>.value(nextFavouriteState!);
  }
}
