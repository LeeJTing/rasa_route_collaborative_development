import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/local_food.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/food_logic_facade.dart';
import 'package:rasa_route_collaborative_development/view_models/local_food_list_view_model.dart';

void main() {
  group('LocalFoodListViewModel stress', () {
    test('latest overlapping catalogue request wins', () async {
      final Completer<List<LocalFood>> older = Completer<List<LocalFood>>();
      final Completer<List<LocalFood>> latest = Completer<List<LocalFood>>();
      final _FakeFoodLogic logic = _FakeFoodLogic(
        loads: <Future<List<LocalFood>>>[older.future, latest.future],
      );
      final LocalFoodListViewModel viewModel = _TestViewModel(logic);
      addTearDown(viewModel.dispose);

      final Future<void> olderLoad = viewModel.loadFoods();
      final Future<void> latestLoad = viewModel.loadFoods();
      latest.complete(<LocalFood>[_food(2, 'Cendol')]);
      await latestLoad;
      older.complete(<LocalFood>[_food(1, 'Old result')]);
      await olderLoad;

      expect(viewModel.displayedFoods.map((LocalFood food) => food.id), <int>[
        2,
      ]);
    });

    test('search matches food name only and ignores case', () async {
      final _FakeFoodLogic logic = _FakeFoodLogic(
        loads: <Future<List<LocalFood>>>[
          Future<List<LocalFood>>.value(<LocalFood>[
            _food(1, 'Cendol'),
            _food(2, 'Char Kway Teow'),
            _food(3, 'Ice Kacang'),
          ]),
        ],
      );
      final LocalFoodListViewModel viewModel = _TestViewModel(logic);
      addTearDown(viewModel.dispose);
      await viewModel.loadFoods();

      viewModel.updateSearch('CE');

      final List<String> names = viewModel.displayedFoods
          .map((LocalFood food) => food.name)
          .toList(growable: false);
      expect(names, containsAll(<String>['Cendol', 'Ice Kacang']));
      expect(names, isNot(contains('Char Kway Teow')));
    });

    test('duplicate favourite taps submit only one write', () async {
      final Completer<bool> update = Completer<bool>();
      final _FakeFoodLogic logic = _FakeFoodLogic(
        loads: <Future<List<LocalFood>>>[
          Future<List<LocalFood>>.value(<LocalFood>[_food(1, 'Cendol')]),
        ],
        favouriteResult: update.future,
      );
      final LocalFoodListViewModel viewModel = _TestViewModel(logic);
      addTearDown(viewModel.dispose);
      await viewModel.loadFoods();

      final Future<String?> first = viewModel.toggleFavourite(1);
      final Future<String?> second = viewModel.toggleFavourite(1);
      update.complete(true);
      await Future.wait(<Future<String?>>[first, second]);

      expect(logic.favouriteCalls, 1);
      expect(viewModel.displayedFoods.single.isFavourite, isTrue);
    });

    test('refresh removes selections for foods no longer available', () async {
      final _FakeFoodLogic logic = _FakeFoodLogic(
        loads: <Future<List<LocalFood>>>[
          Future<List<LocalFood>>.value(<LocalFood>[
            _food(1, 'Cendol'),
            _food(2, 'Nasi Lemak'),
          ]),
          Future<List<LocalFood>>.value(<LocalFood>[_food(2, 'Nasi Lemak')]),
        ],
      );
      final LocalFoodListViewModel viewModel = _TestViewModel(logic);
      addTearDown(viewModel.dispose);
      await viewModel.loadFoods();
      viewModel.toggleSelectionMode();
      viewModel.toggleSelection(1);

      await viewModel.loadFoods();

      expect(viewModel.selectedIds, isEmpty);
    });
  });
}

class _TestViewModel extends LocalFoodListViewModel {
  _TestViewModel(this.logic);

  final FoodLogicFacade logic;

  @override
  FoodLogicFacade createFoodLogic() => logic;
}

class _FakeFoodLogic extends FoodLogicFacade {
  _FakeFoodLogic({required this.loads, this.favouriteResult});

  final List<Future<List<LocalFood>>> loads;
  final Future<bool>? favouriteResult;
  int loadCalls = 0;
  int favouriteCalls = 0;

  @override
  Future<List<LocalFood>> getLocalFoods() => loads[loadCalls++];

  @override
  Future<bool> toggleFavouriteFood(int foodId) {
    favouriteCalls += 1;
    return favouriteResult ?? Future<bool>.value(true);
  }
}

LocalFood _food(int id, String name) => LocalFood(
  id: id,
  name: name,
  description: 'Description',
  origin: 'Origin',
  culturalBackground: 'Background',
  ingredients: 'Ingredients',
  category: 'Chinese',
  cookingStyle: 'Boiled',
  mealType: 'All-Day Dining',
  foodType: 'Food',
  tastes: const <String>['Sweet'],
  mainTaste: 'Sweet',
);
