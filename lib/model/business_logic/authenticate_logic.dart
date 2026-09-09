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

  // Short, cause-specific messages from [emailError] - one reason per line so
  // the login screen can tell the tourist WHAT is wrong, not just that it is.

  static const String emailTooLongMessage = 'Email is too long.';
  static const String emailMissingAtMessage = "Email needs an '@'.";
  static const String emailTooManyAtMessage = "Email can have only one '@'.";
  static const String emailMissingNameMessage =
      "Email needs a name before the '@'.";
  static const String emailMissingDomainMessage =
      "Email needs a domain after the '@'.";
  static const String emailSpaceMessage = "Email can't contain spaces.";
  static const String emailDotMessage =
      "Email can't start, end, or double a dot.";
  static const String emailInvalidCharMessage =
      "Email has characters that aren't allowed.";
  static const String emailNoTldMessage =
      'Email needs a domain like example.com.';
  static const String emailTldBadMessage = 'Email domain looks incomplete.';
  static const String emailInvalidDomainMessage =
      'Email domain has invalid characters.';

  /// Why [value] is not a deliverable email address, or null when it is one.
  ///
  /// Pure - no repository, no network. Used by the login screen to block the
  /// Send-OTP button and by [sendEmailOtp]/[verifyEmailOtp] as a final guard.
  ///
  /// Deliberately pragmatic rather than full RFC 5322: it rejects what a
  /// tourist would actually mistype, which is also what a mail provider
  /// (Gmail etc.) would refuse to deliver to:
  ///   * boundary failures - `username@`, `@domain.com`, `username@domain`
  ///     (no dot, so no TLD), `username@domain.c` (one-letter TLD);
  ///   * dot errors - `.user@…`, `user.@…`, `user..name@…`, `…@domain.`;
  ///   * formatting blunders - spaces, or more than one `@`;
  ///   * symbols providers ban in the local part - `!`, `^`, `&`, `?`, …
  ///
  /// `null` when [value] is empty/whitespace - an empty field is "required",
  /// a separate concern from "malformed" (the caller decides which message to
  /// show for an untouched field).
  String? emailError(String value) {
    final String email = value.trim();
    if (email.isEmpty) return null;
    if (email.length > 254) return emailTooLongMessage;
    if (email.contains(RegExp(r'\s'))) return emailSpaceMessage;

    // Exactly one '@', with a local part before it and a domain after it.
    final int firstAt = email.indexOf('@');
    final int lastAt = email.lastIndexOf('@');
    if (firstAt < 0) return emailMissingAtMessage;
    if (firstAt != lastAt) return emailTooManyAtMessage;
    if (firstAt == 0) return emailMissingNameMessage;
    if (firstAt == email.length - 1) return emailMissingDomainMessage;

    final String local = email.substring(0, firstAt);
    final String domain = email.substring(firstAt + 1);

    // Local part: letters/digits plus . _ % + - ; no leading/trailing dot, no
    // doubled dots, no spaces or symbols (covers the ! ^ & ? cases).
    if (local.length > 64 || domain.length > 253) return emailTooLongMessage;
    if (local.contains('..') || local.startsWith('.') || local.endsWith('.')) {
      return emailDotMessage;
    }
    if (!RegExp(
      r'^[A-Za-z0-9](?:[A-Za-z0-9._%+-]*[A-Za-z0-9])?$',
    ).hasMatch(local)) {
      return emailInvalidCharMessage;
    }

    // Domain: at least one dot (a real TLD), letter/digit/hyphen labels, no
    // leading/trailing/doubled dots, and a TLD of two or more letters.
    if (domain.startsWith('.') ||
        domain.endsWith('.') ||
        domain.contains('..')) {
      return emailDotMessage;
    }
    if (!domain.contains('.')) return emailNoTldMessage;
    final List<String> labels = domain.split('.');
    final String tld = labels.last;
    if (tld.length < 2 || !RegExp(r'^[A-Za-z]{2,}$').hasMatch(tld)) {
      return emailTldBadMessage;
    }
    for (final String label in labels) {
      if (label.isEmpty) return emailDotMessage;
      if (!RegExp(
        r'^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$',
      ).hasMatch(label)) {
        return emailInvalidDomainMessage;
      }
    }
    return null;
  }

  /// Sends a passwordless OTP to [email], gated by the per-email rate limit.
  ///
  /// Only a *successful* send is recorded, so a mistyped / rejected address
  /// never burns one of the three slots.
  Future<void> sendEmailOtp(String email) async {
    final String normalizedEmail = email.trim();

    if (normalizedEmail.isEmpty) {
      throw ArgumentError('Email cannot be empty.');
    }

    // Defense in depth: the login screen blocks malformed addresses before
    // navigation, but the OTP screen can also be reached with a stale pending
    // email (deep-link/restart). Never ask Supabase to mail a string that
    // cannot be an address.
    final String? formatError = emailError(normalizedEmail);
    if (formatError != null) {
      throw ArgumentError(formatError);
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

    // Same final guard as [sendEmailOtp]: never hand a malformed address to
    // the verification call.
    final String? formatError = emailError(normalizedEmail);
    if (formatError != null) {
      throw ArgumentError(formatError);
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
