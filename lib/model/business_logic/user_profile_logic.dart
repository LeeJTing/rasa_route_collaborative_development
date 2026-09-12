import 'package:meta/meta.dart' show visibleForTesting;

import '../../domain_model/auth_session.dart';
import '../../domain_model/dietary_restriction.dart';
import '../../domain_model/food_preference.dart';
import '../../domain_model/tourist.dart';
import '../repositories/tourist_repository_facade.dart';

/// Profile set-up and preference management.
///
/// A business-logic class knows exactly one thing below it: a **repository
/// facade**. It never sees a repository, a shared client or Flutter.
///
/// "Who is the tourist" is an auth question ([AuthRepository]); "what does
/// the tourist like" is a profile question ([TouristProfileRepository]). This
/// class answers both by resolving the signed-in `tourist_id` (and the auth
/// session's email) first, then handing it to the profile repository.
class UserProfileLogic {
  UserProfileLogic({@visibleForTesting TouristRepositoryFacade? repository})
    : repository = repository ?? TouristRepositoryFacade();

  final TouristRepositoryFacade repository;

  /// The signed-in tourist's id (the app-facing `tourist_id`, not the auth
  /// user id), or `null` when nobody is signed in.
  Future<String?> _touristId() => repository.currentTouristId();

  /// The full profile of the signed-in tourist: identity from the auth
  /// session, preferences + restrictions from the junction tables. `null`
  /// when nobody is signed in or the tourist row cannot be resolved.
  Future<Tourist?> getTourist() async {
    final String? touristId = await _touristId();
    if (touristId == null || touristId.isEmpty) return null;
    final AuthSession? session = await repository.getCurrentSession();
    return repository.getTouristProfile(
      touristId: touristId,
      authUserId: session?.userId ?? '',
      email: session?.email ?? '',
    );
  }

  /// The signed-in tourist's selected food preferences (tastes + categories).
  Future<List<FoodPreference>> getFoodPreferences() async {
    final String? touristId = await _touristId();
    if (touristId == null || touristId.isEmpty) {
      return const <FoodPreference>[];
    }
    return repository.getFoodPreferences(touristId);
  }

  /// Every selectable food preference (from `food_preference`).
  Future<List<FoodPreference>> foodPreferenceOptions() =>
      repository.foodPreferenceOptions();

  /// Persists the signed-in tourist's preference selection (by id).
  Future<void> saveFoodPreferences(List<int> preferenceIds) async {
    final String? touristId = await _touristId();
    if (touristId == null || touristId.isEmpty) {
      throw StateError('Sign in to save your food preferences.');
    }
    await repository.saveFoodPreferences(touristId, preferenceIds);
  }

  /// The signed-in tourist's dietary restrictions.
  Future<List<DietaryRestriction>> getDietaryRestrictions() async {
    final String? touristId = await _touristId();
    if (touristId == null || touristId.isEmpty) {
      return const <DietaryRestriction>[];
    }
    return repository.getDietaryRestrictions(touristId);
  }

  /// Every dietary restriction a tourist can pick.
  Future<List<DietaryRestriction>> dietaryRestrictionOptions() =>
      repository.dietaryRestrictionOptions();
  
  Future<bool> needsProfileSetup() async => repository.accountJustCreated;

  /// Persists the signed-in tourist's dietary-restriction selection.
  Future<void> saveDietaryRestrictions(List<int> restrictionIds) async {
    final String? touristId = await _touristId();
    if (touristId == null || touristId.isEmpty) {
      throw StateError('Sign in to save your dietary restrictions.');
    }
    await repository.saveDietaryRestrictions(touristId, restrictionIds);
  }

  /// The signed-in tourist's favourited local-food ids.
  Future<Set<int>> favouriteFoodIds() async {
    final String? touristId = await _touristId();
    if (touristId == null || touristId.isEmpty) return <int>{};
    return repository.favouriteFoodIds(touristId);
  }

  /// Removes one dish from the signed-in tourist's favourites.
  Future<void> removeFavourite(int localFoodId) async {
    final String? touristId = await _touristId();
    if (touristId == null || touristId.isEmpty) {
      throw StateError('Sign in to remove favourite foods.');
    }
    await repository.removeFavourite(touristId, localFoodId);
  }
}
