import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/core/view_state.dart';
import 'package:rasa_route_collaborative_development/domain_model/food_preference.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/tourist_information_logic_facade.dart';
import 'package:rasa_route_collaborative_development/view_models/edit_food_preference_view_model.dart';

void main() {
  group('EditFoodPreferenceViewModel', () {
    test('load populates options and the current selection', () async {
      final _FakeTouristInformationLogicFacade facade =
          _FakeTouristInformationLogicFacade(
            options: <FoodPreference>[
              _taste(1, 'Sweet'),
              _taste(2, 'Sour'),
              _taste(3, 'Spicy'),
              _taste(4, 'Bitter'),
              _category(5, 'Malay'),
              _category(6, 'Chinese'),
              _category(7, 'Indian'),
            ],
            current: <FoodPreference>[
              _taste(1, 'Sweet'),
              _category(5, 'Malay'),
              _category(6, 'Chinese'),
            ],
          );
      final EditFoodPreferenceViewModel viewModel = EditFoodPreferenceViewModel(
        touristLogic: facade,
      );

      await viewModel.load();

      expect(viewModel.tasteOptions.map((FoodPreference p) => p.name), <String>[
        'Sweet',
        'Sour',
        'Spicy',
        'Bitter',
      ]);
      expect(
        viewModel.selectedTastes.map((FoodPreference p) => p.name),
        <String>['Sweet'],
      );
      expect(
        viewModel.unselectedTastes.map((FoodPreference p) => p.name),
        <String>['Sour', 'Spicy', 'Bitter'],
      );
      expect(
        viewModel.selectedCategories.map((FoodPreference p) => p.name),
        <String>['Malay', 'Chinese'],
      );
      expect(viewModel.selectedTasteCount, 1);
      expect(viewModel.selectedCategoryCount, 2);
      expect(viewModel.state, ViewState.ready);
    });

    test(
      'toggleTaste moves an option between selected and unselected',
      () async {
        final _FakeTouristInformationLogicFacade facade =
            _FakeTouristInformationLogicFacade(
              options: <FoodPreference>[_taste(1, 'Sweet'), _taste(2, 'Sour')],
              current: const <FoodPreference>[],
            );
        final EditFoodPreferenceViewModel viewModel =
            EditFoodPreferenceViewModel(touristLogic: facade);
        await viewModel.load();

        viewModel.toggleTaste(_taste(1, 'Sweet'));
        expect(
          viewModel.selectedTastes.map((FoodPreference p) => p.name),
          <String>['Sweet'],
        );
        expect(viewModel.selectedTasteCount, 1);

        viewModel.toggleTaste(_taste(1, 'Sweet'));
        expect(viewModel.selectedTastes, isEmpty);
        expect(viewModel.selectedTasteCount, 0);
      },
    );

    test('save delegates the selected ids', () async {
      final _FakeTouristInformationLogicFacade facade =
          _FakeTouristInformationLogicFacade(
            options: <FoodPreference>[
              _taste(1, 'Sweet'),
              _taste(2, 'Sour'),
              _category(3, 'Malay'),
            ],
            current: const <FoodPreference>[],
          );
      final EditFoodPreferenceViewModel viewModel = EditFoodPreferenceViewModel(
        touristLogic: facade,
      );
      await viewModel.load();
      viewModel.toggleTaste(_taste(1, 'Sweet'));
      viewModel.toggleCategory(_category(3, 'Malay'));

      await viewModel.save();

      expect(facade.savedPreferenceIds.toSet(), <int>{1, 3});
      expect(viewModel.state, ViewState.ready);
    });
  });
}

FoodPreference _taste(int id, String name) =>
    FoodPreference(id: id, kind: FoodPreferenceKind.taste, name: name);

FoodPreference _category(int id, String name) =>
    FoodPreference(id: id, kind: FoodPreferenceKind.category, name: name);

/// Fakes the logic facade - the only seam `EditFoodPreferenceViewModel` knows.
class _FakeTouristInformationLogicFacade extends TouristInformationLogicFacade {
  _FakeTouristInformationLogicFacade({
    this.options = const <FoodPreference>[],
    this.current = const <FoodPreference>[],
  });

  final List<FoodPreference> options;
  final List<FoodPreference> current;
  List<int> savedPreferenceIds = <int>[];

  @override
  Future<List<FoodPreference>> foodPreferenceOptions() async => options;

  @override
  Future<List<FoodPreference>> getFoodPreferences() async => current;

  @override
  Future<void> saveFoodPreferences(List<int> preferenceIds) async {
    savedPreferenceIds = preferenceIds;
  }
}
