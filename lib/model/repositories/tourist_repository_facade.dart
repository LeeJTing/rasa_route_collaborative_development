import '../../domain_model/app_tutorial.dart';
import '../../domain_model/auth_session.dart';
import '../../domain_model/dietary_restriction.dart';
import '../../domain_model/food_preference.dart';
import '../../domain_model/tourist.dart';

import 'auth_repository.dart';
import 'tourist_profile_repository.dart';
import 'tutorial_repository.dart';

/// Everything about who the tourist is: session, profile, interactions and
/// where they are standing.
///
/// REPOSITORY FACADE - a business-logic class holds ONE of these, not four
/// separate repositories. It groups the repositories for one subject area and
/// re-exposes them as a single flat API. No business rules live here.
class TouristRepositoryFacade {
  TouristRepositoryFacade();

  final AuthRepository _auth = AuthRepository();
  final TouristProfileRepository _profile = TouristProfileRepository();
  final TutorialRepository _tutorial = TutorialRepository();

  // ==========================================================================
  // Authentication - flat API
  // ==========================================================================

  Future<void> sendEmailOtp(String email) => _auth.sendEmailOtp(email);

  /// Every recorded OTP send timestamp for [email] (see `AuthenticateLogic`'s
  /// 3-per-10-minute gate).
  Future<List<DateTime>> otpSendTimes(String email) =>
      _auth.otpSendTimes(email);

  /// Records a successful OTP send for [email].
  Future<void> recordOtpSend(String email) => _auth.recordOtpSend(email);

  Future<AuthSession?> verifyEmailOtp({
    required String email,
    required String token,
  }) => _auth.verifyEmailOtp(email: email, token: token);

  String get pendingAuthEmail => _auth.pendingEmail;

  /// When the freshest code for the pending email was sent, or null when no
  /// code is pending (see `AuthRepository`'s Option B pending-OTP marker).
  DateTime? get pendingOtpSentAt => _auth.pendingOtpSentAt;

  /// Auth -----
  /// When this device last sent ANY OTP, whichever address it was for, or null
  /// when it has not sent one yet. Powers the device-wide resend cooldown, so
  /// switching accounts on one handset gains nothing.
  DateTime? get otpLastDeviceSendAt => _auth.otpLastDeviceSendAt;

  /// Auth end ----

  Future<bool> signInWithGoogle({required String redirectTo}) =>
      _auth.signInWithGoogle(redirectTo: redirectTo);

  Future<AuthSession?> getCurrentSession() => _auth.getCurrentSession();

  Future<void> signOut() => _auth.signOut();

  String get currentUserId => _auth.currentUserId;

  Future<String?> currentTouristId() => _auth.currentTouristId();

  /// True when the sign-in that just completed CREATED the account's `tourist`
  /// row - its first ever authentication, and the only moment the first-run
  /// set-up screen is shown (see `UserProfileLogic.needsProfileSetup`).
  bool get accountJustCreated => _auth.accountJustCreated;

  /// Returns the [Tourist] row for [session]'s auth user, auto-creating it on
  /// first sign-in - the "register" half of the login/register UX.
  Future<Tourist?> getOrCreateTourist(AuthSession session) =>
      _auth.getOrCreateTourist(session);

  // ==========================================================================
  // Profile - flat API
  // ==========================================================================

  /// The full profile for [touristId] (identity + preferences + restrictions).
  Future<Tourist?> getTouristProfile({
    required String touristId,
    String authUserId = '',
    String email = '',
    String displayName = '',
  }) => _profile.getTourist(
    touristId: touristId,
    authUserId: authUserId,
    email: email,
    displayName: displayName,
  );

  /// Every food preference [touristId] has picked (junction rows).
  Future<List<FoodPreference>> getFoodPreferences(String touristId) =>
      _profile.getFoodPreferences(touristId);

  /// Every selectable food preference from `food_preference` (tastes and
  /// categories mixed - group by [FoodPreference.kind]).
  Future<List<FoodPreference>> foodPreferenceOptions() =>
      _profile.foodPreferenceOptions();

  /// Replaces [touristId]'s preference selection (junction rows).
  Future<void> saveFoodPreferences(String touristId, List<int> preferenceIds) =>
      _profile.saveFoodPreferences(touristId, preferenceIds);

  /// Every restriction [touristId] holds.
  Future<List<DietaryRestriction>> getDietaryRestrictions(String touristId) =>
      _profile.getDietaryRestrictions(touristId);

  /// Every restriction a tourist can pick.
  Future<List<DietaryRestriction>> dietaryRestrictionOptions() =>
      _profile.dietaryRestrictionOptions();

  /// Replaces [touristId]'s restriction selection (junction rows).
  Future<void> saveDietaryRestrictions(
    String touristId,
    List<int> restrictionIds,
  ) => _profile.saveDietaryRestrictions(touristId, restrictionIds);

  /// The local-food ids [touristId] has saved.
  Future<Set<int>> favouriteFoodIds(String touristId) =>
      _profile.favouriteFoodIds(touristId);

  /// Removes one saved dish from [touristId]'s favourites.
  Future<void> removeFavourite(String touristId, int localFoodId) =>
      _profile.removeFavourite(touristId, localFoodId);

  // ==========================================================================
  // Guided walkthrough - flat API
  // ==========================================================================
  //
  // Device-scoped, not account-scoped: the tutorial explains the app, and a
  // phone that has never run it is a first-time user whoever is signed in.

  /// What this device remembers about the walkthrough, or
  /// [TutorialProgress.never]. Synchronous, because local storage is already
  /// loaded by the time any screen asks.
  TutorialProgress tutorialProgress() => _tutorial.read();

  /// Records that the walkthrough was finished or skipped.
  Future<void> saveTutorialProgress(TutorialProgress progress) =>
      _tutorial.write(progress);

  /// Forgets that record, so the next launch shows the walkthrough again.
  Future<void> clearTutorialProgress() => _tutorial.clear();
}
