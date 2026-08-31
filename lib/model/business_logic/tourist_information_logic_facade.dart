import 'authenticate_logic.dart';
import '../../domain_model/auth_session.dart';
import '../../domain_model/dietary_restriction.dart';
import '../../domain_model/food_preference.dart';
import '../../domain_model/tourist.dart';
import 'user_profile_logic.dart';

/// Auth and profile. Used by the LoginRegister, Otp, ProfileSetUp and Profile ViewModels.
///
/// LOGIC FACADE - a ViewModel holds ONE of these and talks to it. Behind it the
/// facade fans out to as many business-logic classes as the feature needs. No
/// business rules live here, and it never imports Flutter.
class TouristInformationLogicFacade {
  TouristInformationLogicFacade();

  final AuthenticateLogic authenticate = AuthenticateLogic();
  final UserProfileLogic userProfile = UserProfileLogic();

  Future<void> sendEmailOtp(String email) => authenticate.sendEmailOtp(email);

  Future<AuthSession?> verifyEmailOtp({
    required String email,
    required String token,
  }) => authenticate.verifyEmailOtp(email: email, token: token);

  Future<bool> signInWithGoogle({required String redirectTo}) =>
      authenticate.signInWithGoogle(redirectTo: redirectTo);

  String get pendingAuthEmail => authenticate.pendingEmail;

  /// Completes a Google OAuth sign-in after the browser returns - picks up
  /// the session and auto-creates the tourist row on first sign-in.
  Future<Tourist?> completeGoogleSignIn() =>
      authenticate.completeGoogleSignIn();

  /// Returns the [Tourist] row for [session]'s auth user, auto-creating it on
  /// first sign-in.
  Future<Tourist?> getOrCreateTourist(AuthSession session) =>
      authenticate.getOrCreateTourist(session);

  Future<AuthSession?> getCurrentSession() => authenticate.getCurrentSession();

  Future<void> signOut() => authenticate.signOut();

  Future<String?> currentTouristId() => authenticate.currentTouristId();

  // ===========================================================================
  // Profile - re-exposed from UserProfileLogic
  // ===========================================================================

  /// The signed-in tourist's full profile (identity + preferences +
  /// restrictions), or null when nobody is signed in.
  Future<Tourist?> getTourist() => userProfile.getTourist();

  /// The signed-in tourist's selected food preferences (tastes + categories).
  Future<List<FoodPreference>> getFoodPreferences() =>
      userProfile.getFoodPreferences();

  /// Every selectable food preference from `food_preference`.
  Future<List<FoodPreference>> foodPreferenceOptions() =>
      userProfile.foodPreferenceOptions();

  /// Persists the signed-in tourist's preference selection (by id).
  Future<void> saveFoodPreferences(List<int> preferenceIds) =>
      userProfile.saveFoodPreferences(preferenceIds);

  /// The signed-in tourist's dietary restrictions.
  Future<List<DietaryRestriction>> getDietaryRestrictions() =>
      userProfile.getDietaryRestrictions();

  /// Every dietary restriction a tourist can pick.
  Future<List<DietaryRestriction>> dietaryRestrictionOptions() =>
      userProfile.dietaryRestrictionOptions();

  /// Persists the signed-in tourist's dietary-restriction selection.
  Future<void> saveDietaryRestrictions(List<int> restrictionIds) =>
      userProfile.saveDietaryRestrictions(restrictionIds);

  /// The signed-in tourist's favourited local-food ids.
  Future<Set<int>> favouriteFoodIds() => userProfile.favouriteFoodIds();

  /// Removes one dish from the signed-in tourist's favourites.
  Future<void> removeFavourite(int localFoodId) =>
      userProfile.removeFavourite(localFoodId);
}
