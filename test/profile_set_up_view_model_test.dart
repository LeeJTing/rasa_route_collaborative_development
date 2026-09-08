import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/core/view_state.dart';
import 'package:rasa_route_collaborative_development/domain_model/auth_session.dart';
import 'package:rasa_route_collaborative_development/domain_model/dietary_restriction.dart';
import 'package:rasa_route_collaborative_development/domain_model/food_preference.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/tourist_information_logic_facade.dart';
import 'package:rasa_route_collaborative_development/view_models/profile_set_up_view_model.dart';

void main() {
  // `switchAccount` navigates via AppNavigator (a GlobalKey on the navigator),
  // which reads WidgetsBinding.instance - initialize it so the "not yet
  // initialized" FlutterError doesn't leak into the test zone.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ProfileSetUpViewModel', () {
    test('load fills options and the existing selection', () async {
      final _FakeTouristInformationLogicFacade
      facade = _FakeTouristInformationLogicFacade()
        ..preferenceOptions = <FoodPreference>[
          FoodPreference(id: 1, kind: FoodPreferenceKind.taste, name: 'Sweet'),
          FoodPreference(id: 2, kind: FoodPreferenceKind.taste, name: 'Sour'),
          FoodPreference(
            id: 3,
            kind: FoodPreferenceKind.category,
            name: 'Malay',
          ),
        ]
        ..restrictionOptions = const <DietaryRestriction>[
          DietaryRestriction(id: 10, name: 'Halal'),
          DietaryRestriction(id: 11, name: 'Vegetarian'),
        ]
        ..currentPreferences = <FoodPreference>[
          FoodPreference(id: 2, kind: FoodPreferenceKind.taste, name: 'Sour'),
        ]
        ..currentRestrictions = const <DietaryRestriction>[
          DietaryRestriction(id: 11, name: 'Vegetarian'),
        ];
      final ProfileSetUpViewModel viewModel = ProfileSetUpViewModel(
        touristLogic: facade,
      );

      await viewModel.load();

      expect(viewModel.tasteOptions.map((FoodPreference p) => p.name), <String>[
        'Sweet',
        'Sour',
      ]);
      expect(
        viewModel.categoryOptions.map((FoodPreference p) => p.name),
        <String>['Malay'],
      );
      expect(
        viewModel.dietaryOptions.map((DietaryRestriction r) => r.name),
        <String>['Halal', 'Vegetarian'],
      );

      // The pre-existing selection is pre-ticked so an abandoned first run
      // resumes where the tourist left off.
      expect(
        viewModel.isPreferenceSelected(viewModel.categoryOptions.first),
        isFalse,
      );
      expect(
        viewModel.isPreferenceSelected(viewModel.tasteOptions.last),
        isTrue,
      );
      expect(
        viewModel.isDietarySelected(viewModel.dietaryOptions.last),
        isTrue,
      );
      expect(viewModel.selectedCount, 2);
      expect(viewModel.state, ViewState.ready);
    });

    test('toggles select and deselect options and gates Continue', () async {
      final ProfileSetUpViewModel viewModel = ProfileSetUpViewModel(
        touristLogic: _FakeTouristInformationLogicFacade()
          ..preferenceOptions = <FoodPreference>[
            FoodPreference(
              id: 1,
              kind: FoodPreferenceKind.taste,
              name: 'Sweet',
            ),
          ]
          ..restrictionOptions = const <DietaryRestriction>[
            DietaryRestriction(id: 10, name: 'Halal'),
          ],
      );
      await viewModel.load();

      expect(viewModel.canContinue, isFalse);

      final FoodPreference taste = viewModel.tasteOptions.single;
      viewModel.togglePreference(taste);
      expect(viewModel.canContinue, isTrue);
      expect(viewModel.isPreferenceSelected(taste), isTrue);

      viewModel.togglePreference(taste);
      expect(viewModel.canContinue, isFalse);
      expect(viewModel.isPreferenceSelected(taste), isFalse);
    });

    test(
      'save persists both selections and marks the set-up complete',
      () async {
        final _FakeTouristInformationLogicFacade facade =
            _FakeTouristInformationLogicFacade()
              ..preferenceOptions = <FoodPreference>[
                FoodPreference(
                  id: 1,
                  kind: FoodPreferenceKind.taste,
                  name: 'Sweet',
                ),
              ]
              ..restrictionOptions = const <DietaryRestriction>[
                DietaryRestriction(id: 10, name: 'Halal'),
              ];
        final ProfileSetUpViewModel viewModel = ProfileSetUpViewModel(
          touristLogic: facade,
        );
        await viewModel.load();

        viewModel.togglePreference(viewModel.tasteOptions.single);
        viewModel.toggleDietary(viewModel.dietaryOptions.single);

        await viewModel.save();

        expect(facade.savedPreferenceIds, <int>[1]);
        expect(facade.savedRestrictionIds, <int>[10]);
        expect(viewModel.saved, isTrue);
        expect(viewModel.hasError, isFalse);
      },
    );

    test('load exposes the signed-in account email', () async {
      final _FakeTouristInformationLogicFacade facade =
          _FakeTouristInformationLogicFacade()
            ..session = const AuthSession(
              accessToken: 'access',
              refreshToken: 'refresh',
              userId: 'auth-1',
              email: 'wrong.account@example.com',
            );
      final ProfileSetUpViewModel viewModel = ProfileSetUpViewModel(
        touristLogic: facade,
      );

      await viewModel.load();

      expect(viewModel.email, 'wrong.account@example.com');
      expect(viewModel.state, ViewState.ready);
    });

    test('switchAccount signs out (wrong-account fallback)', () async {
      final _FakeTouristInformationLogicFacade facade =
          _FakeTouristInformationLogicFacade();
      final ProfileSetUpViewModel viewModel = ProfileSetUpViewModel(
        touristLogic: facade,
      );

      await viewModel.switchAccount();

      expect(facade.signOutCalls, 1);
    });

    test('skipForNow marks the session skip without persisting anything', () {
      final _FakeTouristInformationLogicFacade facade =
          _FakeTouristInformationLogicFacade();
      final ProfileSetUpViewModel viewModel = ProfileSetUpViewModel(
        touristLogic: facade,
      );

      // Skip is "for now" only: nothing is saved or written anywhere, so the
      // next login routes back here until the tourist completes set-up.
      viewModel.skipForNow();

      expect(viewModel.skipped, isTrue);
      expect(viewModel.state, ViewState.idle);
    });
  });
}

/// Fakes the logic facade - the only seam `ProfileSetUpViewModel` knows.
class _FakeTouristInformationLogicFacade extends TouristInformationLogicFacade {
  List<FoodPreference> preferenceOptions = const <FoodPreference>[];
  List<DietaryRestriction> restrictionOptions = const <DietaryRestriction>[];
  List<FoodPreference> currentPreferences = const <FoodPreference>[];
  List<DietaryRestriction> currentRestrictions = const <DietaryRestriction>[];
  List<int> savedPreferenceIds = const <int>[];
  List<int> savedRestrictionIds = const <int>[];

  /// The session returned by [getCurrentSession] - null by default, so the
  /// email tests set it explicitly and the option tests never see one.
  AuthSession? session;
  int signOutCalls = 0;

  @override
  Future<AuthSession?> getCurrentSession() async => session;

  @override
  Future<void> signOut() async {
    signOutCalls++;
  }

  @override
  Future<List<FoodPreference>> foodPreferenceOptions() async =>
      preferenceOptions;

  @override
  Future<List<DietaryRestriction>> dietaryRestrictionOptions() async =>
      restrictionOptions;

  @override
  Future<List<FoodPreference>> getFoodPreferences() async => currentPreferences;

  @override
  Future<List<DietaryRestriction>> getDietaryRestrictions() async =>
      currentRestrictions;

  @override
  Future<void> saveFoodPreferences(List<int> preferenceIds) async {
    savedPreferenceIds = List<int>.of(preferenceIds);
  }

  @override
  Future<void> saveDietaryRestrictions(List<int> restrictionIds) async {
    savedRestrictionIds = List<int>.of(restrictionIds);
  }
}
