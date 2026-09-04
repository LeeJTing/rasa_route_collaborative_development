import 'package:meta/meta.dart' show visibleForTesting;

import '../core/base_view_model.dart';
import '../domain_model/auth_session.dart';
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
  }) : touristLogic = touristLogic ?? TouristInformationLogicFacade();

  final TouristInformationLogicFacade touristLogic;

  static const String _googleOAuthRedirectTo =
      'com.rasaroute.app://login-callback';

  String _email = '';
  bool _otpSent = false;
  bool _googleFlowStarted = false;
  bool _googleSignInComplete = false;
  bool _checkingSession = true;
  bool _signedIn = false;

  String get email => _email;
  bool get otpSent => _otpSent;

  /// True while the entry session check is running - the View shows a splash
  /// instead of the form so an already-signed-in tourist never sees the
  /// sign-in screen flash.
  bool get checkingSession => _checkingSession;

  /// True once [onInit] resolved a valid session; the View then opens the
  /// shell instead of the form.
  bool get signedIn => _signedIn;

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
  Future<void> completeGoogleSignIn() async {
    _googleSignInComplete = false;
    await runGuarded(() async {
      final tourist = await touristLogic.completeGoogleSignIn();
      if (tourist == null) {
        throw StateError('Google sign-in did not complete. Please try again.');
      }
      _googleSignInComplete = true;
    });
  }
}
