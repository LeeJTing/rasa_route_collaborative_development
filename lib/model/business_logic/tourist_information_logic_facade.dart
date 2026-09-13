import 'app_tutorial_logic.dart';
import 'authenticate_logic.dart';
import '../../domain_model/app_tutorial.dart';
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
  final AppTutorialLogic appTutorial = AppTutorialLogic();

  Future<void> sendEmailOtp(String email) => authenticate.sendEmailOtp(email);

  /// Why [email] is not a deliverable address, or null when it is one. Pure
  /// rule - the login screen reads it live to gate the Send-OTP button.
  String? emailError(String email) => authenticate.emailError(email);

  /// Auth -----
  /// The mailbox identity of [email] (see `AuthenticateLogic.canonicalEmail`).
  ///
  /// This is the address a code is actually sent to: salted spellings of one
  /// mailbox (Gmail dots, `+tag` subaddresses) collapse onto this form, so one
  /// mailbox resolves to one account. Used by the OTP screen to show what it is
  /// sending to instead of what was typed.
  String canonicalEmail(String email) => authenticate.canonicalEmail(email);

  /// True when [email] is a salted spelling of its mailbox rather than the
  /// canonical form - the OTP screen mentions the rewrite only when it is.
  bool isSaltedEmail(String email) => authenticate.isSaltedEmail(email);

  /// Auth end ----

  Future<AuthSession?> verifyEmailOtp({
    required String email,
    required String token,
  }) => authenticate.verifyEmailOtp(email: email, token: token);

  Future<bool> signInWithGoogle({required String redirectTo}) =>
      authenticate.signInWithGoogle(redirectTo: redirectTo);

  String get pendingAuthEmail => authenticate.pendingEmail;

  /// When the freshest code for the pending email was sent, or null when no
  /// code is pending (see `AuthRepository`'s Option B pending-OTP marker).
  DateTime? get pendingOtpSentAt => authenticate.pendingOtpSentAt;

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

  /// C3 first-run gate: true while the signed-in tourist has no food
  /// preferences AND no dietary restrictions yet (see `UserProfileLogic`).
  Future<bool> needsProfileSetup() => userProfile.needsProfileSetup();

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

  // ===========================================================================
  // Guided walkthrough - re-exposed from AppTutorialLogic
  // ===========================================================================

  /// The walkthrough's cards, in order (REQ107).
  List<TutorialStep> get tutorialSteps => AppTutorialLogic.steps;

  /// Whether the walkthrough should open now - a first run, a release that
  /// added a card, or a year since it was last dismissed.
  bool shouldShowTutorial() => appTutorial.shouldShow();

  /// The tourist reached the end and pressed Finish.
  Future<void> completeTutorial() => appTutorial.markCompleted();

  /// The tourist pressed Skip. Recorded the same way as finishing.
  Future<void> skipTutorial() => appTutorial.markSkipped();
}
