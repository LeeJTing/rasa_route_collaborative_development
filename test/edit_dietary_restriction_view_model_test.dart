import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/core/view_state.dart';
import 'package:rasa_route_collaborative_development/domain_model/dietary_restriction.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/tourist_information_logic_facade.dart';
import 'package:rasa_route_collaborative_development/view_models/edit_dietary_restriction_view_model.dart';

void main() {
  group('EditDietaryRestrictionViewModel', () {
    test('load populates options and the current selection', () async {
      final _FakeTouristInformationLogicFacade facade =
          _FakeTouristInformationLogicFacade(
            options: <DietaryRestriction>[
              const DietaryRestriction(id: 1, name: 'Low Salt'),
              const DietaryRestriction(id: 2, name: 'Halal'),
              const DietaryRestriction(id: 3, name: 'Vegan'),
            ],
            current: const <DietaryRestriction>[
              DietaryRestriction(id: 1, name: 'Low Salt'),
              DietaryRestriction(id: 3, name: 'Vegan'),
            ],
          );
      final EditDietaryRestrictionViewModel viewModel =
          EditDietaryRestrictionViewModel(touristLogic: facade);

      await viewModel.load();

      expect(viewModel.restrictions, hasLength(3));
      expect(viewModel.selectedCount, 2);
      expect(
        viewModel.selectedRestrictions.map((DietaryRestriction r) => r.name),
        <String>['Low Salt', 'Vegan'],
      );
      expect(viewModel.state, ViewState.ready);
    });

    test('toggle moves a restriction in and out of the selection', () async {
      final _FakeTouristInformationLogicFacade facade =
          _FakeTouristInformationLogicFacade(
            options: const <DietaryRestriction>[
              DietaryRestriction(id: 1, name: 'Low Salt'),
            ],
            current: const <DietaryRestriction>[],
          );
      final EditDietaryRestrictionViewModel viewModel =
          EditDietaryRestrictionViewModel(touristLogic: facade);
      await viewModel.load();

      viewModel.toggle(const DietaryRestriction(id: 1, name: 'Low Salt'));
      expect(viewModel.selectedCount, 1);

      viewModel.toggle(const DietaryRestriction(id: 1, name: 'Low Salt'));
      expect(viewModel.selectedCount, 0);
    });

    test('save delegates the selected ids', () async {
      final _FakeTouristInformationLogicFacade facade =
          _FakeTouristInformationLogicFacade(
            options: const <DietaryRestriction>[
              DietaryRestriction(id: 1, name: 'Low Salt'),
              DietaryRestriction(id: 2, name: 'Halal'),
            ],
            current: const <DietaryRestriction>[],
          );
      final EditDietaryRestrictionViewModel viewModel =
          EditDietaryRestrictionViewModel(touristLogic: facade);
      await viewModel.load();
      viewModel.toggle(const DietaryRestriction(id: 2, name: 'Halal'));

      await viewModel.save();

      expect(facade.savedIds, <int>[2]);
      expect(viewModel.state, ViewState.ready);
    });
  });
}

/// Fakes the logic facade - the only seam `EditDietaryRestrictionViewModel`
/// knows.
class _FakeTouristInformationLogicFacade extends TouristInformationLogicFacade {
  _FakeTouristInformationLogicFacade({
    this.options = const <DietaryRestriction>[],
    this.current = const <DietaryRestriction>[],
  });

  final List<DietaryRestriction> options;
  final List<DietaryRestriction> current;
  List<int> savedIds = <int>[];

  @override
  Future<List<DietaryRestriction>> dietaryRestrictionOptions() async => options;

  @override
  Future<List<DietaryRestriction>> getDietaryRestrictions() async => current;

  @override
  Future<void> saveDietaryRestrictions(List<int> restrictionIds) async {
    savedIds = restrictionIds;
  }
}
