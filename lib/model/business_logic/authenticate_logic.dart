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

  Future<void> sendEmailOtp(String email) async {
    final String normalizedEmail = email.trim();

    if (normalizedEmail.isEmpty) {
      throw ArgumentError('Email cannot be empty.');
    }

    await repository.sendEmailOtp(normalizedEmail);
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
