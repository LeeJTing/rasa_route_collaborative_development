import 'package:meta/meta.dart' show visibleForTesting;

import '../../domain_model/auth_session.dart';
import '../../domain_model/tourist.dart';
import '../repositories/tourist_repository_facade.dart';

/// Sign-in, sign-up and OTP rules.
///
/// A business-logic class knows exactly one thing below it: a repository
/// facade. It never sees individual repositories, shared clients,
/// Supabase SDK or Flutter.
class AuthenticateLogic {
  AuthenticateLogic({@visibleForTesting TouristRepositoryFacade? repository})
    : repository = repository ?? TouristRepositoryFacade();

  final TouristRepositoryFacade repository;

  /// How many OTP emails one address may receive in [otpSendRateWindow] - the
  /// Grab-style cap that keeps a tourist from hammering "Send OTP" (they can
  /// cancel the OTP screen and request again from the login screen, but only
  /// this many times per window).
  static const int otpSendRateLimit = 3;

  /// The rolling window for [otpSendRateLimit].
  static const Duration otpSendRateWindow = Duration(minutes: 10);

  /// Shown when the same email has already received [otpSendRateLimit] codes
  /// inside [otpSendRateWindow].
  static const String otpSendRateLimitMessage =
      'Too many attempts, please try again later.';

  /// Sends a passwordless OTP to [email], gated by the per-email rate limit.
  ///
  /// Only a *successful* send is recorded, so a mistyped / rejected address
  /// never burns one of the three slots.
  Future<void> sendEmailOtp(String email) async {
    final String normalizedEmail = email.trim();

    if (normalizedEmail.isEmpty) {
      throw ArgumentError('Email cannot be empty.');
    }

    await _assertWithinOtpSendLimit(normalizedEmail);
    await repository.sendEmailOtp(normalizedEmail);
    await repository.recordOtpSend(normalizedEmail);
  }

  Future<void> _assertWithinOtpSendLimit(String email) async {
    final List<DateTime> sends = await repository.otpSendTimes(email);
    final DateTime cutoff = DateTime.now().subtract(otpSendRateWindow);
    final int recent = sends.where((DateTime t) => t.isAfter(cutoff)).length;
    if (recent >= otpSendRateLimit) {
      throw StateError(otpSendRateLimitMessage);
    }
  }

  Future<AuthSession?> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    final String normalizedEmail = email.trim();
    final String normalizedToken = token.trim();

    if (normalizedEmail.isEmpty) {
      throw ArgumentError('Email cannot be empty.');
    }

    if (normalizedToken.isEmpty) {
      throw ArgumentError('OTP cannot be empty.');
    }

    final AuthSession? session = await repository.verifyEmailOtp(
      email: normalizedEmail,
      token: normalizedToken,
    );

    // The first successful verification is also a registration: provision the
    // tourist row the moment the account is authenticated (the UX has no
    // separate register screen).
    if (session != null) {
      await repository.getOrCreateTourist(session);
    }

    return session;
  }

  /// Completes a Google OAuth sign-in after the user returns from the
  /// browser. Picks up the session Supabase established via the deep link,
  /// then auto-creates the tourist row on first sign-in.
  ///
  /// Returns the tourist, or `null` when the flow did not actually complete
  /// (no session yet - e.g. the user cancelled in the browser).
  Future<Tourist?> completeGoogleSignIn() async {
    final AuthSession? session = await repository.getCurrentSession();
    if (session == null) return null;
    return repository.getOrCreateTourist(session);
  }

  /// Returns the [Tourist] row for [session]'s auth user, auto-creating it on
  /// first sign-in.
  Future<Tourist?> getOrCreateTourist(AuthSession session) =>
      repository.getOrCreateTourist(session);

  String get pendingEmail => repository.pendingAuthEmail;

  /// When the freshest code for the pending email was sent, or null when no
  /// code is pending (see `AuthRepository`'s Option B pending-OTP marker).
  DateTime? get pendingOtpSentAt => repository.pendingOtpSentAt;

  Future<bool> signInWithGoogle({required String redirectTo}) {
    return repository.signInWithGoogle(redirectTo: redirectTo);
  }

  Future<AuthSession?> getCurrentSession() {
    return repository.getCurrentSession();
  }

  Future<void> signOut() {
    return repository.signOut();
  }

  String get currentUserId => repository.currentUserId;

  Future<String?> currentTouristId() {
    return repository.currentTouristId();
  }
}
