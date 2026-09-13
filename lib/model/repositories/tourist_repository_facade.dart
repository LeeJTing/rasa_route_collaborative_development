import '../../domain_model/app_tutorial.dart';
import '../../domain_model/auth_session.dart';
import '../../domain_model/dietary_restriction.dart';
import '../../domain_model/food_preference.dart';
import '../../domain_model/tourist.dart';

import 'auth_repository.dart';
import 'interaction_repository.dart';
import 'location_repository.dart';
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

  final AuthRepository auth = AuthRepository();
  final TouristProfileRepository profile = TouristProfileRepository();
  final InteractionRepository interaction = InteractionRepository();
  final LocationRepository location = LocationRepository();
  final TutorialRepository tutorial = TutorialRepository();

  // ==========================================================================
  // Authentication - flat API
  // ==========================================================================

  Future<void> sendEmailOtp(String email) => auth.sendEmailOtp(email);

  /// Every recorded OTP send timestamp for [email] (see `AuthenticateLogic`'s
  /// 3-per-10-minute gate).
  Future<List<DateTime>> otpSendTimes(String email) =>
      auth.otpSendTimes(email);

  /// Records a successful OTP send for [email].
  Future<void> recordOtpSend(String email) => auth.recordOtpSend(email);

  Future<AuthSession?> verifyEmailOtp({
    required String email,
    required String token,
  }) => auth.verifyEmailOtp(email: email, token: token);

  String get pendingAuthEmail => auth.pendingEmail;

  /// When the freshest code for the pending email was sent, or null when no
  /// code is pending (see `AuthRepository`'s Option B pending-OTP marker).
  DateTime? get pendingOtpSentAt => auth.pendingOtpSentAt;

  Future<bool> signInWithGoogle({required String redirectTo}) =>
      auth.signInWithGoogle(redirectTo: redirectTo);

  Future<AuthSession?> getCurrentSession() => auth.getCurrentSession();

  Future<void> signOut() => auth.signOut();

  String get currentUserId => auth.currentUserId;

  Future<String?> currentTouristId() => auth.currentTouristId();

  /// True when the sign-in that just completed CREATED the account's `tourist`
  /// row - its first ever authentication, and the only moment the first-run
  /// set-up screen is shown (see `UserProfileLogic.needsProfileSetup`).
  bool get accountJustCreated => auth.accountJustCreated;

  /// Returns the [Tourist] row for [session]'s auth user, auto-creating it on
  /// first sign-in - the "register" half of the login/register UX.
  Future<Tourist?> getOrCreateTourist(AuthSession session) =>
      auth.getOrCreateTourist(session);

  // ==========================================================================
  // Profile - flat API
  // ==========================================================================

  /// The full profile for [touristId] (identity + preferences + restrictions).
  Future<Tourist?> getTouristProfile({
    required String touristId,
    String authUserId = '',
    String email = '',
    String displayName = '',
  }) => profile.getTourist(
    touristId: touristId,
    authUserId: authUserId,
    email: email,
    displayName: displayName,
  );

  /// Every food preference [touristId] has picked (junction rows).
  Future<List<FoodPreference>> getFoodPreferences(String touristId) =>
      profile.getFoodPreferences(touristId);

  /// Every selectable food preference from `food_preference` (tastes and
  /// categories mixed - group by [FoodPreference.kind]).
  Future<List<FoodPreference>> foodPreferenceOptions() =>
      profile.foodPreferenceOptions();

  /// Replaces [touristId]'s preference selection (junction rows).
  Future<void> saveFoodPreferences(String touristId, List<int> preferenceIds) =>
      profile.saveFoodPreferences(touristId, preferenceIds);

  /// Every restriction [touristId] holds.
  Future<List<DietaryRestriction>> getDietaryRestrictions(String touristId) =>
      profile.getDietaryRestrictions(touristId);

  /// Every restriction a tourist can pick.
  Future<List<DietaryRestriction>> dietaryRestrictionOptions() =>
      profile.dietaryRestrictionOptions();

  /// Replaces [touristId]'s restriction selection (junction rows).
  Future<void> saveDietaryRestrictions(
    String touristId,
    List<int> restrictionIds,
  ) => profile.saveDietaryRestrictions(touristId, restrictionIds);

  /// The local-food ids [touristId] has saved.
  Future<Set<int>> favouriteFoodIds(String touristId) =>
      profile.favouriteFoodIds(touristId);

  /// Removes one saved dish from [touristId]'s favourites.
  Future<void> removeFavourite(String touristId, int localFoodId) =>
      profile.removeFavourite(touristId, localFoodId);

  // ==========================================================================
  // Guided walkthrough - flat API
  // ==========================================================================
  //
  // Device-scoped, not account-scoped: the tutorial explains the app, and a
  // phone that has never run it is a first-time user whoever is signed in.

  /// What this device remembers about the walkthrough, or
  /// [TutorialProgress.never]. Synchronous, because local storage is already
  /// loaded by the time any screen asks.
  TutorialProgress tutorialProgress() => tutorial.read();

  /// Records that the walkthrough was finished or skipped.
  Future<void> saveTutorialProgress(TutorialProgress progress) =>
      tutorial.write(progress);

  /// Forgets that record, so the next launch shows the walkthrough again.
  Future<void> clearTutorialProgress() => tutorial.clear();
}
