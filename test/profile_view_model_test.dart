import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/core/view_state.dart';
import 'package:rasa_route_collaborative_development/domain_model/dietary_restriction.dart';
import 'package:rasa_route_collaborative_development/domain_model/food_preference.dart';
import 'package:rasa_route_collaborative_development/domain_model/tourist.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/tourist_information_logic_facade.dart';
import 'package:rasa_route_collaborative_development/view_models/profile_view_model.dart';

void main() {
  // `signOut` navigates via AppNavigator (a GlobalKey on the navigator), which
  // reads WidgetsBinding.instance - initialize it so the "not yet initialized"
  // FlutterError doesn't leak into the test zone.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ProfileViewModel', () {
    test('load fills preferences and restrictions from the tourist', () async {
      final _FakeTouristInformationLogicFacade facade =
          _FakeTouristInformationLogicFacade(
            tourist: const Tourist(
              touristId: 'tourist-1',
              authUserId: 'auth-1',
              email: 'tourist@example.com',
              displayName: 'Tourist',
              foodPreferences: <FoodPreference>[
                FoodPreference(id: 1, kind: FoodPreferenceKind.taste, name: 'Sweet'),
                FoodPreference(id: 2, kind: FoodPreferenceKind.taste, name: 'Sour'),
                FoodPreference(id: 3, kind: FoodPreferenceKind.category, name: 'Malay'),
              ],
              dietaryRestrictions: <DietaryRestriction>[
                DietaryRestriction(id: 1, name: 'Low Salt'),
                DietaryRestriction(id: 2, name: 'Halal'),
              ],
            ),
          );
      final ProfileViewModel viewModel = ProfileViewModel(
        touristLogic: facade,
      );

      await viewModel.load();

      expect(viewModel.preferredTastes, <String>['Sweet', 'Sour']);
      expect(viewModel.preferredCategories, <String>['Malay']);
      expect(viewModel.email, 'tourist@example.com');
      expect(
        viewModel.dietaryRestrictions.map((DietaryRestriction r) => r.name),
        <String>['Low Salt', 'Halal'],
      );
      expect(viewModel.state, ViewState.ready);
    });

    test('load clears the lists when no tourist resolves', () async {
      final ProfileViewModel viewModel = ProfileViewModel(
        touristLogic: _FakeTouristInformationLogicFacade(tourist: null),
      );

      await viewModel.load();

      expect(viewModel.preferredTastes, isEmpty);
      expect(viewModel.preferredCategories, isEmpty);
      expect(viewModel.dietaryRestrictions, isEmpty);
      expect(viewModel.email, isEmpty);
    });

    test('signOut delegates to the logic facade', () async {
      final _FakeTouristInformationLogicFacade facade =
          _FakeTouristInformationLogicFacade(tourist: null);
      final ProfileViewModel viewModel = ProfileViewModel(
        touristLogic: facade,
      );

      await viewModel.signOut();

      expect(facade.signOutCalls, 1);
    });
  });
}

/// Fakes the logic facade - the only seam `ProfileViewModel` knows.
class _FakeTouristInformationLogicFacade extends TouristInformationLogicFacade {
  _FakeTouristInformationLogicFacade({this.tourist});

  final Tourist? tourist;
  int signOutCalls = 0;

  @override
  Future<Tourist?> getTourist() async => tourist;

  @override
  Future<void> signOut() async {
    signOutCalls++;
  }
}
