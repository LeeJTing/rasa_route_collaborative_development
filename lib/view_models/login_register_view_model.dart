import 'package:meta/meta.dart' show visibleForTesting;

import '../core/base_view_model.dart';
import '../domain_model/auth_session.dart';
import '../domain_model/tourist.dart';
import '../model/business_logic/tourist_information_logic_facade.dart';

/// ViewModel for `LoginRegisterView`.
///
/// Email/password sign-in and registration. Also the app's entry gate: the
/// screen is the initial route, and `onInit` checks whether a session already
/// exists (app restart / deep-link return) so a signed-in tourist skips the
/// form and goes straight to the shell.
///
/// Rules this class follows (see `lib/core/base_view_model.dart`):
///   * no `package:flutter/material.dart` import and no `BuildContext`;
///   * it knows the logic facade(s) below and nothing else - never a
///     repository, never a shared client, never Supabase or Gemini;
///   * state goes in private fields with read-only getters; commands wrap their
///     facade call in `runGuarded` so busy and error states behave the same on
///     every screen.
class LoginRegisterViewModel extends BaseViewModel {
  LoginRegisterViewModel({
    @visibleForTesting TouristInformationLogicFacade? touristLogic,
    @visibleForTesting
    this.googleSessionGracePeriod = const Duration(seconds: 5),
    @visibleForTesting
    this.googleSessionRetryInterval = const Duration(milliseconds: 250),
  }) : touristLogic = touristLogic ?? TouristInformationLogicFacade();

  final TouristInformationLogicFacade touristLogic;

  /// How long [completeGoogleSignIn] keeps polling for the session before
  /// declaring the Google flow incomplete.
  ///
  /// On Android, Supabase opens Google in the system browser and completes the
  /// OAuth only after the `login-callback` deep link brings the app back. That
  /// PKCE code exchange runs asynchronously on Supabase's own deep-link
  /// listener, so the app can be `resumed` a moment BEFORE the session shows
  /// up in `getCurrentSession`. A single immediate check would then throw a
  /// false "did not complete" error even though the sign-in is about to
  /// succeed (the user then appears logged-in "a few seconds later" once a
  /// second lifecycle event re-runs the completion). Polling inside this
  /// window absorbs that delay instead. Zero/small in tests.
  @visibleForTesting
  final Duration googleSessionGracePeriod;

  /// Delay between the polls inside [completeGoogleSignIn]. Small in tests so
  /// the late-session case does not actually wait seconds.
  @visibleForTesting
  final Duration googleSessionRetryInterval;

  static const String _googleOAuthRedirectTo =
      'com.rasaroute.app://login-callback';

  String _email = '';
  bool _otpSent = false;
  bool _googleFlowStarted = false;
  bool _googleSignInComplete = false;
  bool _checkingSession = true;
  bool _signedIn = false;
  bool _needsProfileSetup = false;

  String get email => _email;
  bool get otpSent => _otpSent;

  /// True while the entry session check is running - the View shows a splash
  /// instead of the form so an already-signed-in tourist never sees the
  /// sign-in screen flash.
  bool get checkingSession => _checkingSession;

  /// True once [onInit] resolved a valid session; the View then opens the
  /// shell instead of the form.
  bool get signedIn => _signedIn;

  /// C3 first-run gate: true when the signed-in tourist has configured no
  /// profile yet (no preferences and no restrictions), so the View routes them
  /// to [AppRoutes.profileSetUp] instead of the shell. Only meaningful while
  /// [signedIn] is true.
  bool get needsProfileSetup => _needsProfileSetup;

  /// Entry session check: restore a session if one exists, otherwise leave the
  /// tourist on the sign-in form. Failures (Supabase unreachable /
  /// misconfigured) are treated as "signed out" so the tourist can still reach
  /// sign-in instead of hanging.
  @override
  Future<void> onInit() async {
    AuthSession? session;
    try {
      session = await touristLogic.getCurrentSession();
    } catch (_) {
      session = null;
    }
    _signedIn = session != null;
    _needsProfileSetup =
        session != null && await touristLogic.needsProfileSetup();
    _checkingSession = false;
    safeNotifyListeners();
  }

  /// True once the Google browser flow has been launched. The View watches the
  /// app lifecycle from here and calls [completeGoogleSignIn] on resume.
  bool get googleFlowStarted => _googleFlowStarted;

  /// True once a Google sign-in has actually completed (session present and
  /// the tourist row provisioned). The View navigates to the shell on this.
  bool get googleSignInComplete => _googleSignInComplete;

  bool get canSendOtp => _email.trim().isNotEmpty && !isBusy;

  void setEmail(String value) {
    _email = value;
    safeNotifyListeners();
  }

  Future<void> sendEmailOtp() async {
    _otpSent = false;
    await runGuarded(() async {
      await touristLogic.sendEmailOtp(_email);
      _otpSent = true;
    });
  }

  Future<void> signInWithGoogle() async {
    _googleFlowStarted = false;
    _googleSignInComplete = false;
    await runGuarded(() async {
      _googleFlowStarted = await touristLogic.signInWithGoogle(
        redirectTo: _googleOAuthRedirectTo,
      );
      if (!_googleFlowStarted) {
        throw StateError('Unable to start Google sign-in. Please try again.');
      }
    });
  }

  /// Called when the app returns to the foreground after the Google browser
  /// flow. Completes the OAuth - resolves the session Supabase established
  /// via the deep link and auto-creates the tourist row on first sign-in.
  ///
  /// The Supabase SDK can still be exchanging the PKCE code when the app
  /// resumes, so [_resolveGoogleTourist] keeps retrying within
  /// [googleSessionGracePeriod] before giving up - a successful Google sign-in
  /// must never flash a spurious failure snackbar.
  Future<void> completeGoogleSignIn() async {
    _googleSignInComplete = false;
    await runGuarded(() async {
      final Tourist? tourist = await _resolveGoogleTourist();
      if (tourist == null) {
        throw StateError('Google sign-in did not complete. Please try again.');
      }
      _googleSignInComplete = true;
      _needsProfileSetup = await touristLogic.needsProfileSetup();
    });
  }

  /// Resolves the tourist created by the Google sign-in, waiting (bounded) for
  /// the session that the Supabase deep-link handler is still establishing.
  /// Returns null once [googleSessionGracePeriod] elapses without a session.
  Future<Tourist?> _resolveGoogleTourist() async {
    final DateTime deadline = DateTime.now().add(googleSessionGracePeriod);
    while (true) {
      final Tourist? tourist = await touristLogic.completeGoogleSignIn();
      if (tourist != null) return tourist;
      if (DateTime.now().isAfter(deadline)) return null;
      await Future<void>.delayed(googleSessionRetryInterval);
    }
  }
}
