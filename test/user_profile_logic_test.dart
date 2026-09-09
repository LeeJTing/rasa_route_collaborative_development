import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/auth_session.dart';
import 'package:rasa_route_collaborative_development/domain_model/dietary_restriction.dart';
import 'package:rasa_route_collaborative_development/domain_model/food_preference.dart';
import 'package:rasa_route_collaborative_development/domain_model/tourist.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/user_profile_logic.dart';
import 'package:rasa_route_collaborative_development/model/repositories/tourist_repository_facade.dart';

void main() {
  group('UserProfileLogic.getTourist', () {
    test(
      'resolves the tourist id + session and returns the full profile',
      () async {
        final Tourist tourist = _tourist();
        final _FakeTouristRepositoryFacade repository =
            _FakeTouristRepositoryFacade(
              session: const AuthSession(
                accessToken: 'a',
                refreshToken: 'r',
                userId: 'auth-1',
                email: 'tourist@example.com',
              ),
              touristResult: tourist,
            );
        final UserProfileLogic logic = UserProfileLogic(repository: repository);

        final Tourist? result = await logic.getTourist();

        expect(result, same(tourist));
        expect(repository.lastProfileTouristId, 'tourist-1');
        expect(repository.lastProfileEmail, 'tourist@example.com');
      },
    );

    test('returns null when nobody is signed in', () async {
      final _FakeTouristRepositoryFacade repository =
          _FakeTouristRepositoryFacade(touristId: '');
      final UserProfileLogic logic = UserProfileLogic(repository: repository);

      expect(await logic.getTourist(), isNull);
    });
  });

  group('UserProfileLogic food preference', () {
    test('returns an empty list when nobody is signed in', () async {
      final _FakeTouristRepositoryFacade repository =
          _FakeTouristRepositoryFacade(touristId: '');
      final UserProfileLogic logic = UserProfileLogic(repository: repository);

      expect(await logic.getFoodPreferences(), isEmpty);
    });

    test('saveFoodPreferences throws when nobody is signed in', () async {
      final _FakeTouristRepositoryFacade repository =
          _FakeTouristRepositoryFacade(touristId: '');
      final UserProfileLogic logic = UserProfileLogic(repository: repository);

      expect(() => logic.saveFoodPreferences(<int>[1]), throwsStateError);
    });

    test(
      'saveFoodPreferences delegates with the resolved tourist id',
      () async {
        final _FakeTouristRepositoryFacade repository =
            _FakeTouristRepositoryFacade();
        final UserProfileLogic logic = UserProfileLogic(repository: repository);

        await logic.saveFoodPreferences(<int>[1, 4]);

        expect(repository.saveFoodPreferenceCalls, 1);
        expect(repository.savedPreferenceIds, <int>[1, 4]);
      },
    );
  });

  group('UserProfileLogic dietary restrictions', () {
    test(
      'saveDietaryRestrictions delegates with the resolved tourist id',
      () async {
        final _FakeTouristRepositoryFacade repository =
            _FakeTouristRepositoryFacade();
        final UserProfileLogic logic = UserProfileLogic(repository: repository);

        await logic.saveDietaryRestrictions(<int>[1, 3]);

        expect(repository.saveDietaryCalls, 1);
        expect(repository.savedRestrictionIds, <int>[1, 3]);
      },
    );
  });

  group('UserProfileLogic favourites', () {
    test('favouriteFoodIds returns empty when nobody is signed in', () async {
      final _FakeTouristRepositoryFacade repository =
          _FakeTouristRepositoryFacade(touristId: '');
      final UserProfileLogic logic = UserProfileLogic(repository: repository);

      expect(await logic.favouriteFoodIds(), isEmpty);
    });

    test('removeFavourite delegates with the resolved tourist id', () async {
      final _FakeTouristRepositoryFacade repository =
          _FakeTouristRepositoryFacade();
      final UserProfileLogic logic = UserProfileLogic(repository: repository);

      await logic.removeFavourite(42);

      expect(repository.removedFoodIds, <int>[42]);
    });
  });
}

Tourist _tourist() => const Tourist(
  touristId: 'tourist-1',
  authUserId: 'auth-1',
  email: 'tourist@example.com',
  displayName: 'Tourist',
  foodPreferences: <FoodPreference>[
    FoodPreference(id: 1, kind: FoodPreferenceKind.taste, name: 'Sweet'),
    FoodPreference(id: 2, kind: FoodPreferenceKind.category, name: 'Malay'),
  ],
  dietaryRestrictions: <DietaryRestriction>[
    DietaryRestriction(id: 1, name: 'Low Salt'),
  ],
);

/// Fakes the repository facade - the only seam `UserProfileLogic` knows.
class _FakeTouristRepositoryFacade extends TouristRepositoryFacade {
  _FakeTouristRepositoryFacade({
    this.touristId = 'tourist-1',
    this.session,
    this.touristResult,
  });

  String touristId;
  AuthSession? session;
  Tourist? touristResult;

  String? lastProfileTouristId;
  String? lastProfileEmail;
  int saveFoodPreferenceCalls = 0;
  List<int> savedPreferenceIds = <int>[];
  int saveDietaryCalls = 0;
  List<int> savedRestrictionIds = <int>[];
  List<int> removedFoodIds = <int>[];

  @override
  Future<String?> currentTouristId() async => touristId;

  @override
  Future<AuthSession?> getCurrentSession() async => session;

  @override
  Future<Tourist?> getTouristProfile({
    required String touristId,
    String authUserId = '',
    String email = '',
    String displayName = '',
  }) async {
    lastProfileTouristId = touristId;
    lastProfileEmail = email;
    return touristResult;
  }

  @override
  Future<void> saveFoodPreferences(
    String touristId,
    List<int> preferenceIds,
  ) async {
    saveFoodPreferenceCalls++;
    savedPreferenceIds = preferenceIds;
  }

  @override
  Future<void> saveDietaryRestrictions(
    String touristId,
    List<int> restrictionIds,
  ) async {
    saveDietaryCalls++;
    savedRestrictionIds = restrictionIds;
  }

  @override
  Future<void> removeFavourite(String touristId, int localFoodId) async {
    removedFoodIds.add(localFoodId);
  }
}
